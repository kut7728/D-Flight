import { isKoreanAirport } from "../data/airports";
import { fetchAllItems } from "./http";
import { cell, directionOf, iata, mapRemark, maxSeasonDate, mergeMasterFields, operatingNumber, operatesOn, parseSeoulClock, parseSeoulDateTime, requireDate, requireKey, seoulToday } from "./parse";
import type { Direction, FlightProvider, ProviderCallResult, ProviderFlight } from "./types";
import { ProviderError } from "./types";

/**
 * 라이브 확인 키.
 * schArrvCityCode 는 확인된 schDeptCityCode 의 도착 쪽 짝으로 둔다.
 */
export const KAC_FIELDS = {
  arrivalUrl: "https://apis.data.go.kr/B551178/flight-status/arrival",
  departUrl: "https://apis.data.go.kr/B551178/flight-status/depart",
  infoUrl: "https://apis.data.go.kr/B551178/flight-status/info",
  scheduleIntUrl: "https://apis.data.go.kr/B551178/flight-schedule/int",
  scheduleDomUrl: "https://apis.data.go.kr/B551178/flight-schedule/dom",
  pageSize: 100,
  statusAirport: "airport_code",
  statusDate: "searchday",
  infoAirport: "schAirCode",
  scheduleDate: "schDate",
  scheduleDept: "schDeptCityCode",
  scheduleArrv: "schArrvCityCode",
  flightId: "flightid",
  scheduleAt: "scheduledatetime",
  estimatedAt: "estimateddatetime",
  codeshare: "codeshare",
  masterFlightId: "masterflightid",
  remark: "rmkKor",
  depAirport: "depAirportCode",
  arrAirports: ["arrvAirportCode", "arrAirportCode"],
  io: "io",
  infoFlight: "airFln",
  infoAirportCode: "airport",
  infoStd: "std",
  infoEtd: "etd",
  infoGate: "gate",
  intFlight: "internationalNum",
  intTime: "internationalTime",
  intIo: "internationalIoType",
  intStart: "internationalStdate",
  intEnd: "internationalEddate",
  intAirport: "airportCode",
  intOther: "cityCode",
  intWeekdays: ["internationalSun", "internationalMon", "internationalTue", "internationalWed", "internationalThu", "internationalFri", "internationalSat"],
  domFlight: "domesticNum",
  domStartTime: "domesticStartTime",
  domArrivalTime: "domesticArrivalTime",
  domStart: "domesticStdate",
  domEnd: "domesticEddate",
  domDep: "startcityCode",
  domArr: "arrivalcityCode",
  domWeekdays: ["domesticSun", "domesticMon", "domesticTue", "domesticWed", "domesticThu", "domesticFri", "domesticSat"],
} as const;

const JSON_QUERY = { _type: "json" };

export const kacProvider: FlightProvider = {
  id: "kac",
  supports(airport: string): boolean {
    const code = airport.trim().toUpperCase();
    return code !== "ICN" && isKoreanAirport(code);
  },
  realtime(airport, date, direction, serviceKey) {
    return loadRealtime(airport, date, direction, serviceKey);
  },
  schedule(airport, date, direction, serviceKey) {
    return loadSchedule(airport, date, direction, serviceKey);
  },
  gates(airport, direction, serviceKey) {
    return loadGates(airport, direction, serviceKey);
  },
};

async function loadRealtime(airport: string, date: string, direction: Direction, serviceKey: string): Promise<ProviderCallResult> {
  const code = expectKac(airport);
  const ymd = requireDate(date);
  requireKey(serviceKey);
  const fetched = await fetchAllItems(
    direction === "departure" ? KAC_FIELDS.departUrl : KAC_FIELDS.arrivalUrl,
    { ...JSON_QUERY, [KAC_FIELDS.statusDate]: ymd, [KAC_FIELDS.statusAirport]: code },
    serviceKey,
    KAC_FIELDS.pageSize,
  );
  const flights = mergeMasterFields(
    fetched.items.flatMap((row) => {
      const flight = mapRealtime(row, code, direction);
      return flight ? [flight] : [];
    }),
  );
  return { flights, calls: fetched.calls, rateLimitRemaining: fetched.rateLimitRemaining };
}

async function loadSchedule(airport: string, date: string, direction: Direction, serviceKey: string): Promise<ProviderCallResult> {
  const code = expectKac(airport);
  const ymd = requireDate(date);
  requireKey(serviceKey);
  const place = direction === "departure" ? KAC_FIELDS.scheduleDept : KAC_FIELDS.scheduleArrv;
  const query = { ...JSON_QUERY, [KAC_FIELDS.scheduleDate]: ymd, [place]: code };
  const intl = await fetchAllItems(KAC_FIELDS.scheduleIntUrl, query, serviceKey, KAC_FIELDS.pageSize);
  const domestic = await fetchAllItems(KAC_FIELDS.scheduleDomUrl, query, serviceKey, KAC_FIELDS.pageSize);
  const flights = dedupe([
    ...intl.items.flatMap((row) => {
      const flight = mapInternational(row, code, date, direction);
      return flight ? [flight] : [];
    }),
    ...domestic.items.flatMap((row) => {
      const flight = mapDomestic(row, code, date, direction);
      return flight ? [flight] : [];
    }),
  ]);
  return {
    flights,
    calls: intl.calls + domestic.calls,
    rateLimitRemaining: domestic.rateLimitRemaining ?? intl.rateLimitRemaining,
    seasonLastDate: maxSeasonDate([...intl.items, ...domestic.items], [KAC_FIELDS.intEnd, KAC_FIELDS.domEnd]),
  };
}

async function loadGates(airport: string, direction: Direction, serviceKey: string): Promise<ProviderCallResult> {
  const code = expectKac(airport);
  requireKey(serviceKey);
  const today = seoulToday();
  const fetched = await fetchAllItems(
    KAC_FIELDS.infoUrl,
    { ...JSON_QUERY, [KAC_FIELDS.infoAirport]: code },
    serviceKey,
    KAC_FIELDS.pageSize,
  );
  const flights = fetched.items.flatMap((row) => {
    const flight = mapGate(row, code, direction, today);
    return flight ? [flight] : [];
  });
  return { flights, calls: fetched.calls, rateLimitRemaining: fetched.rateLimitRemaining };
}

function mapRealtime(row: Record<string, unknown>, airport: string, direction: Direction): ProviderFlight | null {
  const homeKeys = direction === "departure" ? [KAC_FIELDS.depAirport] : KAC_FIELDS.arrAirports;
  if (!matchesHome(row, homeKeys, airport)) return null;
  const flightNumber = cell(row, KAC_FIELDS.flightId);
  const scheduledAt = parseSeoulDateTime(cell(row, KAC_FIELDS.scheduleAt));
  if (!flightNumber || !scheduledAt) return null;
  const otherKeys = direction === "departure" ? KAC_FIELDS.arrAirports : [KAC_FIELDS.depAirport];
  return {
    flightNumber,
    operatingFlightNumber: operatingNumber(flightNumber, cell(row, KAC_FIELDS.codeshare), cell(row, KAC_FIELDS.masterFlightId), ["y"]),
    koreanAirport: airport,
    otherAirport: iata(row, otherKeys, airport),
    direction,
    scheduledAt,
    estimatedAt: parseSeoulDateTime(cell(row, KAC_FIELDS.estimatedAt)),
    status: mapRemark(cell(row, KAC_FIELDS.remark)),
    terminal: null,
    gate: null,
    checkInCounter: null,
    baggageBelt: null,
    level: "realtime",
  };
}

function mapInternational(row: Record<string, unknown>, airport: string, date: string, direction: Direction): ProviderFlight | null {
  if (directionOf(cell(row, KAC_FIELDS.intIo)) !== direction) return null;
  if (!matchesHome(row, [KAC_FIELDS.intAirport], airport)) return null;
  if (!operatesOn(row, date, { first: KAC_FIELDS.intStart, last: KAC_FIELDS.intEnd, weekdays: KAC_FIELDS.intWeekdays })) return null;
  const flightNumber = cell(row, KAC_FIELDS.intFlight);
  const scheduledAt = parseSeoulClock(date, cell(row, KAC_FIELDS.intTime));
  if (!flightNumber || !scheduledAt) return null;
  return blankSchedule(flightNumber, airport, iata(row, KAC_FIELDS.intOther, airport), direction, scheduledAt);
}

function mapDomestic(row: Record<string, unknown>, airport: string, date: string, direction: Direction): ProviderFlight | null {
  const homeKey = direction === "departure" ? KAC_FIELDS.domDep : KAC_FIELDS.domArr;
  const otherKey = direction === "departure" ? KAC_FIELDS.domArr : KAC_FIELDS.domDep;
  const timeKey = direction === "departure" ? KAC_FIELDS.domStartTime : KAC_FIELDS.domArrivalTime;
  if (!matchesHome(row, [homeKey], airport)) return null;
  if (!operatesOn(row, date, { first: KAC_FIELDS.domStart, last: KAC_FIELDS.domEnd, weekdays: KAC_FIELDS.domWeekdays })) return null;
  const flightNumber = cell(row, KAC_FIELDS.domFlight);
  const scheduledAt = parseSeoulClock(date, cell(row, timeKey));
  if (!flightNumber || !scheduledAt) return null;
  return blankSchedule(flightNumber, airport, iata(row, otherKey, airport), direction, scheduledAt);
}

function mapGate(row: Record<string, unknown>, airport: string, direction: Direction, today: string): ProviderFlight | null {
  if (directionOf(cell(row, KAC_FIELDS.io)) !== direction) return null;
  if (!matchesHome(row, [KAC_FIELDS.infoAirportCode], airport)) return null;
  const flightNumber = cell(row, KAC_FIELDS.infoFlight);
  const scheduledAt = parseSeoulClock(today, cell(row, KAC_FIELDS.infoStd));
  if (!flightNumber || !scheduledAt) return null;
  return {
    flightNumber,
    operatingFlightNumber: flightNumber,
    koreanAirport: airport,
    otherAirport: null,
    direction,
    scheduledAt,
    estimatedAt: parseSeoulClock(today, cell(row, KAC_FIELDS.infoEtd)),
    status: mapRemark(cell(row, KAC_FIELDS.remark)),
    terminal: null,
    gate: cell(row, KAC_FIELDS.infoGate),
    checkInCounter: null,
    baggageBelt: null,
    level: "realtime",
  };
}

function blankSchedule(flightNumber: string, airport: string, otherAirport: string | null, direction: Direction, scheduledAt: Date): ProviderFlight {
  return {
    flightNumber,
    operatingFlightNumber: flightNumber,
    koreanAirport: airport,
    otherAirport,
    direction,
    scheduledAt,
    estimatedAt: null,
    status: "scheduled",
    terminal: null,
    gate: null,
    checkInCounter: null,
    baggageBelt: null,
    level: "schedule",
  };
}

function matchesHome(row: Record<string, unknown>, keys: readonly string[], airport: string): boolean {
  const codes = keys.flatMap((key) => {
    const code = iata(row, key, "");
    return code ? [code] : [];
  });
  return codes.length === 0 || codes.includes(airport);
}

function dedupe(flights: ProviderFlight[]): ProviderFlight[] {
  const seen = new Set<string>();
  const out: ProviderFlight[] = [];
  for (const flight of flights) {
    const key = `${flight.flightNumber}|${flight.scheduledAt.getTime()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(flight);
  }
  return out;
}

function expectKac(airport: string): string {
  const code = airport.trim().toUpperCase();
  if (!kacProvider.supports(code)) throw new ProviderError("한국공항공사 공급원이 지원하지 않는 공항입니다", false);
  return code;
}
