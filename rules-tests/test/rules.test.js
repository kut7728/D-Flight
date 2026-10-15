import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import firebase from "firebase/compat/app";
import "firebase/compat/firestore";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";

firebase.firestore.setLogLevel("silent");

const [host, portText] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8180").split(":");
const flightKey = "XX100_2026-11-01_HND";

const writePaths = [
  "users/alice",
  "users/alice/devices/phone",
  "users/alice/trackedFlights/t1",
  `flights/${flightKey}`,
  `flights/${flightKey}/reportHistory/h1`,
  "config/app",
  "notices/n1",
  "system/quota_20261101",
];

let testEnv;

describe("Firestore 보안 규칙", { concurrency: 1 }, () => {
  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: "demo-dflight",
      firestore: {
        rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
        host,
        port: Number(portText),
      },
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  it("T-50 다른 사용자 문서·하위 컬렉션은 거부, 본인 읽기는 허용", async () => {
    await seed([
      ["users/alice", { language: "ko" }],
      ["users/alice/devices/phone", { fcmToken: "token-a" }],
      ["users/alice/trackedFlights/t1", { flightKey, sample: true }],
      ["users/bob", { language: "ja" }],
      ["users/bob/devices/phone", { fcmToken: "token-b" }],
      ["users/bob/trackedFlights/t1", { flightKey: "YY100_2026-11-01_NRT", sample: true }],
    ]);

    const alice = testEnv.authenticatedContext("alice").firestore();
    const anon = testEnv.unauthenticatedContext().firestore();

    const own = await assertSucceeds(alice.doc("users/alice").get());
    assert.equal(own.get("language"), "ko");
    const ownDevices = await assertSucceeds(alice.collection("users/alice/devices").get());
    assert.equal(ownDevices.size, 1);
    const ownTracked = await assertSucceeds(alice.collection("users/alice/trackedFlights").get());
    assert.equal(ownTracked.size, 1);

    await assertFails(alice.doc("users/bob").get());
    await assertFails(alice.doc("users/bob/devices/phone").get());
    await assertFails(alice.doc("users/bob/trackedFlights/t1").get());
    await assertFails(alice.collection("users/bob/devices").get());
    await assertFails(alice.collection("users/bob/trackedFlights").get());
    await assertFails(alice.collection("users").get());

    await assertFails(anon.doc("users/alice").get());
    await assertFails(anon.collection("users/alice/devices").get());
    await assertFails(anon.collection("users/alice/trackedFlights").get());
  });

  it("T-51 클라이언트 쓰기는 로그인·비로그인 모두 거부", async () => {
    await seed(writePaths.map((path) => [path, { sample: true }]));
    const contexts = [
      testEnv.authenticatedContext("alice").firestore(),
      testEnv.unauthenticatedContext().firestore(),
    ];

    for (const db of contexts) {
      for (const path of writePaths) {
        const ref = db.doc(path);
        await assertFails(ref.set({ sample: true }));
        await assertFails(ref.update({ sample: false }));
        await assertFails(ref.delete());
      }
    }
  });

  it("T-52 reportHistory와 system 읽기는 거부", async () => {
    await seed([
      [`flights/${flightKey}`, { trackerCount: 0, sample: true }],
      [`flights/${flightKey}/reportHistory/h1`, { authorUid: "alice", sample: true }],
      ["system/quota_20261101", { count: 1 }],
      ["system/limits/days/20261101", { count: 1 }],
    ]);

    const alice = testEnv.authenticatedContext("alice").firestore();
    const anon = testEnv.unauthenticatedContext().firestore();

    const flight = await assertSucceeds(alice.doc(`flights/${flightKey}`).get());
    assert.equal(flight.get("sample"), true);

    for (const db of [alice, anon]) {
      await assertFails(db.doc(`flights/${flightKey}/reportHistory/h1`).get());
      await assertFails(db.collection(`flights/${flightKey}/reportHistory`).get());
      await assertFails(db.doc("system/quota_20261101").get());
      await assertFails(db.doc("system/limits/days/20261101").get());
      await assertFails(db.collection("system").get());
    }
  });

  it("T-98 비로그인 config/app·notices 읽기 허용, 쓰기는 거부", async () => {
    await seed([
      ["config/app", { minimumVersion: "1.0.0" }],
      ["notices/n1", { title: { ko: "안내" } }],
      [`flights/${flightKey}`, { trackerCount: 0, sample: true }],
    ]);

    const anon = testEnv.unauthenticatedContext().firestore();
    const alice = testEnv.authenticatedContext("alice").firestore();

    const config = await assertSucceeds(anon.doc("config/app").get());
    assert.equal(config.get("minimumVersion"), "1.0.0");
    const notices = await assertSucceeds(anon.collection("notices").get());
    assert.equal(notices.size, 1);

    await assertFails(anon.doc("config/app").set({ minimumVersion: "9.0.0" }));
    await assertFails(anon.doc("notices/n2").set({ title: { ko: "위조" } }));
    await assertFails(anon.doc("notices/n1").update({ important: true }));
    await assertFails(anon.doc("notices/n1").delete());

    await assertFails(anon.doc(`flights/${flightKey}`).get());
    await assertFails(anon.collection("flights").get());
    const flight = await assertSucceeds(alice.doc(`flights/${flightKey}`).get());
    assert.equal(flight.get("sample"), true);

    await assertFails(anon.doc("config/other").get());
    await assertFails(anon.doc("airports/HND").get());
  });

  it("users/{uid}/private 는 본인도 읽기·쓰기 거부", async () => {
    await seed([
      ["users/alice", { language: "ko" }],
      ["users/alice/private/limits", { search: 1 }],
      ["users/alice/private/limits/days/20261101", { search: 1 }],
    ]);

    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertFails(alice.doc("users/alice/private/limits").get());
    await assertFails(alice.doc("users/alice/private/limits/days/20261101").get());
    await assertFails(alice.collection("users/alice/private").get());
    await assertFails(alice.doc("users/alice/private/limits").set({ search: 2 }));
    await assertFails(alice.doc("users/alice/private/limits").update({ search: 2 }));
    await assertFails(alice.doc("users/alice/private/limits").delete());

    const own = await assertSucceeds(alice.doc("users/alice").get());
    assert.equal(own.get("language"), "ko");
  });
});

async function seed(entries) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all(entries.map(([path, data]) => db.doc(path).set(data)));
  });
}
