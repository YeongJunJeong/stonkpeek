import type { Config } from "../config.js";
import type { Mood, PortfolioSnapshot, RGB, Signal } from "./types.js";

const MOOD_TEXT: Record<Mood, { emoji: string; message: string }> = {
  gazua: { emoji: "🚀", message: "가즈아" },
  cruise: { emoji: "😎", message: "순항 중" },
  flat: { emoji: "😐", message: "무풍지대" },
  dip: { emoji: "🌊", message: "출렁인다" },
  mullim: { emoji: "🪝", message: "물렸다" },
  deepsea: { emoji: "🌑", message: "심해. 빛이 들지 않는다" },
  rest: { emoji: "🌙", message: "장 마감. 쉬어라" },
};

/** 한국 증시 관습: 빨강 = 상승, 파랑 = 하락 */
const PALETTE_KR: Record<Mood, { color: RGB; brightness: number }> = {
  gazua: { color: { r: 255, g: 45, b: 45 }, brightness: 1.0 },
  cruise: { color: { r: 255, g: 107, b: 90 }, brightness: 0.8 },
  flat: { color: { r: 255, g: 209, b: 122 }, brightness: 0.6 },
  dip: { color: { r: 90, g: 169, b: 255 }, brightness: 0.7 },
  mullim: { color: { r: 45, g: 107, b: 255 }, brightness: 0.8 },
  deepsea: { color: { r: 11, g: 30, b: 91 }, brightness: 0.4 },
  rest: { color: { r: 255, g: 180, b: 107 }, brightness: 0.25 },
};

/** 미국 관습: 녹색 = 상승, 빨강 = 하락 */
const PALETTE_US: Record<Mood, { color: RGB; brightness: number }> = {
  gazua: { color: { r: 45, g: 255, b: 107 }, brightness: 1.0 },
  cruise: { color: { r: 110, g: 230, b: 140 }, brightness: 0.8 },
  flat: PALETTE_KR.flat,
  dip: { color: { r: 255, g: 120, b: 110 }, brightness: 0.7 },
  mullim: { color: { r: 230, g: 57, b: 70 }, brightness: 0.8 },
  deepsea: { color: { r: 80, g: 10, b: 20 }, brightness: 0.4 },
  rest: PALETTE_KR.rest,
};

export function computeSignal(snap: PortfolioSnapshot, cfg: Config): Signal {
  const totalPnlPct =
    snap.totalCost > 0 ? ((snap.totalValue - snap.totalCost) / snap.totalCost) * 100 : 0;

  let mood: Mood;
  if (!snap.marketOpen) mood = "rest";
  else if (totalPnlPct <= -20) mood = "deepsea";
  else if (snap.dayChangePct >= 5) mood = "gazua";
  else if (snap.dayChangePct >= 1) mood = "cruise";
  else if (snap.dayChangePct > -1) mood = "flat";
  else if (snap.dayChangePct > -5) mood = "dip";
  else mood = "mullim";

  // 공습경보: 장중 -3% 이하 급락이면 무드 색 그대로 깜빡인다
  const effect: Signal["effect"] =
    snap.marketOpen && snap.dayChangePct <= -3 ? "blink" : mood === "deepsea" ? "pulse" : "solid";

  const palette = cfg.colorScheme === "us" ? PALETTE_US : PALETTE_KR;
  const { color, brightness } = palette[mood];
  const { emoji, message } = MOOD_TEXT[mood];

  return {
    mood,
    dayChangePct: snap.dayChangePct,
    totalPnlPct,
    dayPnl: snap.dayPnl,
    color,
    brightness,
    effect,
    emoji,
    message,
    offDuty: isOffDuty(snap, cfg),
    holdings: snap.holdings,
    at: snap.at.toISOString(),
  };
}

/** 당일 손익이 출근 후 누적 시급을 넘었으면 true — "주식이 너 대신 벌었다. 퇴근해라." */
function isOffDuty(snap: PortfolioSnapshot, cfg: Config): boolean {
  if (!snap.marketOpen || snap.dayPnl <= 0) return false;
  const { monthly, hoursPerDay, workdaysPerMonth, workStart } = cfg.salary;
  const hourly = monthly / (workdaysPerMonth * hoursPerDay);
  const [h, m] = workStart.split(":").map(Number);
  const start = new Date(snap.at);
  start.setHours(h ?? 9, m ?? 0, 0, 0);
  const elapsedHours = Math.min(
    Math.max((snap.at.getTime() - start.getTime()) / 3_600_000, 0),
    hoursPerDay,
  );
  return elapsedHours > 0 && snap.dayPnl >= elapsedHours * hourly;
}
