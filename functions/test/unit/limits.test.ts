import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { AppError } from "../../src/domain/errors";
import {
  REPORTS_PER_DAY,
  SEARCH_PER_HOUR,
  UPCOMING_TRACKED,
  assertUpcomingTracked,
  consumeReport,
  consumeSearch,
  type ReportCounter,
  type SearchCounter,
} from "../../src/domain/limits";

function isExhausted(error: unknown): boolean {
  return error instanceof AppError && error.errorCode === "resource-exhausted";
}

describe("사용자별 한도", () => {
  it("검색 30회까지 허용하고 31회째는 거부한 뒤 다음 시각에 초기화한다", () => {
    assert.equal(SEARCH_PER_HOUR, 30);
    const now = new Date("2026-10-12T08:30:00Z");
    let state: SearchCounter | undefined;
    for (let i = 0; i < SEARCH_PER_HOUR; i += 1) state = consumeSearch(state, now);
    assert.equal(state?.count, 30);
    assert.throws(() => consumeSearch(state, now), isExhausted);
    const reset = consumeSearch(state, new Date("2026-10-12T09:00:00Z"));
    assert.deepEqual(reset, { hourKey: "2026-10-12T09", count: 1 });
  });

  it("제보 50회까지 허용하고 51회째는 거부한 뒤 다음 날에 초기화한다", () => {
    assert.equal(REPORTS_PER_DAY, 50);
    const now = new Date("2026-10-12T23:00:00Z");
    let state: ReportCounter | undefined;
    for (let i = 0; i < REPORTS_PER_DAY; i += 1) state = consumeReport(state, now);
    assert.throws(() => consumeReport(state, now), isExhausted);
    const reset = consumeReport(state, new Date("2026-10-13T00:00:00Z"));
    assert.deepEqual(reset, { dayKey: "2026-10-13", count: 1 });
  });

  it("다가오는 등록이 30편이면 31번째 등록을 거부한다", () => {
    assert.equal(UPCOMING_TRACKED, 30);
    assert.doesNotThrow(() => assertUpcomingTracked(29));
    assert.throws(() => assertUpcomingTracked(30), isExhausted);
    assert.throws(() => assertUpcomingTracked(31), isExhausted);
  });
});
