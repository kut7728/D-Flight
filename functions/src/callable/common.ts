import { logger } from "firebase-functions/logger";
import type { SecretParam } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { AppError } from "../domain/errors";
import { consumeReportLimit, consumeSearchLimit } from "../store/limits";

export const REGION = "asia-northeast3";

// App Check는 리터럴 true만 쓴다. 배포 CLI가 모듈을 읽어 매니페스트를 만들 때
// FUNCTIONS_EMULATOR 가 있어도 false로 구워지지 않게 한다.
// 에뮬레이터는 skipTokenVerification 으로 비어 있지 않은 X-Firebase-AppCheck 만 통과시킨다.

export type UserLimit = "search" | "report";

export function onAuthenticatedCall<T>(
  handler: (uid: string, data: unknown) => Promise<T>,
  options?: { limit?: UserLimit; secrets?: SecretParam[] },
) {
  return onCall(
    {
      region: REGION,
      invoker: "public",
      enforceAppCheck: true,
      ...(options?.secrets ? { secrets: options.secrets } : {}),
    },
    async (request) => {
      if (!request.auth?.uid || request.auth.uid.includes("/")) {
        throw new HttpsError("unauthenticated", "로그인이 필요합니다");
      }
      const uid = request.auth.uid;
      try {
        if (options?.limit === "search") await consumeSearchLimit(uid);
        if (options?.limit === "report") await consumeReportLimit(uid);
        return await handler(uid, request.data);
      } catch (error) {
        throw toHttpsError(error);
      }
    },
  );
}

function toHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) return error;
  if (error instanceof AppError) {
    return new HttpsError(error.errorCode, error.message);
  }
  logger.error("callable failed", errorLog(error));
  return new HttpsError("internal", "처리에 실패했습니다");
}

function errorLog(error: unknown): { name?: string; message: string; code?: string | number; stack?: string } {
  if (error instanceof Error) {
    const code = "code" in error ? (error as { code?: unknown }).code : undefined;
    return {
      name: error.name,
      message: error.message,
      code: typeof code === "string" || typeof code === "number" ? code : undefined,
      stack: error.stack,
    };
  }
  return { message: "unknown" };
}
