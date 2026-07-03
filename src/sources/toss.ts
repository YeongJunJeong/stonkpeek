import type { Config } from "../config.js";
import type { Holding, PortfolioSnapshot, Source } from "../core/types.js";
import { isKrxOpen } from "./mock.js";

const BASE = "https://openapi.tossinvest.com";

/** 통화별 합산 금액. usd는 해외 종목이 없으면 null. */
interface Price {
  krw: string;
  usd?: string | null;
}

/** 종목 한 건. 금액은 해당 종목 통화(currency) 기준 문자열. */
interface HoldingItem {
  symbol: string;
  name: string;
  marketCountry: string;
  currency: string; // "KRW" | "USD"
  quantity: string;
  lastPrice: string;
  averagePurchasePrice: string;
  marketValue: { purchaseAmount: string; amount: string; amountAfterCost: string };
  profitLoss: { amount: string; rate: string };
  dailyProfitLoss: { amount: string; rate: string };
}

interface HoldingsOverview {
  totalPurchaseAmount: Price; // 투자원금
  marketValue: { amount: Price; amountAfterCost: Price }; // 평가금액
  profitLoss: { amount: Price; rate: string }; // 누적 손익
  dailyProfitLoss: { amount: Price; rate: string }; // 당일 손익
  items: HoldingItem[]; // 종목별 내역
}

interface Account {
  accountNo: string;
  accountSeq: number;
  accountType: string;
}

interface TokenCache {
  token: string;
  expiresAt: number;
}

/**
 * 토스증권 공식 Open API 소스 — 조회 전용. 주문 카테고리는 영원히 사용하지 않는다.
 *
 * 파이프라인:
 *   1. POST /oauth2/token (Basic 인증 + client_credentials) → access token (24h)
 *   2. GET /api/v1/accounts → 종합매매 계좌의 accountSeq 해석 (캐시)
 *   3. GET /api/v1/holdings (X-Tossinvest-Account 헤더) → 평가금액/매입금액/당일손익
 *   4. 해외(USD) 종목이 있으면 GET /api/v1/exchange-rate 로 원화 환산해 합산
 *
 * 토큰은 client당 1개만 유효하므로(재발급 시 이전 토큰 무효화) 만료 직전까지 캐시한다.
 */
export class TossSource implements Source {
  name = "toss";

  private tokenCache?: TokenCache;
  private accountSeq?: number;

  constructor(
    private cfg: Config["toss"],
    private market: Config["market"] = "krx",
  ) {}

  async fetch(): Promise<PortfolioSnapshot> {
    if (!this.cfg.clientId || !this.cfg.clientSecret) {
      throw new Error(
        '토스증권 Open API 키가 설정되지 않았습니다. 키 발급 전까지는 source: "mock"으로 데모를 실행하세요.',
      );
    }

    const token = await this.getToken();
    const seq = await this.resolveAccountSeq(token);
    const h = await this.get<HoldingsOverview>("/api/v1/holdings", token, {
      "X-Tossinvest-Account": String(seq),
    });

    // 해외 종목이 있을 때만 환율을 조회해 원화로 환산한다.
    const usdPresent =
      [h.totalPurchaseAmount.usd, h.marketValue.amount.usd, h.dailyProfitLoss.amount.usd].some(
        (v) => v != null && num(v) !== 0,
      ) || (h.items ?? []).some((it) => it.currency !== "KRW");
    const fx = usdPresent ? await this.getUsdKrw(token) : 0;
    const krw = (p: Price) => num(p.krw) + (p.usd != null ? num(p.usd) * fx : 0);

    // 종목별 내역: 종목 통화가 원화가 아니면 환율로 환산. 등락률(rate)은 통화 무관이라 그대로.
    const holdings: Holding[] = (h.items ?? []).map((it) => {
      const k = (v: string) => num(v) * (it.currency === "KRW" ? 1 : fx);
      return {
        symbol: it.symbol,
        name: it.name,
        country: it.marketCountry,
        quantity: num(it.quantity),
        price: k(it.lastPrice),
        value: k(it.marketValue.amount),
        cost: k(it.marketValue.purchaseAmount),
        dayChangePct: num(it.dailyProfitLoss.rate) * 100,
        totalPnlPct: num(it.profitLoss.rate) * 100,
        dayPnl: k(it.dailyProfitLoss.amount),
        pnl: k(it.profitLoss.amount),
      };
    });

    const now = new Date();
    return {
      totalValue: krw(h.marketValue.amount),
      totalCost: krw(h.totalPurchaseAmount),
      dayChangePct: num(h.dailyProfitLoss.rate) * 100,
      dayPnl: krw(h.dailyProfitLoss.amount),
      marketOpen: this.market === "always" ? true : isKrxOpen(now),
      holdings,
      at: now,
    };
  }

  /** access token 발급/재사용. 만료 60초 전부터 재발급한다. */
  private async getToken(): Promise<string> {
    const now = Date.now();
    if (this.tokenCache && now < this.tokenCache.expiresAt - 60_000) {
      return this.tokenCache.token;
    }

    const basic = Buffer.from(`${this.cfg.clientId}:${this.cfg.clientSecret}`).toString("base64");
    const res = await fetch(`${BASE}/oauth2/token`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${basic}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: "grant_type=client_credentials",
    });
    if (!res.ok) {
      throw new Error(`토스 토큰 발급 실패 (${res.status}): ${await errText(res)}`);
    }
    const json = (await res.json()) as { access_token: string; expires_in: number };
    this.tokenCache = { token: json.access_token, expiresAt: now + json.expires_in * 1000 };
    return json.access_token;
  }

  /** accountNo가 설정돼 있으면 일치하는 계좌, 아니면 첫 계좌의 accountSeq. 한 번 찾으면 캐시. */
  private async resolveAccountSeq(token: string): Promise<number> {
    if (this.accountSeq !== undefined) return this.accountSeq;

    const accounts = await this.get<Account[]>("/api/v1/accounts", token);
    if (accounts.length === 0) {
      throw new Error("토스 종합매매 계좌가 없습니다.");
    }
    const want = this.cfg.accountNo?.trim();
    const acct = want ? accounts.find((a) => a.accountNo === want) : accounts[0];
    if (!acct) {
      throw new Error(`설정한 accountNo(${want})에 해당하는 계좌를 찾을 수 없습니다.`);
    }
    this.accountSeq = acct.accountSeq;
    return acct.accountSeq;
  }

  private fxCache?: { rate: number; validUntil: number };

  private async getUsdKrw(token: string): Promise<number> {
    const now = Date.now();
    if (this.fxCache && now < this.fxCache.validUntil - 2_000) {
      return this.fxCache.rate;
    }
    const r = await this.get<{ rate: string; validUntil: string }>(
      "/api/v1/exchange-rate?baseCurrency=USD&quoteCurrency=KRW",
      token,
    );
    this.fxCache = { rate: num(r.rate), validUntil: Date.parse(r.validUntil) };
    return this.fxCache.rate;
  }

  /** ApiResponse envelope({ result })를 풀어서 반환하는 인증된 GET. */
  private async get<T>(path: string, token: string, headers: Record<string, string> = {}): Promise<T> {
    const res = await fetch(`${BASE}${path}`, {
      headers: { Authorization: `Bearer ${token}`, ...headers },
    });
    if (!res.ok) {
      throw new Error(`토스 API ${path} 실패 (${res.status}): ${await errText(res)}`);
    }
    const json = (await res.json()) as { result: T };
    return json.result;
  }
}

/** decimal 문자열 → number. null/undefined는 0. */
function num(s: string | null | undefined): number {
  return s == null ? 0 : Number(s);
}

/** 에러 본문에서 메시지만 추려 한 줄로. */
async function errText(res: Response): Promise<string> {
  try {
    const body = (await res.json()) as {
      error?: string | { message?: string };
      error_description?: string;
    };
    if (typeof body.error === "object" && body.error?.message) return body.error.message;
    if (body.error_description) return body.error_description;
    if (typeof body.error === "string") return body.error;
    return JSON.stringify(body);
  } catch {
    return res.statusText;
  }
}
