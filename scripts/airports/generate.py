#!/usr/bin/env python3
"""OurAirports CSV로 공항 기본 데이터를 만든다. CSV는 커밋하지 않는다."""

from __future__ import annotations

import csv
import json
import re
import sys
import urllib.request
from pathlib import Path

from timezonefinder import TimezoneFinder

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CSV_URL = "https://davidmegginson.github.io/ourairports-data/airports.csv"
OUTPUTS = [
    ROOT / "data" / "airports.json",
    ROOT / "functions" / "src" / "data" / "airports.json",
    ROOT / "DFlight" / "Resources" / "airports.json",
]
TYPE_RANK = {"large_airport": 3, "medium_airport": 2, "small_airport": 1}
IATA = re.compile(r"^[A-Z]{3}$")
SUFFIXES = (
    " International Airport",
    " Intl. Airport",
    " Intl Airport",
    " Regional Airport",
    " Municipal Airport",
    " Domestic Airport",
    " Airport",
    " Airfield",
    " Aerodrome",
    " Airstrip",
    " Air Base",
    " Airpark",
    " Air Park",
)
# ponytail: timezonefinder 9에는 closest_timezone_at이 없다. 바다로 잡히면 주변 격자를 본다.
OFFSETS = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))
STEPS = (0.02, 0.05, 0.1, 0.25, 0.5, 1, 2, 4)
EXPECTED_TZ = {
    "ICN": "Asia/Seoul",
    "GMP": "Asia/Seoul",
    "HND": "Asia/Tokyo",
    "NRT": "Asia/Tokyo",
    "KIX": "Asia/Tokyo",
    "LAX": "America/Los_Angeles",
    "JFK": "America/New_York",
    "LHR": "Europe/London",
    "CDG": "Europe/Paris",
    "BKK": "Asia/Bangkok",
    "SIN": "Asia/Singapore",
    "HKG": "Asia/Hong_Kong",
    "HNL": "Pacific/Honolulu",
    "GUM": "Pacific/Guam",
    "SYD": "Australia/Sydney",
    "PEK": "Asia/Shanghai",
}


def short_name(name: str) -> str:
    name = name.strip()
    for suffix in SUFFIXES:
        if name.endswith(suffix) and len(name) - len(suffix) >= 2:
            return name[: -len(suffix)].strip()
    return name


def download() -> str:
    request = urllib.request.Request(CSV_URL, headers={"User-Agent": "dflight-airports-generator"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read().decode("utf-8-sig")


def land_zone(finder: TimezoneFinder, lng: float, lat: float) -> tuple[str | None, bool]:
    zone = finder.timezone_at_land(lng=lng, lat=lat)
    if zone:
        return zone, False
    for step in STEPS:
        for dx, dy in OFFSETS:
            lat2 = lat + dy * step
            if not -90 <= lat2 <= 90:
                continue
            lng2 = lng + dx * step
            if lng2 > 180:
                lng2 -= 360
            elif lng2 < -180:
                lng2 += 360
            zone = finder.timezone_at_land(lng=lng2, lat=lat2)
            if zone:
                return zone, True
    return None, False


def main() -> None:
    overrides = json.loads((HERE / "overrides.json").read_text(encoding="utf-8"))
    best: dict[str, tuple[tuple[int, int, int], dict[str, str]]] = {}
    duplicates = 0
    for raw in csv.DictReader(download().splitlines()):
        rank = TYPE_RANK.get(raw["type"])
        code = (raw.get("iata_code") or "").strip().upper()
        if rank is None or raw.get("scheduled_service") != "yes" or not IATA.fullmatch(code):
            continue
        try:
            lat = float(raw["latitude_deg"])
            lng = float(raw["longitude_deg"])
            row_id = int(raw["id"])
        except ValueError:
            continue
        if not (-90 <= lat <= 90 and -180 <= lng <= 180):
            continue
        key = (rank, 1 if raw.get("wikipedia_link") else 0, -row_id)
        if code in best:
            duplicates += 1
            if key <= best[code][0]:
                continue
        best[code] = (key, {**raw, "lat": str(lat), "lng": str(lng)})

    finder = TimezoneFinder(in_memory=True)
    airports = []
    failures: list[str] = []
    fallbacks: list[str] = []
    for code, (_, raw) in best.items():
        zone, used_fallback = land_zone(finder, float(raw["lng"]), float(raw["lat"]))
        if not zone:
            failures.append(code)
            continue
        if used_fallback:
            fallbacks.append(f"{code}:{zone}")
        extra = overrides.get(code, {})
        name_en = extra.get("nameEn") or short_name(raw["name"])
        airports.append(
            {
                "code": code,
                "nameKo": extra.get("nameKo") or name_en,
                "nameJa": extra.get("nameJa") or name_en,
                "nameEn": name_en,
                "city": (raw.get("municipality") or "").strip(),
                "country": (raw.get("iso_country") or "").strip(),
                "timeZone": zone,
                "terminals": extra.get("terminals") or [],
                "mapURL": extra.get("mapURL"),
                "korean": (raw.get("iso_country") or "").strip() == "KR",
            }
        )

    airports.sort(key=lambda item: item["code"])
    by_code = {item["code"]: item for item in airports}
    mismatches = [f"{code}: {by_code.get(code, {}).get('timeZone')}" for code, zone in EXPECTED_TZ.items() if by_code.get(code, {}).get("timeZone") != zone]
    missing = sorted(set(overrides) - set(by_code))
    payload = json.dumps(airports, ensure_ascii=False, separators=(",", ":")) + "\n"
    for path in OUTPUTS:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload, encoding="utf-8")

    size = OUTPUTS[0].stat().st_size
    print(f"airports {len(airports)}")
    print(f"bytes {size}")
    print(f"duplicates {duplicates}")
    print(f"tz_failures {len(failures)} {' '.join(failures)}")
    print(f"tz_fallback {len(fallbacks)} {' '.join(fallbacks)}")
    print(f"missing_overrides {len(missing)} {' '.join(missing)}")
    print(f"tz_mismatches {len(mismatches)} {' '.join(mismatches)}")
    if failures or mismatches or missing:
        sys.exit(1)


if __name__ == "__main__":
    main()
