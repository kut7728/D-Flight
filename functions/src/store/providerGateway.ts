import { createRequire } from "node:module";
import { logger } from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import type { Direction, FlightProvider, ProviderCallResult, ProviderFlight } from "../providers/types";
import { ProviderError } from "../providers/types";
import { firestore } from "./db";

export const dataGoKrServiceKey = defineSecret("DATA_GO_KR_SERVICE_KEY");

export type FlightCaller = (
  airport: string,
  date: string,
  direction: Direction,
  level: "realtime" | "schedule" | "gates",
  serviceKey: string,
) => Promise<ProviderCallResult>;

let override: FlightCaller | null = null;

/** 같은 프로세스 테스트가 공급원을 갈아 끼운다. 에뮬레이터 프로세스는 픽스처를 읽는다. */
export function setFlightCallerForTests(caller: FlightCaller | null): void {
  override = caller;
}

export async function callFlightProvider(
  airport: string,
  date: string,
  direction: Direction,
  level: "realtime" | "schedule" | "gates",
  serviceKey: string,
): Promise<ProviderCallResult> {
  if (override) return override(airport, date, direction, level, serviceKey);
  if (process.env.FUNCTIONS_EMULATOR === "true") return readFixture(airport, date, direction, level);
  return liveCall(airport, date, direction, level, serviceKey);
}

async function liveCall(
  airport: string,
  date: string,
  direction: Direction,
  level: "realtime" | "schedule" | "gates",
  serviceKey: string,
): Promise<ProviderCallResult> {
  const provider = loadProviders().providerFor(airport);
  if (!provider) return { flights: [], calls: 0, rateLimitRemaining: null };
  try {
    if (level === "gates") {
      if (!provider.gates) return { flights: [], calls: 0, rateLimitRemaining: null };
      return await provider.gates(airport, direction, serviceKey);
    }
    if (level === "realtime") return await provider.realtime(airport, date, direction, serviceKey);
    return await provider.schedule(airport, date, direction, serviceKey);
  } catch (error) {
    logger.warn("공공 API 호출 실패", { airport, direction, level });
    if (error instanceof ProviderError) throw error;
    throw new ProviderError("provider", true);
  }
}

function loadProviders(): { providerFor: (airport: string) => FlightProvider | null } {
  const require = createRequire(__filename);
  return require("../providers/index.js") as { providerFor: (airport: string) => FlightProvider | null };
}

async function readFixture(
  airport: string,
  date: string,
  direction: Direction,
  level: "realtime" | "schedule" | "gates",
): Promise<ProviderCallResult> {
  const db = firestore();
  const control = await db.doc("system/providerFixture").get();
  if (control.get("error") === true) throw new ProviderError("fixture", control.get("retryable") !== false);
  const snap = await db.collection("system/providerFixture/rows").get();
  const flights: ProviderFlight[] = [];
  for (const doc of snap.docs) {
    const row = doc.data();
    if (row.airport !== airport || row.direction !== direction || row.level !== level) continue;
    if (level !== "gates" && row.date !== date) continue;
    const flight = asFlight(row, level === "gates" ? "realtime" : level);
    if (flight) flights.push(flight);
  }
  const calls = typeof control.get("calls") === "number" ? control.get("calls") : 1;
  const rateLimitRemaining = typeof control.get("rateLimitRemaining") === "number" ? control.get("rateLimitRemaining") : null;
  const seasonLastDate = typeof control.get("seasonLastDate") === "string" ? control.get("seasonLastDate") : null;
  return { flights, calls, rateLimitRemaining, seasonLastDate };
}

function asFlight(row: FirebaseFirestore.DocumentData, level: "realtime" | "schedule"): ProviderFlight | null {
  if (typeof row.flightNumber !== "string" || typeof row.operatingFlightNumber !== "string") return null;
  if (typeof row.koreanAirport !== "string" || (row.direction !== "departure" && row.direction !== "arrival")) return null;
  const scheduledAt = typeof row.scheduledAt === "string" ? new Date(row.scheduledAt) : null;
  if (!scheduledAt || Number.isNaN(scheduledAt.getTime())) return null;
  const estimatedAt = typeof row.estimatedAt === "string" ? new Date(row.estimatedAt) : null;
  return {
    flightNumber: row.flightNumber,
    operatingFlightNumber: row.operatingFlightNumber,
    koreanAirport: row.koreanAirport,
    otherAirport: typeof row.otherAirport === "string" ? row.otherAirport : null,
    direction: row.direction,
    scheduledAt,
    estimatedAt: estimatedAt && !Number.isNaN(estimatedAt.getTime()) ? estimatedAt : null,
    status: isStatus(row.status) ? row.status : "unknown",
    terminal: typeof row.terminal === "string" ? row.terminal : null,
    gate: typeof row.gate === "string" ? row.gate : null,
    checkInCounter: typeof row.checkInCounter === "string" ? row.checkInCounter : null,
    baggageBelt: typeof row.baggageBelt === "string" ? row.baggageBelt : null,
    level,
  };
}

function isStatus(value: unknown): value is ProviderFlight["status"] {
  return value === "scheduled" || value === "delayed" || value === "cancelled" || value === "departed" || value === "arrived" || value === "unknown";
}
