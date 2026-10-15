import type { Direction, FlightStatusValue, ProviderFlight } from "./types";
import { ProviderError } from "./types";

const SEOUL_OFFSET_MS = 9 * 60 * 60 * 1000;

const STATUS_EXACT: Record<string, FlightStatusValue> = {
  결항: "cancelled",
  취소: "cancelled",
  회항: "cancelled",
  cancelled: "cancelled",
  canceled: "cancelled",
  cancel: "cancelled",
  diverted: "cancelled",
  diversion: "cancelled",
  지연: "delayed",
  delayed: "delayed",
  delay: "delayed",
  출발: "departed",
  이륙: "departed",
  departed: "departed",
  departure: "departed",
  airborne: "departed",
  takeoff: "departed",
  tookoff: "departed",
  도착: "arrived",
  착륙: "arrived",
  arrived: "arrived",
  arrival: "arrived",
  landed: "arrived",
  landing: "arrived",
  예정: "scheduled",
  출발예정: "scheduled",
  도착예정: "scheduled",
  체크인: "scheduled",
  체크인오픈: "scheduled",
  수속중: "scheduled",
  수속마감: "scheduled",
  탑승: "scheduled",
  탑승중: "scheduled",
  탑승준비: "scheduled",
  탑승마감: "scheduled",
  탑승개시: "scheduled",
  게이트오픈: "scheduled",
  마감: "scheduled",
  마감예정: "scheduled",
  운항: "scheduled",
  정상: "scheduled",
  scheduled: "scheduled",
  ontime: "scheduled",
  boarding: "scheduled",
  checkin: "scheduled",
  gateopen: "scheduled",
  gateclosed: "scheduled",
  finalcall: "scheduled",
};

const IIAC_TERMINAL: Record<string, string> = { P01: "T1", P02: "T1", P03: "T2" };

export function requireDate(date: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new ProviderError("날짜 형식이 올바르지 않습니다", false);
  return date.replaceAll("-", "");
}

export function requireKey(serviceKey: string): void {
  if (!serviceKey.trim()) throw new ProviderError("서비스 키가 없습니다", false);
}

export function cell(row: Record<string, unknown>, keys: string | readonly string[]): string | null {
  for (const key of listKeys(keys)) {
    const value = row[key];
    if (typeof value !== "string" && typeof value !== "number") continue;
    const trimmed = String(value).trim();
    if (trimmed !== "" && trimmed !== "-") return trimmed;
  }
  return null;
}

export function iata(row: Record<string, unknown>, keys: string | readonly string[], koreanAirport: string): string | null {
  for (const key of listKeys(keys)) {
    const value = cell(row, key);
    if (!value || !/^[A-Za-z]{3}$/.test(value)) continue;
    const code = value.toUpperCase();
    if (code !== koreanAirport) return code;
  }
  return null;
}

function listKeys(keys: string | readonly string[]): readonly string[] {
  return typeof keys === "string" ? [keys] : keys;
}

function compactYmd(value: string | null): string | null {
  if (!value) return null;
  const iso = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (iso) return `${iso[1]}${iso[2]}${iso[3]}`;
  return /^\d{8}$/.test(value) ? value : null;
}

/** 걸러지기 전의 일정 행에서 운항 종료일 최댓값. */
export function maxSeasonDate(rows: readonly Record<string, unknown>[], keys: readonly (string | readonly string[])[]): string | null {
  let max: string | null = null;
  for (const row of rows) {
    for (const key of keys) {
      const ymd = compactYmd(cell(row, key));
      if (!ymd) continue;
      const iso = `${ymd.slice(0, 4)}-${ymd.slice(4, 6)}-${ymd.slice(6, 8)}`;
      if (!max || iso > max) max = iso;
    }
  }
  return max;
}

export function mapRemark(value: string | null): FlightStatusValue {
  if (!value) return "scheduled";
  const key = value.toLowerCase().replace(/[\s-]/g, "");
  return STATUS_EXACT[key] ?? "unknown";
}

export function iiacTerminal(value: string | null): string | null {
  if (!value) return null;
  return IIAC_TERMINAL[value.toUpperCase()] ?? null;
}

/** YYYYMMDDHHMM. 조회일이 아니라 필드 안의 날짜. 한국은 서머타임이 없다. */
export function parseSeoulDateTime(value: string | null): Date | null {
  if (!value || !/^\d{12}$/.test(value)) return null;
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(4, 6));
  const day = Number(value.slice(6, 8));
  const hour = Number(value.slice(8, 10));
  const minute = Number(value.slice(10, 12));
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) return null;
  return new Date(Date.UTC(year, month - 1, day, hour - 9, minute));
}

export function parseSeoulClock(date: string, hhmm: string | null): Date | null {
  if (!hhmm) return null;
  const digits = hhmm.replace(/\D/g, "");
  const clock = digits.length === 3 ? `0${digits}` : digits;
  if (!/^\d{4}$/.test(clock)) return null;
  return parseSeoulDateTime(`${date.replaceAll("-", "")}${clock}`);
}

export function seoulToday(now = new Date()): string {
  const seoul = new Date(now.getTime() + SEOUL_OFFSET_MS);
  const month = String(seoul.getUTCMonth() + 1).padStart(2, "0");
  const day = String(seoul.getUTCDate()).padStart(2, "0");
  return `${seoul.getUTCFullYear()}-${month}-${day}`;
}

/** weekdays[0]은 일요일. 기간은 YYYYMMDD 또는 YYYY-MM-DDTHH:MM:SS. */
export function operatesOn(
  row: Record<string, unknown>,
  date: string,
  fields: { first: string | readonly string[]; last: string | readonly string[]; weekdays: readonly string[] },
): boolean {
  const first = compactYmd(cell(row, fields.first));
  const last = compactYmd(cell(row, fields.last));
  const ymd = date.replaceAll("-", "");
  if (!first || !last) return false;
  if (ymd < first || ymd > last) return false;
  const day = new Date(Date.UTC(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10)))).getUTCDay();
  const name = fields.weekdays[day];
  if (!name) return false;
  return cell(row, [name])?.toUpperCase() === "Y";
}

export function operatingNumber(flightNumber: string, codeshare: string | null, master: string | null, slaveFlags: readonly string[]): string {
  const flag = codeshare?.trim().toLowerCase() ?? "";
  if (slaveFlags.includes(flag) && master) return master;
  return flightNumber;
}

export function mergeMasterFields(flights: ProviderFlight[]): ProviderFlight[] {
  const masters = new Map<string, ProviderFlight>();
  for (const flight of flights) {
    if (flight.operatingFlightNumber === flight.flightNumber) masters.set(flight.flightNumber, flight);
  }
  return flights.map((flight) => {
    if (flight.operatingFlightNumber === flight.flightNumber) return flight;
    const master = masters.get(flight.operatingFlightNumber);
    if (!master) return flight;
    return {
      ...flight,
      estimatedAt: flight.estimatedAt ?? master.estimatedAt,
      status: flight.status === "unknown" ? master.status : flight.status,
      terminal: flight.terminal ?? master.terminal,
      gate: flight.gate ?? master.gate,
      checkInCounter: flight.checkInCounter ?? master.checkInCounter,
      baggageBelt: flight.baggageBelt ?? master.baggageBelt,
    };
  });
}

export function directionOf(value: string | null): Direction | null {
  if (!value) return null;
  if (value === "출발" || /^(D|O|OUT|DEP|DEPARTURE)$/i.test(value)) return "departure";
  if (value === "도착" || /^(A|I|IN|ARR|ARRIVAL)$/i.test(value)) return "arrival";
  return null;
}
