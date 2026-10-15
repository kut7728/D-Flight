export const MINUTE = 60_000;
export const HOUR = 60 * MINUTE;
export const DAY = 24 * HOUR;
/** 시각 변경으로 인정하는 최소 차이. 5분 미만은 저장하지 않아 기준이 흔들리지 않는다. */
export const TIME_CHANGE = 5 * MINUTE;

export function localDate(instant: Date, timeZone: string): string {
  const parts = partsOf(instant, timeZone);
  return `${pad(parts.year)}-${pad(parts.month)}-${pad(parts.day)}`;
}

export function seoulToday(now: Date): string {
  return localDate(now, "Asia/Seoul");
}

export function addDays(date: string, days: number): string {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

export function addYears(date: string, years: number): string {
  const [year, month, day] = date.split("-").map(Number);
  const next = new Date(Date.UTC(year + years, month - 1, day));
  return next.toISOString().slice(0, 10);
}

export function isRealDate(date: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
  const [year, month, day] = date.split("-").map(Number);
  const utc = new Date(Date.UTC(year, month - 1, day));
  return utc.getUTCFullYear() === year && utc.getUTCMonth() === month - 1 && utc.getUTCDate() === day;
}

/** 출발 공항을 검색 전에 모르므로 창은 서울 오늘 −1일 ~ +1년. */
export function isDepartureDateAllowed(date: string, now: Date): boolean {
  if (!isRealDate(date)) return false;
  const today = seoulToday(now);
  return date >= addDays(today, -1) && date <= addYears(today, 1);
}

export function zonedTimeToUtc(date: string, hhmm: string, timeZone: string): Date {
  const [year, month, day] = date.split("-").map(Number);
  const [hour, minute] = hhmm.split(":").map(Number);
  const utcGuess = Date.UTC(year, month - 1, day, hour, minute, 0);
  const first = offsetMs(timeZone, utcGuess);
  const second = offsetMs(timeZone, utcGuess - first);
  return new Date(utcGuess - second);
}

export function startOfLocalDay(date: string, timeZone: string): Date {
  return zonedTimeToUtc(date, "00:00", timeZone);
}

export function yyyymmdd(date: string): string {
  return date.replaceAll("-", "");
}

export function iso(date: Date | null): string | null {
  if (!date) return null;
  return date.toISOString().replace(".000Z", "Z");
}

function offsetMs(timeZone: string, utcMs: number): number {
  const parts = partsOf(new Date(utcMs), timeZone);
  const asUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
  return asUtc - utcMs;
}

function partsOf(instant: Date, timeZone: string): {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
} {
  const formatted = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(instant);
  const pick = (type: string) => Number(formatted.find((part) => part.type === type)?.value);
  let hour = pick("hour");
  if (hour === 24) hour = 0;
  return {
    year: pick("year"),
    month: pick("month"),
    day: pick("day"),
    hour,
    minute: pick("minute"),
    second: pick("second"),
  };
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}
