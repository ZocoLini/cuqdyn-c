@echo off
setlocal

REM === run_evaluation.bat ================================================
REM Double-click this file in Windows Explorer to launch the full
REM CUQDyn1_Plus manuscript evaluation pipeline.
REM
REM The run can take many hours (examples ~1.5 h, tutorial ~0.5 h,
REM SBC ~6-20 h depending on UseFastSBC, PyMC ~1.5 h, reports ~10 min).
REM
REM This window stays open and shows progress in real time via the
REM runner's own diary log.  Press Ctrl+C to abort early; stages that
REM already completed are saved.
REM
REM Before running, edit the three paths below to match your machine.
REM ========================================================================

REM ---- EDIT THESE THREE PATHS -------------------------------------------
set REPO=C:\Users\user\Documents\CUQDyn1_Plus_v2026
set MEIGO=C:\Users\user\Documents\MEIGO64
set USE_FAST_SBC=false
REM -----------------------------------------------------------------------

REM PyTensor will compile to native code if g++ is on PATH.
set "PATH=C:\msys64\ucrt64\bin;%PATH%"

REM Make MEIGO visible to the runner.
set "MEIGO64_PATH=%MEIGO%"

echo ==========================================================
echo  CUQDyn1_Plus full evaluation
echo  Started  %DATE% %TIME%
echo  Repo     %REPO%
echo  MEIGO    %MEIGO%
echo  Fast SBC %USE_FAST_SBC%
echo  Log      %REPO%\scripts\eval_logs\<timestamp>\
echo ==========================================================
echo.

REM Locate MATLAB: try PATH first, then standard install folders.
where matlab >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "MATLAB_EXE=matlab"
) else if exist "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" (
    set "MATLAB_EXE=C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
) else if exist "C:\Program Files\MATLAB_R2026a\bin\matlab.exe" (
    set "MATLAB_EXE=C:\Program Files\MATLAB_R2026a\bin\matlab.exe"
) else if exist "C:\Program Files\MATLAB\R2025b\bin\matlab.exe" (
    set "MATLAB_EXE=C:\Program Files\MATLAB\R2025b\bin\matlab.exe"
) else if exist "C:\Program Files\MATLAB\R2025a\bin\matlab.exe" (
    set "MATLAB_EXE=C:\Program Files\MATLAB\R2025a\bin\matlab.exe"
) else (
    echo !!! MATLAB not found on PATH or in standard install locations.
    echo !!! Edit this file to set MATLAB_EXE to the full path of matlab.exe.
    pause
    exit /b 1
)
echo  MATLAB   %MATLAB_EXE%

REM Launch MATLAB.  -batch executes the statement, then exits.
REM The runner writes everything to disk; this window echoes
REM MATLAB's console output live.
"%MATLAB_EXE%" -batch "addpath(genpath('%REPO%')); run_full_evaluation('UseFastSBC', %USE_FAST_SBC%)" >nul 2>&1

if %ERRORLEVEL% neq 0 (
    echo.
    echo !!! MATLAB exited with code %ERRORLEVEL% -- the runner may have
    echo !!! been interrupted.  Check the latest diary in:
    echo !!!   %REPO%\scripts\eval_logs\
)

echo.
echo ==========================================================
echo  Finished  %DATE% %TIME%
echo  See the latest summary in:
echo    %REPO%\scripts\eval_logs\<latest>\
echo ==========================================================
pause
endlocal
