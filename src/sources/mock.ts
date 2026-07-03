import type { Holding, PortfolioSnapshot, Source } from "../core/types.js";

/** 데모용 가짜 종목들. 평가/매입 비중을 다르게 둬서 종목마다 수익률이 다르게 보이도록. */
const MOCK_DEFS = [
  { symbol: "005930", name: "삼성전자", country: "KR", valueW: 0.45, costW: 0.4, dayOffset: +0.6 },
  { symbol: "AAPL", name: "Apple", country: "US", valueW: 0.3, costW: 0.36, dayOffset: -1.1 },
  { symbol: "035720", name: "카카오", country: "KR", valueW: 0.25, costW: 0.24, dayOffset: +0.4 },
];

/**
 * 랜덤워크 데모 소스. API 키 없이 전체 파이프라인을 굴려볼 수 있다.
 * 2% 확률로 급락 이벤트가 온다. 현실 고증.
 */
export class MockSource implements Source {
  name = "mock";

  private readonly cost = 10_000_000;
  private readonly prevClose: number;
  private value: number;

  constructor(private opts: { alwaysOpen?: boolean; volatility?: number } = {}) {
    // 누적 손익이 어느 정도 쌓인 상태(-15% ~ +15%)에서 시작
    this.prevClose = this.cost * (1 + (Math.random() * 0.3 - 0.15));
    this.value = this.prevClose;
  }

  async fetch(): Promise<PortfolioSnapshot> {
    const vol = this.opts.volatility ?? 0.0015;
    let step = (Math.random() * 2 - 1) * vol;
    if (Math.random() < 0.02) step -= 0.015; // 급락 이벤트
    this.value *= 1 + step;

    const now = new Date();
    const dayChangePct = (this.value / this.prevClose - 1) * 100;

    const holdings: Holding[] = MOCK_DEFS.map((d) => {
      const value = this.value * d.valueW;
      const cost = this.cost * d.costW;
      const day = dayChangePct + d.dayOffset;
      const quantity = Math.max(1, Math.round(value / 150_000));
      return {
        symbol: d.symbol,
        name: d.name,
        country: d.country,
        quantity,
        price: value / quantity,
        value,
        cost,
        dayChangePct: day,
        totalPnlPct: (value / cost - 1) * 100,
        dayPnl: value - value / (1 + day / 100),
        pnl: value - cost,
      };
    });

    return {
      totalValue: this.value,
      totalCost: this.cost,
      dayChangePct,
      dayPnl: this.value - this.prevClose,
      marketOpen: this.opts.alwaysOpen ? true : isKrxOpen(now),
      holdings,
      at: now,
    };
  }
}

/** KRX 정규장: 평일 09:00 ~ 15:30 (로컬 시각이 KST라고 가정. 휴장일 미반영) */
export function isKrxOpen(d: Date): boolean {
  const day = d.getDay();
  if (day === 0 || day === 6) return false;
  const mins = d.getHours() * 60 + d.getMinutes();
  return mins >= 9 * 60 && mins < 15 * 60 + 30;
}
