@echo off
rem Ghidra analysis of Tiberian Sun's Game.exe (headless).
rem   ghidra-scan.cmd import                 - import the exe again and analyse it
rem   ghidra-scan.cmd <Script.java> [args]   - run a script on the existing project
rem Results go to analysis\scan, the log to analysis\scan\headless.log.
rem Needs GHIDRA_INSTALL_DIR. analysis\bin\Game.exe is a copy of your own Game.exe (dev\check-game.ps1 -Copy).
setlocal
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "PROJ=%ROOT%\analysis\ghidra"
set "OUT=%ROOT%\analysis\scan"
set "EXE=%ROOT%\analysis\bin\Game.exe"
set "SCRIPTS=%ROOT%\dev\ghidra_scripts"
if not exist "%OUT%" mkdir "%OUT%"
if not exist "%PROJ%" mkdir "%PROJ%"

if /i "%~1"=="import" (
  call "%GHIDRA_INSTALL_DIR%\support\analyzeHeadless.bat" "%PROJ%" TibSun -import "%EXE%" -overwrite -max-cpu 8 > "%OUT%\headless.log" 2>&1
  exit /b %ERRORLEVEL%
)

set "SCRIPT=%~1"
shift
set "ARGS="
:collect
if "%~1"=="" goto run
set "ARGS=%ARGS% %1"
shift
goto collect
:run
call "%GHIDRA_INSTALL_DIR%\support\analyzeHeadless.bat" "%PROJ%" TibSun -process Game.exe -noanalysis -readOnly -scriptPath "%SCRIPTS%" -postScript %SCRIPT% "%OUT%" %ARGS% -max-cpu 8 > "%OUT%\headless.log" 2>&1
exit /b %ERRORLEVEL%
