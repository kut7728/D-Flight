import { AppError } from "./errors";

/** api-spec §1 사용자별 한도. 창은 서버 UTC. */
export const SEARCH_PER_HOUR = 30;
export const REPORTS_PER_DAY = 50;
export const UPCOMING_TRACKED = 30;

export type SearchCounter = { hourKey: string; count: number };
export type ReportCounter = { dayKey: string; count: number };

const exhausted = () => new AppError("resource-exhausted", "잠시 후 다시 시도해 주세요");

export function hourKey(now: Date): string {
  return now.toISOString().slice(0, 13);
}

export function dayKey(now: Date): string {
  return now.toISOString().slice(0, 10);
}

function sameWindowCount(same: boolean, count: number): number {
  if (!same || !Number.isFinite(count) || count < 0) return 0;
  return Math.floor(count);
}

export function consumeSearch(current: SearchCounter | undefined, now: Date): SearchCounter {
  const key = hourKey(now);
  const count = sameWindowCount(current?.hourKey === key, current?.count ?? 0);
  if (count >= SEARCH_PER_HOUR) throw exhausted();
  return { hourKey: key, count: count + 1 };
}

export function consumeReport(current: ReportCounter | undefined, now: Date): ReportCounter {
  const key = dayKey(now);
  const count = sameWindowCount(current?.dayKey === key, current?.count ?? 0);
  if (count >= REPORTS_PER_DAY) throw exhausted();
  return { dayKey: key, count: count + 1 };
}

/** `currentCount`는 추가 전의 다가오는 등록 수. 30이면 31번째라 거부한다. */
export function assertUpcomingTracked(currentCount: number): void {
  if (currentCount >= UPCOMING_TRACKED) throw exhausted();
}
