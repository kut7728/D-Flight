export type Direction = "departure" | "arrival";
export type ProviderId = "iiac" | "kac";
export type FlightStatusValue = "scheduled" | "delayed" | "cancelled" | "departed" | "arrived" | "unknown";

export interface ProviderFlight {
  flightNumber: string;
  operatingFlightNumber: string;
  koreanAirport: string;
  otherAirport: string | null;
  direction: Direction;
  scheduledAt: Date;
  estimatedAt: Date | null;
  status: FlightStatusValue;
  terminal: string | null;
  gate: string | null;
  checkInCounter: string | null;
  baggageBelt: string | null;
  level: "realtime" | "schedule";
}

export interface ProviderCallResult {
  flights: ProviderFlight[];
  calls: number;
  rateLimitRemaining: number | null;
  /** 일정 응답의 lastdate 최댓값(YYYY-MM-DD). 그 날짜에 운항하는 편만 남은 뒤에는 비어 있다. */
  seasonLastDate?: string | null;
}

export interface FlightProvider {
  id: ProviderId;
  supports(airport: string): boolean;
  realtime(airport: string, date: string, direction: Direction, serviceKey: string): Promise<ProviderCallResult>;
  schedule(airport: string, date: string, direction: Direction, serviceKey: string): Promise<ProviderCallResult>;
  gates?(airport: string, direction: Direction, serviceKey: string): Promise<ProviderCallResult>;
}

export class ProviderError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
  ) {
    super(message);
    this.name = "ProviderError";
  }
}
