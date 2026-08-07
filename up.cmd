@echo off
REM Обёртка для Windows CMD → PowerShell up.ps1
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0up.ps1" %*
