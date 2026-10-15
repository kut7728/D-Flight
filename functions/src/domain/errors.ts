export type AppErrorCode =
  | "invalid-argument"
  | "not-found"
  | "already-exists"
  | "permission-denied"
  | "resource-exhausted"
  | "failed-precondition"
  | "unavailable";

export class AppError extends Error {
  constructor(
    readonly errorCode: AppErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "AppError";
  }
}

export function invalidArgument(): AppError {
  return new AppError("invalid-argument", "입력이 올바르지 않습니다");
}

export function notFound(): AppError {
  return new AppError("not-found", "항공편을 찾을 수 없습니다");
}

export function alreadyExists(): AppError {
  return new AppError("already-exists", "이미 등록된 항공편입니다");
}

export function exhausted(): AppError {
  return new AppError("resource-exhausted", "잠시 후 다시 시도해 주세요");
}

export function unavailable(): AppError {
  return new AppError("unavailable", "지금은 확인할 수 없습니다");
}
