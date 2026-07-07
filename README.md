# TossPeek

[![Latest Release](https://img.shields.io/github/v/release/YeongJunJeong/tosspeek?label=release&color=blue)](https://github.com/YeongJunJeong/tosspeek/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D6)](#설치)
[![License](https://img.shields.io/badge/license-Proprietary-lightgrey)](#라이선스)

**토스증권 오픈 API로 내 주식 계좌를 Windows 작업표시줄에서 바로 확인하는 트레이 도구.**

토스 앱을 따로 열지 않아도, 작업표시줄 트레이 아이콘 하나로 실시간 수익 상황을 확인할 수 있습니다.
[토스증권 Open API](https://openapi.tossinvest.com)(조회 전용)로 실제 보유 종목·수익률을 읽어옵니다.

> A Windows taskbar (system tray) widget that shows your **Toss Securities** stock portfolio
> using the official Toss Securities Open API (read-only).

## 동작 방식

- **토스증권 오픈 API** 를 통한 조회.
- 인증: OAuth2 `client_credentials` (Client ID / Client Secret) → 액세스 토큰 발급.
- 조회: 계좌(`/api/v1/accounts`) → 보유 종목(`/api/v1/holdings`) → 해외 종목이 있으면 환율(`/api/v1/exchange-rate`)로 원화 환산.
- API 키를 넣기 전에는 데모(mock) 데이터로 동작을 미리 볼 수 있습니다.

## 기능

- 작업표시줄 트레이 아이콘이 오늘 수익 상황에 따라 색으로 바뀝니다.
- 아이콘에 마우스를 올리면 보유 종목이 하나씩 돌아가며 현재가·당일/누적 수익률·손익을 작은 창으로 보여줍니다.
- 컴퓨터를 켜면 별도 실행 없이 백그라운드에서 조용히 시작됩니다 (터미널 창 없음).
- 트레이 아이콘 우클릭 메뉴에서 설정(계좌 연동, 자동 실행 등)을 관리합니다.
- **숨김 모드**: 자리를 비우거나 화면을 남에게 보일 때, 단축키(`Ctrl+Alt+H`) 한 번으로 색을 회색으로 감춥니다. 다시 누르면 복귀합니다.

## 설치

1. [Download](https://github.com/YeongJunJeong/tosspeek/releases/latest) 에서 ZIP을 받아 원하는 폴더에 압축을 풉니다.
2. 압축을 푼 폴더에서 **`설치.cmd` 를 더블클릭**합니다. 나머지는 자동으로 진행됩니다.
3. 잠시 기다리면 시계 옆 작업표시줄에 TossPeek 아이콘이 나타납니다.

> Node.js가 없으면 설치 창이 다운로드 페이지를 대신 열어 줍니다. [Node.js](https://nodejs.org)를 설치한 뒤 `설치.cmd`를 다시 더블클릭하세요.

- 다음부터는 컴퓨터를 켜면 자동으로 실행됩니다.
- 아이콘이 안 보이면 작업표시줄의 **숨겨진 아이콘 버튼(`^`)** 을 눌러 확인하세요.
- 처음에는 데모 데이터가 표시됩니다. 실제 계좌 연동은 아래 안내를 따르세요.
- 실수로 껐다면 바탕화면의 **TossPeek** 아이콘을 더블클릭해 다시 켤 수 있습니다. (아이콘이 없으면 트레이 우클릭 → **바탕화면 아이콘 추가**)

## 토스증권 계좌 연동

트레이 아이콘을 **우클릭 → 설정…** 을 열고 화면에서 그대로 입력하면 됩니다. 설정 파일을 직접 만질 필요 없습니다.

1. 데이터 소스를 **토스증권 (실계좌 조회)** 로 선택합니다. (기본값은 데모 데이터)
2. 토스증권에서 발급받은 **Client ID** 와 **Client Secret** 을 입력합니다.
3. 계좌번호는 비워 두면 첫 번째 종합매매 계좌를 자동으로 사용합니다. 계좌가 여러 개면 원하는 계좌번호를 넣으세요.
4. 저장하면 바로 실계좌 데이터로 바뀝니다.

토스증권 오픈 API 키는 토스증권에서 발급받으며, 외부에 공개하지 마세요.

## 명령어 (고급 · 선택 사항)

> 고급기능으로 일반 사용자는 트레이 아이콘에서 마우스로 다룰 수 있습니다.

```
tosspeek demo             목업 데이터로 터미널 데모 (API 키 불필요)
tosspeek start            설정된 소스로 데몬 실행
tosspeek tray             작업표시줄 트레이 아이콘 + 종목 시세 위젯 띄우기
tosspeek holdings         보유 종목별 수익률 표 출력
tosspeek install-startup  로그인 시 자동 실행 등록 + 바탕화면 아이콘 생성 + 즉시 실행
tosspeek uninstall-startup  자동 실행 등록 해제
tosspeek help             도움말
```

## 안내

- 토스증권 오픈 API를 **조회 전용**으로만 사용합니다. 주문·매매 기능은 포함하지 않습니다.
- 표시되는 손익 정보는 참고용이며, 정확한 잔고는 토스증권 앱에서 확인하세요.
- 이 프로젝트는 토스증권과 무관한 개인 프로젝트입니다.

## 라이선스

Proprietary — All rights reserved.
