import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { before, describe, it } from "node:test";
import { Timestamp } from "firebase-admin/firestore";
import { quotaDocId } from "../../src/domain/quota";
import { addDays, seoulToday } from "../../src/domain/time";
import { firestore } from "../../src/store/db";
import { runPollFlights } from "../../src/store/flights";

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error("에뮬레이터 환경변수가 없습니다. npm run test:emulator 로 실행하세요.");
  }
});

function projectId(): string {
  return process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "demo-dflight";
}

async function signUp(): Promise<{ uid: string; idToken: string }> {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
  const res = await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      email: `user-${randomUUID()}@example.com`,
      password: "test-password",
      returnSecureToken: true,
    }),
  });
  const body = (await res.json()) as { localId?: string; idToken?: string };
  if (!res.ok || !body.localId || !body.idToken) throw new Error(`auth emulator signup failed: ${res.status}`);
  return { uid: body.localId, idToken: body.idToken };
}

async function callFn(name: string, data: unknown, idToken: string): Promise<{ status: number; body: { result?: Record<string, unknown>; error?: { status?: string } } }> {
  const res = await fetch(`http://127.0.0.1:5001/${projectId()}/asia-northeast3/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-firebase-appcheck": "emulator",
      authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data }),
  });
  const text = await res.text();
  return { status: res.status, body: JSON.parse(text) as { result?: Record<string, unknown>; error?: { status?: string } } };
}

async function clearFixture(seasonLastDate: string | null): Promise<void> {
  const db = firestore();
  const rows = await db.collection("system/providerFixture/rows").get();
  const batch = db.batch();
  for (const doc of rows.docs) batch.delete(doc.ref);
  batch.set(db.doc("system/providerFixture"), { calls: 1, ...(seasonLastDate ? { seasonLastDate } : {}) });
  await batch.commit();
}

describe("항공편 에뮬레이터", () => {
  it("TD-18 시즌 밖 검색은 outside_schedule_season, 대기 등록은 조회되면 키를 유지한다", async () => {
    const now = new Date();
    const today = seoulToday(now);
    const date = addDays(today, 200);
    const seasonLastDate = addDays(today, 30);
    await clearFixture(seasonLastDate);
    const user = await signUp();

    const missed = await callFn("searchFlight", { flightNumber: "XX180", departureDate: date }, user.idToken);
    assert.equal(missed.body.error, undefined);
    assert.deepEqual(missed.body.result?.candidates, []);
    assert.equal(missed.body.result?.notFoundReason, "outside_schedule_season");

    const foreign = await callFn(
      "createManualFlight",
      { flightNumber: "XX181", departureDate: date, departureAirport: "NRT", arrivalAirport: "KIX", awaitAutoData: true },
      user.idToken,
    );
    assert.equal(foreign.body.error?.status, "INVALID_ARGUMENT");

    const created = await callFn(
      "createManualFlight",
      { flightNumber: "XX180", departureDate: date, departureAirport: "ICN", arrivalAirport: "NRT", awaitAutoData: true },
      user.idToken,
    );
    const flightKey = "XX180_" + date + "_ICN";
    assert.equal(created.body.result?.flightKey, flightKey);
    const before = await firestore().doc(`flights/${flightKey}`).get();
    assert.equal(before.get("origin"), "pending");
    assert.equal(before.get("departure.scheduledAt"), null);
    assert.equal(before.get("sync.phase"), "schedule");
    assert.ok(before.get("sync.nextPollAt"));

    await firestore().doc("system/providerFixture/rows/xx180").set({
      airport: "ICN",
      date,
      direction: "departure",
      level: "schedule",
      flightNumber: "XX180",
      operatingFlightNumber: "YY180",
      koreanAirport: "ICN",
      otherAirport: "NRT",
      scheduledAt: `${date}T01:00:00.000Z`,
      status: "scheduled",
    });
    process.env.FUNCTIONS_EMULATOR = "true";
    await runPollFlights(new Date(now.getTime() + 60_000), "test-key");

    const after = await firestore().doc(`flights/${flightKey}`).get();
    assert.equal(after.exists, true);
    assert.equal(after.get("origin"), "airport_data");
    assert.equal(after.get("operating.flightNumber"), "YY180");
    assert.ok((after.get("searchKeys") as string[]).includes(`YY180_${date}`));
    assert.equal(after.get("departure.scheduledAt")?.toDate?.().toISOString(), `${date}T01:00:00.000Z`);
    const renamed = await firestore().doc(`flights/YY180_${date}_ICN`).get();
    assert.equal(renamed.exists, false);
  });

  it("시각 없는 NRT→ICN 대기 등록은 도착 일정으로 승격된다", async () => {
    const now = new Date();
    const date = addDays(seoulToday(now), 200);
    await clearFixture(null);
    const user = await signUp();
    const created = await callFn(
      "createManualFlight",
      { flightNumber: "XX191", departureDate: date, departureAirport: "NRT", arrivalAirport: "ICN", awaitAutoData: true },
      user.idToken,
    );
    const flightKey = `XX191_${date}_NRT`;
    assert.equal(created.body.result?.flightKey, flightKey);
    await firestore().doc("system/providerFixture/rows/xx191").set({
      airport: "ICN",
      date,
      direction: "arrival",
      level: "schedule",
      flightNumber: "XX191",
      operatingFlightNumber: "XX191",
      koreanAirport: "ICN",
      otherAirport: "NRT",
      scheduledAt: `${date}T03:30:00.000Z`,
      status: "scheduled",
    });
    process.env.FUNCTIONS_EMULATOR = "true";
    await runPollFlights(new Date(now.getTime() + 60_000), "test-key");
    const after = await firestore().doc(`flights/${flightKey}`).get();
    assert.equal(after.get("origin"), "airport_data");
    assert.equal(after.get("arrival.scheduledAt")?.toDate?.().toISOString(), `${date}T03:30:00.000Z`);
    assert.equal((await firestore().doc(`flights/XX191_${date}_ICN`).get()).exists, false);
  });

  it("코드쉐어 이전은 추적 문서의 키와 출발 시각을 같이 바꾼다", async () => {
    const now = new Date();
    const date = addDays(seoulToday(now), 180);
    await clearFixture(null);
    const user = await signUp();
    const oldKey = `XX192_${date}_ICN`;
    const newKey = `YY192_${date}_ICN`;
    const scheduledAt = Timestamp.fromDate(new Date(`${date}T01:00:00.000Z`));
    await firestore().doc(`flights/${oldKey}`).set({
      operating: { airline: "XX", flightNumber: "XX192" },
      searchKeys: [`XX192_${date}`],
      origin: "airport_data",
      departure: side("ICN", "Asia/Seoul", true, scheduledAt),
      arrival: side("NRT", "Asia/Tokyo", false, null),
      status: { value: "scheduled", source: "airport_data", updatedAt: Timestamp.fromDate(now) },
      sync: { phase: "schedule", nextPollAt: Timestamp.fromDate(now), lastSuccessAt: null, lastFailureAt: null, consecutiveFailures: 0, provider: "iiac" },
      trackerCount: 1,
    });
    await firestore().doc(`users/${user.uid}/trackedFlights/track-xx192`).set({
      flightKey: oldKey,
      enteredFlightNumber: "XX192",
      departureDate: date,
      scheduledDepartureAt: Timestamp.fromDate(new Date("2020-01-01T00:00:00Z")),
      notify: { changes: true, dayBefore: true, leaveForAirport: true, boarding: true },
    });
    await firestore().doc("system/providerFixture/rows/xx192").set({
      airport: "ICN",
      date,
      direction: "departure",
      level: "schedule",
      flightNumber: "XX192",
      operatingFlightNumber: "YY192",
      koreanAirport: "ICN",
      otherAirport: "NRT",
      scheduledAt: `${date}T01:00:00.000Z`,
      status: "scheduled",
    });
    process.env.FUNCTIONS_EMULATOR = "true";
    await runPollFlights(new Date(now.getTime() + 60_000), "test-key");
    assert.equal((await firestore().doc(`flights/${oldKey}`).get()).exists, false);
    assert.equal((await firestore().doc(`flights/${newKey}`).get()).exists, true);
    const tracked = await firestore().doc(`users/${user.uid}/trackedFlights/track-xx192`).get();
    assert.equal(tracked.get("flightKey"), newKey);
    assert.equal(tracked.get("scheduledDepartureAt")?.toDate?.().toISOString(), `${date}T01:00:00.000Z`);
  });

  it("같은 폴링의 운항 편명 문서가 코드쉐어 이전을 다시 덮지 않는다", async () => {
    const now = new Date();
    const date = addDays(seoulToday(now), 140);
    await clearFixture(null);
    const kept = `${date}T01:00:00.000Z`;
    const stale = `${date}T01:04:00.000Z`;
    const sourceKey = `XX194_${date}_ICN`;
    const targetKey = `YY194_${date}_ICN`;
    await firestore().doc(`flights/${sourceKey}`).set({
      operating: { airline: "XX", flightNumber: "XX194" },
      searchKeys: [`XX194_${date}`],
      origin: "airport_data",
      departure: { ...side("ICN", "Asia/Seoul", true, null), gate: { value: "15", source: "airport_data", updatedAt: Timestamp.fromDate(now), previousValue: null } },
      arrival: side("NRT", "Asia/Tokyo", false, null),
      status: { value: "scheduled", source: "airport_data", updatedAt: Timestamp.fromDate(now) },
      sync: { phase: "schedule", nextPollAt: Timestamp.fromDate(new Date(now.getTime() - 120_000)), lastSuccessAt: null, lastFailureAt: null, consecutiveFailures: 0, provider: "iiac" },
      trackerCount: 1,
    });
    await firestore().doc(`flights/${targetKey}`).set({
      operating: { airline: "YY", flightNumber: "YY194" },
      searchKeys: [`YY194_${date}`],
      origin: "airport_data",
      departure: side("ICN", "Asia/Seoul", true, Timestamp.fromDate(new Date(stale))),
      arrival: side("NRT", "Asia/Tokyo", false, null),
      status: { value: "scheduled", source: "airport_data", updatedAt: Timestamp.fromDate(now) },
      sync: { phase: "schedule", nextPollAt: Timestamp.fromDate(new Date(now.getTime() - 60_000)), lastSuccessAt: Timestamp.fromDate(new Date(now.getTime() - 86_400_000)), lastFailureAt: null, consecutiveFailures: 0, provider: "iiac" },
      trackerCount: 1,
    });
    await firestore().doc("system/providerFixture/rows/xx194").set({
      airport: "ICN",
      date,
      direction: "departure",
      level: "schedule",
      flightNumber: "XX194",
      operatingFlightNumber: "YY194",
      koreanAirport: "ICN",
      otherAirport: "NRT",
      scheduledAt: kept,
      status: "scheduled",
    });
    process.env.FUNCTIONS_EMULATOR = "true";
    const pollAt = new Date(now.getTime() + 60_000);
    await runPollFlights(pollAt, "test-key");
    const saved = await firestore().doc(`flights/${targetKey}`).get();
    assert.equal((await firestore().doc(`flights/${sourceKey}`).get()).exists, false);
    assert.equal(saved.get("departure.scheduledAt")?.toDate?.().toISOString(), kept);
    assert.equal(saved.get("departure.gate.value"), "15");
    const keys = saved.get("searchKeys") as string[];
    assert.ok(keys.includes(`XX194_${date}`));
    assert.ok(keys.includes(`YY194_${date}`));
    const nextPollAt = saved.get("sync.nextPollAt")?.toDate?.() as Date | undefined;
    assert.ok(nextPollAt && nextPollAt.getTime() > pollAt.getTime());
    const before = quotaTotal(await quotaCounts(pollAt));
    await runPollFlights(pollAt, "test-key");
    assert.equal(quotaTotal(await quotaCounts(pollAt)), before);
  });

  it("동시에 검색해도 호출 수가 더해진다", async () => {
    const now = new Date();
    const date = addDays(seoulToday(now), 160);
    await clearFixture(null);
    const [left, right] = await Promise.all([signUp(), signUp()]);
    const before = await quotaCounts(now);
    const [a, b] = await Promise.all([
      callFn("searchFlight", { flightNumber: "XX901", departureDate: date }, left.idToken),
      callFn("searchFlight", { flightNumber: "XX902", departureDate: date }, right.idToken),
    ]);
    assert.equal(a.body.result?.notFoundReason, "no_korean_airport_data");
    assert.equal(b.body.result?.notFoundReason, "no_korean_airport_data");
    const after = await quotaCounts(now);
    assert.equal(after["iiac:schedule:departure"] - before["iiac:schedule:departure"], 2);
    assert.equal(after["iiac:schedule:arrival"] - before["iiac:schedule:arrival"], 4);
    assert.equal(after["kac:schedule:departure"] - before["kac:schedule:departure"], 28);
    assert.equal(after["kac:schedule:arrival"] - before["kac:schedule:arrival"], 56);
  });
});

function side(airport: string, timeZone: string, korean: boolean, scheduledAt: Timestamp | null): Record<string, unknown> {
  const empty = { value: null, source: null, updatedAt: null, previousValue: null };
  return {
    airport,
    timeZone,
    scheduledAt,
    estimatedAt: { value: null, source: null, updatedAt: null },
    terminal: empty,
    gate: empty,
    checkInCounter: korean ? empty : null,
    baggageBelt: korean ? null : empty,
    autoDataSupported: korean,
  };
}

function quotaTotal(counts: Record<string, number>): number {
  return Object.values(counts).reduce((sum, value) => sum + value, 0);
}

async function quotaCounts(now: Date): Promise<Record<string, number>> {
  const raw = (await firestore().doc(`system/${quotaDocId(now)}`).get()).get("counts");
  const counts: Record<string, number> = {};
  if (!raw || typeof raw !== "object") return counts;
  for (const [key, value] of Object.entries(raw)) if (typeof value === "number") counts[key] = value;
  return new Proxy(counts, { get: (target, prop) => (typeof prop === "string" ? target[prop] ?? 0 : 0) });
}
