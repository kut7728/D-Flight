const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const net = require("node:net");
const path = require("node:path");

function ensureEmulatorSecret() {
  const file = path.join(__dirname, "..", ".secret.local");
  const key = "DATA_GO_KR_SERVICE_KEY=";
  let current = "";
  try {
    current = fs.readFileSync(file, "utf8");
  } catch (error) {
    if (!error || error.code !== "ENOENT") throw error;
  }
  const filled = current.split(/\r?\n/).some((line) => line.startsWith(key) && line.slice(key.length).length > 0);
  if (filled) return;
  const prefix = current.length === 0 || current.endsWith("\n") ? "" : "\n";
  fs.appendFileSync(file, `${prefix}${key}emulator-only-dummy\n`);
}

const PORTS = [8180, 9099, 5001];
const WAIT_TRIES = 36;
const RETRIES = 4;
const DELAY_MS = 5000;

function isBusy(port) {
  return new Promise((resolve) => {
    const socket = net.connect({ port, host: "127.0.0.1" });
    const finish = (busy) => {
      socket.removeAllListeners();
      socket.destroy();
      resolve(busy);
    };
    socket.setTimeout(400);
    socket.on("connect", () => finish(true));
    socket.on("timeout", () => finish(true));
    socket.on("error", () => finish(false));
  });
}

async function busyPorts() {
  const busy = [];
  for (const port of PORTS) {
    if (await isBusy(port)) busy.push(port);
  }
  return busy;
}

async function waitUntilFree() {
  for (let i = 1; i <= WAIT_TRIES; i += 1) {
    const busy = await busyPorts();
    if (busy.length === 0) return;
    console.error(`포트 사용 중 (${busy.join(", ")}). 다른 에뮬레이터를 기다립니다. ${i}/${WAIT_TRIES}`);
    await new Promise((resolve) => setTimeout(resolve, DELAY_MS));
  }
  throw new Error("에뮬레이터 포트가 계속 사용 중입니다.");
}

function runFirebase() {
  return spawnSync(
    "firebase",
    [
      "emulators:exec",
      "--project",
      "demo-dflight",
      "--only",
      "auth,firestore,functions",
      "tsx --test --test-concurrency=1 test/emulator/*.test.ts",
    ],
    { stdio: "inherit" },
  );
}

async function main() {
  ensureEmulatorSecret();
  for (let attempt = 1; attempt <= RETRIES; attempt += 1) {
    await waitUntilFree();
    const result = runFirebase();
    if (result.error) throw result.error;
    if (result.status === 0) return;
    const busy = await busyPorts();
    if (busy.length === 0 || attempt === RETRIES) process.exit(result.status ?? 1);
    console.error(`포트가 사용 중입니다 (${busy.join(", ")}). 다시 시도합니다.`);
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
