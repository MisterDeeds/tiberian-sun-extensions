@echo off
rem Removes the Tiberian Sun Extensions again (our files in the game folder, program folder, shortcuts, settings).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install.ps1" -Remove
echo.
pause
