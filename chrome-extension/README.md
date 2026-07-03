# StonkPeek — 크롬 확장

툴바 아이콘이 무드 색 점으로, 배지가 당일 등락률로 바뀝니다. 직장인용 스텔스 포트폴리오.

## 동작 방식

```
StonkPeek 데몬 ──(HttpSink, 127.0.0.1:17654)──► 이 확장(service worker) ──► 툴바 아이콘 + 배지
```

`state.json`은 샌드박스 밖이라 직접 못 읽습니다. 데몬의 `HttpSink`가 최신 Signal을 localhost로 노출하고, 확장은 그 한 곳만 폴링합니다. **증권사 키는 브라우저로 들어가지 않습니다.**

## 설치

1. 데몬에서 http 싱크를 켭니다 — `stonkpeek.config.json`:
   ```json
   { "sinks": { "http": { "enabled": true, "port": 17654 } } }
   ```
   포트를 바꾸면 `manifest.json`의 `host_permissions`와 `background.js`의 `ENDPOINT`도 같이 바꿉니다.
2. `stonkpeek start` (또는 키 없이 `stonkpeek demo`)로 데몬을 띄웁니다.
3. `chrome://extensions` → **개발자 모드** 켜기 → **압축해제된 확장 프로그램 로드** → 이 폴더 선택.

## 보유 종목 팝업

- **아이콘 클릭** → 종목별 당일/누적 수익률 리스트가 뜹니다 (`/signal` 피드의 `holdings`).

## 보스키 (즉시 회색/숨김)

- **단축키**로 토글합니다 (아이콘 클릭은 팝업이 열리므로 단축키 전용).
- 단축키는 `chrome://extensions/shortcuts`에서 지정 (기본 제안 `Ctrl+Shift+9`).
- 회색이면 데몬이 꺼졌거나(자동) 보스키로 숨긴 상태(수동)입니다.

## 파일

- `manifest.json` — MV3. `alarms`로 30초마다 폴링, `host_permissions`로 localhost fetch 허용, `default_popup`으로 팝업 연결.
- `background.js` — 서비스워커. `OffscreenCanvas`로 무드 색 점을 그려 `chrome.action.setIcon`에 넣고, 배지/툴팁을 갱신.
- `popup.html` / `popup.js` — 클릭 시 뜨는 보유 종목 리스트. `/signal`을 읽어 렌더.
