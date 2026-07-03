# StonkPeek

> **계좌를 쳐다보지 말고, 느껴라.**
> Ambient portfolio for your room — your smart bulb, RGB keyboard, and Claude Code statusline quietly reflect how your stocks are doing.

차트 앱을 하루 30번 여는 대신, 방 안의 사물이 은은하게 계좌 상태를 알려줍니다.
물리면 방이 파래지고, 가즈아면 방이 붉어집니다. 그게 전부입니다. 우리는 진심입니다.

## 무드

| 상태 | 조건 | 방의 색 (KR 스킴) |
|---|---|---|
| 🚀 가즈아 | 당일 +5% 이상 | 진홍 |
| 😎 순항 중 | +1 ~ +5% | 연한 빨강 |
| 😐 무풍지대 | -1 ~ +1% | 따뜻한 노랑 |
| 🌊 출렁인다 | -1 ~ -5% | 하늘색 |
| 🪝 물렸다 | -5% 이하 | 파랑 |
| 🌑 심해 | 누적 -20% 이하 | 심해 남색 (숨쉬듯 점멸) |
| 🌙 쉬어라 | 장 마감 | 주황 무드등 |

> 🇰🇷 한국은 **빨강 = 상승, 파랑 = 하락**입니다. 미국과 반대죠. `colorScheme: "us"`로 바꿀 수 있습니다.

### 부가 기능

- **공습경보**: 장중 -3% 급락 시 전구가 깜빡입니다. 끌 수 있지만, 기본값은 켜짐입니다.
- **퇴근 판정기**: 오늘 계좌 수익이 출근 후 누적 시급을 넘는 순간 알려줍니다 — *"오늘 주식이 너 대신 벌었다. 퇴근해라."*

## 빠른 시작

```bash
npm install
npm run demo   # 목업 데이터로 터미널에서 무드 체험 (API 키 불필요)
```

## Claude Code 상태줄에 연결

`~/.claude/settings.json`:

```json
{ "statusLine": { "type": "command", "command": "npx stonkpeek statusline" } }
```

데몬(`stonkpeek start`)을 켜두면 상태줄에 `🪝 -5.21% 물렸다` 가 뜹니다.

## 작업표시줄 트레이 (Windows)

> 직장인용 스텔스 모드. 시계 옆 점 하나가 등락 색으로 바뀝니다. 옆 사람 눈엔 그냥 알림 아이콘, 나한텐 글랜스.
> 감정 실린 문구나 알림 팝업 없이, 숫자만 담백하게 보여줍니다.

```bash
stonkpeek start   # 데몬 (state.json 갱신) — 한 창에서
stonkpeek tray     # 트레이 아이콘 — 다른 창에서
```

- 시계 옆 트레이(▲)에 등락 색 점이 뜹니다. OS 기본 툴팁은 일부러 안 씁니다 — 아래 시세 위젯과 겹쳐 보이는 걸 막기 위함. 숫자는 우클릭 메뉴 맨 위에서도 볼 수 있습니다.
- 그 점에 마우스를 **0.5초** 올리고 있으면, Windows 날씨 위젯처럼 작업표시줄 코너에 종목별 시세 창이 뜹니다 — 보유 종목을 하나씩 자동으로 돌며 종목명·현재가·당일/누적 수익률·손익을 보여주다가, 커서를 치우면 사라집니다. 우클릭 메뉴에서 이 위젯을 끌 수도 있습니다.
- **더블클릭**(또는 우클릭 → 보유 종목): 종목별 평가금액·당일/누적 수익률 창이 뜹니다.
- **보스키**: `Ctrl+Alt+H`를 누르면 즉시 무채색 점으로 바뀝니다(사장님 모드). 한 번 더 누르면 복귀. 단축키 충돌 시 우클릭 메뉴에도 같은 항목이 있습니다.
- `statusline`과 같은 **읽기 전용 소비자** — `~/.stonkpeek/state.json`만 읽으므로 증권사 API 호출도, 키도 트레이 쪽엔 없습니다.
- 데몬이 꺼져 있으면 회색 점으로 표시됩니다. (API 키 없이 시험만 해보려면 `stonkpeek demo`도 state.json을 씁니다.)

### 컴퓨터 켤 때 자동 실행

매번 `stonkpeek start` / `stonkpeek tray`를 손으로 켤 필요 없습니다.

```bash
npm run build              # 전역 설치 없이 클론해서 쓰는 경우, 먼저 빌드
node dist/cli.js install-startup
```

Windows 로그인 시 데몬(`start`)과 트레이가 창 하나 안 뜨고 조용히 자동 실행됩니다(로그인 Startup 폴더에 `.vbs` 하나 등록하는 방식 — 관리자 권한 불필요, 서비스 아님). 해제하려면:

```bash
node dist/cli.js uninstall-startup
```

## 크롬 확장 (툴바 구석)

> 브라우저 구석에서 무드만 슬쩍. 옆 사람 눈엔 그냥 확장 아이콘, 나한텐 글랜스.

크롬은 샌드박스라 `state.json`을 직접 못 읽습니다. 데몬이 **localhost 피드**(`HttpSink`)를 열고, 확장이 그걸 읽습니다.

1. `stonkpeek.config.json`에서 http 싱크를 켭니다:
   ```json
   { "sinks": { "http": { "enabled": true, "port": 17654 } } }
   ```
   그리고 `stonkpeek start` (또는 `stonkpeek demo`).
2. 크롬 → `chrome://extensions` → **개발자 모드** → **압축해제된 확장 프로그램 로드** → `chrome-extension/` 폴더 선택.
3. 툴바 아이콘이 무드 색 점으로, 배지가 등락률(`-5`)로 바뀝니다. 호버하면 `-5.21% 물렸다 (누적 -12.3%)`.

- **아이콘 클릭 → 보유 종목 팝업**: 종목별 당일/누적 수익률 리스트가 뜹니다.
- **보스키**: 단축키로 즉시 회색/숨김 토글. `chrome://extensions/shortcuts`에서 지정합니다(기본 제안 `Ctrl+Shift+9`).
- 데몬이 꺼져 있으면 회색 점으로 표시됩니다. 증권사 키는 데몬에만 있고 브라우저엔 들어가지 않습니다 — 확장은 localhost만 읽습니다.

## 스마트 전구 (Philips Hue)

`stonkpeek.config.json`:

```json
{
  "sinks": {
    "hue": { "enabled": true, "bridgeIp": "192.168.0.x", "apiKey": "...", "lightIds": [1] }
  }
}
```

## 키보드 RGB (OpenRGB)

OpenRGB를 SDK 서버 모드로 실행한 뒤:

```json
{ "sinks": { "openrgb": { "enabled": true, "host": "127.0.0.1", "port": 6742 } } }
```

## 데이터 소스

- `mock` — 랜덤워크 데모 (기본값). 가끔 급락 이벤트가 옵니다. 현실 고증.
- `toss` — 토스증권 공식 Open API (조회 전용). 보유 종목의 평가금액·매입금액·당일손익을 읽어 무드로 환산합니다. 해외(USD) 종목은 환율로 원화 환산해 합산.

### 토스증권 연결

토스증권 WTS → 설정 → Open API에서 `client_id` / `client_secret`을 발급받아 `stonkpeek.config.json`에 넣습니다.

```json
{
  "source": "toss",
  "toss": { "clientId": "tsck_...", "clientSecret": "tssk_...", "accountNo": "" }
}
```

`accountNo`는 비워두면 첫 종합매매 계좌를 자동 사용합니다. **조회 전용 키만 필요하며, 주문 API는 호출하지 않습니다.**

**이 프로젝트는 주문 기능을 영원히 만들지 않습니다.** 무드등이지 트레이딩 봇이 아닙니다.

## 보유 종목 보기

무드(합산)와 별개로, 종목별 수익률을 보고 싶을 때:

```bash
stonkpeek holdings   # 종목별 평가금액·당일/누적 수익률 표 (현재 소스에서 즉시 조회)
```

```
📊 보유 종목 — source: toss
🌊 삼성전자 (005930)   3주     1,026,000원   당일 -4.72%   누적 -2.00%
🌊 테슬라 (TSLA)  0.002448주        1,399원   당일 -1.90%   누적 +74.51%
```

같은 종목 리스트가 **트레이 더블클릭 창**과 **크롬 확장 팝업**에도 뜹니다 (둘 다 데몬의 state.json / localhost 피드를 읽음).

## 설계 문서

[ARCHITECTURE.md](./ARCHITECTURE.md) — 플러그인 구조, Signal 스펙, 새 사물(싱크) 붙이는 법.

## License

MIT
