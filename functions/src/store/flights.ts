import { randomUUID } from "node:crypto";
import { FieldValue, Timestamp, type Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions/logger";
import { alreadyExists, exhausted, invalidArgument, notFound, unavailable } from "../domain/errors";
import {
  applyAirportRow,
  applyGate,
  buildDrafts,
  bundleKinds,
  dataLevelOf,
  mergeFlightDocs,
  hasKorean,
  KOREAN_AIRPORT_CODES,
  manualFlight,
  markFailure,
  markSuccess,
  modeFor,
  notFoundReason,
  parseFlightKey,
  planFlight,
  pollGroups,
  providerIdFor,
  providerLevel,
  rowMatches,
  scheduledDepartureAt,
  searchBlocked,
  searchKey,
  stampPlan,
  syncProvider,
  type ChangeEvent,
  type ChangeKind,
  type DataLevel,
  type NotFoundReason,
  type FlightDoc,
  type InfoValue,
  type Side,
  type StatusValue,
  type SyncState,
  type TimeValue,
} from "../domain/flight";
import { canonicalizeFields, parseManual, parseSearch, parseTrack, parseUntrack } from "../domain/flightInput";
import { assertUpcomingTracked } from "../domain/limits";
import {
  bucketFor,
  quotaCutoffId,
  quotaDocId,
  quotaMode,
  ratioOf,
  recordCalls,
  type QuotaBucket,
  type QuotaCounts,
} from "../domain/quota";
import { addDays, DAY, iso, MINUTE, seoulToday, zonedTimeToUtc } from "../domain/time";
import type { Direction, ProviderCallResult, ProviderFlight } from "../providers/types";
import { getAirport, isKoreanAirport } from "./airports";
import { firestore } from "./db";
import { consumeSearchLimit } from "./limits";
import { callFlightProvider } from "./providerGateway";

const CACHE_MS = 10 * MINUTE;
const POLL_LIMIT = 200;
const NOTIFY = { changes: true, dayBefore: true, leaveForAirport: true, boarding: true };

type Candidate = {
  flightKey: string;
  operating: { airline: string; flightNumber: string };
  departure: { airport: string; scheduledAt: string | null; timeZone: string };
  arrival: { airport: string; scheduledAt: string | null; timeZone: string };
  dataLevel: DataLevel;
  alreadyTracked: boolean;
};

export async function searchFlightFor(
  uid: string,
  data: unknown,
  serviceKey: string,
  now = new Date(),
): Promise<{ candidates: Candidate[]; notFoundReason: NotFoundReason | null }> {
  const input = parseSearch(data, now);
  const today = seoulToday(now);
  const existing = await firestore().collection("flights").where("searchKeys", "array-contains", searchKey(input.flightNumber, input.departureDate)).get();
  const tracked = await trackedKeys(uid);
  if (!existing.empty) {
    await consumeSearchLimit(uid, now);
    const candidates = existing.docs.flatMap((doc) => {
      const flight = fromDoc(doc);
      return flight ? [candidate(flight, dataLevelOf(flight), tracked.has(flight.flightKey))] : [];
    });
    return { candidates, notFoundReason: null };
  }

  const level = providerLevel(input.departureDate, today);
  const quota = await readQuota(now);
  if (searchBlocked(quota, level)) throw exhausted();
  await consumeSearchLimit(uid, now);

  const rows: ProviderFlight[] = [];
  const quotaHits: QuotaHit[] = [];
  let ok = false;
  let seasonLastDate: string | null = null;
  const tasks = searchTasks(input.departureDate, level, serviceKey, now);
  const settled = await Promise.allSettled(tasks);
  for (const item of settled) {
    if (item.status === "rejected") continue;
    ok = true;
    rows.push(...item.value.flights);
    recordCalls(quota, item.value.bucket, item.value.result.calls, item.value.result.rateLimitRemaining);
    quotaHits.push({ bucket: item.value.bucket, calls: item.value.result.calls, remaining: item.value.result.rateLimitRemaining });
    const last = item.value.result.seasonLastDate;
    if (level === "schedule" && last && (!seasonLastDate || last > seasonLastDate)) seasonLastDate = last;
  }
  if (!ok) throw unavailable();
  await writeQuota(now, quotaHits);

  const drafts = buildDrafts(rows, input, airportFacts, now);
  if (drafts.length === 0) {
    return { candidates: [], notFoundReason: notFoundReason(level, { departureDate: input.departureDate, today, seasonLastDate }) };
  }

  const candidates: Candidate[] = [];
  for (const draft of drafts) {
    const probe = planFlight({ ...draft.flight, trackerCount: 1 }, now, "normal");
    const mode = probe.call === "none" ? "normal" : modeFor(quota, { ...draft.flight, trackerCount: 1 }, probe.call, now);
    let flight = stampPlan({ ...draft.flight, trackerCount: 1 }, now, mode, false);
    flight = { ...flight, trackerCount: 0, sync: { ...flight.sync, lastSuccessAt: now, provider: syncProvider(flight) } };
    await writeCache(flight, now);
    candidates.push(candidate(flight, draft.dataLevel, tracked.has(flight.flightKey)));
  }
  return { candidates, notFoundReason: null };
}

export async function trackFlightFor(uid: string, data: unknown, now = new Date()): Promise<{ trackedId: string }> {
  const input = parseTrack(data);
  const trackedId = await commitTrack(uid, input.flightKey, input.enteredFlightNumber, now, async (tx) => {
    const cache = await tx.get(firestore().doc(`system/searchCache/items/${input.flightKey}`));
    const expireAt = asDate(cache.get("expireAt"));
    const flight = cache.exists && expireAt && expireAt.getTime() > now.getTime() ? fromData(cache.get("flight"), input.flightKey) : null;
    if (!flight) throw notFound();
    return flight;
  });
  return { trackedId };
}

export async function createManualFlightFor(
  uid: string,
  data: unknown,
  now = new Date(),
): Promise<{ trackedId: string; flightKey: string }> {
  const input = parseManual(data, now);
  const departure = getAirport(input.departureAirport);
  const arrival = getAirport(input.arrivalAirport);
  if (!departure || !arrival) throw invalidArgument();
  const fields = canonicalizeFields(input.fields, departure.terminals, arrival.terminals);
  const arrivalDate = input.arrivalTime ? addDays(input.departureDate, input.arrivalDayOffset) : null;
  const flight = manualFlight({
    flightNumber: input.flightNumber,
    departureDate: input.departureDate,
    departure: { ...departure, terminals: departure.terminals },
    arrival: { ...arrival, terminals: arrival.terminals },
    departureAt: input.departureTime ? zonedTimeToUtc(input.departureDate, input.departureTime, departure.timeZone) : null,
    arrivalAt: arrivalDate && input.arrivalTime ? zonedTimeToUtc(arrivalDate, input.arrivalTime, arrival.timeZone) : null,
    fields,
    now,
    awaitAutoData: input.awaitAutoData,
  });
  const trackedId = await commitTrack(uid, flight.flightKey, input.flightNumber, now, async () => flight);
  return { trackedId, flightKey: flight.flightKey };
}

export async function untrackFlightFor(uid: string, data: unknown): Promise<Record<string, never>> {
  const input = parseUntrack(data);
  const db = firestore();
  const trackedRef = db.doc(`users/${uid}/trackedFlights/${input.trackedId}`);
  await db.runTransaction(async (tx) => {
    const tracked = await tx.get(trackedRef);
    if (!tracked.exists) throw notFound();
    const key = tracked.get("flightKey");
    if (typeof key === "string" && key.length > 0 && !key.includes("/")) {
      const flightRef = db.doc(`flights/${key}`);
      const flight = await tx.get(flightRef);
      if (flight.exists) {
        const count = numberOf(flight.get("trackerCount"));
        const next = count > 0 ? count - 1 : 0;
        tx.update(flightRef, next === 0 ? { trackerCount: next, "sync.nextPollAt": null } : { trackerCount: next });
      }
    }
    tx.delete(trackedRef);
  });
  return {};
}

export async function runPollFlights(now: Date, serviceKey: string): Promise<ChangeEvent[]> {
  const due = await firestore().collection("flights").where("sync.nextPollAt", "<=", Timestamp.fromDate(now)).orderBy("sync.nextPollAt").limit(POLL_LIMIT).get();
  const quota = await readQuota(now);
  const quotaHits: QuotaHit[] = [];
  const work = new Map<string, Work>();
  const groups = new Map<string, Group>();

  for (const doc of due.docs) {
    const flight = fromDoc(doc);
    if (!flight) continue;
    const probe = planFlight(flight, now, "normal");
    const mode = probe.call === "none" ? "normal" : modeFor(quota, flight, probe.call, now);
    const plan = planFlight(flight, now, mode);
    if (plan.call === "none" || !hasKorean(flight)) {
      work.set(flight.flightKey, {
        originalKey: flight.flightKey,
        flight: { ...flight, sync: { ...flight.sync, phase: plan.phase, nextPollAt: plan.nextPollAt, provider: syncProvider(flight) } },
        kinds: [],
        attempted: false,
        failed: false,
      });
      continue;
    }
    work.set(flight.flightKey, { originalKey: flight.flightKey, flight, kinds: [], attempted: false, failed: false });
    for (const group of pollGroups(flight, plan.call, now)) {
      const id = `${group.provider}|${group.airport}|${group.date}|${group.direction}|${group.level}`;
      const found = groups.get(id) ?? { ...group, keys: [] as string[] };
      found.keys.push(flight.flightKey);
      groups.set(id, found);
    }
  }

  for (const group of groups.values()) {
    const bucket = bucketFor(group.provider, group.level === "gates" ? "gates" : group.level, group.direction);
    if (quotaMode(ratioOf(quota, bucket)) === "frequentOnly" && group.level !== "realtime" && group.level !== "gates") continue;
    let result: ProviderCallResult;
    try {
      result = await callFlightProvider(group.airport, group.date, group.direction, group.level, serviceKey);
    } catch (error) {
      logger.warn("항공편 조회 실패", { airport: group.airport, direction: group.direction, level: group.level });
      for (const key of group.keys) {
        const item = work.get(key);
        if (!item) continue;
        item.failed = true;
        item.attempted = true;
      }
      void error;
      continue;
    }
    recordCalls(quota, bucket, result.calls, result.rateLimitRemaining);
    quotaHits.push({ bucket, calls: result.calls, remaining: result.rateLimitRemaining });
    for (const key of group.keys) {
      const item = work.get(key);
      if (!item) continue;
      item.attempted = true;
      const row = result.flights.find((flight) => rowMatches(item.flight, flight));
      if (!row) continue;
      const applied = group.level === "gates" ? applyGate(item.flight, group.direction, row.gate, now) : applyAirportRow(item.flight, row, now);
      item.flight = applied.flight;
      item.kinds.push(...applied.kinds);
    }
  }

  const events: ChangeEvent[] = [];
  for (const item of work.values()) {
    if (!item.attempted && !item.failed) {
      const probe = planFlight(item.flight, now, "normal");
      const mode = probe.call === "none" ? "normal" : modeFor(quota, item.flight, probe.call, now);
      const plan = planFlight(item.flight, now, mode);
      item.flight.sync = { ...item.flight.sync, phase: plan.phase, nextPollAt: plan.nextPollAt, provider: syncProvider(item.flight) };
      await persistPolled(item.originalKey, item.flight);
      continue;
    }
    const probe = planFlight(item.flight, now, "normal");
    const mode = probe.call === "none" ? "normal" : modeFor(quota, item.flight, probe.call, now);
    const plan = planFlight(item.flight, now, mode);
    item.flight.sync = item.failed ? markFailure(item.flight.sync, plan, now) : markSuccess(item.flight.sync, plan, now);
    item.flight.sync.provider = syncProvider(item.flight);
    await persistPolled(item.originalKey, item.flight);
    const kinds = bundleKinds(item.kinds);
    if (kinds.length > 0) events.push({ flightKey: item.flight.flightKey, kinds });
  }
  await writeQuota(now, quotaHits);
  return events;
}

export async function runDailyCleanup(now = new Date()): Promise<void> {
  const cutoff = new Date(now.getTime() - 30 * DAY);
  const db = firestore();
  await deleteMatching(db.collection("flights").where("trackerCount", "==", 0).where("departure.scheduledAt", "<=", Timestamp.fromDate(cutoff)), async (doc) => {
    await deleteCollection(`flights/${doc.id}/reportHistory`);
    await doc.ref.delete();
  });
  await deleteMatching(db.collectionGroup("reportHistory").where("expireAt", "<=", Timestamp.fromDate(now)), async (doc) => {
    await doc.ref.delete();
  });
  await deleteMatching(db.collection("system/searchCache/items").where("expireAt", "<=", Timestamp.fromDate(now)), async (doc) => {
    await doc.ref.delete();
  });
  const old = quotaCutoffId(now);
  for (const ref of await db.collection("system").listDocuments()) {
    if (/^quota_\d{8}$/.test(ref.id) && ref.id < old) await ref.delete();
  }
}

type Work = { originalKey: string; flight: FlightDoc; kinds: ChangeKind[]; attempted: boolean; failed: boolean };
type Group = { provider: "iiac" | "kac"; airport: string; date: string; direction: Direction; level: "realtime" | "schedule" | "gates"; keys: string[] };

function searchTasks(date: string, level: "realtime" | "schedule", serviceKey: string, now: Date) {
  const tasks: Array<Promise<{ bucket: ReturnType<typeof bucketFor>; result: ProviderCallResult; flights: ProviderFlight[] }>> = [];
  for (const airport of KOREAN_AIRPORT_CODES) {
    if (!isKoreanAirport(airport)) continue;
    const provider = providerIdFor(airport, true);
    if (!provider) continue;
    const calls: Array<[string, Direction]> = [
      [date, "departure"],
      [date, "arrival"],
      [addDays(date, 1), "arrival"],
    ];
    for (const [queryDate, direction] of calls) {
      const bucket = bucketFor(provider, level, direction);
      tasks.push(
        cachedCall(provider, airport, queryDate, direction, level, serviceKey, now).then((result) => ({
          bucket,
          result,
          flights: result.flights,
        })),
      );
    }
  }
  return tasks;
}

async function cachedCall(
  provider: "iiac" | "kac",
  airport: string,
  date: string,
  direction: Direction,
  level: "realtime" | "schedule",
  serviceKey: string,
  now: Date,
): Promise<ProviderCallResult> {
  const id = `api_${provider}_${airport}_${date}_${direction}_${level}`;
  if (process.env.FUNCTIONS_EMULATOR !== "true") {
    const hit = await readApiCache(id, now);
    if (hit) return { ...hit, calls: 0 };
  }
  const result = await callFlightProvider(airport, date, direction, level, serviceKey);
  if (process.env.FUNCTIONS_EMULATOR !== "true") await writeApiCache(id, result, now);
  return result;
}

async function commitTrack(
  uid: string,
  key: string,
  enteredFlightNumber: string,
  now: Date,
  loadMissing: (tx: Transaction) => Promise<FlightDoc>,
): Promise<string> {
  const db = firestore();
  const tracked = db.collection(`users/${uid}/trackedFlights`);
  const flightRef = db.doc(`flights/${key}`);
  return db.runTransaction(async (tx) => {
    const dup = await tx.get(tracked.where("flightKey", "==", key).limit(1));
    if (!dup.empty) throw alreadyExists();
    const upcoming = await tx.get(tracked.where("scheduledDepartureAt", ">=", Timestamp.fromDate(new Date(now.getTime() - DAY))));
    assertUpcomingTracked(upcoming.size);
    const snap = await tx.get(flightRef);
    let flight: FlightDoc;
    if (snap.exists) {
      const current = fromDoc(snap);
      if (!current) throw notFound();
      flight = { ...current, trackerCount: current.trackerCount + 1 };
      if (flight.sync.nextPollAt === null) flight.sync = stampPlan(flight, now, "normal", true).sync;
    } else {
      flight = { ...(await loadMissing(tx)), trackerCount: 1, flightKey: key };
    }
    const date = parseFlightKey(key)?.date;
    if (date) {
      const extra = searchKey(enteredFlightNumber, date);
      if (!flight.searchKeys.includes(extra)) flight.searchKeys = [...flight.searchKeys, extra];
    }
    const trackedId = randomUUID();
    tx.set(flightRef, toData(flight));
    tx.set(tracked.doc(trackedId), {
      flightKey: key,
      enteredFlightNumber,
      departureDate: date ?? "",
      scheduledDepartureAt: Timestamp.fromDate(scheduledDepartureAt(flight)),
      notify: NOTIFY,
      createdAt: FieldValue.serverTimestamp(),
    });
    return trackedId;
  });
}

async function persistPolled(originalKey: string, flight: FlightDoc): Promise<void> {
  if (flight.flightKey === originalKey) {
    const ref = firestore().doc(`flights/${originalKey}`);
    await firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current = snap.exists ? fromData(snap.data(), originalKey) : null;
      const merged = current ? mergeFlightDocs(current, flight) : flight;
      const data = toData(merged);
      delete data.trackerCount;
      if (snap.exists) tx.update(ref, data);
      else tx.set(ref, data);
    });
    return;
  }
  const db = firestore();
  await db.runTransaction(async (tx) => {
    const oldRef = db.doc(`flights/${originalKey}`);
    const newRef = db.doc(`flights/${flight.flightKey}`);
    const tracks = await tx.get(db.collectionGroup("trackedFlights").where("flightKey", "==", originalKey));
    const oldSnap = await tx.get(oldRef);
    const newSnap = await tx.get(newRef);
    // shortcut: 이전할 등록이 498건을 넘으면 롤백하며, 그 규모부터 분할 이전이 필요하다.
    if (tracks.size > 498) throw new Error("코드쉐어 이전 추적 문서가 트랜잭션 한도를 넘습니다");
    const oldCount = oldSnap.exists ? numberOf(oldSnap.get("trackerCount")) : 0;
    const target = newSnap.exists ? fromData(newSnap.data(), flight.flightKey) : null;
    const moved = { ...flight, trackerCount: oldCount };
    const merged = target ? mergeFlightDocs(target, moved) : { ...moved, trackerCount: oldCount + (newSnap.exists ? numberOf(newSnap.get("trackerCount")) : 0) };
    const departureAt = Timestamp.fromDate(scheduledDepartureAt(merged));
    tx.set(newRef, toData(merged));
    if (oldSnap.exists) tx.delete(oldRef);
    for (const doc of tracks.docs) tx.update(doc.ref, { flightKey: merged.flightKey, scheduledDepartureAt: departureAt });
  });
}

async function trackedKeys(uid: string): Promise<Set<string>> {
  const snap = await firestore().collection(`users/${uid}/trackedFlights`).select("flightKey").limit(500).get();
  return new Set(snap.docs.map((doc) => doc.get("flightKey")).filter((key): key is string => typeof key === "string"));
}

function candidate(flight: FlightDoc, dataLevel: DataLevel, alreadyTracked: boolean): Candidate {
  return {
    flightKey: flight.flightKey,
    operating: flight.operating,
    departure: { airport: flight.departure.airport, scheduledAt: iso(flight.departure.scheduledAt), timeZone: flight.departure.timeZone },
    arrival: { airport: flight.arrival.airport, scheduledAt: iso(flight.arrival.scheduledAt), timeZone: flight.arrival.timeZone },
    dataLevel,
    alreadyTracked,
  };
}

function airportFacts(code: string) {
  const airport = getAirport(code);
  if (!airport) return null;
  return { timeZone: airport.timeZone, korean: airport.korean, terminals: airport.terminals };
}

type QuotaHit = { bucket: QuotaBucket; calls: number; remaining: number | null };

function countsFrom(snap: FirebaseFirestore.DocumentSnapshot): QuotaCounts {
  const raw = snap.get("counts");
  if (!raw || typeof raw !== "object") return {};
  const counts: QuotaCounts = {};
  for (const [key, value] of Object.entries(raw)) {
    if (typeof value === "number" && Number.isFinite(value)) counts[key as keyof QuotaCounts] = value;
  }
  return counts;
}

async function readQuota(now: Date): Promise<QuotaCounts> {
  return countsFrom(await firestore().doc(`system/${quotaDocId(now)}`).get());
}

async function writeQuota(now: Date, hits: readonly QuotaHit[]): Promise<void> {
  if (hits.length === 0) return;
  const ref = firestore().doc(`system/${quotaDocId(now)}`);
  await firestore().runTransaction(async (tx) => {
    const counts = countsFrom(await tx.get(ref));
    for (const hit of hits) recordCalls(counts, hit.bucket, hit.calls, hit.remaining);
    tx.set(ref, { date: seoulToday(now), counts, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
}

async function writeCache(flight: FlightDoc, now: Date): Promise<void> {
  await firestore().doc(`system/searchCache/items/${flight.flightKey}`).set({
    expireAt: Timestamp.fromDate(new Date(now.getTime() + CACHE_MS)),
    flight: toData(flight),
  });
}

async function readApiCache(id: string, now: Date): Promise<ProviderCallResult | null> {
  const snap = await firestore().doc(`system/searchCache/items/${id}`).get();
  const expireAt = asDate(snap.get("expireAt"));
  if (!snap.exists || !expireAt || expireAt.getTime() <= now.getTime()) return null;
  const packed = snap.get("result");
  if (!packed || typeof packed !== "object") return null;
  return unpackResult(packed as PackedResult);
}

async function writeApiCache(id: string, result: ProviderCallResult, now: Date): Promise<void> {
  await firestore().doc(`system/searchCache/items/${id}`).set({
    expireAt: Timestamp.fromDate(new Date(now.getTime() + CACHE_MS)),
    result: packResult(result),
  });
}

type PackedFlight = Omit<ProviderFlight, "scheduledAt" | "estimatedAt"> & { scheduledAt: string; estimatedAt: string | null };
type PackedResult = { calls: number; rateLimitRemaining: number | null; flights: PackedFlight[]; seasonLastDate?: string | null };

function packResult(result: ProviderCallResult): PackedResult {
  return {
    calls: result.calls,
    rateLimitRemaining: result.rateLimitRemaining,
    seasonLastDate: result.seasonLastDate ?? null,
    flights: result.flights.map((flight) => ({
      ...flight,
      scheduledAt: flight.scheduledAt.toISOString(),
      estimatedAt: flight.estimatedAt?.toISOString() ?? null,
    })),
  };
}

function unpackResult(packed: PackedResult): ProviderCallResult {
  return {
    calls: packed.calls,
    rateLimitRemaining: packed.rateLimitRemaining,
    seasonLastDate: typeof packed.seasonLastDate === "string" ? packed.seasonLastDate : null,
    flights: (packed.flights ?? []).map((flight) => ({
      ...flight,
      scheduledAt: new Date(flight.scheduledAt),
      estimatedAt: flight.estimatedAt ? new Date(flight.estimatedAt) : null,
    })),
  };
}

async function deleteMatching(
  query: FirebaseFirestore.Query,
  remove: (doc: FirebaseFirestore.QueryDocumentSnapshot) => Promise<void>,
): Promise<void> {
  for (;;) {
    const page = await query.limit(200).get();
    if (page.empty) return;
    for (const doc of page.docs) await remove(doc);
  }
}

async function deleteCollection(path: string): Promise<void> {
  const db = firestore();
  for (;;) {
    const page = await db.collection(path).limit(200).get();
    if (page.empty) return;
    const batch = db.batch();
    for (const doc of page.docs) batch.delete(doc.ref);
    await batch.commit();
  }
}

function toData(flight: FlightDoc): Record<string, unknown> {
  return {
    operating: flight.operating,
    searchKeys: flight.searchKeys,
    origin: flight.origin,
    departure: sideData(flight.departure),
    arrival: sideData(flight.arrival),
    status: { value: flight.status.value, source: flight.status.source, updatedAt: stamp(flight.status.updatedAt) },
    sync: {
      phase: flight.sync.phase,
      nextPollAt: stamp(flight.sync.nextPollAt),
      lastSuccessAt: stamp(flight.sync.lastSuccessAt),
      lastFailureAt: stamp(flight.sync.lastFailureAt),
      consecutiveFailures: flight.sync.consecutiveFailures,
      provider: flight.sync.provider,
    },
    trackerCount: flight.trackerCount,
  };
}

function sideData(side: Side): Record<string, unknown> {
  return {
    airport: side.airport,
    timeZone: side.timeZone,
    scheduledAt: stamp(side.scheduledAt),
    estimatedAt: timeData(side.estimatedAt),
    terminal: infoData(side.terminal),
    gate: infoData(side.gate),
    checkInCounter: side.checkInCounter ? infoData(side.checkInCounter) : null,
    baggageBelt: side.baggageBelt ? infoData(side.baggageBelt) : null,
    autoDataSupported: side.autoDataSupported,
  };
}

function infoData(item: InfoValue): Record<string, unknown> {
  return { value: item.value, source: item.source, updatedAt: stamp(item.updatedAt), previousValue: item.previousValue };
}

function timeData(item: TimeValue): Record<string, unknown> {
  return { value: stamp(item.value), source: item.source, updatedAt: stamp(item.updatedAt) };
}

function fromDoc(snap: FirebaseFirestore.DocumentSnapshot): FlightDoc | null {
  return snap.exists ? fromData(snap.data(), snap.id) : null;
}

function fromData(data: unknown, flightKey: string): FlightDoc | null {
  if (!data || typeof data !== "object") return null;
  const raw = data as Record<string, unknown>;
  const operating = raw.operating as { airline?: unknown; flightNumber?: unknown } | undefined;
  if (!operating || typeof operating.flightNumber !== "string" || typeof operating.airline !== "string") return null;
  const departure = sideFrom(raw.departure);
  const arrival = sideFrom(raw.arrival);
  if (!departure || !arrival) return null;
  return {
    flightKey,
    operating: { airline: operating.airline, flightNumber: operating.flightNumber },
    searchKeys: Array.isArray(raw.searchKeys) ? raw.searchKeys.filter((key): key is string => typeof key === "string") : [],
    origin: raw.origin === "user" || raw.origin === "pending" ? raw.origin : "airport_data",
    departure,
    arrival,
    status: statusFrom(raw.status),
    sync: syncFrom(raw.sync),
    trackerCount: numberOf(raw.trackerCount),
  };
}

function sideFrom(value: unknown): Side | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as Record<string, unknown>;
  if (typeof raw.airport !== "string" || typeof raw.timeZone !== "string") return null;
  return {
    airport: raw.airport,
    timeZone: raw.timeZone,
    scheduledAt: asDate(raw.scheduledAt),
    estimatedAt: timeFrom(raw.estimatedAt),
    terminal: infoFrom(raw.terminal),
    gate: infoFrom(raw.gate),
    checkInCounter: raw.checkInCounter ? infoFrom(raw.checkInCounter) : null,
    baggageBelt: raw.baggageBelt ? infoFrom(raw.baggageBelt) : null,
    autoDataSupported: raw.autoDataSupported === true,
  };
}

function infoFrom(value: unknown): InfoValue {
  if (!value || typeof value !== "object") return { value: null, source: null, updatedAt: null, previousValue: null };
  const raw = value as Record<string, unknown>;
  return {
    value: typeof raw.value === "string" ? raw.value : null,
    source: raw.source === "airport_data" || raw.source === "user" ? raw.source : null,
    updatedAt: asDate(raw.updatedAt),
    previousValue: typeof raw.previousValue === "string" ? raw.previousValue : null,
  };
}

function timeFrom(value: unknown): TimeValue {
  if (!value || typeof value !== "object") return { value: null, source: null, updatedAt: null };
  const raw = value as Record<string, unknown>;
  return {
    value: asDate(raw.value),
    source: raw.source === "airport_data" || raw.source === "user" ? raw.source : null,
    updatedAt: asDate(raw.updatedAt),
  };
}

function statusFrom(value: unknown): StatusValue {
  if (!value || typeof value !== "object") return { value: "unknown", source: null, updatedAt: null };
  const raw = value as Record<string, unknown>;
  const status = raw.value;
  const known = status === "scheduled" || status === "delayed" || status === "cancelled" || status === "departed" || status === "arrived" || status === "unknown";
  return {
    value: known ? status : "unknown",
    source: raw.source === "airport_data" || raw.source === "user" ? raw.source : null,
    updatedAt: asDate(raw.updatedAt),
  };
}

function syncFrom(value: unknown): SyncState {
  if (!value || typeof value !== "object") {
    return { phase: "schedule", nextPollAt: null, lastSuccessAt: null, lastFailureAt: null, consecutiveFailures: 0, provider: null };
  }
  const raw = value as Record<string, unknown>;
  const phase = raw.phase === "hourly" || raw.phase === "frequent" || raw.phase === "done" || raw.phase === "schedule" ? raw.phase : "schedule";
  return {
    phase,
    nextPollAt: asDate(raw.nextPollAt),
    lastSuccessAt: asDate(raw.lastSuccessAt),
    lastFailureAt: asDate(raw.lastFailureAt),
    consecutiveFailures: numberOf(raw.consecutiveFailures),
    provider: typeof raw.provider === "string" ? raw.provider : null,
  };
}

function stamp(date: Date | null): Timestamp | null {
  return date ? Timestamp.fromDate(date) : null;
}

function asDate(value: unknown): Date | null {
  if (value == null) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value === "object" && "toDate" in value && typeof value.toDate === "function") {
    const date = value.toDate();
    return date instanceof Date && !Number.isNaN(date.getTime()) ? date : null;
  }
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function numberOf(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
}
