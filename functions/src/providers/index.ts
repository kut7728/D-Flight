import { iiacProvider } from "./iiac";
import { kacProvider } from "./kac";
import type { FlightProvider } from "./types";

export type { Direction, FlightProvider, FlightStatusValue, ProviderCallResult, ProviderFlight, ProviderId } from "./types";
export { ProviderError } from "./types";
export { IIAC_FIELDS, iiacProvider } from "./iiac";
export { KAC_FIELDS, kacProvider } from "./kac";

export function providerFor(airport: string): FlightProvider | null {
  const code = airport.trim().toUpperCase();
  if (iiacProvider.supports(code)) return iiacProvider;
  if (kacProvider.supports(code)) return kacProvider;
  return null;
}
