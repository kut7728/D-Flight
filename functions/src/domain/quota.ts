import type { Direction, ProviderId } from "../providers/types";
import { addDays, seoulToday, yyyymmdd } from "./time";

/** data-sync §7 개발 한도. KAC 게이트는 실시간 5,000에 포함한다. */
export const QUOTA_LIMITS = {
  "iiac:realtime:departure": 500,
  "iiac:realtime:arrival": 500,
  "iiac:schedule:departure": 1000,
  "iiac:schedule:arrival": 1000,
  "kac:realtime": 5000,
  "kac:schedule:departure": 5000,
  "kac:schedule:arrival": 5000,
} as const;

export type QuotaBucket = keyof typeof QUOTA_LIMITS;
export type QuotaCounts = Partial<Record<QuotaBucket, number>>;
export type QuotaMode = "normal" | "stretched" | "frequentOnly";

export function quotaDocId(now: Date): string {
  return `quota_${yyyymmdd(seoulToday(now))}`;
}

export function quotaCutoffId(now: Date): string {
  return `quota_${yyyymmdd(addDays(seoulToday(now), -30))}`;
}

export function bucketFor(provider: ProviderId, kind: "realtime" | "schedule" | "gates", direction: Direction): QuotaBucket {
  if (provider === "kac" && (kind === "realtime" || kind === "gates")) return "kac:realtime";
  if (provider === "kac") return direction === "departure" ? "kac:schedule:departure" : "kac:schedule:arrival";
  if (kind === "schedule") return direction === "departure" ? "iiac:schedule:departure" : "iiac:schedule:arrival";
  return direction === "departure" ? "iiac:realtime:departure" : "iiac:realtime:arrival";
}

export function ratioOf(counts: QuotaCounts, bucket: QuotaBucket): number {
  return (counts[bucket] ?? 0) / QUOTA_LIMITS[bucket];
}

export function maxRatio(counts: QuotaCounts, buckets: readonly QuotaBucket[]): number {
  return buckets.reduce((max, bucket) => Math.max(max, ratioOf(counts, bucket)), 0);
}

/** 80%부터 hourly를 늘리고, 95%부터는 임박 구간만 조회한다. */
export function quotaMode(ratio: number): QuotaMode {
  if (ratio >= 0.95) return "frequentOnly";
  if (ratio >= 0.8) return "stretched";
  return "normal";
}

export function stricter(left: QuotaMode, right: QuotaMode): QuotaMode {
  const rank: Record<QuotaMode, number> = { normal: 0, stretched: 1, frequentOnly: 2 };
  return rank[left] >= rank[right] ? left : right;
}

export function recordCalls(counts: QuotaCounts, bucket: QuotaBucket, calls: number, remaining: number | null): void {
  const used = (counts[bucket] ?? 0) + Math.max(0, calls);
  const fromHeader = remaining === null ? used : Math.max(used, QUOTA_LIMITS[bucket] - remaining);
  counts[bucket] = fromHeader;
}
