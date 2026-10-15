import { readFileSync } from "node:fs";
import { join } from "node:path";

export type Airport = {
  code: string;
  nameKo: string;
  nameJa: string;
  nameEn: string;
  city: string;
  country: string;
  timeZone: string;
  terminals: string[];
  mapURL: string | null;
  korean: boolean;
};

const airports = JSON.parse(readFileSync(join(__dirname, "airports.json"), "utf8")) as Airport[];

const byCode = new Map<string, Airport>(airports.map((airport) => [airport.code, airport]));

export function getAirport(code: string): Airport | undefined {
  return byCode.get(code.trim().toUpperCase());
}

export function isKoreanAirport(code: string): boolean {
  return getAirport(code)?.korean === true;
}
