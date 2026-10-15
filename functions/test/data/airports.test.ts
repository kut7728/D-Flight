import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it } from "node:test";
import { getAirport, isKoreanAirport, type Airport } from "../../src/data/airports";

const root = join(__dirname, "../../..");
const paths = [
  join(root, "data/airports.json"),
  join(root, "functions/src/data/airports.json"),
  join(root, "DFlight/Resources/airports.json"),
];

describe("airports.json", () => {
  const files = paths.map((path) => readFileSync(path, "utf8"));
  const rows = JSON.parse(files[0]) as Airport[];

  it("세 파일이 같고 한 줄이다", () => {
    assert.equal(files[1], files[0]);
    assert.equal(files[2], files[0]);
    assert.equal(files[0].trim().includes("\n"), false);
    assert.ok(rows.length > 1000);
    assert.equal(new Set(rows.map((row) => row.code)).size, rows.length);
  });

  it("키와 korean 플래그가 계약과 같다", () => {
    const keys = ["code", "nameKo", "nameJa", "nameEn", "city", "country", "timeZone", "terminals", "mapURL", "korean"];
    const icn = rows.find((row) => row.code === "ICN");
    assert.ok(icn);
    assert.deepEqual(Object.keys(icn), keys);
    assert.equal("terminalCodes" in icn, false);
    for (const row of rows) {
      assert.equal(row.korean, row.country === "KR");
      assert.equal(row.timeZone.startsWith("Etc/"), false);
      assert.ok(Array.isArray(row.terminals));
    }
  });
});

describe("getAirport", () => {
  it("인천·김포·하네다·없는 코드", () => {
    const icn = getAirport(" icn ");
    assert.ok(icn);
    assert.equal(icn.code, "ICN");
    assert.equal(icn.nameKo, "인천");
    assert.equal(icn.nameJa, "仁川");
    assert.equal(icn.nameEn, "Incheon");
    assert.equal(icn.country, "KR");
    assert.equal(icn.timeZone, "Asia/Seoul");
    assert.deepEqual(icn.terminals, ["T1", "T2"]);
    assert.equal(icn.mapURL, "https://www.airport.kr/geomap/ap_en/view.do?type=2&alertType=0&tmnlId=P01");
    assert.equal(icn.korean, true);

    const gmp = getAirport("GMP");
    assert.deepEqual(gmp?.terminals, []);
    assert.ok(gmp?.mapURL);

    const hnd = getAirport("hnd");
    assert.deepEqual(hnd?.terminals, ["T1", "T2", "T3"]);
    assert.equal(hnd?.korean, false);
    assert.equal(hnd?.country, "JP");

    const kix = getAirport("KIX");
    assert.deepEqual(kix?.terminals, ["T1", "T2"]);

    const pus = getAirport("PUS");
    assert.deepEqual(pus?.terminals, []);
    assert.equal(pus?.mapURL, null);

    const den = getAirport("DEN");
    assert.ok(den);
    assert.equal(den.nameKo, den.nameEn);
    assert.equal(den.nameJa, den.nameEn);
    assert.deepEqual(den.terminals, []);
    assert.equal(den.mapURL, null);

    assert.equal(getAirport("NOPE"), undefined);
    assert.equal(isKoreanAirport("ICN"), true);
    assert.equal(isKoreanAirport("gmp"), true);
    assert.equal(isKoreanAirport("HND"), false);
    assert.equal(isKoreanAirport("NOPE"), false);
  });
});
