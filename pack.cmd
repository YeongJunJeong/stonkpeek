@echo off
chcp 65001 >nul
cd /d "%~dp0"
title TossPeek 릴리스 패키징

rem 배포용 ZIP 생성 — 사용자가 빌드 없이 바로 설치할 수 있도록 dist 를 포함한다.
rem 결과물 TossPeek.zip 을 GitHub Releases 에 업로드하면 된다.
rem 일반 dependencies 가 없고 openrgb-sdk 만 동적 import 라, node_modules 없이도
rem 기본 기능은 모두 동작한다 (RGB 싱크만 별도 설치 필요).

echo TossPeek 릴리스 ZIP 을 만듭니다...
echo.

call npm install
if errorlevel 1 goto error

call npm run build
if errorlevel 1 goto error

set OUT=TossPeek.zip
if exist "%OUT%" del "%OUT%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path 'dist','tray','assets','package.json','설치.cmd','README.md','tosspeek.config.example.json' -DestinationPath '%OUT%' -Force"
if errorlevel 1 goto error

echo.
echo ================================================
echo    완료: %OUT%
echo    이 파일을 GitHub Releases 에 업로드하세요.
echo ================================================
echo.
pause
exit /b 0

:error
echo.
echo  패키징에 실패했습니다. 위 메시지를 확인해 주세요.
echo.
pause
exit /b 1
