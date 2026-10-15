import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { AppError } from "../../src/domain/errors";
import { parseDeleteAccount, parseRegisterDevice, parseSettings, parseUpdateFlightNotify } from "../../src/domain/validate";

const FCM = `tok_${"a".repeat(40)}:APA91bTest`;
const LIVE = "ab".repeat(32);
const DEVICE = "11111111-1111-4111-8111-111111111111";

function rejectsInvalid(fn: () => void): void {
  assert.throws(fn, (error: unknown) => error instanceof AppError && error.errorCode === "invalid-argument");
}

describe("parseSettings", () => {
  it("허용 필드를 받는다", () => {
    assert.deepEqual(parseSettings({ language: "system", pushLanguage: "ko", notificationsEnabled: false, liveActivityEnabled: true }), {
      language: "system",
      pushLanguage: "ko",
      notificationsEnabled: false,
      liveActivityEnabled: true,
    });
  });

  it("모르는 필드·잘못된 값·빈 객체는 거부한다", () => {
    rejectsInvalid(() => parseSettings({}));
    rejectsInvalid(() => parseSettings({ theme: "dark" }));
    rejectsInvalid(() => parseSettings({ language: "jp" }));
    rejectsInvalid(() => parseSettings({ pushLanguage: "system" }));
    rejectsInvalid(() => parseSettings({ notificationsEnabled: "true" }));
    rejectsInvalid(() => parseSettings({ liveActivityEnabled: 1 }));
    rejectsInvalid(() => parseSettings([]));
    rejectsInvalid(() => parseSettings(null));
  });
});

describe("parseRegisterDevice", () => {
  it("등록과 로그아웃 입력을 받는다", () => {
    assert.deepEqual(parseRegisterDevice({ deviceId: DEVICE, fcmToken: FCM, liveActivityStartToken: LIVE, appVersion: "1.0.0" }), {
      deviceId: DEVICE,
      fcmToken: FCM,
      liveActivityStartToken: LIVE,
      appVersion: "1.0.0",
    });
    assert.deepEqual(parseRegisterDevice({ deviceId: DEVICE, fcmToken: null }), {
      deviceId: DEVICE,
      fcmToken: null,
    });
  });

  it("긴 문자열·한글·공백·URL·형식 오류는 거부한다", () => {
    rejectsInvalid(() => parseRegisterDevice({ deviceId: DEVICE, fcmToken: "한".repeat(40), appVersion: "1.0.0" }));
    rejectsInvalid(() => parseRegisterDevice({ deviceId: DEVICE, fcmToken: `${FCM} token`, appVersion: "1.0.0" }));
    rejectsInvalid(() => parseRegisterDevice({ deviceId: DEVICE, fcmToken: "https://evil.example/token-value-long", appVersion: "1.0.0" }));
    rejectsInvalid(() => parseRegisterDevice({ deviceId: DEVICE, fcmToken: "a".repeat(5000), appVersion: "1.0.0" }));
    rejectsInvalid(() => parseRegisterDevice({ deviceId: "short", fcmToken: FCM, appVersion: "1.0.0" }));
    rejectsInvalid(() => parseRegisterDevice({ deviceId: DEVICE, fcmToken: FCM, appVersion: "v1.0.0" }));
    rejectsInvalid(() => parseRegisterDevice({ deviceId: DEVICE, fcmToken: FCM, liveActivityStartToken: "zzzz".repeat(16), appVersion: "1.0.0" }));
    rejectsInvalid(() => parseRegisterDevice({ deviceId: DEVICE, fcmToken: FCM, extra: true, appVersion: "1.0.0" }));
    rejectsInvalid(() => parseRegisterDevice({ deviceId: DEVICE, fcmToken: FCM }));
  });
});

describe("parseUpdateFlightNotify", () => {
  it("바꿀 bool만 받는다", () => {
    assert.deepEqual(parseUpdateFlightNotify({ trackedId: "track_1", notify: { changes: false } }), {
      trackedId: "track_1",
      notify: { changes: false },
    });
  });

  it("모르는 필드와 잘못된 bool은 거부한다", () => {
    rejectsInvalid(() => parseUpdateFlightNotify({ trackedId: "track_1", notify: {} }));
    rejectsInvalid(() => parseUpdateFlightNotify({ trackedId: "track_1", notify: { email: true } }));
    rejectsInvalid(() => parseUpdateFlightNotify({ trackedId: "bad/id", notify: { changes: true } }));
    rejectsInvalid(() => parseUpdateFlightNotify({ trackedId: "track_1", notify: { changes: "true" } }));
    rejectsInvalid(() => parseUpdateFlightNotify({ trackedId: "track_1", notify: { boarding: true }, userId: "x" }));
  });
});

describe("parseDeleteAccount", () => {
  it("빈 입력만 받는다", () => {
    assert.equal(parseDeleteAccount(undefined), undefined);
    assert.equal(parseDeleteAccount(null), undefined);
    assert.equal(parseDeleteAccount({}), undefined);
    rejectsInvalid(() => parseDeleteAccount({ uid: "x" }));
  });
});
