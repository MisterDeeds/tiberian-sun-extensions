@echo off
rem Installs the Tiberian Sun Extensions from this folder (a double-click is enough).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install.ps1" -StartLauncher
echo.
pause
