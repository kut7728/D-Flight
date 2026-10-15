import { AppError, invalidArgument } from "./errors";

export type AppLanguage = "system" | "ko" | "ja" | "en";
export type PushLanguage = "ko" | "ja" | "en";

export type SettingsPatch = {
  language?: AppLanguage;
  pushLanguage?: PushLanguage;
  notificationsEnabled?: boolean;
  liveActivityEnabled?: boolean;
};

export type RegisterDeviceInput = {
  deviceId: string;
  fcmToken: string | null;
  liveActivityStartToken?: string | null;
  appVersion?: string;
};

export type NotifyFlags = {
  changes?: boolean;
  dayBefore?: boolean;
  leaveForAirport?: boolean;
  boarding?: boolean;
};

export type UpdateFlightNotifyInput = {
  trackedId: string;
  notify: NotifyFlags;
};

const LANGUAGES = new Set<AppLanguage>(["system", "ko", "ja", "en"]);
const PUSH_LANGUAGES = new Set<PushLanguage>(["ko", "ja", "en"]);
const SETTINGS_KEYS = ["language", "pushLanguage", "notificationsEnabled", "liveActivityEnabled"] as const;
const DEVICE_KEYS = ["deviceId", "fcmToken", "liveActivityStartToken", "appVersion"] as const;
const NOTIFY_KEYS = ["changes", "dayBefore", "leaveForAirport", "boarding"] as const;

const DEVICE_ID = /^[A-Za-z0-9_-]{8,128}$/;
const TRACKED_ID = /^[A-Za-z0-9_-]{1,128}$/;
const FCM_TOKEN = /^[A-Za-z0-9:_\-.]{32,4096}$/;
const LIVE_ACTIVITY_TOKEN = /^[A-Fa-f0-9]{32,4096}$/;
const APP_VERSION = /^\d{1,3}\.\d{1,3}\.\d{1,3}$/;

function expectObject(data: unknown): Record<string, unknown> {
  if (data === null || typeof data !== "object" || Array.isArray(data)) throw invalidArgument();
  return data as Record<string, unknown>;
}

function assertKnownKeys(obj: Record<string, unknown>, allowed: readonly string[]): void {
  for (const key of Object.keys(obj)) {
    if (!allowed.includes(key)) throw invalidArgument();
  }
}

function expectEnum<T extends string>(value: unknown, allowed: Set<T>): T {
  if (typeof value !== "string" || !allowed.has(value as T)) throw invalidArgument();
  return value as T;
}

function expectBool(value: unknown): boolean {
  if (typeof value !== "boolean") throw invalidArgument();
  return value;
}

export function parseSettings(data: unknown): SettingsPatch {
  const obj = expectObject(data);
  assertKnownKeys(obj, SETTINGS_KEYS);
  if (Object.keys(obj).length === 0) throw invalidArgument();

  const patch: SettingsPatch = {};
  if ("language" in obj) patch.language = expectEnum(obj.language, LANGUAGES);
  if ("pushLanguage" in obj) patch.pushLanguage = expectEnum(obj.pushLanguage, PUSH_LANGUAGES);
  if ("notificationsEnabled" in obj) patch.notificationsEnabled = expectBool(obj.notificationsEnabled);
  if ("liveActivityEnabled" in obj) patch.liveActivityEnabled = expectBool(obj.liveActivityEnabled);
  return patch;
}

export function parseRegisterDevice(data: unknown): RegisterDeviceInput {
  const obj = expectObject(data);
  assertKnownKeys(obj, DEVICE_KEYS);
  if (typeof obj.deviceId !== "string" || !DEVICE_ID.test(obj.deviceId)) throw invalidArgument();
  if (!("fcmToken" in obj)) throw invalidArgument();

  let fcmToken: string | null;
  if (obj.fcmToken === null) fcmToken = null;
  else if (typeof obj.fcmToken === "string" && FCM_TOKEN.test(obj.fcmToken)) fcmToken = obj.fcmToken;
  else throw invalidArgument();

  const input: RegisterDeviceInput = { deviceId: obj.deviceId, fcmToken };

  if ("liveActivityStartToken" in obj) {
    if (obj.liveActivityStartToken === null) input.liveActivityStartToken = null;
    else if (typeof obj.liveActivityStartToken === "string" && LIVE_ACTIVITY_TOKEN.test(obj.liveActivityStartToken)) {
      input.liveActivityStartToken = obj.liveActivityStartToken;
    } else throw invalidArgument();
  }

  if ("appVersion" in obj) {
    if (typeof obj.appVersion !== "string" || !APP_VERSION.test(obj.appVersion)) throw invalidArgument();
    input.appVersion = obj.appVersion;
  } else if (fcmToken !== null) {
    throw invalidArgument();
  }

  return input;
}

export function parseUpdateFlightNotify(data: unknown): UpdateFlightNotifyInput {
  const obj = expectObject(data);
  assertKnownKeys(obj, ["trackedId", "notify"]);
  if (typeof obj.trackedId !== "string" || !TRACKED_ID.test(obj.trackedId)) throw invalidArgument();

  const notifyObj = expectObject(obj.notify);
  assertKnownKeys(notifyObj, NOTIFY_KEYS);
  const present = NOTIFY_KEYS.filter((key) => key in notifyObj);
  if (present.length === 0) throw invalidArgument();

  const notify: NotifyFlags = {};
  for (const key of present) notify[key] = expectBool(notifyObj[key]);
  return { trackedId: obj.trackedId, notify };
}

export function parseDeleteAccount(data: unknown): void {
  if (data === undefined || data === null) return;
  const obj = expectObject(data);
  if (Object.keys(obj).length > 0) throw invalidArgument();
}

export function isAppError(error: unknown): error is AppError {
  return error instanceof AppError;
}
