import { fetchAllItems } from "./http";
import { cell, iata, iiacTerminal, mapRemark, maxSeasonDate, mergeMasterFields, operatingNumber, operatesOn, parseSeoulClock, parseSeoulDateTime, requireDate, requireKey } from "./parse";
import type { Direction, FlightProvider, ProviderCallResult, ProviderFlight } from "./types";
import { ProviderError } from "./types";

/** 라이브 확인 키. scheduleDatetime 의 t 는 소문자. */
export const IIAC_FIELDS = {
  arrivalUrl: "https://apis.data.go.kr/B551177/statusOfAllFltDeOdp/getFltArrivalsDeOdp",
  departureUrl: "https://apis.data.go.kr/B551177/statusOfAllFltDeOdp/getFltDeparturesDeOdp",
  scheduleArrivalUrl: "https://apis.data.go.kr/B551177/PaxFltSched/getPaxFltSchedArrivals",
  scheduleDepartureUrl: "https://apis.data.go.kr/B551177/PaxFltSched/getPaxFltSchedDepartures",
  realtimePageSize: 2000,
  schedulePageSize: 3000,
  flightId: "flightId",
  scheduleAt: "scheduleDatetime",
  estimatedAt: "estimatedDatetime",
  otherAirport: "airportCode",
  codeshare: "codeshare",
  masterFlightId: "masterFlightId",
  terminal: "terminalId",
  gate: "gateNumber",
  checkIn: "chkinRange",
  belt: "carousel",
  remark: "remark",
  scheduleFlightId: "flightid",
  scheduleTime: "st",
  scheduleOtherAirport: "airportcode",
  firstDate: "firstdate",
  lastDate: "lastdate",
  weekdays: ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
} as const;

export const iiacProvider: FlightProvider = {
  id: "iiac",
  supports(airport: string): boolean {
    return airport.trim().toUpperCase() === "ICN";
  },
  realtime(airport, date, direction, serviceKey) {
    return loadRealtime(airport, date, direction, serviceKey);
  },
  schedule(airport, date, direction, serviceKey) {
    return loadSchedule(airport, date, direction, serviceKey);
  },
};

async function loadRealtime(airport: string, date: string, direction: Direction, serviceKey: string): Promise<ProviderCallResult> {
  const code = expectIcn(airport);
  const ymd = requireDate(date);
  requireKey(serviceKey);
  const fetched = await fetchAllItems(
    direction === "departure" ? IIAC_FIELDS.departureUrl : IIAC_FIELDS.arrivalUrl,
    { searchdtCode: "E", searchDate: ymd, searchFrom: "0000", searchTo: "2400", passengerOrCargo: "P" },
    serviceKey,
    IIAC_FIELDS.realtimePageSize,
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
  const code = expectIcn(airport);
  requireDate(date);
  requireKey(serviceKey);
  const fetched = await fetchAllItems(
    direction === "departure" ? IIAC_FIELDS.scheduleDepartureUrl : IIAC_FIELDS.scheduleArrivalUrl,
    {},
    serviceKey,
    IIAC_FIELDS.schedulePageSize,
  );
  const flights = fetched.items.flatMap((row) => {
    const flight = mapSchedule(row, code, date, direction);
    return flight ? [flight] : [];
  });
  return {
    flights,
    calls: fetched.calls,
    rateLimitRemaining: fetched.rateLimitRemaining,
    seasonLastDate: maxSeasonDate(fetched.items, [IIAC_FIELDS.lastDate]),
  };
}

function mapRealtime(row: Record<string, unknown>, airport: string, direction: Direction): ProviderFlight | null {
  const flightNumber = cell(row, IIAC_FIELDS.flightId);
  const scheduledAt = parseSeoulDateTime(cell(row, IIAC_FIELDS.scheduleAt));
  if (!flightNumber || !scheduledAt) return null;
  return {
    flightNumber,
    operatingFlightNumber: operatingNumber(flightNumber, cell(row, IIAC_FIELDS.codeshare), cell(row, IIAC_FIELDS.masterFlightId), ["slave"]),
    koreanAirport: airport,
    otherAirport: iata(row, IIAC_FIELDS.otherAirport, airport),
    direction,
    scheduledAt,
    estimatedAt: parseSeoulDateTime(cell(row, IIAC_FIELDS.estimatedAt)),
    status: mapRemark(cell(row, IIAC_FIELDS.remark)),
    terminal: iiacTerminal(cell(row, IIAC_FIELDS.terminal)),
    gate: cell(row, IIAC_FIELDS.gate),
    checkInCounter: direction === "departure" ? cell(row, IIAC_FIELDS.checkIn) : null,
    baggageBelt: direction === "arrival" ? cell(row, IIAC_FIELDS.belt) : null,
    level: "realtime",
  };
}

function mapSchedule(row: Record<string, unknown>, airport: string, date: string, direction: Direction): ProviderFlight | null {
  if (!operatesOn(row, date, { first: IIAC_FIELDS.firstDate, last: IIAC_FIELDS.lastDate, weekdays: IIAC_FIELDS.weekdays })) return null;
  const flightNumber = cell(row, IIAC_FIELDS.scheduleFlightId);
  const scheduledAt = parseSeoulClock(date, cell(row, IIAC_FIELDS.scheduleTime));
  if (!flightNumber || !scheduledAt) return null;
  return {
    flightNumber,
    operatingFlightNumber: flightNumber,
    koreanAirport: airport,
    otherAirport: iata(row, IIAC_FIELDS.scheduleOtherAirport, airport),
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

function expectIcn(airport: string): string {
  const code = airport.trim().toUpperCase();
  if (code !== "ICN") throw new ProviderError("인천공항 공급원은 ICN만 지원합니다", false);
  return code;
}
