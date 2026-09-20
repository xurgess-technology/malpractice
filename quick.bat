@echo off
setlocal
rem DEBUG ONLY: drop straight into the middle of a surgery (scripts/quick_start.gd). No launch
rem printout, no sign-in sheet, no lobby, no fax order: the window opens leaning over the patient
rem with the step's tool in hand, one press of E from the step.
rem
rem   quick.bat --quick=gunshot:extract --patient=bob --shift=1
rem
rem   --quick=<ailment>:<step_id>   gunshot: sedate, extract, dress
rem                                 amputation: sedate, tourniquet, cut, dress
rem   --patient=<id>                bob (default) or seal
rem   --shift=<n>                   the difficulty, 1 by default
rem   --seed=<n>                    optional; the same hospital every time without it
rem
rem With no arguments at all it runs whatever you ran last time.
cd /d "%~dp0"

set "GODOT=%USERPROFILE%\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=%USERPROFILE%\Desktop\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=%USERPROFILE%\Desktop\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT%" (
  echo.
  echo Could not find Godot. Looked under your Desktop for
  echo   Godot_v4.7.2-stable_win64.exe
  echo.
  echo Open quick.bat in Notepad and point GODOT at your Godot 4.7 executable.
  echo.
  pause
  exit /b 1
)

rem The last-used arguments live in tools\.quick_args (gitignored), so quick.bat on its own
rem repeats the last case you were working on.
set "ARGS=%*"
if not "%ARGS%"=="" goto :save
if not exist "tools\.quick_args" goto :nothing
set /p ARGS=<"tools\.quick_args"
if "%ARGS%"=="" goto :nothing
echo Reusing the last arguments: %ARGS%
goto :go

:nothing
echo.
echo Nothing to run: give it a case, for example
echo   quick.bat --quick=gunshot:extract --patient=bob --shift=1
echo.
pause
exit /b 1

:save
> "tools\.quick_args" echo %ARGS%

:go
title Malpractice (quick)
echo Starting Malpractice from %CD%
echo Using %GODOT%
echo.
rem Same reason as play.bat: a stale .godot/ (the import cache) after a pull is a black screen and
rem "nil" script errors. Re-running import is quick when nothing changed.
echo Checking for anything new to import...
"%GODOT%" --headless --path . --import
echo.
"%GODOT%" --path . -- %ARGS%
set RC=%ERRORLEVEL%
echo.
echo Game closed (exit code %RC%).
if not "%RC%"=="0" pause
