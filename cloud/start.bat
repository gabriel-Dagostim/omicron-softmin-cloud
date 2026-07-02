@echo off
setlocal EnableExtensions
title OMICRON ^| Softmin
cd /d "%~dp0"

echo.
echo   ============================================
echo     OMICRON
echo     Softmin
echo     Pedro Piovezan - GHOST
echo   ============================================
echo.

if not exist "bin\softmin.exe" (
  echo Este start.bat deve ficar na pasta do Softmin onde exista bin\softmin.exe.
  echo Se ainda nao instalou, execute instalador.bat a partir do pendrive.
  pause
  exit /b 1
)

start "Softmin" /low /B bin\softmin.exe --config=config.json --log-file=logs\softmin.log
echo Softmin iniciado em segundo plano. Log: logs\softmin.log
