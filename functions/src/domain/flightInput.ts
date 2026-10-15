import { invalidArgument } from "./errors";
import { isDepartureDateAllowed } from "./time";

/** IATA 두 자리(숫자만 제외) 또는 ICAO 세 글자, 숫자 1~4, 접미 글자 하나. iOS와 같은 식. */
export const FLIGHT_NUMBER_PATTERN = "(?:[A-Z][A-Z0-9]|[0-9][A-Z]|[A-Z]{3})[0-9]{1,4}[A-Z]?";
export const FLIGHT_NUMBER = new RegExp(`^${FLIGHT_NUMBER_PATTERN}$`);
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const AIRPORT = /^[A-Z]{3}$/;
const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;
const GATE = /^[0-9A-Z]{1,5}$/;
const CHECK_IN = /^[0-9A-Z-]{1,7}$/;
const BELT = /^[0-9A-Z]{1,3}$/;
const TERMINAL = /^T?[0-9A-Z]{1,2}$/;
const FLIGHT_KEY = new RegExp(`^${FLIGHT_NUMBER_PATTERN}_\\d{4}-\\d{2}-\\d{2}_[A-Z]{3}$`);
const TRACKED_ID = /^[A-Za-z0-9_-]{1,128}$/;

const FIELD_KEYS = [
  "departure.terminal",
  "departure.gate",
  "departure.checkInCounter",
  "arrival.terminal",
  "arrival.gate",
  "arrival.baggageBelt",
] as const;

export type ManualFieldKey = (typeof FIELD_KEYS)[number];
export type ManualFields = Partial<Record<ManualFieldKey, string | null>>;

export type SearchInput = { flightNumber: string; departureDate: string };
export type TrackInput = { flightKey: string; enteredFlightNumber: string };
export type UntrackInput = { trackedId: string };
export type ManualInput = {
  flightNumber: string;
  departureDate: string;
  departureAirport: string;
  arrivalAirport: string;
  departureTime: string | null;
  arrivalTime: string | null;
  arrivalDayOffset: number;
  fields: ManualFields;
  awaitAutoData: boolean;
};

function objectOf(data: unknown): Record<string, unknown> {
  if (data === null || typeof data !== "object" || Array.isArray(data)) throw invalidArgument();
  return data as Record<string, unknown>;
}

function knownKeys(obj: Record<string, unknown>, allowed: readonly string[]): void {
  for (const key of Object.keys(obj)) {
    if (!allowed.includes(key)) throw invalidArgument();
  }
}

export function normalizeFlightNumber(value: unknown): string {
  if (typeof value !== "string") throw invalidArgument();
  const flightNumber = value.replace(/\s+/g, "").toUpperCase();
  if (!FLIGHT_NUMBER.test(flightNumber)) throw invalidArgument();
  return flightNumber;
}

export function parseSearch(data: unknown, now: Date): SearchInput {
  const obj = objectOf(data);
  knownKeys(obj, ["flightNumber", "departureDate"]);
  const flightNumber = normalizeFlightNumber(obj.flightNumber);
  if (typeof obj.departureDate !== "string" || !DATE.test(obj.departureDate) || !isDepartureDateAllowed(obj.departureDate, now)) {
    throw invalidArgument();
  }
  return { flightNumber, departureDate: obj.departureDate };
}

export function parseTrack(data: unknown): TrackInput {
  const obj = objectOf(data);
  knownKeys(obj, ["flightKey", "enteredFlightNumber"]);
  if (typeof obj.flightKey !== "string" || !FLIGHT_KEY.test(obj.flightKey)) throw invalidArgument();
  return { flightKey: obj.flightKey, enteredFlightNumber: normalizeFlightNumber(obj.enteredFlightNumber) };
}

export function parseUntrack(data: unknown): UntrackInput {
  const obj = objectOf(data);
  knownKeys(obj, ["trackedId"]);
  if (typeof obj.trackedId !== "string" || !TRACKED_ID.test(obj.trackedId)) throw invalidArgument();
  return { trackedId: obj.trackedId };
}

export function parseManual(data: unknown, now: Date): ManualInput {
  const obj = objectOf(data);
  knownKeys(obj, [
    "flightNumber",
    "departureDate",
    "departureAirport",
    "arrivalAirport",
    "departureTime",
    "arrivalTime",
    "arrivalDayOffset",
    "fields",
    "awaitAutoData",
  ]);
  const flightNumber = normalizeFlightNumber(obj.flightNumber);
  if (typeof obj.departureDate !== "string" || !isDepartureDateAllowed(obj.departureDate, now)) throw invalidArgument();
  const departureAirport = airportCode(obj.departureAirport);
  const arrivalAirport = airportCode(obj.arrivalAirport);
  if (departureAirport === arrivalAirport) throw invalidArgument();
  if ("awaitAutoData" in obj && typeof obj.awaitAutoData !== "boolean") throw invalidArgument();
  const awaitAutoData = obj.awaitAutoData === true;
  let departureTime: string | null = null;
  if ("departureTime" in obj && obj.departureTime !== null) {
    if (typeof obj.departureTime !== "string" || !HHMM.test(obj.departureTime)) throw invalidArgument();
    departureTime = obj.departureTime;
  }
  if (!awaitAutoData && departureTime === null) throw invalidArgument();

  let arrivalTime: string | null = null;
  if ("arrivalTime" in obj && obj.arrivalTime !== null) {
    if (typeof obj.arrivalTime !== "string" || !HHMM.test(obj.arrivalTime)) throw invalidArgument();
    arrivalTime = obj.arrivalTime;
  }
  let arrivalDayOffset = 0;
  if ("arrivalDayOffset" in obj) {
    if (typeof obj.arrivalDayOffset !== "number" || !Number.isInteger(obj.arrivalDayOffset)) throw invalidArgument();
    if (obj.arrivalDayOffset < -1 || obj.arrivalDayOffset > 2) throw invalidArgument();
    arrivalDayOffset = obj.arrivalDayOffset;
  }
  if (arrivalTime === null && arrivalDayOffset !== 0) throw invalidArgument();

  const fields = "fields" in obj ? parseFields(obj.fields) : {};
  return {
    flightNumber,
    departureDate: obj.departureDate,
    departureAirport,
    arrivalAirport,
    departureTime,
    arrivalTime,
    arrivalDayOffset,
    fields,
    awaitAutoData,
  };
}

export function canonicalizeFields(
  fields: ManualFields,
  departureTerminals: readonly string[],
  arrivalTerminals: readonly string[],
): ManualFields {
  const next: ManualFields = { ...fields };
  const departureTerminal = next["departure.terminal"];
  const arrivalTerminal = next["arrival.terminal"];
  if (typeof departureTerminal === "string") next["departure.terminal"] = canonicalTerminal(departureTerminal, departureTerminals);
  if (typeof arrivalTerminal === "string") next["arrival.terminal"] = canonicalTerminal(arrivalTerminal, arrivalTerminals);
  return next;
}

function parseFields(data: unknown): ManualFields {
  const obj = objectOf(data);
  knownKeys(obj, FIELD_KEYS);
  const fields: ManualFields = {};
  for (const key of FIELD_KEYS) {
    if (!(key in obj)) continue;
    const value = obj[key];
    if (value === null) {
      fields[key] = null;
      continue;
    }
    if (typeof value !== "string") throw invalidArgument();
    fields[key] = matchField(key, value);
  }
  return fields;
}

function matchField(key: ManualFieldKey, value: string): string {
  const pattern = key.endsWith("gate") ? GATE : key.endsWith("checkInCounter") ? CHECK_IN : key.endsWith("baggageBelt") ? BELT : TERMINAL;
  const normalized = value.toUpperCase();
  if (!pattern.test(normalized)) throw invalidArgument();
  return normalized;
}

function canonicalTerminal(value: string, terminals: readonly string[]): string {
  if (terminals.length === 0) return value;
  const found = terminals.find((terminal) => terminal.toUpperCase() === value.toUpperCase());
  if (!found) throw invalidArgument();
  return found;
}

function airportCode(value: unknown): string {
  if (typeof value !== "string") throw invalidArgument();
  const code = value.trim().toUpperCase();
  if (!AIRPORT.test(code)) throw invalidArgument();
  return code;
}
