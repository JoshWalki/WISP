@echo off
setlocal EnableDelayedExpansion

REM ============================================================================
REM WISP Companion - Setup Verification Script
REM ============================================================================
REM This script verifies that your WISP Companion setup is correct
REM ============================================================================

title WISP Companion - Verification

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

echo.
echo ============================================================================
echo              WISP COMPANION SETUP VERIFICATION
echo ============================================================================
echo.

set "PASS_COUNT=0"
set "FAIL_COUNT=0"
set "WARN_COUNT=0"

REM ============================================================================
REM Check 1: Node.js
REM ============================================================================

echo [1/12] Checking Node.js installation...

where node >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('node --version') do set NODE_VERSION=%%i
    echo [PASS] Node.js: !NODE_VERSION!
    set /a PASS_COUNT+=1
) else (
    echo [FAIL] Node.js not found
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 2: npm
REM ============================================================================

echo [2/12] Checking npm installation...

where npm >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('npm --version') do set NPM_VERSION=%%i
    echo [PASS] npm: v!NPM_VERSION!
    set /a PASS_COUNT+=1
) else (
    echo [FAIL] npm not found
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 3: Dependencies
REM ============================================================================

echo [3/12] Checking Node.js dependencies...

if exist "node_modules" (
    echo [PASS] node_modules folder exists
    set /a PASS_COUNT+=1
) else (
    echo [FAIL] node_modules not found - run: npm install
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 4: Token Configuration
REM ============================================================================

echo [4/12] Checking security token configuration...

if exist ".env" (
    findstr "WISP_TOKEN" .env >nul 2>&1
    if !errorlevel! equ 0 (
        echo [PASS] .env file exists with WISP_TOKEN
        set /a PASS_COUNT+=1
    ) else (
        echo [FAIL] WISP_TOKEN not found in .env - run: npm run generate-token
        set /a FAIL_COUNT+=1
    )
) else (
    echo [FAIL] .env file not found - run: npm run generate-token
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 5: PsExec
REM ============================================================================

echo [5/12] Checking PsExec installation...

set "PSEXEC_FOUND=0"

if exist "C:\SysinternalsSuite\PsExec.exe" (
    echo [PASS] PsExec found at: C:\SysinternalsSuite\PsExec.exe
    set "PSEXEC_FOUND=1"
    set /a PASS_COUNT+=1
)

if exist "%SCRIPT_DIR%SysinternalsSuite\PsExec.exe" (
    echo [PASS] PsExec found at: %SCRIPT_DIR%SysinternalsSuite\PsExec.exe
    set "PSEXEC_FOUND=1"
    set /a PASS_COUNT+=1
)

if exist "%SCRIPT_DIR%PsExec.exe" (
    echo [PASS] PsExec found at: %SCRIPT_DIR%PsExec.exe
    set "PSEXEC_FOUND=1"
    set /a PASS_COUNT+=1
)

if "!PSEXEC_FOUND!"=="0" (
    echo [WARN] PsExec not found - install Sysinternals Suite
    set /a WARN_COUNT+=1
)

echo.

REM ============================================================================
REM Check 6: Scripts Directory
REM ============================================================================

echo [6/12] Checking scripts directory...

if exist "C:\WISP\scripts" (
    echo [PASS] C:\WISP\scripts exists
    set /a PASS_COUNT+=1
) else (
    echo [FAIL] C:\WISP\scripts not found - run setup.bat
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 7: SystemReport.bat
REM ============================================================================

echo [7/12] Checking SystemReport.bat...

if exist "%SCRIPT_DIR%scripts\SystemReport.bat" (
    echo [PASS] SystemReport.bat found in scripts directory
    set /a PASS_COUNT+=1
) else if exist "%SCRIPT_DIR%SystemReport.bat" (
    echo [WARN] SystemReport.bat found in root - should be in scripts directory
    set /a WARN_COUNT+=1
) else (
    echo [FAIL] SystemReport.bat not found
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 8: Configuration File
REM ============================================================================

echo [8/12] Checking config.js...

if exist "server/config.js" (
    echo [PASS] config.js exists
    set /a PASS_COUNT+=1
) else (
    echo [FAIL] config.js not found
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 9: Server File
REM ============================================================================

echo [9/12] Checking server.js...

if exist "server/server.js" (
    echo [PASS] server.js exists
    set /a PASS_COUNT+=1
) else (
    echo [FAIL] server.js not found
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 10: HTML File
REM ============================================================================

echo [10/12] Checking system_report.html...

if exist "system_report.html" (
    findstr "WISP_CONFIG" system_report.html >nul 2>&1
    if !errorlevel! equ 0 (
        findstr "loadWispConfig" system_report.html >nul 2>&1
        if !errorlevel! equ 0 (
            echo [PASS] system_report.html configured for automatic token loading
            set /a PASS_COUNT+=1
        ) else (
            echo [WARN] system_report.html may need update for automatic token loading
            set /a WARN_COUNT+=1
        )
    ) else (
        echo [FAIL] WISP_CONFIG not found in system_report.html
        set /a FAIL_COUNT+=1
    )
) else (
    echo [FAIL] system_report.html not found
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 11: Logs Directory
REM ============================================================================

echo [11/12] Checking logs directory...

if not exist "logs" (
    echo [INFO] Creating logs directory...
    mkdir logs
)

if exist "logs" (
    echo [PASS] logs directory exists
    set /a PASS_COUNT+=1
) else (
    echo [FAIL] Could not create logs directory
    set /a FAIL_COUNT+=1
)

echo.

REM ============================================================================
REM Check 12: Service Health (if running)
REM ============================================================================

echo [12/12] Checking if service is running...

powershell -Command "try { $response = Invoke-WebRequest -Uri 'http://127.0.0.1:8765/health' -TimeoutSec 2; if ($response.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1

if %errorlevel% equ 0 (
    echo [PASS] Service is running and healthy
    set /a PASS_COUNT+=1
) else (
    echo [INFO] Service is not running - start via start-service.bat
)

echo.

REM ============================================================================
REM Summary
REM ============================================================================

echo ============================================================================
echo                           VERIFICATION SUMMARY
echo ============================================================================
echo.
echo Passed:   !PASS_COUNT!
echo Warnings: !WARN_COUNT!
echo Failed:   !FAIL_COUNT!
echo.
echo ============================================================================

if !FAIL_COUNT! gtr 0 (
    echo.
    echo [RESULT] Setup is INCOMPLETE - please fix the failed checks above
    echo.
    echo Run setup.bat to complete the setup process.
) else if !WARN_COUNT! gtr 0 (
    echo.
    echo [RESULT] Setup is MOSTLY COMPLETE - address warnings for full functionality
    echo.
) else (
    echo.
    echo [RESULT] Setup is COMPLETE - all checks passed!
    echo.
    echo You can now start the service with: start-service.bat
)

echo ============================================================================
echo.

pause
endlocal
