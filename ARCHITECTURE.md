# stonkmood — Architecture

> 계좌를 쳐다보지 말고, 느껴라. (Feel your portfolio, don't watch it.)

## 1. 핵심 설계 사상

- **소스 → 시그널 → 싱크** 단방향 파이프라인. 모든 것은 플러그인.
- 코어는 증권사도, 전구도 모른다. `PortfolioSnapshot`을 받아 `Signal`로 정규화할 뿐.
- 싱크 하나가 죽어도 나머지는 산다 (`Promise.allSettled`).
- 조회 전용. 주문 API는 영원히 안 붙인다. 이 프로젝트는 무드등이지 트레이딩 봇이 아니다.

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────────────┐
│   Source     │     │       Core        │     │        Sinks          │
│              │     │                   │     │                       │
│  toss (조회) │ ──► │  PortfolioSnapshot│ ──► │  terminal (데모)      │
│  mock (데모) │     │   → computeSignal │     │  hue (스마트 전구)    │
│  upbit (?)   │     │   → state.json    │     │  openrgb (키보드 RGB) │
└─────────────┘     └──────────────────┘     │  statusline (읽기전용)│
                                              └──────────────────────┘
```

## 2. 데이터 모델

### PortfolioSnapshot (소스가 만드는 것)

| 필드 | 의미 |
|---|---|
| `totalValue` | 현재 평가금액 (KRW) |
| `totalCost` | 총 매입금액 |
| `dayChangePct` | 당일 등락률 (%) |
| `dayPnl` | 당일 손익 (KRW) |
| `marketOpen` | 장중 여부 |
| `at` | 측정 시각 |

### Signal (코어가 만드는 것 — 모든 싱크의 공용어)

`mood`, `color(RGB)`, `brightness`, `effect(solid/pulse/blink)`, `emoji`, `message`, `offDuty(퇴근 판정)`, 수치들.

## 3. 무드 매핑 (제품의 영혼)

| Mood | 조건 | KR 색 | 효과 | 메시지 |
|---|---|---|---|---|
| `gazua` | 당일 +5% ↑ | 진홍 🔴 | solid | 가즈아 |
| `cruise` | +1 ~ +5% | 연한 빨강 | solid | 순항 중 |
| `flat` | -1 ~ +1% | 따뜻한 노랑 | solid | 무풍지대 |
| `dip` | -1 ~ -5% | 하늘색 | solid | 출렁인다 |
| `mullim` | -5% ↓ | 파랑 🔵 | solid | 물렸다 |
| `deepsea` | **누적** -20% ↓ | 심해 남색 | pulse | 심해. 빛이 들지 않는다 |
| `rest` | 장 마감 | 주황 무드등 (어둡게) | solid | 장 마감. 쉬어라 |

추가 규칙:
- **공습경보**: 장중 당일 -3% 이하면 `effect: blink` (전구 깜빡임, 끌 수 있으나 기본 켜짐)
- **컬러 스킴**: `kr`(빨강=상승/파랑=하락, 기본값) / `us`(녹색=상승/빨강=하락). 한국 증시 색 관습이 미국과 반대라는 것 자체가 README 콘텐츠.
- **퇴근 판정기**: 월급 → 시급 환산, `당일 손익 ≥ 출근 후 경과시간 × 시급`이면 `offDuty: true` → "오늘 주식이 너 대신 벌었다. 퇴근해라."

## 4. 플러그인 인터페이스

```ts
interface Source {
  name: string;
  fetch(): Promise<PortfolioSnapshot>;
}

interface Sink {
  name: string;
  init?(): Promise<void>;     // 연결 수립 (실패해도 다른 싱크는 동작)
  apply(signal: Signal): Promise<void>;
  close?(): Promise<void>;
}
```

새 사물을 붙이고 싶으면 `Sink` 하나 구현해서 PR. 이게 커뮤니티 성장 동력.

## 5. Claude Code 상태줄 통합

데몬(`stonkmood start`)이 매 틱마다 `~/.stonkmood/state.json`에 Signal을 기록.
`stonkmood statusline`은 그 파일을 읽어 한 줄 출력하는 **읽기 전용 명령** — Claude Code가 상태줄 갱신할 때마다 실행해도 API 호출이 없어서 가볍다.

```jsonc
// ~/.claude/settings.json
{ "statusLine": { "type": "command", "command": "npx stonkmood statusline" } }
```

출력 예: `🪝 -5.21% 물렸다` / `😎 +1.84% 순항 중 │ 🏃 퇴근각`

## 6. 토스증권 소스 (구현 완료)

- 인증: OAuth 2.0 Client Credentials → `POST https://openapi.tossinvest.com/oauth2/token` (Basic 인증 + `application/x-www-form-urlencoded`). 토큰은 client당 1개만 유효(재발급 시 이전 토큰 무효화)하므로 만료 직전까지 캐시한다.
- 계좌 해석: `GET /api/v1/accounts` → 종합매매 계좌의 `accountSeq`. 이후 사용자 컨텍스트 API의 `X-Tossinvest-Account` 헤더로 사용 (캐시).
- 자산 조회: `GET /api/v1/holdings` → `totalPurchaseAmount`(매입), `marketValue.amount`(평가), `dailyProfitLoss`(당일손익/등락률)를 `PortfolioSnapshot`으로 정규화.
- 환율: 해외(USD) 종목이 있으면 `GET /api/v1/exchange-rate?baseCurrency=USD&quoteCurrency=KRW`로 원화 환산해 합산. 국내 종목만이면 환율 호출 생략.
- **주문 카테고리는 사용하지 않음.** `MockSource`(랜덤워크 + 2% 확률 급락 이벤트)는 키 없이 전체 파이프라인을 굴리는 데모용으로 유지.

## 7. 로드맵

- [x] v0.1 코어 + mock 소스 + terminal/statusline 싱크 (지금)
- [ ] v0.2 Hue 싱크 실기기 검증 + OpenRGB 싱크 + `doctor` 명령
- [x] v0.3 토스증권 공식 Open API 소스 (토큰 발급 + 계좌/보유/환율 조회)
- [ ] v0.4 데모 GIF/영상 README + 공개, CONTRIBUTING.md ("당신의 사물을 연결하세요")
- [ ] 이후: Govee/Tuya, e-ink, Slack 상태, 배경화면 틴트 — 커뮤니티 PR 영역
