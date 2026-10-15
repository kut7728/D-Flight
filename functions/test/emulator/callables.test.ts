import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { before, describe, it } from "node:test";
import { AppError } from "../../src/domain/errors";
import { SEARCH_PER_HOUR } from "../../src/domain/limits";
import { auth, firestore } from "../../src/store/db";
import { consumeSearchLimit, userLimitsPath } from "../../src/store/limits";

const FCM_A = `tokA${"a".repeat(40)}:APA91bTest`;
const FCM_B = `tokB${"b".repeat(40)}:APA91bTest`;
const DEVICE_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const DEVICE_A2 = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const DEVICE_B = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const FLIGHT = "XX100_2026-11-01_ICN";
const FLIGHT_B = "XX200_2026-11-01_NRT";

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error("에뮬레이터 환경변수가 없습니다. npm run test:emulator 로 실행하세요.");
  }
});

function projectId(): string {
  return process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "demo-dflight";
}

async function signUp(): Promise<{ uid: string; idToken: string }> {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
  const res = await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      email: `user-${randomUUID()}@example.com`,
      password: "test-password",
      returnSecureToken: true,
    }),
  });
  const body = (await res.json()) as { localId?: string; idToken?: string };
  if (!res.ok || !body.localId || !body.idToken) {
    throw new Error(`auth emulator signup failed: ${res.status}`);
  }
  return { uid: body.localId, idToken: body.idToken };
}

async function callFn(
  name: string,
  data: unknown,
  idToken?: string,
  appCheck = true,
): Promise<{ status: number; body: { result?: unknown; error?: { status?: string } } }> {
  const res = await fetch(`http://127.0.0.1:5001/${projectId()}/asia-northeast3/${name}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      // 에뮬레이터는 이 헤더가 비어 있지 않으면 App Check 검증을 건너뛴다.
      ...(appCheck ? { "x-firebase-appcheck": "emulator" } : {}),
      ...(idToken ? { authorization: `Bearer ${idToken}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  const text = await res.text();
  let body: { result?: unknown; error?: { status?: string } };
  try {
    body = JSON.parse(text) as { result?: unknown; error?: { status?: string } };
  } catch {
    throw new Error(`non-json ${res.status}`);
  }
  return { status: res.status, body };
}

describe("callable 에뮬레이터", () => {
  it("T-53 로그인 없이 호출하면 unauthenticated", async () => {
    const res = await callFn("updateSettings", { language: "ko" });
    assert.equal(res.body.error?.status, "UNAUTHENTICATED");
  });

  it("App Check 헤더가 없으면 unauthenticated", async () => {
    const user = await signUp();
    const res = await callFn("updateSettings", { language: "ko" }, user.idToken, false);
    assert.equal(res.body.error?.status, "UNAUTHENTICATED");
  });

  it("사용자 문서가 없어도 계정 삭제가 끝난다", async () => {
    const user = await signUp();
    await firestore().doc(`users/${user.uid}/devices/${DEVICE_A}`).set({ fcmToken: FCM_A, appVersion: "1.0.0" });
    const deleted = await callFn("deleteAccount", {}, user.idToken);
    assert.equal(deleted.status, 200, JSON.stringify(deleted.body.error));
    assert.equal((await firestore().doc(`users/${user.uid}`).get()).exists, false);
    assert.equal((await firestore().collection(`users/${user.uid}/devices`).get()).empty, true);
    await assert.rejects(() => auth().getUser(user.uid), (error: { code?: string }) => error.code === "auth/user-not-found");
  });

  it("잘못된 설정은 invalid-argument", async () => {
    const user = await signUp();
    const res = await callFn("updateSettings", { language: "jp", extra: true }, user.idToken);
    assert.equal(res.body.error?.status, "INVALID_ARGUMENT");
  });

  it("updateSettings 는 필드를 합치고 첫 저장에만 createdAt 을 둔다", async () => {
    const user = await signUp();
    const first = await callFn("updateSettings", { language: "ko", notificationsEnabled: true }, user.idToken);
    assert.equal(first.status, 200);
    const created = (await firestore().doc(`users/${user.uid}`).get()).get("createdAt");
    assert.ok(created);

    const second = await callFn("updateSettings", { pushLanguage: "ja", liveActivityEnabled: false }, user.idToken);
    assert.equal(second.status, 200);
    const saved = await firestore().doc(`users/${user.uid}`).get();
    assert.equal(saved.get("language"), "ko");
    assert.equal(saved.get("pushLanguage"), "ja");
    assert.equal(saved.get("notificationsEnabled"), true);
    assert.equal(saved.get("liveActivityEnabled"), false);
    assert.deepEqual(saved.get("createdAt"), created);
    assert.ok(saved.get("updatedAt"));
  });

  it("T-57 같은 fcmToken 은 다른 사용자 기기에서 지운다", async () => {
    const a = await signUp();
    const b = await signUp();
    const regA = await callFn(
      "registerDevice",
      { deviceId: DEVICE_A, fcmToken: FCM_A, appVersion: "1.0.0" },
      a.idToken,
    );
    assert.equal(regA.status, 200, JSON.stringify(regA.body.error));
    assert.equal(
      (await callFn("registerDevice", { deviceId: DEVICE_A2, fcmToken: FCM_B, appVersion: "1.2.0" }, a.idToken)).status,
      200,
    );

    const regB = await callFn(
      "registerDevice",
      { deviceId: DEVICE_B, fcmToken: FCM_A, appVersion: "1.0.0" },
      b.idToken,
    );
    assert.equal(regB.status, 200, JSON.stringify(regB.body.error));

    assert.equal((await firestore().doc(`users/${a.uid}/devices/${DEVICE_A}`).get()).exists, false);
    const kept = await firestore().doc(`users/${a.uid}/devices/${DEVICE_A2}`).get();
    assert.equal(kept.get("fcmToken"), FCM_B);
    const moved = await firestore().doc(`users/${b.uid}/devices/${DEVICE_B}`).get();
    assert.equal(moved.get("fcmToken"), FCM_A);
    assert.equal(moved.get("appVersion"), "1.0.0");

    const logout = await callFn("registerDevice", { deviceId: DEVICE_B, fcmToken: null }, b.idToken);
    assert.equal(logout.status, 200);
    const cleared = await firestore().doc(`users/${b.uid}/devices/${DEVICE_B}`).get();
    assert.equal(cleared.get("fcmToken"), null);
    assert.equal(cleared.get("appVersion"), "1.0.0");
  });

  it("updateFlightNotify 는 본인 문서의 bool 만 바꾸고 없으면 not-found", async () => {
    const user = await signUp();
    const missing = await callFn("updateFlightNotify", { trackedId: "missing-track", notify: { changes: false } }, user.idToken);
    assert.equal(missing.body.error?.status, "NOT_FOUND");

    await firestore().doc(`users/${user.uid}/trackedFlights/track1`).set({
      flightKey: FLIGHT,
      notify: { changes: true, dayBefore: true, leaveForAirport: true, boarding: true },
    });
    const updated = await callFn("updateFlightNotify", { trackedId: "track1", notify: { changes: false } }, user.idToken);
    assert.equal(updated.status, 200);
    const notify = (await firestore().doc(`users/${user.uid}/trackedFlights/track1`).get()).get("notify");
    assert.deepEqual(notify, { changes: false, dayBefore: true, leaveForAirport: true, boarding: true });
  });

  it("T-55 계정 삭제는 등록 수·작성자만 정리하고 제보 값은 남긴다", async () => {
    const user = await signUp();
    const other = await signUp();
    const db = firestore();
    await db.doc(`users/${user.uid}`).set({ language: "ko" });
    await db.doc(`users/${user.uid}/devices/${DEVICE_A}`).set({ fcmToken: FCM_A, appVersion: "1.0.0" });
    await db.doc(`flights/${FLIGHT}`).set({
      trackerCount: 2,
      origin: "user",
      operating: { airline: "XX", flightNumber: "XX100" },
    });
    await db.doc(`users/${user.uid}/trackedFlights/mine`).set({ flightKey: FLIGHT });
    await db.doc(`users/${other.uid}/trackedFlights/theirs`).set({ flightKey: FLIGHT });
    await db.doc(`users/${user.uid}/trackedFlights/orphan`).set({ flightKey: "YY200_2026-11-01_KIX" });
    await db.doc(`flights/${FLIGHT}/reportHistory/mine`).set({
      field: "departure.gate",
      oldValue: null,
      newValue: "A1",
      authorUid: user.uid,
    });
    await db.doc(`flights/${FLIGHT}/reportHistory/other`).set({
      field: "departure.gate",
      oldValue: "A1",
      newValue: "B2",
      authorUid: other.uid,
    });

    const deleted = await callFn("deleteAccount", {}, user.idToken);
    assert.equal(deleted.status, 200, JSON.stringify(deleted.body.error));

    assert.equal((await db.doc(`users/${user.uid}`).get()).exists, false);
    assert.equal((await db.collection(`users/${user.uid}/devices`).get()).empty, true);
    assert.equal((await db.collection(`users/${user.uid}/trackedFlights`).get()).empty, true);
    assert.equal((await db.doc(`flights/${FLIGHT}`).get()).get("trackerCount"), 1);
    assert.equal((await db.doc(`users/${other.uid}/trackedFlights/theirs`).get()).exists, true);
    const mine = await db.doc(`flights/${FLIGHT}/reportHistory/mine`).get();
    assert.equal(mine.get("authorUid"), null);
    assert.equal(mine.get("newValue"), "A1");
    assert.equal(mine.get("field"), "departure.gate");
    assert.equal((await db.doc(`flights/${FLIGHT}/reportHistory/other`).get()).get("authorUid"), other.uid);
    await assert.rejects(() => auth().getUser(user.uid), (error: { code?: string }) => error.code === "auth/user-not-found");
  });

  it("T-56 일부만 지운 뒤 다시 호출하면 이어서 끝나고 횟수를 두 번 빼지 않는다", async () => {
    const user = await signUp();
    const db = firestore();
    await db.doc(`flights/${FLIGHT}`).set({ trackerCount: 1, origin: "user" });
    await db.doc(`users/${user.uid}/trackedFlights/left`).set({ flightKey: FLIGHT });
    await db.doc(`flights/${FLIGHT_B}`).set({ trackerCount: 0, origin: "user" });
    await db.doc(`flights/${FLIGHT}/reportHistory/done`).set({
      field: "departure.terminal",
      oldValue: null,
      newValue: "T1",
      authorUid: null,
    });
    await db.doc(`flights/${FLIGHT_B}/reportHistory/left`).set({
      field: "arrival.gate",
      oldValue: null,
      newValue: "C3",
      authorUid: user.uid,
    });

    const resumed = await callFn("deleteAccount", {}, user.idToken);
    assert.equal(resumed.status, 200, JSON.stringify(resumed.body.error));
    assert.equal((await db.doc(`flights/${FLIGHT}`).get()).get("trackerCount"), 0);
    assert.equal((await db.doc(`flights/${FLIGHT_B}`).get()).get("trackerCount"), 0);
    assert.equal((await db.doc(`users/${user.uid}/trackedFlights/left`).get()).exists, false);
    assert.equal((await db.doc(`flights/${FLIGHT}/reportHistory/done`).get()).get("newValue"), "T1");
    const left = await db.doc(`flights/${FLIGHT_B}/reportHistory/left`).get();
    assert.equal(left.get("authorUid"), null);
    assert.equal(left.get("newValue"), "C3");
    await assert.rejects(() => auth().getUser(user.uid), (error: { code?: string }) => error.code === "auth/user-not-found");

    await db.doc(`users/${user.uid}`).set({ language: "ko" });
    await auth().createUser({ uid: user.uid });
    const custom = await auth().createCustomToken(user.uid);
    const host = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
    const signed = await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=demo-key`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    });
    const tokenBody = (await signed.json()) as { idToken?: string };
    assert.ok(tokenBody.idToken);
    const again = await callFn("deleteAccount", {}, tokenBody.idToken);
    assert.equal(again.status, 200, JSON.stringify(again.body.error));
    assert.equal((await db.doc(`flights/${FLIGHT}`).get()).get("trackerCount"), 0);
    assert.equal((await db.doc(`users/${user.uid}`).get()).exists, false);
  });
});

describe("한도 저장", () => {
  it("T-58 검색 31회째는 resource-exhausted 이고 카운터는 system/userLimits 에 있다", async () => {
    const user = await signUp();
    for (let i = 0; i < SEARCH_PER_HOUR; i += 1) await consumeSearchLimit(user.uid);
    await assert.rejects(() => consumeSearchLimit(user.uid), (error: unknown) => error instanceof AppError && error.errorCode === "resource-exhausted");
    const saved = await firestore().doc(userLimitsPath(user.uid)).get();
    assert.equal(saved.get("searchCount"), SEARCH_PER_HOUR);
    assert.equal(userLimitsPath(user.uid), `system/userLimits/users/${user.uid}`);
  });
});
