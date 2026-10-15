import { FieldValue } from "firebase-admin/firestore";
import { AppError } from "../domain/errors";
import type { NotifyFlags, RegisterDeviceInput, SettingsPatch } from "../domain/validate";
import { firestore } from "./db";

export async function mergeSettings(uid: string, patch: SettingsPatch): Promise<void> {
  const ref = firestore().doc(`users/${uid}`);
  await firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const write: Record<string, unknown> = { ...patch, updatedAt: FieldValue.serverTimestamp() };
    if (!snap.exists) write.createdAt = FieldValue.serverTimestamp();
    tx.set(ref, write, { merge: true });
  });
}

export async function registerDevice(uid: string, input: RegisterDeviceInput): Promise<void> {
  const db = firestore();
  const ref = db.doc(`users/${uid}/devices/${input.deviceId}`);
  const data: Record<string, unknown> = {
    fcmToken: input.fcmToken,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (input.appVersion !== undefined) data.appVersion = input.appVersion;
  if (input.liveActivityStartToken !== undefined) data.liveActivityStartToken = input.liveActivityStartToken;
  await ref.set(data, { merge: true });

  if (input.fcmToken === null) return;
  await deleteTokenFromOtherUsers(input.fcmToken, ref.path, uid);
}

async function deleteTokenFromOtherUsers(token: string, keepPath: string, uid: string): Promise<void> {
  const db = firestore();
  const dupes = await db.collectionGroup("devices").where("fcmToken", "==", token).get();
  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops === 0) return;
    await batch.commit();
    batch = db.batch();
    ops = 0;
  };
  for (const doc of dupes.docs) {
    const owner = doc.ref.parent.parent?.id;
    if (!owner || owner === uid || doc.ref.path === keepPath) continue;
    batch.delete(doc.ref);
    ops += 1;
    if (ops >= 400) await flush();
  }
  await flush();
}

export async function updateFlightNotify(uid: string, trackedId: string, notify: NotifyFlags): Promise<void> {
  const ref = firestore().doc(`users/${uid}/trackedFlights/${trackedId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new AppError("not-found", "대상을 찾을 수 없습니다");

  const update: Record<string, boolean> = {};
  for (const [key, value] of Object.entries(notify)) {
    if (typeof value === "boolean") update[`notify.${key}`] = value;
  }
  try {
    await ref.update(update);
  } catch (error) {
    if (isNotFound(error)) throw new AppError("not-found", "대상을 찾을 수 없습니다");
    throw error;
  }
}

function isNotFound(error: unknown): boolean {
  if (typeof error !== "object" || error === null || !("code" in error)) return false;
  const code = (error as { code: unknown }).code;
  return code === 5 || code === "not-found" || code === "NOT_FOUND";
}
