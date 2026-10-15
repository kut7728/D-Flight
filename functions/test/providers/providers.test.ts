import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { afterEach, describe, it } from "node:test";
import path from "node:path";
import { kacProvider, providerFor, ProviderError } from "../../src/providers";

const KEY = "zzSECRET99";
const originalFetch = globalThis.fetch;
const fixtureDir = path.join(__dirname, "fixtures");

function load(name: string): unknown {
  return JSON.parse(readFileSync(path.join(fixtureDir, name), "utf8"));
}

function install(match: (url: URL) => unknown, remaining?: string): URL[] {
  const urls: URL[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const url = new URL(String(input));
    urls.push(url);
    const body = match(url);
    if (body instanceof Error) throw body;
    return new Response(JSON.stringify(body), {
      status: 200,
      headers: remaining ? { "x-ratelimit-remaining": remaining } : undefined,
    });
  }) as typeof fetch;
  return urls;
}

function byPath(routes: Record<string, unknown>): (url: URL) => unknown {
  return (url) => routes[Object.keys(routes).find((part) => url.pathname.includes(part)) ?? ""] ?? emptyPage();
}

function emptyPage(): unknown {
  return { response: { header: { resultCode: "00", resultMsg: "NORMAL SERVICE." }, body: { items: "", totalCount: 0 } } };
}

function find<T extends { flightNumber: string }>(flights: T[], flightNumber: string): T {
  const flight = flights.find((item) => item.flightNumber === flightNumber);
  assert.ok(flight, flightNumber);
  return flight;
}

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe("providerFor", () => {
  it("인천은 IIAC, 그 외 한국 공항은 KAC", () => {
    assert.equal(providerFor("ICN")?.id, "iiac");
    assert.equal(providerFor("gmp")?.id, "kac");
    assert.equal(providerFor("NRT"), null);
    assert.equal(kacProvider.supports("ICN"), false);
  });
});

describe("IIAC 운항 현황", () => {
  it("배열 응답을 파싱하고 코드쉐어·터미널·자정 날짜를 유지한다", async () => {
    const urls = install(byPath({ getFltDeparturesDeOdp: load("iiac-depart.json") }), "480");
    const provider = providerFor("ICN");
    assert.ok(provider);
    const result = await provider.realtime("ICN", "2026-10-16", "departure", KEY);

    assert.equal(result.calls, 1);
    assert.equal(result.rateLimitRemaining, 480);
    assert.equal(result.flights.length, 7);
    assert.equal(urls[0].searchParams.get("type"), "json");
    assert.equal(urls[0].searchParams.get("searchdtCode"), "E");
    assert.equal(urls[0].searchParams.get("searchDate"), "20261016");
    assert.equal(urls[0].searchParams.get("passengerOrCargo"), "P");
    assert.equal(urls[0].searchParams.get("numOfRows"), "2000");
    assert.equal(urls[0].searchParams.get("_type"), null);
    assert.equal(urls[0].searchParams.get("serviceKey"), KEY);

    const master = find(result.flights, "XX100");
    const slave = find(result.flights, "YY200");
    assert.equal(master.operatingFlightNumber, "XX100");
    assert.equal(master.terminal, "T2");
    assert.equal(master.gate, "12");
    assert.equal(master.checkInCounter, "A01-A12");
    assert.equal(master.baggageBelt, null);
    assert.equal(master.status, "delayed");
    assert.equal(master.otherAirport, "NRT");
    assert.equal(master.scheduledAt.toISOString(), "2026-10-15T03:00:00.000Z");
    assert.equal(master.estimatedAt?.toISOString(), "2026-10-15T03:30:00.000Z");
    assert.equal(slave.operatingFlightNumber, "XX100");
    assert.equal(slave.gate, "12");
    assert.equal(slave.terminal, "T2");
    assert.equal(slave.checkInCounter, "A01-A12");
    assert.equal(slave.status, "scheduled");
    assert.equal(slave.estimatedAt?.toISOString(), "2026-10-15T03:30:00.000Z");

    const midnight = find(result.flights, "XX300");
    assert.equal(midnight.scheduledAt.toISOString(), "2026-10-15T14:50:00.000Z");
    assert.equal(midnight.status, "departed");
    assert.equal(midnight.checkInCounter, "A B C D");
    assert.equal(find(result.flights, "XX401").terminal, "T1");
    assert.equal(find(result.flights, "XX401").checkInCounter, null);
    assert.equal(find(result.flights, "XX402").terminal, "T1");
    assert.equal(find(result.flights, "XX402").status, "scheduled");
    assert.equal(find(result.flights, "XX403").status, "scheduled");
    assert.equal(find(result.flights, "XX404").status, "scheduled");
  });

  it("item 이 객체 하나여도 도착 편으로 읽는다", async () => {
    install(byPath({ getFltArrivalsDeOdp: load("iiac-arrive-single.json") }));
    const result = await providerFor("ICN")!.realtime("icn", "2026-10-16", "arrival", KEY);
    assert.equal(result.flights.length, 1);
    const flight = result.flights[0];
    assert.equal(flight.flightNumber, "YY500");
    assert.equal(flight.terminal, "T1");
    assert.equal(flight.baggageBelt, null);
    assert.equal(flight.checkInCounter, null);
    assert.equal(flight.status, "arrived");
    assert.equal(flight.level, "realtime");
  });
});

describe("IIAC 정기운항편", () => {
  it("요청한 날짜의 기간·요일에 맞는 편만 시각을 만든다", async () => {
    const urls = install(byPath({ getPaxFltSchedDepartures: load("iiac-schedule.json") }));
    const result = await providerFor("ICN")!.schedule("ICN", "2026-10-15", "departure", KEY);
    assert.deepEqual(result.flights.map((flight) => flight.flightNumber), ["XX110"]);
    const flight = result.flights[0];
    assert.equal(flight.scheduledAt.toISOString(), "2026-10-15T00:30:00.000Z");
    assert.equal(flight.operatingFlightNumber, "XX110");
    assert.equal(flight.otherAirport, "NRT");
    assert.equal(flight.gate, null);
    assert.equal(flight.terminal, null);
    assert.equal(flight.level, "schedule");
    assert.equal(flight.status, "scheduled");
    assert.equal(urls[0].searchParams.get("lang"), null);
    assert.equal(urls[0].searchParams.get("airport"), null);
  });
});

describe("KAC", () => {
  it("코드쉐어는 Y일 때만 운항 편명으로 보고 다른 공항 행은 버린다", async () => {
    const urls = install(byPath({ "/flight-status/depart": load("kac-depart.json") }));
    const result = await providerFor("GMP")!.realtime("GMP", "2026-10-15", "departure", KEY);
    assertKacPage(urls[0]);
    assert.equal(urls[0].searchParams.get("airport_code"), "GMP");
    assert.equal(urls[0].searchParams.get("searchday"), "20261015");
    assert.deepEqual(result.flights.map((flight) => flight.flightNumber), ["XX120", "YY120"]);
    const own = find(result.flights, "XX120");
    const shared = find(result.flights, "YY120");
    assert.equal(own.operatingFlightNumber, "XX120");
    assert.equal(own.otherAirport, "CJU");
    assert.equal(own.status, "cancelled");
    assert.equal(own.terminal, null);
    assert.equal(own.gate, null);
    assert.equal(shared.operatingFlightNumber, "XX120");
    assert.equal(shared.status, "scheduled");
  });

  it("도착은 arrAirportCode 와 arrvAirportCode 를 둘 다 읽는다", async () => {
    install(byPath({ "/flight-status/arrival": load("kac-arrive.json") }));
    const result = await kacProvider.realtime("GMP", "2026-10-15", "arrival", KEY);
    assert.deepEqual(result.flights.map((flight) => flight.flightNumber), ["XX160", "YY160"]);
    assert.equal(find(result.flights, "XX160").otherAirport, "CJU");
    assert.equal(find(result.flights, "YY160").otherAirport, "HND");
  });

  it("운항 현황은 100건씩 페이지를 넘긴다", async () => {
    const urls = install((url) => {
      assertKacPage(url);
      const page = Number(url.searchParams.get("pageNo"));
      const start = (page - 1) * 100 + 1;
      const count = page === 3 ? 50 : 100;
      return {
        response: {
          header: { resultCode: "00" },
          body: {
            totalCount: 250,
            items: {
              item: Array.from({ length: count }, (_, index) => ({
                flightid: `XX${String(start + index).padStart(3, "0")}`,
                scheduledatetime: "202610150900",
                codeshare: "N",
                masterflightid: null,
                rmkKor: "예정",
                depAirportCode: "GMP",
                arrvAirportCode: "CJU",
                io: "O",
              })),
            },
          },
        },
      };
    });
    const result = await kacProvider.realtime("GMP", "2026-10-15", "departure", KEY);
    assert.equal(result.calls, 3);
    assert.equal(result.flights.length, 250);
    assert.equal(urls.length, 3);
  });

  it("스케줄은 T가 있는 기간과 출도착 시각을 구분한다", async () => {
    const urls = install(byPath({
      "/flight-schedule/int": load("kac-schedule-int.json"),
      "/flight-schedule/dom": load("kac-schedule-dom.json"),
    }));
    const depart = await kacProvider.schedule("GMP", "2026-10-15", "departure", KEY);
    assert.deepEqual(depart.flights.map((flight) => flight.flightNumber), ["XX140", "XX170"]);
    assert.equal(depart.flights[0].scheduledAt.toISOString(), "2026-10-14T23:30:00.000Z");
    assert.equal(depart.flights[0].otherAirport, "HND");
    assert.equal(depart.flights[1].scheduledAt.toISOString(), "2026-10-14T22:00:00.000Z");
    assert.equal(depart.flights[1].otherAirport, "CJU");
    assert.equal(depart.calls, 2);
    assert.ok(urls.some((url) => url.searchParams.get("schDeptCityCode") === "GMP"));
    for (const url of urls) assertKacPage(url);

    const arrive = await kacProvider.schedule("GMP", "2026-10-15", "arrival", KEY);
    assert.deepEqual(arrive.flights.map((flight) => flight.flightNumber), ["XX150", "XX171"]);
    assert.equal(arrive.flights[0].scheduledAt.toISOString(), "2026-10-15T10:10:00.000Z");
    assert.equal(arrive.flights[0].otherAirport, "HND");
    assert.equal(arrive.flights[1].scheduledAt.toISOString(), "2026-10-15T02:20:00.000Z");
    assert.ok(urls.some((url) => url.searchParams.get("schArrvCityCode") === "GMP"));
  });

  it("당일 게이트는 HHMM을 오늘 한국 시간으로 읽고 100건씩 넘긴다", async () => {
    const urls = install(byPath({ "/flight-status/info": load("kac-info.json") }));
    const result = await kacProvider.gates!("GMP", "departure", KEY);
    assertKacPage(urls[0]);
    assert.equal(urls[0].searchParams.get("schAirCode"), "GMP");
    assert.equal(urls[0].searchParams.get("airport_code"), null);
    assert.equal(result.flights.length, 1);
    const flight = result.flights[0];
    assert.equal(flight.flightNumber, "XX130");
    assert.equal(flight.gate, "22");
    assert.equal(flight.terminal, null);
    assert.equal(flight.status, "scheduled");
    assert.equal(flight.scheduledAt.toISOString().slice(11, 19), "06:40:00");
    assert.equal(flight.estimatedAt?.toISOString().slice(11, 19), "07:00:00");
    assert.equal(kstDay(flight.scheduledAt), kstDay(new Date()));

    const pagedUrls = install((url) => {
      assertKacPage(url);
      const page = url.searchParams.get("pageNo");
      const start = page === "1" ? 1 : 101;
      const count = page === "1" ? 100 : 1;
      return {
        response: {
          header: { resultCode: "00" },
          body: {
            totalCount: 101,
            items: {
              item: Array.from({ length: count }, (_, index) => ({
                airFln: `XX${String(start + index).padStart(3, "0")}`,
                airport: "PUS",
                io: "O",
                std: "0900",
                gate: String(start + index),
                rmkKor: "예정",
              })),
            },
          },
        },
      };
    });
    const paged = await kacProvider.gates!("PUS", "departure", KEY);
    assert.equal(paged.calls, 2);
    assert.equal(paged.flights.length, 101);
    assert.equal(pagedUrls.length, 2);
  });
});

function assertKacPage(url: URL): void {
  assert.equal(url.searchParams.get("type"), "json");
  assert.equal(url.searchParams.get("_type"), "json");
  assert.equal(url.searchParams.get("numOfRows"), "100");
}

describe("오류", () => {
  it("실패 메시지에서 serviceKey를 지운다", async () => {
    globalThis.fetch = (async (input: RequestInfo | URL) => {
      throw new Error(`failed ${String(input)}`);
    }) as typeof fetch;
    await assert.rejects(
      () => providerFor("ICN")!.realtime("ICN", "2026-10-15", "departure", KEY),
      (error: unknown) => {
        assert.ok(error instanceof ProviderError);
        assert.equal(error.retryable, true);
        assert.equal(error.message.includes(KEY), false);
        assert.match(error.message, /serviceKey=REDACTED/);
        return true;
      },
    );
  });

  it("HTTP 400은 재시도하지 않고 키를 남기지 않는다", async () => {
    globalThis.fetch = (async () => new Response("no", { status: 400 })) as typeof fetch;
    await assert.rejects(
      () => providerFor("ICN")!.realtime("ICN", "2026-10-15", "departure", KEY),
      (error: unknown) => {
        assert.ok(error instanceof ProviderError);
        assert.equal(error.retryable, false);
        assert.equal(error.message.includes(KEY), false);
        return true;
      },
    );
  });
});

function kstDay(date: Date): string {
  return new Date(date.getTime() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}
