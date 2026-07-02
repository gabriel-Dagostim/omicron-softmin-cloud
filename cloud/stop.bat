@echo off
title OMICRON ^| Softmin ^| parar
echo.
echo   OMICRON / Softmin - a parar o minerador...
echo.
taskkill /F /IM softmin.exe 2>nul
if errorlevel 1 (
  echo Nenhum processo softmin.exe encontrado.
) else (
  echo softmin.exe finalizado.
)
