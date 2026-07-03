import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Signal } from "./types.js";

const STATE_DIR = join(homedir(), ".stonkpeek");
const STATE_FILE = join(STATE_DIR, "state.json");

/** 데몬이 매 틱 기록. statusline 등 읽기 전용 소비자가 API 호출 없이 가져다 쓴다. */
export function writeState(signal: Signal): void {
  mkdirSync(STATE_DIR, { recursive: true });
  writeFileSync(STATE_FILE, JSON.stringify(signal));
}

export function readState(): Signal | null {
  try {
    return JSON.parse(readFileSync(STATE_FILE, "utf8")) as Signal;
  } catch {
    return null;
  }
}
