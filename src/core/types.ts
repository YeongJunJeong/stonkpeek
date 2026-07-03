/** 개별 보유 종목. 금액은 모두 KRW로 환산된 값. */
export interface Holding {
  symbol: string;
  name: string;
  /** 시장 국가 코드 ("KR", "US" 등) */
  country: string;
  quantity: number;
  /** 1주당 현재 시장 가격 (KRW 환산) */
  price: number;
  /** 현재 평가금액 (KRW) */
  value: number;
  /** 매입금액 (KRW) */
  cost: number;
  /** 당일 등락률 (%) */
  dayChangePct: number;
  /** 누적 수익률 (%) */
  totalPnlPct: number;
  /** 당일 손익 (KRW) */
  dayPnl: number;
  /** 누적 손익 (KRW) */
  pnl: number;
}

/** 소스(증권사)가 만들어내는 정규화된 계좌 스냅샷 */
export interface PortfolioSnapshot {
  /** 현재 평가금액 (KRW) */
  totalValue: number;
  /** 총 매입금액 (KRW) */
  totalCost: number;
  /** 당일 등락률 (%) */
  dayChangePct: number;
  /** 당일 손익 (KRW) */
  dayPnl: number;
  /** 장중 여부 */
  marketOpen: boolean;
  /** 보유 종목별 내역 (소스가 줄 수 있으면) */
  holdings: Holding[];
  /** 측정 시각 */
  at: Date;
}

export type Mood =
  | "gazua" // 당일 +5% 이상
  | "cruise" // +1 ~ +5%
  | "flat" // -1 ~ +1%
  | "dip" // -1 ~ -5%
  | "mullim" // -5% 이하
  | "deepsea" // 누적 -20% 이하 (당일 등락 무관)
  | "rest"; // 장 마감

export interface RGB {
  r: number;
  g: number;
  b: number;
}

/** 코어가 만들어내는, 모든 싱크가 알아듣는 공용어 */
export interface Signal {
  mood: Mood;
  dayChangePct: number;
  totalPnlPct: number;
  dayPnl: number;
  color: RGB;
  /** 0..1 */
  brightness: number;
  effect: "solid" | "pulse" | "blink";
  emoji: string;
  message: string;
  /** 퇴근 판정: 당일 손익이 출근 후 누적 시급을 넘었는가 */
  offDuty: boolean;
  /** 보유 종목별 내역 (상세 표면용 — 무드 계산엔 쓰지 않고 그대로 실어 나른다) */
  holdings: Holding[];
  /** ISO 8601 */
  at: string;
}

export interface Source {
  name: string;
  fetch(): Promise<PortfolioSnapshot>;
}

export interface Sink {
  name: string;
  /** 연결 수립. 실패해도 다른 싱크는 계속 동작한다. */
  init?(): Promise<void>;
  apply(signal: Signal): Promise<void>;
  close?(): Promise<void>;
}
