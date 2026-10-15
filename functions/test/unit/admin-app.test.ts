import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { getApp, getApps, initializeApp } from "firebase-admin/app";
import { auth, firestore } from "../../src/store/db";

describe("Admin 기본 앱", () => {
  it("이름 있는 앱만 있어도 firestore와 auth가 기본 앱을 만든다", () => {
    initializeApp({ projectId: "demo-dflight" }, "other");
    process.env.GCLOUD_PROJECT ??= "demo-dflight";
    assert.ok(firestore());
    assert.ok(auth());
    assert.equal(getApp().name, "[DEFAULT]");
    assert.ok(getApps().some((app) => app.name === "other"));
  });
});
