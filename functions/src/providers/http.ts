import { ProviderError } from "./types";

const TIMEOUT_MS = 10_000;
const MAX_PAGES = 40;
const SUCCESS_CODES = new Set(["00", "0", "03"]);
const RETRYABLE_CODES = new Set(["01", "04", "05", "23"]);

export interface FetchedItems {
  items: Record<string, unknown>[];
  calls: number;
  rateLimitRemaining: number | null;
}

export function redact(message: string, serviceKey: string): string {
  let out = message.replace(/([?&]serviceKey=)[^&\s]*/gi, "$1REDACTED");
  if (serviceKey) {
    out = out.split(serviceKey).join("REDACTED");
    out = out.split(encodeURIComponent(serviceKey)).join("REDACTED");
  }
  return out;
}

export async function fetchAllItems(
  endpoint: string,
  query: Record<string, string>,
  serviceKey: string,
  pageSize: number,
): Promise<FetchedItems> {
  const items: Record<string, unknown>[] = [];
  let calls = 0;
  let rateLimitRemaining: number | null = null;
  let totalCount = Number.POSITIVE_INFINITY;

  for (let page = 1; items.length < totalCount; page += 1) {
    if (page > MAX_PAGES) throw new ProviderError("공공 API 페이지가 너무 많습니다", false);
    const url = endpointUrl(endpoint, {
      ...query,
      serviceKey,
      pageNo: String(page),
      numOfRows: String(pageSize),
      type: "json",
    });
    const result = await getJson(url, serviceKey);
    calls += 1;
    if (result.rateLimitRemaining != null) rateLimitRemaining = result.rateLimitRemaining;
    totalCount = result.totalCount;
    if (result.items.length === 0) break;
    items.push(...result.items);
    if (items.length >= totalCount) break;
  }

  return { items, calls, rateLimitRemaining };
}

function endpointUrl(endpoint: string, query: Record<string, string>): string {
  const url = new URL(endpoint);
  for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
  return url.toString();
}

async function getJson(
  url: string,
  serviceKey: string,
): Promise<{ items: Record<string, unknown>[]; totalCount: number; rateLimitRemaining: number | null }> {
  let response: Response;
  try {
    response = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
  } catch (error) {
    throw new ProviderError(redact(errorText(error), serviceKey), true);
  }

  const rateLimitRemaining = readRemaining(response.headers);
  if (!response.ok) {
    const retryable = response.status === 429 || response.status >= 500;
    throw new ProviderError(redact(`공공 API HTTP ${response.status}`, serviceKey), retryable);
  }

  let text: string;
  try {
    text = await response.text();
  } catch (error) {
    throw new ProviderError(redact(errorText(error), serviceKey), true);
  }
  if (text.trimStart().startsWith("<")) {
    throw new ProviderError("공공 API가 JSON 대신 XML을 반환했습니다", false);
  }

  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new ProviderError("공공 API JSON 파싱 실패", false);
  }
  const page = readEnvelope(json);
  return { ...page, rateLimitRemaining };
}

function readEnvelope(json: unknown): { items: Record<string, unknown>[]; totalCount: number } {
  const root = asRecord(asRecord(json)?.response) ?? asRecord(json);
  if (!root) throw new ProviderError("공공 API 응답 형식이 올바르지 않습니다", false);
  const header = asRecord(root.header);
  const code = header ? text(header.resultCode) : null;
  if (code && !SUCCESS_CODES.has(code)) {
    throw new ProviderError(`공공 API 결과 코드 ${code}`, RETRYABLE_CODES.has(code));
  }
  return readItems(asRecord(root.body));
}

function readItems(body: Record<string, unknown> | undefined): { items: Record<string, unknown>[]; totalCount: number } {
  if (!body) return { items: [], totalCount: 0 };
  const raw = body.items;
  const item = Array.isArray(raw) ? raw : asRecord(raw)?.item;
  const list = item == null || item === "" ? [] : Array.isArray(item) ? item : [item];
  const items = list.filter(isRecord);
  const total = Number(body.totalCount);
  return { items, totalCount: Number.isFinite(total) ? total : items.length };
}

function readRemaining(headers: Headers): number | null {
  const raw = headers.get("x-ratelimit-remaining");
  if (raw == null || raw.trim() === "") return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

function errorText(error: unknown): string {
  if (!(error instanceof Error)) return "공공 API 호출 실패";
  const cause = error.cause instanceof Error ? ` ${error.cause.message}` : "";
  return `${error.message}${cause}`;
}

function text(value: unknown): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  const trimmed = String(value).trim();
  return trimmed === "" ? null : trimmed;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return isRecord(value) ? value : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
