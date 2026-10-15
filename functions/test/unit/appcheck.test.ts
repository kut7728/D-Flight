import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { describe, it } from "node:test";

const root = path.resolve(__dirname, "../..");
const names = [
  "updateSettings",
  "registerDevice",
  "updateFlightNotify",
  "deleteAccount",
  "searchFlight",
  "trackFlight",
  "createManualFlight",
  "untrackFlight",
];

function loadAndRejectMissingAppCheck(functionsEmulator: string | undefined): Array<{ name: string; statusCode: number; status?: string; message?: string }> {
  const env = { ...process.env };
  if (functionsEmulator === undefined) delete env.FUNCTIONS_EMULATOR;
  else env.FUNCTIONS_EMULATOR = functionsEmulator;
  const script = `
    const fns = require("./lib/index.js");
    const names = ${JSON.stringify(names)};
    function call(fn) {
      const req = {
        method: "POST",
        body: { data: {} },
        headers: { "content-type": "application/json" },
        header(name) {
          const key = Object.keys(this.headers).find((item) => item.toLowerCase() === name.toLowerCase());
          return key ? this.headers[key] : undefined;
        },
      };
      const res = {
        statusCode: 0,
        payload: undefined,
        headersSent: false,
        status(code) { this.statusCode = code; return this; },
        send(body) { this.payload = body; this.headersSent = true; },
        write() { return true; },
        end() {},
        on() { return this; },
        getHeader() {},
        setHeader() {},
      };
      return Promise.resolve(fn(req, res)).then(() => ({
        statusCode: res.statusCode,
        status: res.payload && res.payload.error && res.payload.error.status,
        message: res.payload && res.payload.error && res.payload.error.message,
      }));
    }
    Promise.all(names.map(async (name) => ({ name, ...(await call(fns[name])) }))).then((rows) => {
      process.stdout.write("\\n__RESULT__" + JSON.stringify(rows));
    }).catch((error) => {
      console.error(error && error.message);
      process.exit(1);
    });
  `;
  const result = spawnSync(process.execPath, ["-e", script], { cwd: root, env, encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  const marked = result.stdout.split("__RESULT__").pop();
  assert.ok(marked, result.stdout);
  return JSON.parse(marked) as Array<{ name: string; statusCode: number; status?: string; message?: string }>;
}

describe("빌드된 callable의 App Check", () => {
  it("배포되는 코드의 enforceAppCheck 는 true 리터럴이다", () => {
    const source = fs.readFileSync(path.join(root, "lib/callable/common.js"), "utf8");
    assert.match(source, /enforceAppCheck:\s*true/);
    assert.equal(source.includes("FUNCTIONS_EMULATOR"), false);
  });

  for (const functionsEmulator of [undefined, "true"] as const) {
    const label = functionsEmulator === undefined ? "FUNCTIONS_EMULATOR 없음" : "FUNCTIONS_EMULATOR=true";
    it(`${label} 이어도 토큰이 없으면 거부한다`, () => {
      const rows = loadAndRejectMissingAppCheck(functionsEmulator);
      assert.deepEqual(rows.map((row) => row.name), names);
      for (const row of rows) {
        assert.equal(row.statusCode, 401, row.name);
        assert.equal(row.status, "UNAUTHENTICATED", row.name);
        assert.equal(row.message, "Unauthenticated", row.name);
      }
    });
  }
});
