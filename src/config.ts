import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export interface Config {
  source: "mock" | "toss";
  colorScheme: "kr" | "us";
  pollIntervalSec: number;
  market: "krx" | "always";
  salary: {
    monthly: number;
    hoursPerDay: number;
    workdaysPerMonth: number;
    /** "HH:MM" */
    workStart: string;
  };
  sinks: {
    terminal: { enabled: boolean };
    hue: { enabled: boolean; bridgeIp: string; apiKey: string; lightIds: number[] };
    openrgb: { enabled: boolean; host: string; port: number };
    http: { enabled: boolean; port: number };
  };
  toss: { clientId: string; clientSecret: string; accountNo: string };
}

export const DEFAULT_CONFIG: Config = {
  source: "mock",
  colorScheme: "kr",
  pollIntervalSec: 60,
  market: "krx",
  salary: { monthly: 4_000_000, hoursPerDay: 8, workdaysPerMonth: 22, workStart: "09:00" },
  sinks: {
    terminal: { enabled: true },
    hue: { enabled: false, bridgeIp: "", apiKey: "", lightIds: [1] },
    openrgb: { enabled: false, host: "127.0.0.1", port: 6742 },
    http: { enabled: false, port: 17654 },
  },
  toss: { clientId: "", clientSecret: "", accountNo: "" },
};

/**
 * 설정 파일을 다음 순서로 찾고, 없으면 기본값:
 *   1. ./stonkpeek.config.json                (프로젝트 폴더에서 직접 실행할 때)
 *   2. <프로젝트 루트>/stonkpeek.config.json   (dist/ 옆 — cwd와 무관)
 *   3. ~/.stonkpeek/config.json               (전역 설치용)
 *
 * 2번이 핵심: 자동 시작(로그인 시 .vbs 실행)은 cwd가 System32라 1번을 못 찾는다.
 * config.ts는 dist/config.js(또는 tsx로 src/config.ts)로 실행되며, 둘 다 프로젝트
 * 루트 한 단계 아래이므로 import.meta.url 기준 ../ 가 곧 프로젝트 루트다.
 */
export function loadConfig(): Config {
  const projectRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
  const candidates = [
    join(process.cwd(), "stonkpeek.config.json"),
    join(projectRoot, "stonkpeek.config.json"),
    join(homedir(), ".stonkpeek", "config.json"),
  ];
  for (const p of candidates) {
    if (existsSync(p)) {
      const user = JSON.parse(readFileSync(p, "utf8"));
      return deepMerge(DEFAULT_CONFIG, user);
    }
  }
  return DEFAULT_CONFIG;
}

function deepMerge<T>(base: T, override: Partial<T>): T {
  const out: any = { ...base };
  for (const [k, v] of Object.entries(override as object)) {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      out[k] = deepMerge((base as any)[k] ?? {}, v);
    } else {
      out[k] = v;
    }
  }
  return out;
}
