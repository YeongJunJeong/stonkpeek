@echo off
chcp 65001 >nul
cd /d "%~dp0"
title TossPeek 설치

echo ================================================
echo    TossPeek 설치
echo ================================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo  Node.js 가 설치되어 있지 않습니다.
  echo  설치 페이지를 엽니다. Node.js 를 설치한 뒤 이 파일을 다시 실행하세요.
  echo.
  start https://nodejs.org
  pause
  exit /b 1
)

rem 배포 ZIP에는 dist 가 이미 들어 있어 곧바로 등록만 하면 된다.
rem 소스에서 직접 실행할 때만 내려받기/빌드를 거친다.
if exist "dist\cli.js" (
  echo  준비된 파일을 확인했습니다. 바로 설치합니다.
  goto register
)

echo  [1/2] 필요한 구성요소를 내려받는 중... (몇 분 걸릴 수 있어요)
call npm install
if errorlevel 1 goto error

echo.
echo  [2/2] 준비하는 중...
call npm run build
if errorlevel 1 goto error

:register
echo.
echo  자동 실행 등록 및 시작...
node dist/cli.js install-startup
if errorlevel 1 goto error

echo.
echo ================================================
echo    설치가 끝났습니다!
echo    시계 옆 작업표시줄에서 TossPeek 아이콘을 확인하세요.
echo    (안 보이면 숨겨진 아이콘 버튼을 눌러 보세요.)
echo ================================================
echo.
pause
exit /b 0

:error
echo.
echo  설치 중 문제가 발생했습니다. 위 메시지를 확인해 주세요.
echo.
pause
exit /b 1
