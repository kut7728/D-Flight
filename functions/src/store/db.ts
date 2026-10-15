import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

const DEFAULT_APP = "[DEFAULT]";

function ensureApp(): void {
  // App Check 검증이 이름 있는 앱만 만들어도 기본 앱은 따로 연다.
  if (getApps().some((app) => app.name === DEFAULT_APP)) return;
  const projectId = process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT;
  initializeApp(projectId ? { projectId } : undefined);
}

export function firestore() {
  ensureApp();
  return getFirestore();
}

export function auth() {
  ensureApp();
  return getAuth();
}
