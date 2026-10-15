import { createRequire } from "node:module";
import type { Airport } from "../data/airports";

type AirportsModule = {
  getAirport: (code: string) => Airport | undefined;
  isKoreanAirport: (code: string) => boolean;
};

let loaded: AirportsModule | null = null;

function airports(): AirportsModule {
  if (loaded) return loaded;
  const require = createRequire(__filename);
  loaded = require("../data/airports.js") as AirportsModule;
  return loaded;
}

export function getAirport(code: string): Airport | undefined {
  return airports().getAirport(code);
}

export function isKoreanAirport(code: string): boolean {
  return airports().isKoreanAirport(code);
}
