@echo off
setlocal

REM ============================================================================
REM WISP Companion - Quick Start Script
REM ============================================================================
REM Starts the WISP Companion service with pre-flight checks
REM ============================================================================

title WISP Companion Service

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

echo.
echo ============================================================================
echo                     WISP COMPANION SERVICE
echo ============================================================================
echo.

REM Pre-flight checks
echo Performing pre-flight checks...
echo.

REM Check Node.js
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Node.js not found!
    echo Please install Node.js from https://nodejs.org/
    pause
    exit /b 1
)

REM Check .env
if not exist ".env" (
    echo [ERROR] .env file not found!
    echo.
    echo Please run: npm run generate-token
    echo.
    pause
    exit /b 1
)

REM Check node_modules
if not exist "node_modules" (
    echo [WARNING] Dependencies not installed. Installing now...
    call npm install
    if %errorlevel% neq 0 (
        echo [ERROR] Failed to install dependencies!
        pause
        exit /b 1
    )
)

REM Check if port 8765 is in use
echo Checking if port 8765 is available...
netstat -ano | findstr ":8765.*LISTENING" >nul 2>&1

if %errorlevel% equ 0 (
    echo.
    echo ============================================================================
    echo [WARNING] Port 8765 is ALREADY IN USE
    echo ============================================================================
    echo.
    echo Something is already listening on port 8765.
    echo This could be:
    echo   - WISP Companion already running in another window
    echo   - Another application using this port
    echo.

    REM Try to identify the process
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":8765.*LISTENING"') do set "PID=%%a"
    if defined PID (
        echo Process ID using port 8765: !PID!
        for /f "tokens=1" %%b in ('tasklist /FI "PID eq !PID!" /NH 2^>nul ^| findstr !PID!') do echo Process name: %%b
    )
    echo.
    echo You should:
    echo   1. Close the other instance, or
    echo   2. Use the already-running service
    echo.
    pause
    exit /b 1
)

echo [PASS] Pre-flight checks complete
echo.

REM Display startup information
for /f "tokens=2 delims==" %%a in ('findstr "WISP_TOKEN" .env') do set "WISP_TOKEN=%%a"

echo ============================================================================
echo SERVICE INFORMATION:
echo ============================================================================
echo.
echo URL:    http://127.0.0.1:8765
echo Token:  %WISP_TOKEN%
echo Logs:   %SCRIPT_DIR%logs\audit.log
echo.
echo ============================================================================
echo.

REM Start the service
echo Starting WISP Companion service...
echo.
echo Press Ctrl+C to stop the service.
echo.
echo ============================================================================
echo.

start system_report.html
call npm start


REM Check if npm start exited with an error
if %errorlevel% neq 0 (
    echo.
    echo ============================================================================
    echo [ERROR] Server failed to start! Exit code: %errorlevel%
    echo ============================================================================
    echo.
    echo Possible causes:
    echo   - Port 8765 is already in use
    echo   - .env file is missing or invalid
    echo   - Syntax error in server.js
    echo.
    echo Check logs\error.log for details.
    echo.
    pause
    exit /b %errorlevel%
)

endlocal
