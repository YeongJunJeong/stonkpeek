# stonkmood

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
{ "statusLine": { "type": "command", "command": "npx stonkmood statusline" } }
```

데몬(`stonkmood start`)을 켜두면 상태줄에 `🪝 -5.21% 물렸다` 가 뜹니다.

## 스마트 전구 (Philips Hue)

`stonkmood.config.json`:

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

토스증권 WTS → 설정 → Open API에서 `client_id` / `client_secret`을 발급받아 `stonkmood.config.json`에 넣습니다.

```json
{
  "source": "toss",
  "toss": { "clientId": "tsck_...", "clientSecret": "tssk_...", "accountNo": "" }
}
```

`accountNo`는 비워두면 첫 종합매매 계좌를 자동 사용합니다. **조회 전용 키만 필요하며, 주문 API는 호출하지 않습니다.**

**이 프로젝트는 주문 기능을 영원히 만들지 않습니다.** 무드등이지 트레이딩 봇이 아닙니다.

## 설계 문서

[ARCHITECTURE.md](./ARCHITECTURE.md) — 플러그인 구조, Signal 스펙, 새 사물(싱크) 붙이는 법.

## License

MIT
