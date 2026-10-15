import { FieldValue } from "firebase-admin/firestore";
import {
  consumeReport,
  consumeSearch,
  type ReportCounter,
  type SearchCounter,
} from "../domain/limits";
import { firestore } from "./db";

/** 서버 전용. `system/**` 는 클라이언트 읽기·쓰기를 거부해야 한다. */
export function userLimitsPath(uid: string): string {
  return `system/userLimits/users/${uid}`;
}

function searchCounter(data: FirebaseFirestore.DocumentData | undefined): SearchCounter | undefined {
  if (!data || typeof data.searchHourKey !== "string" || typeof data.searchCount !== "number") return undefined;
  return { hourKey: data.searchHourKey, count: data.searchCount };
}

function reportCounter(data: FirebaseFirestore.DocumentData | undefined): ReportCounter | undefined {
  if (!data || typeof data.reportDayKey !== "string" || typeof data.reportCount !== "number") return undefined;
  return { dayKey: data.reportDayKey, count: data.reportCount };
}

export async function consumeSearchLimit(uid: string, now = new Date()): Promise<void> {
  const ref = firestore().doc(userLimitsPath(uid));
  await firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const next = consumeSearch(searchCounter(snap.data()), now);
    tx.set(
      ref,
      { searchHourKey: next.hourKey, searchCount: next.count, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  });
}

export async function consumeReportLimit(uid: string, now = new Date()): Promise<void> {
  const ref = firestore().doc(userLimitsPath(uid));
  await firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const next = consumeReport(reportCounter(snap.data()), now);
    tx.set(
      ref,
      { reportDayKey: next.dayKey, reportCount: next.count, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  });
}
