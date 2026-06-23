#!/usr/bin/env node
import { loadConfig, type Config } from "./config.js";
import { runEngine } from "./core/engine.js";
import { readState } from "./core/state.js";
import type { Sink, Source } from "./core/types.js";
import { HueSink } from "./sinks/hue.js";
import { OpenRgbSink } from "./sinks/openrgb.js";
import { TerminalSink } from "./sinks/terminal.js";
import { MockSource } from "./sources/mock.js";
import { TossSource } from "./sources/toss.js";

const HELP = `stonkmood — 계좌를 쳐다보지 말고, 느껴라.

사용법:
  stonkmood demo        목업 데이터로 터미널 데모 (API 키 불필요)
  stonkmood start       설정된 소스/싱크로 데몬 실행
  stonkmood statusline  Claude Code 상태줄용 한 줄 출력 (state.json 읽기 전용)
  stonkmood help        이 도움말
`;

function buildSource(cfg: Config): Source {
  return cfg.source === "toss" ? new TossSource(cfg.toss, cfg.market) : new MockSource();
}

function buildSinks(cfg: Config): Sink[] {
  const sinks: Sink[] = [];
  if (cfg.sinks.terminal.enabled) sinks.push(new TerminalSink());
  if (cfg.sinks.hue.enabled) sinks.push(new HueSink(cfg.sinks.hue));
  if (cfg.sinks.openrgb.enabled) sinks.push(new OpenRgbSink(cfg.sinks.openrgb));
  return sinks;
}

async function daemon(cfg: Config, source: Source, sinks: Sink[]): Promise<void> {
  const engine = await runEngine(cfg, source, sinks);
  const shutdown = async () => {
    await engine.stop();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

async function main(): Promise<void> {
  const cmd = process.argv[2] ?? "help";

  switch (cmd) {
    case "demo": {
      const cfg = loadConfig();
      console.log("📈 stonkmood demo — 목업 포트폴리오로 무드를 시연합니다. Ctrl+C로 종료.\n");
      await daemon(
        { ...cfg, pollIntervalSec: 1 },
        new MockSource({ alwaysOpen: true, volatility: 0.004 }),
        [new TerminalSink()],
      );
      break;
    }

    case "start": {
      const cfg = loadConfig();
      const sinks = buildSinks(cfg);
      if (sinks.length === 0) {
        console.error("활성화된 싱크가 없습니다. stonkmood.config.json의 sinks를 확인하세요.");
        process.exit(1);
      }
      console.log(
        `📈 stonkmood start — source: ${cfg.source}, sinks: ${sinks.map((s) => s.name).join(", ")}`,
      );
      await daemon(cfg, buildSource(cfg), sinks);
      break;
    }

    case "statusline": {
      const sig = readState();
      const stale = !sig || Date.now() - Date.parse(sig.at) > 10 * 60_000;
      if (!sig || stale) {
        console.log("💤 stonkmood: 데몬 꺼짐");
        break;
      }
      const pct = `${sig.dayChangePct >= 0 ? "+" : ""}${sig.dayChangePct.toFixed(2)}%`;
      const offDuty = sig.offDuty ? " │ 🏃 퇴근각" : "";
      console.log(`${sig.emoji} ${pct} ${sig.message}${offDuty}`);
      break;
    }

    case "help":
    default:
      console.log(HELP);
  }
}

main().catch((err) => {
  console.error("[stonkmood]", err instanceof Error ? err.message : err);
  process.exit(1);
});
