#!/usr/bin/env node
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadConfig, type Config } from "./config.js";
import { runEngine } from "./core/engine.js";
import { readState } from "./core/state.js";
import type { Sink, Source } from "./core/types.js";
import { HttpSink } from "./sinks/http.js";
import { HueSink } from "./sinks/hue.js";
import { OpenRgbSink } from "./sinks/openrgb.js";
import { TerminalSink } from "./sinks/terminal.js";
import { MockSource } from "./sources/mock.js";
import { TossSource } from "./sources/toss.js";

const HELP = `stonkpeek — 계좌를 쳐다보지 말고, 느껴라.

사용법:
  stonkpeek demo        목업 데이터로 터미널 데모 (API 키 불필요)
  stonkpeek start       설정된 소스/싱크로 데몬 실행
  stonkpeek statusline  Claude Code 상태줄용 한 줄 출력 (state.json 읽기 전용)
  stonkpeek holdings    보유 종목별 수익률 표 (현재 소스에서 즉시 조회)
  stonkpeek tray        Windows 작업표시줄 트레이 점 + 종목 시세 위젯(마우스 오버) 띄우기
  stonkpeek install-startup    컴퓨터 켤 때(로그인 시) 데몬+트레이 자동 실행 등록
  stonkpeek uninstall-startup  자동 실행 등록 해제
  stonkpeek help        이 도움말
`;

/** cli.ts(tsx로 직접 실행) / dist/cli.js(빌드본) 어느 쪽이든 동일하게 통하는 이 파일 자신의 절대 경로. */
function selfPath(): string {
  return fileURLToPath(import.meta.url);
}

/**
 * `spawn(...).unref()`만으로는 일부 환경(터미널/에이전트 샌드박스가 자식 프로세스를 잡 오브젝트로
 * 묶어두는 경우 등)에서 부모가 죽을 때 자식까지 같이 죽는다 — 정상 종료 코드로 즉시 사라져서
 * 겉으로는 "그냥 안 뜬다"처럼 보인다. `cmd /c start`를 한 겹 거치면 완전히 독립된 프로세스로
 * 뜬다 — Windows에서 백그라운드 프로세스를 안정적으로 분리 실행하는 표준적인 방법.
 */
function spawnDetachedViaStart(exe: string, args: string[]): void {
  const child = spawn("cmd.exe", ["/c", "start", '""', exe, ...args], {
    detached: true,
    stdio: "ignore",
    windowsHide: true,
  });
  child.unref();
}

/** 데몬(`stonkpeek start`)을 창 없는 백그라운드 프로세스로 띄운다. state.json이 갱신되기 시작한다. */
function launchDaemonBackground(): void {
  spawnDetachedViaStart(process.execPath, [selfPath(), "start"]);
}

/** Windows 로그인 시 자동 실행 등록에 쓰는 Startup 폴더 경로. */
function startupFolder(): string {
  const appData = process.env.APPDATA ?? join(homedir(), "AppData", "Roaming");
  return join(appData, "Microsoft", "Windows", "Start Menu", "Programs", "Startup");
}

const STARTUP_VBS_NAME = "stonkpeek-autostart.vbs";

/** Windows 트레이 아이콘(.NET NotifyIcon)을 별도 프로세스로 분리 실행한다. */
function launchTray(): void {
  if (process.platform !== "win32") {
    console.error("tray 명령은 현재 Windows 전용입니다 (.NET NotifyIcon). macOS/Linux 메뉴바 싱크는 PR 환영.");
    process.exit(1);
  }
  // src/cli.ts(tsx)와 dist/cli.js(빌드) 모두 프로젝트 루트 한 단계 아래 → ../tray 로 동일.
  const script = join(dirname(fileURLToPath(import.meta.url)), "..", "tray", "stonkpeek-tray.ps1");
  const args = [
    "-STA", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
    "-File", script,
  ];
  spawnDetachedViaStart("powershell.exe", args);
  console.log(
    "🟢 트레이 아이콘을 띄웠습니다. 시계 옆 트레이(▲)를 확인하세요." +
      "\n   색이 갱신되려면 데몬이 돌아야 합니다 — 다른 창에서 stonkpeek start (또는 demo).",
  );
}

function buildSource(cfg: Config): Source {
  return cfg.source === "toss" ? new TossSource(cfg.toss, cfg.market) : new MockSource();
}

function buildSinks(cfg: Config): Sink[] {
  const sinks: Sink[] = [];
  if (cfg.sinks.terminal.enabled) sinks.push(new TerminalSink());
  if (cfg.sinks.hue.enabled) sinks.push(new HueSink(cfg.sinks.hue));
  if (cfg.sinks.openrgb.enabled) sinks.push(new OpenRgbSink(cfg.sinks.openrgb));
  if (cfg.sinks.http.enabled) sinks.push(new HttpSink(cfg.sinks.http));
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
      console.log("📈 stonkpeek demo — 목업 포트폴리오로 무드를 시연합니다. Ctrl+C로 종료.\n");
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
        console.error("활성화된 싱크가 없습니다. stonkpeek.config.json의 sinks를 확인하세요.");
        process.exit(1);
      }
      console.log(
        `📈 stonkpeek start — source: ${cfg.source}, sinks: ${sinks.map((s) => s.name).join(", ")}`,
      );
      await daemon(cfg, buildSource(cfg), sinks);
      break;
    }

    case "statusline": {
      const sig = readState();
      const stale = !sig || Date.now() - Date.parse(sig.at) > 10 * 60_000;
      if (!sig || stale) {
        console.log("💤 stonkpeek: 데몬 꺼짐");
        break;
      }
      const pct = `${sig.dayChangePct >= 0 ? "+" : ""}${sig.dayChangePct.toFixed(2)}%`;
      const offDuty = sig.offDuty ? " │ 🏃 퇴근각" : "";
      console.log(`${sig.emoji} ${pct} ${sig.message}${offDuty}`);
      break;
    }

    case "holdings": {
      const cfg = loadConfig();
      const snap = await buildSource(cfg).fetch();
      if (!snap.holdings || snap.holdings.length === 0) {
        console.log("보유 종목 정보가 없습니다. (소스가 종목 리스트를 제공하지 않거나 보유가 없음)");
        break;
      }
      const won = (n: number) => Math.round(n).toLocaleString("ko-KR").padStart(13) + "원";
      const pctC = (n: number) => {
        const s = `${n >= 0 ? "+" : ""}${n.toFixed(2)}%`.padStart(8);
        const color = n > 0 ? 31 : n < 0 ? 34 : 90; // KR 관습: 상승 빨강 / 하락 파랑
        return `\x1b[${color}m${s}\x1b[0m`;
      };
      const emo = (p: number) => (p >= 5 ? "🚀" : p >= 1 ? "😎" : p > -1 ? "😐" : p > -5 ? "🌊" : "🪝");

      console.log(`\n📊 보유 종목 — source: ${cfg.source}\n`);
      for (const h of [...snap.holdings].sort((a, b) => b.value - a.value)) {
        const label = `${h.name} (${h.symbol})`.padEnd(22);
        console.log(
          `${emo(h.dayChangePct)} ${label} ${String(h.quantity).padStart(5)}주  ${won(h.value)}   당일 ${pctC(h.dayChangePct)}   누적 ${pctC(h.totalPnlPct)}`,
        );
      }
      const tTot = snap.totalCost > 0 ? (snap.totalValue / snap.totalCost - 1) * 100 : 0;
      console.log(`${"─".repeat(74)}`);
      console.log(
        `   ${"합계".padEnd(20)} ${"".padStart(6)}  ${won(snap.totalValue)}   당일 ${pctC(snap.dayChangePct)}   누적 ${pctC(tTot)}\n`,
      );
      break;
    }

    case "tray": {
      launchTray();
      break;
    }

    // Startup 폴더의 .vbs가 로그인 시 조용히 호출하는 내부용 명령. 직접 쳐도 되지만
    // 보통은 install-startup으로 등록해두고 잊어버리는 용도.
    case "autostart": {
      launchDaemonBackground();
      launchTray();
      break;
    }

    case "install-startup": {
      if (process.platform !== "win32") {
        console.error("install-startup은 현재 Windows 전용입니다.");
        process.exit(1);
      }
      if (selfPath().endsWith(".ts")) {
        console.error(
          "빌드된 dist/cli.js(또는 전역 설치된 stonkpeek)에서 실행해야 합니다.\n" +
            "먼저 `npm run build` 후 `node dist/cli.js install-startup`을 실행하세요.",
        );
        process.exit(1);
      }
      const folder = startupFolder();
      mkdirSync(folder, { recursive: true });
      const vbsPath = join(folder, STARTUP_VBS_NAME);
      // node.exe를 완전히 숨김창(0)으로 띄우는 전통적인 방법 — .lnk/.cmd는 콘솔 창이 잠깐 보였다 사라진다.
      const vbs = [
        'Set WshShell = CreateObject("WScript.Shell")',
        `WshShell.Run """${process.execPath}"" ""${selfPath()}"" autostart", 0, False`,
      ].join("\r\n");
      writeFileSync(vbsPath, vbs);
      console.log(
        `🟢 자동 시작 등록 완료 — 다음 로그인부터 데몬+트레이가 조용히 뜹니다.\n   ${vbsPath}\n   해제하려면: stonkpeek uninstall-startup`,
      );
      break;
    }

    case "uninstall-startup": {
      const vbsPath = join(startupFolder(), STARTUP_VBS_NAME);
      if (existsSync(vbsPath)) {
        unlinkSync(vbsPath);
        console.log("🔴 자동 시작 등록을 해제했습니다.");
      } else {
        console.log("등록된 자동 시작이 없습니다.");
      }
      break;
    }

    case "help":
    default:
      console.log(HELP);
  }
}

main().catch((err) => {
  console.error("[stonkpeek]", err instanceof Error ? err.message : err);
  process.exit(1);
});
