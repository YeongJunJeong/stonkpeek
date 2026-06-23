import type { Signal, Sink } from "../core/types.js";

/** 데모/디버그용 싱크: 무드 색 블록과 한 줄 메시지를 터미널에 찍는다. */
export class TerminalSink implements Sink {
  name = "terminal";

  private tick = 0;

  async apply(sig: Signal): Promise<void> {
    const { r, g, b } = sig.color;

    // 공습경보(-3% 이하)면 짝수/홀수 틱마다 블록을 교대로 켜고 꺼서 깜빡임을 준다.
    const blinkOff = sig.effect === "blink" && this.tick % 2 === 1;
    const block = blinkOff
      ? " ".repeat(16)
      : `\x1b[38;2;${r};${g};${b}m${"█".repeat(16)}\x1b[0m`;

    const pct = `${sig.dayChangePct >= 0 ? "+" : ""}${sig.dayChangePct.toFixed(2)}%`;
    const total = `(누적 ${sig.totalPnlPct >= 0 ? "+" : ""}${sig.totalPnlPct.toFixed(1)}%)`;
    const alarm = sig.effect === "blink" ? "  🚨 공습경보" : "";
    const offDuty = sig.offDuty ? "  🏃 오늘 주식이 너 대신 벌었다. 퇴근해라." : "";
    const time = new Date().toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });

    const line = `${block}  ${sig.emoji} ${pct} ${total}  ${sig.message}${alarm}${offDuty}  \x1b[2m${time}\x1b[0m`;

    // 첫 틱은 줄바꿈, 이후에는 같은 줄을 덮어쓴다.
    if (this.tick === 0) {
      process.stdout.write(line + "\n");
    } else {
      process.stdout.write(`\r\x1b[2K${line}`);
    }
    this.tick++;
  }
}
