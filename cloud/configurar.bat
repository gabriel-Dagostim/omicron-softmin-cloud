@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title Softmin ^| reconfigurar

echo.
echo   Softmin - reconfigurar config.json
echo.

set "ROOT=%ProgramData%\Softmin"
if exist "%ROOT%\Reconfig-Softmin.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\Reconfig-Softmin.ps1"
  pause
  exit /b %ERRORLEVEL%
)

echo Instalacao nao encontrada em "%ROOT%".
echo Copie settings.json ou settings.ini para essa pasta e execute:
echo   powershell -NoProfile -ExecutionPolicy Bypass -File Reconfig-Softmin.ps1
echo.
pause
exit /b 1
