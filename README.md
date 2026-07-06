# TossPeek

[![Latest Release](https://img.shields.io/github/v/release/YeongJunJeong/tosspeek?label=release&color=blue)](https://github.com/YeongJunJeong/tosspeek/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows-0078D6)](#download-and-install)
[![License](https://img.shields.io/badge/license-Proprietary-lightgrey)](#license)

> **계좌를 쳐다보지 말고, 느껴라.**

내 주식을 차트 앱으로 계속 들여다보지 않아도, 작업표시줄에서 살짝 엿볼(peek) 수 있게 해주는 Windows용 상시 실행 도구입니다.

## 기능

- 시계 옆 트레이 아이콘 하나가 오늘 수익 상황에 따라 색으로 바뀝니다.
- 그 아이콘에 마우스를 잠깐 올리면, 보유 종목이 하나씩 자동으로 돌아가며 현재가·당일/누적 수익률·손익이 작은 창으로 뜹니다.
- 컴퓨터를 켜면 별도 실행 없이 자동으로 백그라운드에서 조용히 시작됩니다 (터미널 창 없음).
- 트레이 아이콘 우클릭 메뉴에서 설정(계좌 연동, 자동 실행 등)을 관리할 수 있습니다.
- 자리를 비웠거나 남에게 보이면 안 될 때를 위한 즉시 숨김 기능이 있습니다.

## Download and Install

[Download](https://github.com/YeongJunJeong/tosspeek/releases/latest) · [Releases](https://github.com/YeongJunJeong/tosspeek/releases)

**Requirements:** Windows, [Node.js](https://nodejs.org)

압축을 푼 폴더에서:

```bash
npm install
npm run build
node dist/cli.js install-startup
```

- 트레이 아이콘이 바로 뜹니다. 재부팅 필요 없이 다음 로그인부터 자동 실행됩니다.
- 안 보이면 작업표시줄 숨겨진 아이콘(`^`) 확인.
- 계좌 연동 전까지는 데모 데이터가 표시됩니다. 우클릭 → 설정에서 연동.
- 실수로 껐다면 바탕화면 "TossPeek 실행" 아이콘으로 재실행.

## License

Proprietary — All rights reserved.
