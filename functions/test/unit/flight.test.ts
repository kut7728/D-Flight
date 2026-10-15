import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { AppError } from "../../src/domain/errors";
import {
  applyAirportRow,
  applyUserFields,
  buildDrafts,
  dataLevelOf,
  manualFlight,
  mergeFlightDocs,
  markFailure,
  markSuccess,
  notFoundReason,
  planPoll,
  pollGroups,
  providerLevel,
  searchBlocked,
  type AirportFacts,
  type FlightDoc,
} from "../../src/domain/flight";
import { canonicalizeFields, parseManual, parseSearch } from "../../src/domain/flightInput";
import { assertUpcomingTracked, consumeSearch, SEARCH_PER_HOUR, type SearchCounter } from "../../src/domain/limits";
import { quotaDocId, quotaMode, recordCalls, type QuotaCounts } from "../../src/domain/quota";
import { addDays, seoulToday, zonedTimeToUtc } from "../../src/domain/time";
import { maxSeasonDate } from "../../src/providers/parse";
import type { ProviderFlight } from "../../src/providers/types";

const FACTS: Record<string, AirportFacts> = {
  ICN: { timeZone: "Asia/Seoul", korean: true, terminals: ["T1", "T2"] },
  GMP: { timeZone: "Asia/Seoul", korean: true, terminals: [] },
  CJU: { timeZone: "Asia/Seoul", korean: true, terminals: [] },
  HND: { timeZone: "Asia/Tokyo", korean: false, terminals: ["T1", "T2", "T3"] },
  NRT: { timeZone: "Asia/Tokyo", korean: false, terminals: ["T1", "T2", "T3"] },
  KIX: { timeZone: "Asia/Tokyo", korean: false, terminals: ["T1", "T2"] },
  BKK: { timeZone: "Asia/Bangkok", korean: false, terminals: [] },
};

const facts = (code: string) => FACTS[code] ?? null;
const D10 = new Date("2026-10-22T03:00:00Z");
const DATE = "2026-11-01";
const DEP = new Date("2026-11-01T01:00:00Z");

function row(partial: Partial<ProviderFlight> = {}): ProviderFlight {
  return {
    flightNumber: "XX100",
    operatingFlightNumber: "XX100",
    koreanAirport: "ICN",
    otherAirport: "NRT",
    direction: "departure",
    scheduledAt: DEP,
    estimatedAt: null,
    status: "scheduled",
    terminal: null,
    gate: null,
    checkInCounter: null,
    baggageBelt: null,
    level: "schedule",
    ...partial,
  };
}

function draft(partial: Partial<ProviderFlight> = {}, now = D10): FlightDoc {
  const built = buildDrafts([row(partial)], { flightNumber: partial.flightNumber ?? partial.operatingFlightNumber ?? "XX100", departureDate: DATE }, facts, now);
  assert.equal(built.length, 1);
  return { ...built[0].flight, trackerCount: 1 };
}

function plan(flight: FlightDoc, now: Date, mode: "normal" | "stretched" | "frequentOnly" = "normal") {
  return planPoll({
    now,
    departureDate: DATE,
    timeZone: flight.departure.timeZone,
    departureAt: flight.departure.estimatedAt.value ?? flight.departure.scheduledAt,
    arrivalAt: flight.arrival.estimatedAt.value ?? flight.arrival.scheduledAt,
    status: flight.status.value,
    trackerCount: flight.trackerCount,
    korean: flight.departure.autoDataSupported || flight.arrival.autoDataSupported,
    mode,
  });
}

describe("항공편 도메인", () => {
  it("T-01 D-10은 시간표이고 게이트는 비어 있다", () => {
    assert.equal(providerLevel(DATE, seoulToday(D10)), "schedule");
    const built = buildDrafts([row()], { flightNumber: "XX100", departureDate: DATE }, facts, D10);
    assert.equal(built[0].dataLevel, "schedule");
    const flight = { ...built[0].flight, trackerCount: 1 };
    assert.equal(flight.flightKey, "XX100_2026-11-01_ICN");
    assert.equal(flight.departure.gate.value, null);
    assert.equal(flight.departure.autoDataSupported, true);
    assert.equal(flight.arrival.autoDataSupported, false);
    const next = plan(flight, D10);
    assert.equal(next.phase, "schedule");
    assert.equal(next.call, "schedule");
    assert.ok(next.nextPollAt && next.nextPollAt.getTime() - D10.getTime() === 24 * 60 * 60 * 1000);
  });

  it("T-02 D-3에 들어오면 1시간 주기이고 터미널·체크인만 채운다", () => {
    const now = new Date("2026-10-28T15:00:00Z");
    const flight = draft();
    const next = plan(flight, now);
    assert.equal(next.phase, "hourly");
    assert.equal(next.call, "realtime");
    assert.equal(next.nextPollAt?.getTime(), now.getTime() + 60 * 60 * 1000);
    const applied = applyAirportRow(flight, row({ level: "realtime", terminal: "T1", checkInCounter: "A1", gate: null }), now);
    assert.equal(applied.flight.departure.terminal.value, "T1");
    assert.equal(applied.flight.departure.checkInCounter?.value, "A1");
    assert.equal(applied.flight.departure.gate.value, null);
    assert.ok(applied.kinds.includes("departureTerminal"));
  });

  it("T-04 게이트 108에서 112면 변경 이벤트와 이전 값을 남긴다", () => {
    const now = new Date("2026-11-01T00:00:00Z");
    const flight = draft({ gate: "108", level: "realtime" }, now);
    const applied = applyAirportRow(flight, row({ level: "realtime", gate: "112" }), now);
    assert.deepEqual(applied.kinds, ["gateChanged"]);
    assert.equal(applied.flight.departure.gate.value, "112");
    assert.equal(applied.flight.departure.gate.previousValue, "108");
    const assigned = applyAirportRow(draft(), row({ level: "realtime", gate: "108" }), now);
    assert.deepEqual(assigned.kinds, ["gateAssigned"]);
  });

  it("T-05 45분 지연은 출발 시각 이벤트다", () => {
    const now = new Date("2026-11-01T00:00:00Z");
    const flight = draft({ level: "realtime" }, now);
    const applied = applyAirportRow(flight, row({ level: "realtime", estimatedAt: new Date(DEP.getTime() + 45 * 60 * 1000) }), now);
    assert.deepEqual(applied.kinds, ["departureTime"]);
    assert.equal(applied.flight.departure.scheduledAt?.toISOString(), DEP.toISOString());
    assert.equal(applied.flight.departure.estimatedAt.value?.toISOString(), new Date(DEP.getTime() + 45 * 60 * 1000).toISOString());
  });

  it("T-06 결항은 결항 이벤트다", () => {
    const now = new Date("2026-11-01T00:00:00Z");
    const applied = applyAirportRow(draft({ level: "realtime" }, now), row({ level: "realtime", status: "cancelled" }), now);
    assert.deepEqual(applied.kinds, ["cancelled"]);
    assert.equal(applied.flight.status.value, "cancelled");
  });

  it("T-07 게이트와 시각이 같이 바뀌면 이벤트 하나다", () => {
    const now = new Date("2026-11-01T00:00:00Z");
    const flight = draft({ gate: "108", level: "realtime" }, now);
    const applied = applyAirportRow(
      flight,
      row({ level: "realtime", gate: "112", estimatedAt: new Date(DEP.getTime() + 45 * 60 * 1000) }),
      now,
    );
    assert.deepEqual(applied.kinds, ["departureTime", "gateChanged"]);
  });

  it("T-08 3분 변경은 알리지 않고 값도 유지한다", () => {
    const now = new Date("2026-11-01T00:00:00Z");
    const flight = draft({ level: "realtime" }, now);
    const applied = applyAirportRow(flight, row({ level: "realtime", estimatedAt: new Date(DEP.getTime() + 3 * 60 * 1000) }), now);
    assert.deepEqual(applied.kinds, []);
    assert.equal(applied.flight.departure.estimatedAt.value, null);
    const exact = applyAirportRow(flight, row({ level: "realtime", estimatedAt: new Date(DEP.getTime() + 5 * 60 * 1000) }), now);
    assert.deepEqual(exact.kinds, ["departureTime"]);
  });

  it("T-09 API가 게이트를 빼면 마지막 값을 유지하고 사용자 값은 API 값으로 덮는다", () => {
    const now = new Date("2026-11-01T00:00:00Z");
    const flight = draft({ gate: "108", level: "realtime" }, now);
    const kept = applyAirportRow(flight, row({ level: "realtime", gate: null }), now);
    assert.equal(kept.flight.departure.gate.value, "108");
    assert.deepEqual(kept.kinds, []);
    const reported = applyUserFields(flight, { "departure.gate": "12" }, now);
    assert.equal(reported.departure.gate.source, "user");
    const overwritten = applyAirportRow(reported, row({ level: "realtime", gate: "15" }), now);
    assert.equal(overwritten.flight.departure.gate.value, "15");
    assert.equal(overwritten.flight.departure.gate.previousValue, "12");
    assert.equal(overwritten.flight.departure.gate.source, "airport_data");
    const userKept = applyAirportRow(reported, row({ level: "realtime", gate: null }), now);
    assert.equal(userKept.flight.departure.gate.value, "12");
    assert.equal(userKept.flight.departure.gate.source, "user");
  });

  it("T-10 연속 실패 2회를 세고 성공하면 0으로 돌아간다", () => {
    const now = new Date("2026-11-01T00:00:00Z");
    const base = draft().sync;
    const once = markFailure(base, { phase: "hourly", nextPollAt: now }, now);
    const twice = markFailure(once, { phase: "hourly", nextPollAt: now }, now);
    assert.equal(twice.consecutiveFailures, 2);
    assert.equal(markSuccess(twice, { phase: "hourly", nextPollAt: now }, now).consecutiveFailures, 0);
  });

  it("T-11 도착 + 1시간, 출발 + 6시간, 결항 후 출발 시각이면 조회를 멈춘다", () => {
    const arrival = new Date("2026-11-01T04:00:00Z");
    const base = {
      now: new Date(arrival.getTime() + 60 * 60 * 1000),
      departureDate: DATE,
      timeZone: "Asia/Seoul",
      departureAt: DEP,
      arrivalAt: arrival,
      status: "scheduled" as const,
      trackerCount: 1,
      korean: true,
      mode: "normal" as const,
    };
    assert.equal(planPoll(base).phase, "done");
    assert.equal(planPoll({ ...base, now: new Date(arrival.getTime() + 60 * 60 * 1000 - 1) }).phase, "frequent");
    assert.equal(planPoll({ ...base, arrivalAt: null, now: new Date(DEP.getTime() + 6 * 60 * 60 * 1000) }).phase, "done");
    assert.equal(planPoll({ ...base, status: "cancelled", now: new Date(DEP.getTime() + 1000), arrivalAt: new Date(DEP.getTime() + 8 * 60 * 60 * 1000) }).phase, "done");
    assert.notEqual(planPoll({ ...base, status: "cancelled", now: new Date(DEP.getTime() - 60 * 1000) }).phase, "done");
  });

  it("T-20 하네다에서 인천은 출발만 자동 정보가 없다", () => {
    const built = buildDrafts(
      [row({ direction: "arrival", koreanAirport: "ICN", otherAirport: "HND", scheduledAt: new Date("2026-11-01T04:30:00Z") })],
      { flightNumber: "XX100", departureDate: DATE },
      facts,
      D10,
    );
    assert.equal(built.length, 1);
    assert.equal(built[0].flight.flightKey, "XX100_2026-11-01_HND");
    assert.equal(built[0].flight.departure.autoDataSupported, false);
    assert.equal(built[0].flight.departure.scheduledAt, null);
    assert.equal(built[0].flight.arrival.autoDataSupported, true);
    assert.ok(built[0].flight.arrival.scheduledAt);
  });

  it("국내선 양쪽 행은 한 문서로 합친다", () => {
    const built = buildDrafts(
      [
        row({ koreanAirport: "GMP", otherAirport: "CJU", terminal: null, gate: null }),
        row({
          direction: "arrival",
          koreanAirport: "CJU",
          otherAirport: "GMP",
          scheduledAt: new Date("2026-11-01T02:10:00Z"),
          baggageBelt: "3",
        }),
      ],
      { flightNumber: "XX100", departureDate: DATE },
      facts,
      D10,
    );
    assert.equal(built.length, 1);
    assert.equal(built[0].flight.departure.airport, "GMP");
    assert.equal(built[0].flight.arrival.airport, "CJU");
    assert.equal(built[0].flight.departure.autoDataSupported, true);
    assert.equal(built[0].flight.arrival.autoDataSupported, true);
    assert.equal(built[0].flight.arrival.baggageBelt?.value, "3");
    assert.ok(built[0].flight.departure.scheduledAt);
    assert.ok(built[0].flight.arrival.scheduledAt);
  });

  it("T-22 한국 공항이 없는 직접 입력은 조회하지 않고, 못 찾음 이유는 구간을 따른다", () => {
    assert.equal(notFoundReason("schedule"), "no_korean_airport_data");
    assert.equal(notFoundReason("realtime"), "not_in_schedule");
    const flight = manualFlight({
      flightNumber: "XX220",
      departureDate: DATE,
      departure: { code: "NRT", ...FACTS.NRT },
      arrival: { code: "BKK", ...FACTS.BKK },
      departureAt: zonedTimeToUtc(DATE, "08:30", "Asia/Tokyo"),
      arrivalAt: zonedTimeToUtc(DATE, "10:05", "Asia/Bangkok"),
      fields: {},
      now: D10,
    });
    assert.equal(flight.origin, "user");
    assert.equal(flight.sync.phase, "done");
    assert.equal(flight.sync.nextPollAt, null);
    assert.equal(flight.departure.autoDataSupported, false);
    assert.equal(flight.arrival.autoDataSupported, false);
    assert.equal(flight.departure.scheduledAt?.toISOString(), "2026-10-31T23:30:00.000Z");
  });

  it("T-24 T-25 코드쉐어는 운항 편명 문서 하나를 공유한다", () => {
    const built = buildDrafts(
      [
        row({ flightNumber: "XX5701", operatingFlightNumber: "YY1075" }),
        row({ flightNumber: "YY1075", operatingFlightNumber: "YY1075" }),
      ],
      { flightNumber: "XX5701", departureDate: DATE },
      facts,
      D10,
    );
    assert.equal(built.length, 1);
    assert.equal(built[0].flight.flightKey, "YY1075_2026-11-01_ICN");
    assert.deepEqual(built[0].flight.searchKeys, ["YY1075_2026-11-01", "XX5701_2026-11-01"]);
    const renamed = applyAirportRow(
      { ...draft(), searchKeys: ["XX100_2026-11-01"] },
      row({ flightNumber: "XX100", operatingFlightNumber: "YY100", level: "realtime" }),
      D10,
    );
    assert.equal(renamed.flight.flightKey, "YY100_2026-11-01_ICN");
    assert.ok(renamed.flight.searchKeys.includes("XX100_2026-11-01"));
    assert.ok(renamed.flight.searchKeys.includes("YY100_2026-11-01"));
  });

  it("T-30 자정을 넘는 지연도 출발 날짜 키는 그대로다", () => {
    const scheduled = zonedTimeToUtc(DATE, "23:50", "Asia/Seoul");
    const estimated = zonedTimeToUtc(addDays(DATE, 1), "00:20", "Asia/Seoul");
    const flight = draft({ scheduledAt: scheduled, level: "realtime" });
    const applied = applyAirportRow(flight, row({ level: "realtime", scheduledAt: scheduled, estimatedAt: estimated }), D10);
    assert.equal(applied.flight.flightKey, "XX100_2026-11-01_ICN");
    assert.deepEqual(applied.kinds, ["departureTime"]);
    assert.equal(applied.flight.departure.estimatedAt.value?.toISOString(), estimated.toISOString());
  });

  it("T-58 검색 31회와 등록 31편은 거부한다", () => {
    const now = new Date("2026-10-15T01:00:00Z");
    let state: SearchCounter | undefined;
    for (let i = 0; i < SEARCH_PER_HOUR; i += 1) state = consumeSearch(state, now);
    assert.throws(() => consumeSearch(state, now), (error: unknown) => error instanceof AppError && error.errorCode === "resource-exhausted");
    assert.throws(() => assertUpcomingTracked(30), (error: unknown) => error instanceof AppError && error.errorCode === "resource-exhausted");
  });

  it("T-60 80%부터 1시간 주기가 3시간이 된다", () => {
    assert.equal(quotaMode(0.8), "stretched");
    assert.equal(quotaMode(0.79), "normal");
    const now = new Date("2026-10-30T00:00:00Z");
    const flight = draft();
    assert.equal(plan(flight, now, "normal").nextPollAt?.getTime(), now.getTime() + 60 * 60 * 1000);
    assert.equal(plan(flight, now, "stretched").nextPollAt?.getTime(), now.getTime() + 3 * 60 * 60 * 1000);
    assert.equal(plan(flight, now, "stretched").phase, "hourly");
  });

  it("T-61 95%면 출발 6시간 이내만 조회하고 검색은 거부한다", () => {
    assert.equal(quotaMode(0.95), "frequentOnly");
    const hourlyNow = new Date("2026-10-30T00:00:00Z");
    const flight = draft();
    const skipped = plan(flight, hourlyNow, "frequentOnly");
    assert.equal(skipped.call, "none");
    assert.equal(skipped.phase, "hourly");
    assert.equal(skipped.nextPollAt?.getTime(), hourlyNow.getTime() + 60 * 60 * 1000);
    const soon = new Date(DEP.getTime() - 2 * 60 * 60 * 1000);
    assert.equal(plan(flight, soon, "frequentOnly").call, "realtime");
    const counts: QuotaCounts = { "iiac:realtime:departure": 475 };
    assert.equal(searchBlocked(counts, "realtime"), true);
    assert.equal(searchBlocked({}, "realtime"), false);
  });

  it("T-62 날짜가 바뀌면 호출 기록 문서가 바뀐다", () => {
    assert.notEqual(quotaDocId(new Date("2026-10-15T14:30:00Z")), quotaDocId(new Date("2026-10-15T15:30:00Z")));
    const counts: QuotaCounts = {};
    recordCalls(counts, "iiac:realtime:departure", 10, null);
    assert.equal(counts["iiac:realtime:departure"], 10);
    const fresh: QuotaCounts = {};
    assert.equal(fresh["iiac:realtime:departure"], undefined);
    assert.equal(searchBlocked(fresh, "realtime"), false);
  });

  it("수하물 배정만 알리고 직접 입력 시각은 공항 시간대다", () => {
    const now = new Date("2026-11-01T00:00:00Z");
    const flight = draft({ direction: "arrival", koreanAirport: "ICN", otherAirport: "HND", level: "realtime" }, now);
    const applied = applyAirportRow(
      { ...flight, arrival: { ...flight.arrival, baggageBelt: flight.arrival.baggageBelt ?? { value: null, source: null, updatedAt: null, previousValue: null } } },
      row({ direction: "arrival", koreanAirport: "ICN", otherAirport: "HND", level: "realtime", baggageBelt: "7", scheduledAt: flight.arrival.scheduledAt ?? DEP }),
      now,
    );
    assert.ok(applied.kinds.includes("baggageAssigned"));
    const manual = manualFlight({
      flightNumber: "XX300",
      departureDate: DATE,
      departure: { code: "ICN", ...FACTS.ICN },
      arrival: { code: "NRT", ...FACTS.NRT },
      departureAt: zonedTimeToUtc(DATE, "10:00", "Asia/Seoul"),
      arrivalAt: null,
      fields: { "departure.terminal": "T1", "departure.gate": "12" },
      now,
    });
    assert.equal(manual.departure.scheduledAt?.toISOString(), "2026-11-01T01:00:00.000Z");
    assert.equal(manual.departure.terminal.value, "T1");
    assert.equal(manual.departure.terminal.source, "user");
    assert.equal(manual.sync.phase === "done", false);
    assert.equal(dataLevelOf(manual), "user");
  });

  it("검색·직접 입력의 형식 오류를 거부한다", () => {
    assert.throws(() => parseSearch({ flightNumber: "X", departureDate: DATE }, D10), isInvalid);
    assert.equal(parseSearch({ flightNumber: "xx 100", departureDate: DATE }, D10).flightNumber, "XX100");
    for (const number of ["5701", "1234", "12345", "12A345", "XX12345", "XX123456"]) {
      assert.throws(() => parseSearch({ flightNumber: number, departureDate: DATE }, D10), isInvalid);
    }
    for (const number of ["7C101", "C7101", "XXX1234", "NH5701A"]) {
      assert.equal(parseSearch({ flightNumber: number, departureDate: DATE }, D10).flightNumber, number);
    }
    assert.throws(() => parseSearch({ flightNumber: "XX100", departureDate: "2020-01-01" }, D10), isInvalid);
    assert.throws(() => parseSearch({ flightNumber: "XX100", departureDate: DATE, extra: true }, D10), isInvalid);
    const manual = parseManual(
      {
        flightNumber: "XX100",
        departureDate: DATE,
        departureAirport: "nrt",
        arrivalAirport: "kix",
        departureTime: "08:30",
        arrivalTime: "10:05",
        arrivalDayOffset: 0,
        fields: { "departure.gate": "12" },
      },
      D10,
    );
    assert.equal(manual.departureAirport, "NRT");
    assert.throws(() => canonicalizeFields({ "departure.terminal": "P01" }, ["T1", "T2"], []), isInvalid);
    assert.equal(canonicalizeFields({ "departure.terminal": "t1" }, ["T1", "T2"], [])["departure.terminal"], "T1");
  });

  it("TD-18 공개 시즌 밖이면 대기 등록하고, 찾으면 문서 키는 그대로 둔다", () => {
    const today = seoulToday(D10);
    assert.equal(maxSeasonDate([{ lastdate: "20260328" }, { lastdate: "2026-10-25T00:00:00" }], ["lastdate"]), "2026-10-25");
    assert.equal(notFoundReason("schedule", { departureDate: DATE, today, seasonLastDate: "2026-03-28" }), "outside_schedule_season");
    assert.equal(notFoundReason("schedule", { departureDate: DATE, today, seasonLastDate: "2026-12-01" }), "no_korean_airport_data");
    assert.equal(notFoundReason("schedule", { departureDate: "2026-10-01", today, seasonLastDate: "2026-03-28" }), "no_korean_airport_data");
    assert.equal(notFoundReason("realtime", { departureDate: DATE, today, seasonLastDate: "2026-03-28" }), "not_in_schedule");

    assert.throws(
      () =>
        manualFlight({
          flightNumber: "XX180",
          departureDate: DATE,
          departure: { code: "NRT", ...FACTS.NRT },
          arrival: { code: "BKK", ...FACTS.BKK },
          departureAt: null,
          arrivalAt: null,
          fields: {},
          now: D10,
          awaitAutoData: true,
        }),
      isInvalid,
    );
    const pending = manualFlight({
      flightNumber: "XX180",
      departureDate: DATE,
      departure: { code: "ICN", ...FACTS.ICN },
      arrival: { code: "NRT", ...FACTS.NRT },
      departureAt: null,
      arrivalAt: null,
      fields: {},
      now: D10,
      awaitAutoData: true,
    });
    assert.equal(pending.origin, "pending");
    assert.equal(pending.departure.scheduledAt, null);
    assert.equal(pending.arrival.scheduledAt, null);
    assert.equal(pending.sync.phase, "schedule");
    assert.equal(pending.sync.nextPollAt?.toISOString(), D10.toISOString());
    assert.equal(pending.flightKey, "XX180_2026-11-01_ICN");

    const found = applyAirportRow(
      { ...pending, trackerCount: 1 },
      row({ flightNumber: "XX180", operatingFlightNumber: "YY180", scheduledAt: DEP, level: "schedule" }),
      D10,
    );
    assert.equal(found.flight.flightKey, "XX180_2026-11-01_ICN");
    assert.equal(found.flight.origin, "airport_data");
    assert.equal(found.flight.operating.flightNumber, "YY180");
    assert.equal(found.flight.operating.airline, "YY");
    assert.ok(found.flight.searchKeys.includes("XX180_2026-11-01"));
    assert.ok(found.flight.searchKeys.includes("YY180_2026-11-01"));
    assert.equal(found.flight.departure.scheduledAt?.toISOString(), DEP.toISOString());
    assert.equal(found.kinds.length, 0);

    const parsed = parseManual(
      { flightNumber: "XX180", departureDate: DATE, departureAirport: "ICN", arrivalAirport: "NRT", awaitAutoData: true },
      D10,
    );
    assert.equal(parsed.awaitAutoData, true);
    assert.equal(parsed.departureTime, null);
    assert.throws(
      () => parseManual({ flightNumber: "XX180", departureDate: DATE, departureAirport: "ICN", arrivalAirport: "NRT" }, D10),
      isInvalid,
    );
  });

  it("도착만 한국이고 시각이 없는 대기 등록은 출발일·다음날 도착을 조회하고 당일 오전에 끝내지 않는다", () => {
    const pending = manualFlight({
      flightNumber: "XX190",
      departureDate: DATE,
      departure: { code: "NRT", ...FACTS.NRT },
      arrival: { code: "ICN", ...FACTS.ICN },
      departureAt: null,
      arrivalAt: null,
      fields: {},
      now: D10,
      awaitAutoData: true,
    });
    const groups = pollGroups({ ...pending, trackerCount: 1 }, "schedule", D10);
    assert.deepEqual(
      groups.map((group) => `${group.airport}:${group.date}:${group.direction}:${group.level}`),
      ["ICN:2026-11-01:arrival:schedule", "ICN:2026-11-02:arrival:schedule"],
    );
    const input = {
      departureDate: DATE,
      timeZone: "Asia/Tokyo",
      departureAt: null,
      arrivalAt: null,
      status: "unknown" as const,
      trackerCount: 1,
      korean: true,
      mode: "normal" as const,
    };
    const morning = planPoll({ ...input, now: new Date("2026-10-31T22:00:00Z") });
    assert.equal(morning.phase, "hourly");
    assert.equal(morning.call, "realtime");
    const afternoon = planPoll({ ...input, now: new Date("2026-11-01T06:00:00Z") });
    assert.equal(afternoon.phase, "hourly");
    assert.equal(planPoll({ ...input, now: new Date("2026-11-02T15:00:00Z") }).phase, "done");
    const found = applyAirportRow(
      { ...pending, trackerCount: 1 },
      row({
        flightNumber: "XX190",
        operatingFlightNumber: "YY190",
        direction: "arrival",
        koreanAirport: "ICN",
        otherAirport: "NRT",
        scheduledAt: new Date("2026-11-02T03:30:00Z"),
        level: "schedule",
      }),
      D10,
    );
    assert.equal(found.flight.flightKey, "XX190_2026-11-01_NRT");
    assert.equal(found.flight.origin, "airport_data");
    assert.equal(found.flight.arrival.scheduledAt?.toISOString(), "2026-11-02T03:30:00.000Z");
  });

  it("같은 운항 편명으로 합칠 때 빈 값이 기존 시각·제보를 지우지 않고 공항 정보와 더 최신 값을 남긴다", () => {
    const older = new Date("2026-10-01T00:00:00Z");
    const newer = new Date("2026-11-01T00:00:00Z");
    const current = draft();
    current.trackerCount = 2;
    current.searchKeys = ["XX100_2026-11-01"];
    current.departure.scheduledAt = DEP;
    current.departure.estimatedAt = { value: DEP, source: "user", updatedAt: older };
    current.departure.gate = { value: "12", source: "user", updatedAt: newer, previousValue: null };
    current.departure.terminal = { value: "T1", source: "airport_data", updatedAt: newer, previousValue: null };
    const incoming = draft({ flightNumber: "YY100", operatingFlightNumber: "YY100" });
    incoming.flightKey = "YY100_2026-11-01_ICN";
    incoming.trackerCount = 1;
    incoming.searchKeys = ["YY100_2026-11-01"];
    incoming.departure.scheduledAt = null;
    incoming.departure.estimatedAt = { value: null, source: null, updatedAt: null };
    incoming.departure.gate = { value: "15", source: "airport_data", updatedAt: older, previousValue: null };
    incoming.departure.terminal = { value: "T2", source: "airport_data", updatedAt: older, previousValue: "T1" };
    const merged = mergeFlightDocs(current, incoming);
    assert.equal(merged.flightKey, "YY100_2026-11-01_ICN");
    assert.equal(merged.trackerCount, 3);
    assert.deepEqual(merged.searchKeys, ["XX100_2026-11-01", "YY100_2026-11-01"]);
    assert.equal(merged.departure.scheduledAt?.toISOString(), DEP.toISOString());
    assert.equal(merged.departure.estimatedAt.value?.toISOString(), DEP.toISOString());
    assert.equal(merged.departure.gate.value, "15");
    assert.equal(merged.departure.gate.source, "airport_data");
    assert.equal(merged.departure.terminal.value, "T1");
    const again = mergeFlightDocs(merged, {
      ...incoming,
      departure: {
        ...incoming.departure,
        terminal: { value: "T2", source: "airport_data", updatedAt: new Date("2026-11-02T00:00:00Z"), previousValue: "T1" },
      },
    });
    assert.equal(again.departure.terminal.value, "T2");
    const sameNow = new Date("2026-11-01T00:00:00Z");
    current.sync.lastSuccessAt = sameNow;
    incoming.sync.lastSuccessAt = sameNow;
    current.sync.nextPollAt = new Date("2026-10-01T00:00:00Z");
    incoming.sync.nextPollAt = new Date("2026-11-02T00:00:00Z");
    incoming.departure.scheduledAt = new Date("2026-11-01T05:00:00Z");
    const tied = mergeFlightDocs(current, incoming);
    assert.equal(tied.departure.scheduledAt?.toISOString(), DEP.toISOString());
    assert.equal(tied.sync.nextPollAt?.toISOString(), "2026-11-02T00:00:00.000Z");
    assert.ok(tied.searchKeys.includes("XX100_2026-11-01"));
    assert.equal(tied.departure.gate.value, "15");
    const fresh = mergeFlightDocs(
      { ...current, sync: { ...current.sync, lastSuccessAt: older } },
      {
        ...incoming,
        sync: { ...incoming.sync, lastSuccessAt: newer },
        departure: { ...incoming.departure, scheduledAt: new Date("2026-11-01T05:00:00Z"), gate: { value: null, source: null, updatedAt: null, previousValue: null } },
      },
    );
    assert.equal(fresh.departure.scheduledAt?.toISOString(), "2026-11-01T05:00:00.000Z");
    assert.equal(fresh.departure.gate.value, "12");
    const freshNull = mergeFlightDocs(
      { ...current, sync: { ...current.sync, lastSuccessAt: older } },
      { ...incoming, sync: { ...incoming.sync, lastSuccessAt: newer }, departure: { ...incoming.departure, scheduledAt: null, gate: { value: null, source: null, updatedAt: null, previousValue: null } } },
    );
    assert.equal(freshNull.departure.scheduledAt?.toISOString(), DEP.toISOString());
    assert.equal(freshNull.departure.gate.value, "12");
  });
});

function isInvalid(error: unknown): boolean {
  return error instanceof AppError && error.errorCode === "invalid-argument";
}
