# StonkPeek — Architecture

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
                                              │  tray (Win, 읽기전용) │
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
| `holdings` | 종목별 내역 배열 (`Holding[]`) — 소스가 줄 수 있으면 |
| `at` | 측정 시각 |

**Holding** (종목 한 건, 금액은 모두 KRW 환산): `symbol`, `name`, `country`, `quantity`, `price`(1주당 현재 시장가), `value`, `cost`, `dayChangePct`, `totalPnlPct`, `dayPnl`, `pnl`. 토스는 `/api/v1/holdings`의 `items`(`price`는 `lastPrice`)에서, mock은 가짜 3종목을 만든다. 해외(USD) 종목은 환율로 원화 환산.

### Signal (코어가 만드는 것 — 모든 싱크의 공용어)

`mood`, `color(RGB)`, `brightness`, `effect(solid/pulse/blink)`, `emoji`, `message`, `offDuty(퇴근 판정)`, 수치들. `holdings`는 무드 계산엔 안 쓰지만 그대로 실어 날라 상세 표면(트레이 창·크롬 팝업·`holdings` 명령)이 쓴다.

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

데몬(`stonkpeek start`)이 매 틱마다 `~/.stonkpeek/state.json`에 Signal을 기록.
`stonkpeek statusline`은 그 파일을 읽어 한 줄 출력하는 **읽기 전용 명령** — Claude Code가 상태줄 갱신할 때마다 실행해도 API 호출이 없어서 가볍다.

```jsonc
// ~/.claude/settings.json
{ "statusLine": { "type": "command", "command": "npx stonkpeek statusline" } }
```

**화면형 싱크 (읽기 전용 소비자) 패턴.** `state.json`을 폴링만 하는 소비자는 엔진 밖 별도 프로세스라 키도 API 호출도 없다 — 전구·키보드 같은 *사물형 싱크*와 구분된다. `statusline`(Claude Code), `tray`(Windows 작업표시줄, `.NET NotifyIcon`을 PowerShell로 구동 → [tray/stonkpeek-tray.ps1](./tray/stonkpeek-tray.ps1))가 여기 속한다. 직장인 스텔스용: 시계 옆 점 색만 등락으로 바뀌고, 전역 보스키(`Ctrl+Alt+H`)로 즉시 무채색이 된다. `tray`는 감정 실린 문구·이모지·풍선 알림 없이 숫자만 보여주는 담백한 표시일 뿐이다(무드 문구·공습경보 점멸·퇴근 알림은 `statusline`/`terminal` 싱크에만 남아 있다).

`tray` 프로세스는 화면 표면을 두 개 갖는다. 기존 등락 점(NotifyIcon)·메뉴에 더해, **트레이 점에 마우스를 0.5초 올리고 있으면 나타나는 종목별 자동 회전 위젯**을 띄운다 — Windows 날씨 위젯처럼 보유 종목을 하나씩(기본 4초 간격) 돌아가며 종목명·현재가·당일/누적 수익률·손익을 보여주다가, 커서가 멀어지면 사라진다. Windows는 서드파티 프로세스가 실제 OS 작업표시줄/알림 영역 내부에 직접 텍스트를 그리는 공개 API를 제공하지 않으므로(explorer.exe 인젝션 같은 비공식 방법은 쓰지 않음), hover 시점의 아이콘 위치를 기준으로 작업표시줄 바로 위에 붙는 테두리 없는 always-on-top WinForms 창으로 근사한다 — 진짜 작업표시줄 안에 렌더링되는 것은 아니라는 점을 명확히 해 둔다. `NotifyIcon.MouseMove`는 Windows 11의 새 트레이 UI에서 신뢰할 수 없어(실측상 아예 안 붙는 경우가 흔함) 대신 `Shell_NotifyIconGetRect` API로 아이콘의 실제 화면 사각형을 얻어 커서 위치를 100ms마다 폴링해 hover 진입/이탈을 판정한다. 진입은 500ms 이상 머물러야 위젯이 뜬다(스쳐 지나갈 때 깜빡이지 않도록). 컨텍스트 메뉴에서 이 hover 동작 자체를 켜고 끌 수 있고, 보스키 토글에도 즉시 반응한다.

**자동 시작 (`stonkpeek install-startup`).** 오픈소스로 배포되는 도구라 "매번 손으로 켜야 함"은 채택 장벽이다. Windows 로그인 시 Startup 폴더(`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`)에 등록되는 `.vbs` 하나로 데몬(`start`)과 `tray`를 조용히(창 없이) 띄운다 — 관리자 권한도, Windows 서비스도 필요 없다(서비스는 Session 0 격리 때문에 트레이 아이콘을 애초에 못 띄운다). `uninstall-startup`으로 해제. 내부적으로 백그라운드 프로세스는 `spawn(...).unref()`가 아니라 `cmd /c start`를 한 겹 거쳐 띄운다 — 일부 환경(잡 오브젝트로 자식 프로세스를 부모에 묶어두는 터미널/샌드박스 등)에서는 `unref()`만으로 분리한 자식이 부모 종료와 함께 조용히(exit code 0으로) 같이 죽는 사례가 있어, 완전히 독립된 프로세스로 뜨는 걸 보장하는 표준적인 우회로 택했다.

브라우저처럼 샌드박스라 `state.json`을 직접 못 읽는 소비자를 위해 `HttpSink`(엔진 안의 진짜 싱크, [src/sinks/http.ts](./src/sinks/http.ts))가 `127.0.0.1:17654/signal`에 최신 Signal을 JSON으로 노출한다. **크롬 툴바 확장**([chrome-extension/](./chrome-extension/))이 이 피드를 폴링해 아이콘을 무드 색 점으로, 배지를 등락률로 칠한다 — 키는 데몬에만 남는다. 같은 피드로 VS Code 상태바·같은 와이파이의 폰 위젯도 동일하게 붙일 수 있다.

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
- [x] v0.4 Windows 작업표시줄 트레이 싱크 (읽기 전용 + 전역 보스키로 즉시 회색)
- [x] v0.4 `HttpSink`(localhost 피드) + 크롬 툴바 확장 (무드 색 아이콘 + 등락률 배지 + 보스키)
- [x] v0.4 종목별 내역(`Holding[]`) — `holdings` 명령 + 트레이 더블클릭 창 + 크롬 팝업
- [x] v0.5 트레이 종목별 자동 회전 위젯 (작업표시줄 코너, 날씨 위젯 스타일, 마우스 오버 0.5초 후 표시)
- [x] v0.5 `install-startup`/`uninstall-startup` — Windows 로그인 시 데몬+트레이 자동 실행 (Startup 폴더 `.vbs`, 관리자 권한/서비스 불필요)
- [ ] v0.5 데모 GIF/영상 README + 공개, CONTRIBUTING.md ("당신의 사물을 연결하세요")
- [ ] HttpSink 위에 VS Code 상태바 / 모바일 위젯 (같은 피드 재사용)
- [ ] 이후: Govee/Tuya, e-ink, Slack 상태, 배경화면 틴트 — 커뮤니티 PR 영역
