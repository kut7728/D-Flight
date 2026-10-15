import { auth, firestore } from "./db";

const PAGE = 100;

/**
 * 한도 감소와 등록 문서 삭제는 항공편마다 한 트랜잭션이다.
 * 중간에 끊기면 남아 있는 trackedFlights 만 다시 처리한다.
 */
export async function deleteAccountData(uid: string): Promise<void> {
  await releaseTrackedFlights(uid);
  await clearReportAuthors(uid);
  await deleteKnownUserTree(uid);
  await deleteAuthUser(uid);
}

/** devices 만 지운 뒤 사용자 문서를 지운다. 문서가 없어도 delete 는 성공한다. */
async function deleteKnownUserTree(uid: string): Promise<void> {
  const db = firestore();
  await deleteAll(`users/${uid}/devices`);
  await db.doc(`users/${uid}`).delete();
}

async function deleteAll(path: string): Promise<void> {
  const db = firestore();
  for (;;) {
    const page = await db.collection(path).limit(400).get();
    if (page.empty) return;
    const batch = db.batch();
    for (const doc of page.docs) batch.delete(doc.ref);
    await batch.commit();
  }
}

async function releaseTrackedFlights(uid: string): Promise<void> {
  const db = firestore();
  const col = db.collection(`users/${uid}/trackedFlights`);
  for (;;) {
    const page = await col.limit(PAGE).get();
    if (page.empty) return;
    for (const doc of page.docs) {
      await db.runTransaction(async (tx) => {
        const tracked = await tx.get(doc.ref);
        if (!tracked.exists) return;
        const flightKey = tracked.get("flightKey");
        if (typeof flightKey === "string" && flightKey.length > 0 && !flightKey.includes("/")) {
          const flightRef = db.doc(`flights/${flightKey}`);
          const flight = await tx.get(flightRef);
          if (flight.exists) {
            const count = flight.get("trackerCount");
            const next = typeof count === "number" && count > 0 ? count - 1 : 0;
            tx.update(flightRef, { trackerCount: next });
          }
        }
        tx.delete(doc.ref);
      });
    }
  }
}

async function clearReportAuthors(uid: string): Promise<void> {
  const db = firestore();
  // reportHistory.authorUid 의 컬렉션 그룹 단일 필드 색인이 필요하다.
  for (;;) {
    const page = await db.collectionGroup("reportHistory").where("authorUid", "==", uid).limit(200).get();
    if (page.empty) return;
    const batch = db.batch();
    for (const doc of page.docs) batch.update(doc.ref, { authorUid: null });
    await batch.commit();
  }
}

async function deleteAuthUser(uid: string): Promise<void> {
  try {
    await auth().deleteUser(uid);
  } catch (error) {
    if (isAuthUserNotFound(error)) return;
    throw error;
  }
}

function isAuthUserNotFound(error: unknown): boolean {
  if (typeof error !== "object" || error === null) return false;
  if ("code" in error && (error as { code?: unknown }).code === "auth/user-not-found") return true;
  const info = "errorInfo" in error ? (error as { errorInfo?: { code?: unknown } }).errorInfo : undefined;
  return info?.code === "auth/user-not-found";
}
