import type { Direction, FlightStatusValue, ProviderFlight, ProviderId } from "../providers/types";
import { invalidArgument } from "./errors";
import { FLIGHT_NUMBER_PATTERN, type ManualFieldKey, type ManualFields } from "./flightInput";
import { bucketFor, maxRatio, quotaMode, ratioOf, type QuotaBucket, type QuotaCounts, type QuotaMode, stricter } from "./quota";
import { addDays, DAY, HOUR, localDate, MINUTE, startOfLocalDay, TIME_CHANGE } from "./time";

export type Source = "airport_data" | "user";
export type Origin = Source | "pending";
export type Phase = "schedule" | "hourly" | "frequent" | "done";
export type DataLevel = "realtime" | "schedule" | "user";
export type NotFoundReason = "no_korean_airport_data" | "not_in_schedule" | "outside_schedule_season";
export type PollCall = "realtime" | "schedule" | "none";

export type ChangeKind =
  | "departureTime"
  | "cancelled"
  | "departureTerminal"
  | "gateAssigned"
  | "gateChanged"
  | "arrivalTime"
  | "baggageAssigned";

export type ChangeEvent = { flightKey: string; kinds: ChangeKind[] };

export type InfoValue = {
  value: string | null;
  source: Source | null;
  updatedAt: Date | null;
  previousValue: string | null;
};

export type TimeValue = { value: Date | null; source: Source | null; updatedAt: Date | null };

export type StatusValue = { value: FlightStatusValue; source: Source | null; updatedAt: Date | null };

export type Side = {
  airport: string;
  timeZone: string;
  scheduledAt: Date | null;
  estimatedAt: TimeValue;
  terminal: InfoValue;
  gate: InfoValue;
  checkInCounter: InfoValue | null;
  baggageBelt: InfoValue | null;
  autoDataSupported: boolean;
};

export type SyncState = {
  phase: Phase;
  nextPollAt: Date | null;
  lastSuccessAt: Date | null;
  lastFailureAt: Date | null;
  consecutiveFailures: number;
  provider: string | null;
};

export type FlightDoc = {
  flightKey: string;
  operating: { airline: string; flightNumber: string };
  searchKeys: string[];
  origin: Origin;
  departure: Side;
  arrival: Side;
  status: StatusValue;
  sync: SyncState;
  trackerCount: number;
};

export type AirportFacts = { timeZone: string; korean: boolean; terminals: readonly string[] };
export type Facts = (code: string) => AirportFacts | null;

/** data 모듈이 목록을 내보내기 전까지 검색 대상. 한국 공항이 늘면 여기도 추가한다. */
export const KOREAN_AIRPORT_CODES = [
  "CJJ", "CJU", "GMP", "HIN", "ICN", "KPO", "KUV", "KWJ", "MWX", "PUS", "RSU", "TAE", "USN", "WJU", "YNY",
] as const;

export function bundleKinds(kinds: readonly ChangeKind[]): ChangeKind[] {
  return KIND_ORDER.filter((kind) => kinds.includes(kind));
}

const KIND_ORDER: ChangeKind[] = [
  "departureTime",
  "cancelled",
  "departureTerminal",
  "gateAssigned",
  "gateChanged",
  "arrivalTime",
  "baggageAssigned",
];

const STATUS_RANK: Record<FlightStatusValue, number> = {
  unknown: 0,
  scheduled: 1,
  delayed: 2,
  departed: 3,
  arrived: 4,
  cancelled: 5,
};

export function airlineOf(flightNumber: string): string {
  return /^([A-Z0-9]{2}[A-Z]?)[0-9]/.exec(flightNumber)?.[1] ?? flightNumber.slice(0, 2);
}

export function flightKey(operating: string, date: string, origin: string): string {
  return `${operating}_${date}_${origin}`;
}

export function searchKey(number: string, date: string): string {
  return `${number}_${date}`;
}

const FLIGHT_KEY_RE = new RegExp(`^(${FLIGHT_NUMBER_PATTERN})_(\\d{4}-\\d{2}-\\d{2})_([A-Z]{3})$`);

export function parseFlightKey(key: string): { flightNumber: string; date: string; origin: string } | null {
  const match = FLIGHT_KEY_RE.exec(key);
  if (!match) return null;
  return { flightNumber: match[1], date: match[2], origin: match[3] };
}

export function providerIdFor(airport: string, korean: boolean): ProviderId | null {
  if (!korean) return null;
  return airport === "ICN" ? "iiac" : "kac";
}

export function hasKorean(flight: FlightDoc): boolean {
  return flight.departure.autoDataSupported || flight.arrival.autoDataSupported;
}

export function departureInstant(flight: FlightDoc): Date | null {
  return flight.departure.estimatedAt.value ?? flight.departure.scheduledAt;
}

export function arrivalInstant(flight: FlightDoc): Date | null {
  return flight.arrival.estimatedAt.value ?? flight.arrival.scheduledAt;
}

export function scheduledDepartureAt(flight: FlightDoc): Date {
  if (flight.departure.scheduledAt) return flight.departure.scheduledAt;
  const parsed = parseFlightKey(flight.flightKey);
  return startOfLocalDay(parsed?.date ?? "1970-01-01", flight.departure.timeZone || "UTC");
}

/** 조회일 D-3~D+6(서울)이면 운항 현황, 그 밖은 시간표. */
export function providerLevel(departureDate: string, today: string): "realtime" | "schedule" {
  return departureDate >= addDays(today, -3) && departureDate <= addDays(today, 6) ? "realtime" : "schedule";
}

/**
 * 시간표 구간에 없으면 한국 공항 데이터로 못 찾는 것, 운항 현황 구간에 없으면 일정에 없는 것.
 * D-3 전이고 요청일이 응답에서 본 lastdate보다 뒤면 공개 시즌 밖이다.
 */
export function notFoundReason(
  level: "realtime" | "schedule",
  season?: { departureDate: string; today: string; seasonLastDate: string | null },
): NotFoundReason {
  if (
    level === "schedule" &&
    season &&
    season.departureDate > addDays(season.today, 3) &&
    season.seasonLastDate !== null &&
    season.departureDate > season.seasonLastDate
  ) {
    return "outside_schedule_season";
  }
  return level === "schedule" ? "no_korean_airport_data" : "not_in_schedule";
}

export function dataLevelOf(flight: FlightDoc): DataLevel {
  if (flight.origin === "user") return "user";
  return flight.sync.phase === "schedule" ? "schedule" : "realtime";
}

export function searchBuckets(level: "realtime" | "schedule"): QuotaBucket[] {
  const buckets = new Set<QuotaBucket>();
  for (const code of KOREAN_AIRPORT_CODES) {
    const provider = providerIdFor(code, true);
    if (!provider) continue;
    buckets.add(bucketFor(provider, level, "departure"));
    buckets.add(bucketFor(provider, level, "arrival"));
  }
  return [...buckets];
}

export function searchBlocked(counts: QuotaCounts, level: "realtime" | "schedule"): boolean {
  return quotaMode(maxRatio(counts, searchBuckets(level))) === "frequentOnly";
}

export type BuiltDraft = { flight: FlightDoc; dataLevel: "realtime" | "schedule" };

export function buildDrafts(
  rows: readonly ProviderFlight[],
  query: { flightNumber: string; departureDate: string },
  facts: Facts,
  now: Date,
): BuiltDraft[] {
  const groups = new Map<string, { rows: ProviderFlight[]; numbers: Set<string> }>();
  for (const row of rows) {
    if (row.flightNumber !== query.flightNumber && row.operatingFlightNumber !== query.flightNumber) continue;
    const origin = row.direction === "departure" ? row.koreanAirport : row.otherAirport;
    if (!origin) continue;
    if (!rowOnQueryDate(row, query.departureDate, facts)) continue;
    const key = flightKey(row.operatingFlightNumber, query.departureDate, origin);
    const group = groups.get(key) ?? { rows: [], numbers: new Set<string>() };
    group.rows.push(row);
    group.numbers.add(row.flightNumber);
    group.numbers.add(row.operatingFlightNumber);
    group.numbers.add(query.flightNumber);
    groups.set(key, group);
  }

  return [...groups.entries()].map(([key, group]) => {
    const parsed = parseFlightKey(key);
    const sample = group.rows[0];
    const origin = parsed?.origin ?? "";
    const destination = destinationOf(group.rows);
    let flight = blankFlight(key, sample.operatingFlightNumber, origin, destination, facts);
    for (const row of group.rows) flight = fillRow(flight, row, facts, now);
    flight.searchKeys = keysOf(sample.operatingFlightNumber, group.numbers, query.departureDate);
    flight.sync.provider = syncProvider(flight);
    const dataLevel = group.rows.some((row) => row.level === "realtime") ? "realtime" : "schedule";
    return { flight, dataLevel };
  });
}

export function planPoll(input: {
  now: Date;
  departureDate: string;
  timeZone: string;
  departureAt: Date | null;
  arrivalAt: Date | null;
  status: FlightStatusValue;
  trackerCount: number;
  korean: boolean;
  mode: QuotaMode;
}): { phase: Phase; nextPollAt: Date | null; call: PollCall } {
  if (input.trackerCount <= 0 || !input.korean) return { phase: "done", nextPollAt: null, call: "none" };
  const timed = input.departureAt;
  // 시각이 없으면 출발일 자정이 아니라 다음날 끝까지 본다. 자정+6시간이면 당일 오전에 끝난다.
  const horizon = startOfLocalDay(addDays(input.departureDate, 2), input.timeZone).getTime();
  const end = input.arrivalAt ? input.arrivalAt.getTime() + HOUR : timed ? timed.getTime() + 6 * HOUR : horizon;
  if (input.now.getTime() >= end) return { phase: "done", nextPollAt: null, call: "none" };
  if (input.status === "cancelled" && input.departureAt && input.now.getTime() >= input.departureAt.getTime()) {
    return { phase: "done", nextPollAt: null, call: "none" };
  }

  const d3 = startOfLocalDay(addDays(input.departureDate, -3), input.timeZone).getTime();
  const frequentAt = timed ? timed.getTime() - 6 * HOUR : end;
  const phase: Phase = input.now.getTime() < d3 ? "schedule" : input.now.getTime() < frequentAt ? "hourly" : "frequent";
  if (input.mode === "frequentOnly" && phase !== "frequent") {
    return { phase, nextPollAt: new Date(input.now.getTime() + HOUR), call: "none" };
  }
  if (phase === "schedule") {
    const daily = input.now.getTime() + DAY;
    const next = d3 < daily && d3 > input.now.getTime() ? d3 : daily;
    return { phase, nextPollAt: new Date(next), call: "schedule" };
  }
  if (phase === "hourly") {
    const interval = input.mode === "stretched" ? 3 * HOUR : HOUR;
    let next = input.now.getTime() + interval;
    if (frequentAt < next && frequentAt > input.now.getTime()) next = frequentAt;
    return { phase, nextPollAt: new Date(next), call: "realtime" };
  }
  return { phase, nextPollAt: new Date(input.now.getTime() + 15 * MINUTE), call: "realtime" };
}

export function planFlight(flight: FlightDoc, now: Date, mode: QuotaMode) {
  const parsed = parseFlightKey(flight.flightKey);
  return planPoll({
    now,
    departureDate: parsed?.date ?? "1970-01-01",
    timeZone: flight.departure.timeZone || "UTC",
    departureAt: departureInstant(flight),
    arrivalAt: arrivalInstant(flight),
    status: flight.status.value,
    trackerCount: flight.trackerCount,
    korean: hasKorean(flight),
    mode,
  });
}

export function modeFor(counts: QuotaCounts, flight: FlightDoc, call: PollCall, now: Date): QuotaMode {
  if (call === "none") return "normal";
  let mode: QuotaMode = "normal";
  for (const group of pollGroups(flight, call, now)) {
    const bucket = bucketFor(group.provider, group.level === "gates" ? "gates" : group.level, group.direction);
    mode = stricter(mode, quotaMode(ratioOf(counts, bucket)));
  }
  return mode;
}

export type PollGroup = {
  provider: ProviderId;
  airport: string;
  date: string;
  direction: Direction;
  level: "realtime" | "schedule" | "gates";
};

export function pollGroups(flight: FlightDoc, call: "realtime" | "schedule", now: Date): PollGroup[] {
  const groups: PollGroup[] = [];
  const keyDate = parseFlightKey(flight.flightKey)?.date ?? null;
  for (const direction of ["departure", "arrival"] as const) {
    const side = flight[direction];
    if (!side.autoDataSupported) continue;
    const provider = providerIdFor(side.airport, true);
    if (!provider) continue;
    const dates = side.scheduledAt
      ? [localDate(side.scheduledAt, side.timeZone)]
      : !keyDate
        ? []
        : direction === "arrival"
          ? [keyDate, addDays(keyDate, 1)]
          : [keyDate];
    const level = call === "schedule" ? "schedule" : "realtime";
    for (const date of dates) {
      groups.push({ provider, airport: side.airport, date, direction, level });
      if (level === "realtime" && provider === "kac" && localDate(now, side.timeZone) === date) {
        groups.push({ provider, airport: side.airport, date: "-", direction, level: "gates" });
      }
    }
  }
  return groups;
}

export function rowMatches(flight: FlightDoc, row: ProviderFlight): boolean {
  const airport = row.direction === "departure" ? flight.departure.airport : flight.arrival.airport;
  if (row.koreanAirport !== airport) return false;
  const date = parseFlightKey(flight.flightKey)?.date ?? "";
  const numbers = new Set<string>([flight.operating.flightNumber]);
  for (const key of flight.searchKeys) {
    const suffix = `_${date}`;
    if (key.endsWith(suffix)) numbers.add(key.slice(0, -suffix.length));
  }
  return numbers.has(row.flightNumber) || numbers.has(row.operatingFlightNumber);
}

export function applyAirportRow(flight: FlightDoc, row: ProviderFlight, now: Date): { flight: FlightDoc; kinds: ChangeKind[] } {
  const kinds: ChangeKind[] = [];
  let next = copyFlight(flight);
  const promote = flight.origin === "pending";
  const parsed = parseFlightKey(flight.flightKey);
  if (parsed && row.operatingFlightNumber !== next.operating.flightNumber) {
    next.operating = { airline: airlineOf(row.operatingFlightNumber), flightNumber: row.operatingFlightNumber };
    if (!promote) next.flightKey = flightKey(row.operatingFlightNumber, parsed.date, parsed.origin);
  }
  const date = parsed?.date ?? "";
  for (const number of [row.flightNumber, row.operatingFlightNumber]) {
    const key = searchKey(number, date);
    if (number && !next.searchKeys.includes(key)) next.searchKeys.push(key);
  }
  if (row.direction === "departure") next.departure = mergeSide(next.departure, row, now, kinds, "departure");
  else next.arrival = mergeSide(next.arrival, row, now, kinds, "arrival");
  next.status = mergeStatus(next.status, row.status, now, kinds);
  if (promote) next.origin = "airport_data";
  return { flight: next, kinds: KIND_ORDER.filter((kind) => kinds.includes(kind)) };
}

export function applyGate(flight: FlightDoc, direction: Direction, gate: string | null, now: Date): { flight: FlightDoc; kinds: ChangeKind[] } {
  if (gate === null) return { flight, kinds: [] };
  const next = copyFlight(flight);
  const side = next[direction];
  const merged = mergeInfo(side.gate, gate, now);
  side.gate = merged.item;
  const kinds: ChangeKind[] = [];
  if (merged.changed && direction === "departure") kinds.push(merged.from === null ? "gateAssigned" : "gateChanged");
  return { flight: next, kinds };
}

export function markSuccess(sync: SyncState, plan: { phase: Phase; nextPollAt: Date | null }, now: Date): SyncState {
  return { ...sync, phase: plan.phase, nextPollAt: plan.nextPollAt, lastSuccessAt: now, consecutiveFailures: 0 };
}

export function markFailure(sync: SyncState, plan: { phase: Phase; nextPollAt: Date | null }, now: Date): SyncState {
  return {
    ...sync,
    phase: plan.phase,
    nextPollAt: plan.nextPollAt,
    lastFailureAt: now,
    consecutiveFailures: sync.consecutiveFailures + 1,
  };
}

export function stampPlan(flight: FlightDoc, now: Date, mode: QuotaMode, dueNow: boolean): FlightDoc {
  const plan = planFlight(flight, now, mode);
  return {
    ...flight,
    sync: {
      ...flight.sync,
      phase: plan.phase,
      nextPollAt: dueNow && plan.call !== "none" ? now : plan.nextPollAt,
      provider: syncProvider(flight),
    },
  };
}

export function manualFlight(input: {
  flightNumber: string;
  departureDate: string;
  departure: AirportFacts & { code: string };
  arrival: AirportFacts & { code: string };
  departureAt: Date | null;
  arrivalAt: Date | null;
  fields: ManualFields;
  now: Date;
  awaitAutoData?: boolean;
}): FlightDoc {
  if (input.awaitAutoData && !input.departure.korean && !input.arrival.korean) throw invalidArgument();
  if (!input.awaitAutoData && !input.departureAt) throw invalidArgument();
  const key = flightKey(input.flightNumber, input.departureDate, input.departure.code);
  let flight = blankFlight(key, input.flightNumber, input.departure.code, input.arrival.code, (code) => {
    if (code === input.departure.code) return input.departure;
    if (code === input.arrival.code) return input.arrival;
    return null;
  });
  flight.origin = input.awaitAutoData ? "pending" : "user";
  flight.departure.scheduledAt = input.departureAt;
  flight.arrival.scheduledAt = input.arrivalAt;
  if (!input.awaitAutoData) flight.status = { value: "scheduled", source: "user", updatedAt: input.now };
  flight.searchKeys = [searchKey(input.flightNumber, input.departureDate)];
  flight = applyUserFields(flight, input.fields, input.now);
  flight.trackerCount = 1;
  flight = stampPlan(flight, input.now, "normal", Boolean(input.awaitAutoData) || hasKorean(flight));
  if (input.awaitAutoData) flight.sync = { ...flight.sync, phase: "schedule", nextPollAt: input.now };
  flight.trackerCount = 0;
  return flight;
}

export function applyUserFields(flight: FlightDoc, fields: ManualFields, now: Date): FlightDoc {
  const next = copyFlight(flight);
  for (const [key, value] of Object.entries(fields) as Array<[ManualFieldKey, string | null]>) {
    const [direction, name] = key.split(".") as [Direction, "terminal" | "gate" | "checkInCounter" | "baggageBelt"];
    const side = next[direction];
    const item = value === null ? emptyInfo() : userItem(value, now);
    if (name === "checkInCounter") side.checkInCounter = item;
    else if (name === "baggageBelt") side.baggageBelt = item;
    else side[name] = item;
  }
  return next;
}

export function syncProvider(flight: FlightDoc): string | null {
  if (flight.departure.autoDataSupported) return providerIdFor(flight.departure.airport, true);
  if (flight.arrival.autoDataSupported) return providerIdFor(flight.arrival.airport, true);
  return null;
}

function rowOnQueryDate(row: ProviderFlight, departureDate: string, facts: Facts): boolean {
  const zone = facts(row.koreanAirport)?.timeZone ?? "Asia/Seoul";
  const date = localDate(row.scheduledAt, zone);
  if (row.direction === "departure") return date === departureDate;
  return date === departureDate || date === addDays(departureDate, 1);
}

function destinationOf(rows: readonly ProviderFlight[]): string {
  for (const row of rows) {
    if (row.direction === "departure" && row.otherAirport) return row.otherAirport;
  }
  for (const row of rows) {
    if (row.direction === "arrival") return row.koreanAirport;
  }
  return "UNK";
}

function fillRow(flight: FlightDoc, row: ProviderFlight, facts: Facts, now: Date): FlightDoc {
  const next = copyFlight(flight);
  const korean = facts(row.koreanAirport) ?? { timeZone: "Asia/Seoul", korean: true, terminals: [] };
  if (row.direction === "departure") {
    if (row.otherAirport && (next.arrival.airport === "UNK" || next.arrival.airport === next.departure.airport)) {
      const other = facts(row.otherAirport) ?? { timeZone: "UTC", korean: false, terminals: [] };
      next.arrival = emptySide(row.otherAirport, other.timeZone, other.korean, "arrival");
    }
    next.departure = { ...emptySide(row.koreanAirport, korean.timeZone, korean.korean, "departure"), ...kept(next.departure) };
    next.departure = writeInitial(next.departure, row, now);
  } else {
    if (row.otherAirport && (next.departure.airport === "UNK" || !next.departure.airport)) {
      const other = facts(row.otherAirport) ?? { timeZone: "UTC", korean: false, terminals: [] };
      next.departure = emptySide(row.otherAirport, other.timeZone, other.korean, "departure");
    }
    next.arrival = writeInitial(
      { ...emptySide(row.koreanAirport, korean.timeZone, korean.korean, "arrival"), ...kept(next.arrival) },
      row,
      now,
    );
  }
  next.status = preferStatus(next.status, row.status, now);
  return next;
}

function kept(side: Side): Partial<Side> {
  return {
    scheduledAt: side.scheduledAt,
    estimatedAt: side.estimatedAt,
    terminal: side.terminal,
    gate: side.gate,
    checkInCounter: side.checkInCounter,
    baggageBelt: side.baggageBelt,
  };
}

function writeInitial(side: Side, row: ProviderFlight, now: Date): Side {
  const next = { ...side, airport: row.direction === "departure" ? row.koreanAirport : side.airport };
  if (row.direction === "departure") next.airport = row.koreanAirport;
  else next.airport = row.koreanAirport;
  next.scheduledAt = row.scheduledAt;
  if (row.estimatedAt) next.estimatedAt = { value: row.estimatedAt, source: "airport_data", updatedAt: now };
  if (row.terminal) next.terminal = airportItem(row.terminal, null, now);
  if (row.gate) next.gate = airportItem(row.gate, null, now);
  if (row.direction === "departure" && row.checkInCounter && next.checkInCounter) {
    next.checkInCounter = airportItem(row.checkInCounter, null, now);
  }
  if (row.direction === "arrival" && row.baggageBelt && next.baggageBelt) {
    next.baggageBelt = airportItem(row.baggageBelt, null, now);
  }
  return next;
}

function mergeSide(side: Side, row: ProviderFlight, now: Date, kinds: ChangeKind[], direction: Direction): Side {
  const before = side.estimatedAt.value ?? side.scheduledAt;
  const scheduledAt = nextInstant(side.scheduledAt, row.scheduledAt, side.scheduledAt);
  const estimatedValue = nextInstant(side.estimatedAt.value, row.estimatedAt, scheduledAt);
  const after = estimatedValue ?? scheduledAt;
  if (before && after && Math.abs(after.getTime() - before.getTime()) >= TIME_CHANGE) {
    kinds.push(direction === "departure" ? "departureTime" : "arrivalTime");
  }
  const terminal = mergeInfo(side.terminal, row.terminal, now);
  const gate = mergeInfo(side.gate, row.gate, now);
  if (direction === "departure" && terminal.changed) kinds.push("departureTerminal");
  if (direction === "departure" && gate.changed) kinds.push(gate.from === null ? "gateAssigned" : "gateChanged");
  const checkIn = side.checkInCounter ? mergeInfo(side.checkInCounter, row.checkInCounter, now) : null;
  const belt = side.baggageBelt ? mergeInfo(side.baggageBelt, row.baggageBelt, now) : null;
  if (direction === "arrival" && belt?.changed && belt.from === null) kinds.push("baggageAssigned");
  return {
    ...side,
    scheduledAt,
    estimatedAt: estimatedValue
      ? { value: estimatedValue, source: "airport_data", updatedAt: estimatedValue.getTime() === side.estimatedAt.value?.getTime() ? side.estimatedAt.updatedAt : now }
      : side.estimatedAt,
    terminal: terminal.item,
    gate: gate.item,
    checkInCounter: checkIn?.item ?? side.checkInCounter,
    baggageBelt: belt?.item ?? side.baggageBelt,
  };
}

function nextInstant(current: Date | null, incoming: Date | null, baseline: Date | null): Date | null {
  if (incoming === null) return current;
  const compare = current ?? baseline;
  if (compare && Math.abs(incoming.getTime() - compare.getTime()) < TIME_CHANGE) return current;
  return incoming;
}

function mergeInfo(current: InfoValue, incoming: string | null, now: Date): { item: InfoValue; from: string | null; changed: boolean } {
  if (incoming === null || incoming === current.value) {
    if (incoming !== null && incoming === current.value && current.source !== "airport_data") {
      return { item: { ...current, source: "airport_data", updatedAt: now }, from: current.value, changed: false };
    }
    return { item: current, from: current.value, changed: false };
  }
  return {
    item: airportItem(incoming, current.value, now),
    from: current.value,
    changed: true,
  };
}

function mergeStatus(current: StatusValue, incoming: FlightStatusValue, now: Date, kinds: ChangeKind[]): StatusValue {
  if (incoming === "unknown" || (incoming === current.value && current.source === "airport_data")) return current;
  if (incoming === "cancelled" && current.value !== "cancelled") kinds.push("cancelled");
  return { value: incoming, source: "airport_data", updatedAt: now };
}

function preferStatus(current: StatusValue, incoming: FlightStatusValue, now: Date): StatusValue {
  if (incoming === "unknown") return current;
  if (STATUS_RANK[incoming] < STATUS_RANK[current.value]) return current;
  if (incoming === current.value && current.source === "airport_data") return current;
  return { value: incoming, source: "airport_data", updatedAt: now };
}

function blankFlight(key: string, operating: string, origin: string, destination: string, facts: Facts): FlightDoc {
  const originFacts = facts(origin) ?? { timeZone: "UTC", korean: false, terminals: [] };
  const destFacts = facts(destination) ?? { timeZone: "UTC", korean: false, terminals: [] };
  return {
    flightKey: key,
    operating: { airline: airlineOf(operating), flightNumber: operating },
    searchKeys: [],
    origin: "airport_data",
    departure: emptySide(origin, originFacts.timeZone, originFacts.korean, "departure"),
    arrival: emptySide(destination, destFacts.timeZone, destFacts.korean, "arrival"),
    status: { value: "unknown", source: null, updatedAt: null },
    sync: {
      phase: "schedule",
      nextPollAt: null,
      lastSuccessAt: null,
      lastFailureAt: null,
      consecutiveFailures: 0,
      provider: null,
    },
    trackerCount: 0,
  };
}

function emptySide(airport: string, timeZone: string, korean: boolean, direction: Direction): Side {
  return {
    airport,
    timeZone,
    scheduledAt: null,
    estimatedAt: emptyTime(),
    terminal: emptyInfo(),
    gate: emptyInfo(),
    checkInCounter: direction === "departure" ? emptyInfo() : null,
    baggageBelt: direction === "arrival" ? emptyInfo() : null,
    autoDataSupported: korean,
  };
}

function emptyInfo(): InfoValue {
  return { value: null, source: null, updatedAt: null, previousValue: null };
}

function emptyTime(): TimeValue {
  return { value: null, source: null, updatedAt: null };
}

function airportItem(value: string, previous: string | null, now: Date): InfoValue {
  return { value, source: "airport_data", updatedAt: now, previousValue: previous };
}

function userItem(value: string, now: Date): InfoValue {
  return { value, source: "user", updatedAt: now, previousValue: null };
}

export function mergeFlightDocs(current: FlightDoc, incoming: FlightDoc): FlightDoc {
  const searchKeys = [...current.searchKeys];
  for (const key of incoming.searchKeys) if (!searchKeys.includes(key)) searchKeys.push(key);
  const incomingNewer = (incoming.sync.lastSuccessAt?.getTime() ?? -1) > (current.sync.lastSuccessAt?.getTime() ?? -1);
  return {
    ...incoming,
    flightKey: incoming.flightKey,
    operating: incoming.operating.flightNumber ? incoming.operating : current.operating,
    searchKeys,
    origin: current.origin === "airport_data" || incoming.origin === "airport_data" ? "airport_data" : current.origin === "user" || incoming.origin === "user" ? "user" : "pending",
    departure: mergeSideDocs(current.departure, incoming.departure, incomingNewer),
    arrival: mergeSideDocs(current.arrival, incoming.arrival, incomingNewer),
    status: mergeStatusValue(current.status, incoming.status),
    sync: mergeSync(current.sync, incoming.sync),
    trackerCount: current.trackerCount + incoming.trackerCount,
  };
}

function mergeSideDocs(current: Side, incoming: Side, incomingNewer: boolean): Side {
  return {
    airport: incoming.airport && incoming.airport !== "UNK" ? incoming.airport : current.airport,
    timeZone: incoming.timeZone || current.timeZone,
    scheduledAt: incomingNewer ? incoming.scheduledAt ?? current.scheduledAt : current.scheduledAt ?? incoming.scheduledAt,
    estimatedAt: mergeTimeValue(current.estimatedAt, incoming.estimatedAt),
    terminal: mergeInfoValue(current.terminal, incoming.terminal),
    gate: mergeInfoValue(current.gate, incoming.gate),
    checkInCounter: mergeOptionalInfo(current.checkInCounter, incoming.checkInCounter),
    baggageBelt: mergeOptionalInfo(current.baggageBelt, incoming.baggageBelt),
    autoDataSupported: current.autoDataSupported || incoming.autoDataSupported,
  };
}

function mergeOptionalInfo(current: InfoValue | null, incoming: InfoValue | null): InfoValue | null {
  if (!current) return incoming;
  if (!incoming) return current;
  return mergeInfoValue(current, incoming);
}

function mergeInfoValue(current: InfoValue, incoming: InfoValue): InfoValue {
  if (incoming.value === null) return current;
  if (current.value === null) return incoming;
  return preferSource(current, incoming);
}

function mergeTimeValue(current: TimeValue, incoming: TimeValue): TimeValue {
  if (incoming.value === null) return current;
  if (current.value === null) return incoming;
  return preferSource(current, incoming);
}

function mergeStatusValue(current: StatusValue, incoming: StatusValue): StatusValue {
  if (incoming.value === "unknown" || incoming.source === null) return current.value === "unknown" ? incoming : current;
  if (current.value === "unknown" || current.source === null) return incoming;
  return preferSource(current, incoming);
}

function preferSource<T extends { source: Source | null; updatedAt: Date | null }>(current: T, incoming: T): T {
  if (current.source === "airport_data" && incoming.source !== "airport_data") return current;
  if (incoming.source === "airport_data" && current.source !== "airport_data") return incoming;
  return (incoming.updatedAt?.getTime() ?? 0) >= (current.updatedAt?.getTime() ?? 0) ? incoming : current;
}

function mergeSync(current: SyncState, incoming: SyncState): SyncState {
  const currentAt = current.lastSuccessAt?.getTime() ?? -1;
  const incomingAt = incoming.lastSuccessAt?.getTime() ?? -1;
  const base = incomingAt >= currentAt ? incoming : current;
  return { ...base, provider: base.provider ?? current.provider ?? incoming.provider };
}

function keysOf(operating: string, numbers: Set<string>, date: string): string[] {
  const rest = [...numbers].filter((number) => number !== operating).sort();
  return [operating, ...rest].map((number) => searchKey(number, date));
}

function copyFlight(flight: FlightDoc): FlightDoc {
  return {
    ...flight,
    operating: { ...flight.operating },
    searchKeys: [...flight.searchKeys],
    departure: copySide(flight.departure),
    arrival: copySide(flight.arrival),
    status: { ...flight.status },
    sync: { ...flight.sync },
  };
}

function copySide(side: Side): Side {
  return {
    ...side,
    estimatedAt: { ...side.estimatedAt },
    terminal: { ...side.terminal },
    gate: { ...side.gate },
    checkInCounter: side.checkInCounter ? { ...side.checkInCounter } : null,
    baggageBelt: side.baggageBelt ? { ...side.baggageBelt } : null,
  };
}
