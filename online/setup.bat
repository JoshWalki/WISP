@echo off
setlocal EnableDelayedExpansion

REM ============================================================================
REM WISP Companion - Automated Setup Script
REM ============================================================================
REM This script will guide you through the complete setup process
REM ============================================================================

title WISP Companion Setup

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

echo.
echo ============================================================================
echo                     WISP COMPANION SETUP WIZARD
echo ============================================================================
echo.
echo This wizard will help you set up the WISP Companion service.
echo.
echo ============================================================================
echo.
pause

REM ============================================================================
REM STEP 1: Check for Administrative Privileges
REM ============================================================================

echo.
echo [STEP 1/9] Checking for administrative privileges...
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script requires administrative privileges!
    echo.
    echo Please right-click this file and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo [SUCCESS] Running with administrative privileges
echo.

REM ============================================================================
REM STEP 2: Check Node.js Installation
REM ============================================================================

echo.
echo [STEP 2/9] Checking Node.js installation...
echo.

where node >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARNING] Node.js is not installed!
    echo.
    echo Attempting to download and install Node.js LTS automatically...
    echo.

    REM Create temp directory for download
    set "TEMP_DIR=%TEMP%\WISP_NodeJS_Install"
    if not exist "!TEMP_DIR!" mkdir "!TEMP_DIR!"

    REM Determine system architecture
    if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
        set "NODE_ARCH=x64"
    ) else if "%PROCESSOR_ARCHITECTURE%"=="ARM64" (
        set "NODE_ARCH=arm64"
    ) else (
        set "NODE_ARCH=x86"
    )

    echo Detecting latest Node.js LTS version...

    REM Download Node.js LTS MSI (using known stable LTS URL)
    set "NODE_MSI=!TEMP_DIR!\nodejs.msi"
    set "NODE_URL=https://nodejs.org/dist/v25.0.0/node-v20.18.0-!NODE_ARCH!.msi"

    echo Downloading Node.js from: !NODE_URL!
    echo This may take a few minutes...
    echo.

    powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '!NODE_URL!' -OutFile '!NODE_MSI!' -UseBasicParsing}" 2>nul

    if !errorlevel! neq 0 (
        echo [ERROR] Failed to download Node.js installer!
        echo.
        echo Please manually download and install Node.js from:
        echo https://nodejs.org/
        echo.
        rd /s /q "!TEMP_DIR!" 2>nul
        pause
        exit /b 1
    )

    echo [SUCCESS] Download complete
    echo.
    echo Installing Node.js...
    echo This will take a few minutes. Please wait...
    echo.

    REM Install Node.js silently
    msiexec /i "!NODE_MSI!" /qn /norestart

    if !errorlevel! neq 0 (
        echo [ERROR] Failed to install Node.js!
        echo.
        echo Please manually install Node.js from:
        echo https://nodejs.org/
        echo.
        rd /s /q "!TEMP_DIR!" 2>nul
        pause
        exit /b 1
    )

    echo [SUCCESS] Node.js installed successfully
    echo.

    REM Refresh environment variables
    echo Refreshing environment variables...
    set "PATH=%PATH%;%ProgramFiles%\nodejs;%APPDATA%\npm"

    REM Clean up
    echo Cleaning up temporary files...
    rd /s /q "!TEMP_DIR!" 2>nul
    echo.

    REM Verify installation
    echo Verifying Node.js installation...
    where node >nul 2>&1
    if !errorlevel! neq 0 (
        echo [WARNING] Node.js installed but not found in PATH
        echo.
        echo Please close and reopen this command prompt, then run setup.bat again.
        echo.
        pause
        exit /b 1
    )
)

for /f "tokens=*" %%i in ('node --version') do set NODE_VERSION=%%i
echo [SUCCESS] Node.js found: %NODE_VERSION%
echo.

where npm >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] npm is not installed!
    echo.
    echo npm should have been installed with Node.js.
    echo Please reinstall Node.js from: https://nodejs.org/
    echo.
    pause
    exit /b 1
)

for /f "tokens=*" %%i in ('npm --version') do set NPM_VERSION=%%i
echo [SUCCESS] npm found: v%NPM_VERSION%
echo.

REM ============================================================================
REM STEP 3: Install Node.js Dependencies
REM ============================================================================

echo.
echo [STEP 3/9] Installing Node.js dependencies...
echo.

if not exist "package.json" (
    echo [ERROR] package.json not found!
    echo Please ensure you are running this script from the correct directory.
    pause
    exit /b 1
)

echo Installing dependencies via npm...
call npm install

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Failed to install dependencies!
    pause
    exit /b 1
)

echo.
echo [SUCCESS] Dependencies installed successfully
echo.

REM ============================================================================
REM STEP 4: Generate Security Token
REM ============================================================================

echo.
echo [STEP 4/9] Generating security token...
echo.

echo Running token generator...
call node scripts\generate-token.js

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Failed to generate token!
    pause
    exit /b 1
)

echo.
echo [SUCCESS] Security token generated and saved to .env file
echo.

REM Read the token from .env file
for /f "tokens=2 delims==" %%a in ('findstr "WISP_TOKEN" .env') do set "WISP_TOKEN=%%a"

REM ============================================================================
REM STEP 5: Check for PsExec
REM ============================================================================

echo.
echo [STEP 5/9] Checking for PsExec...
echo.

set "PSEXEC_FOUND=0"
set "PSEXEC_PATH="

REM Check common locations
if exist "C:\SysinternalsSuite\PsExec.exe" (
    set "PSEXEC_PATH=C:\SysinternalsSuite\PsExec.exe"
    set "PSEXEC_FOUND=1"
)

if exist "%SCRIPT_DIR%SysinternalsSuite\PsExec.exe" (
    set "PSEXEC_PATH=%SCRIPT_DIR%SysinternalsSuite\PsExec.exe"
    set "PSEXEC_FOUND=1"
)

if exist "%SCRIPT_DIR%PsExec.exe" (
    set "PSEXEC_PATH=%SCRIPT_DIR%PsExec.exe"
    set "PSEXEC_FOUND=1"
)

if "!PSEXEC_FOUND!"=="1" (
    echo [SUCCESS] PsExec found at: !PSEXEC_PATH!
    echo.
    echo Accepting PsExec EULA...
    "!PSEXEC_PATH!" /accepteula >nul 2>&1
    echo [SUCCESS] PsExec EULA accepted
) else (
    echo [WARNING] PsExec not found in common locations!
    echo.
    echo Please download Sysinternals Suite from:
    echo https://download.sysinternals.com/files/SysinternalsSuite.zip
    echo.
    echo Extract to one of these locations:
    echo   - C:\SysinternalsSuite\
    echo   - %SCRIPT_DIR%SysinternalsSuite\
    echo   - %SCRIPT_DIR%
    echo.
    echo You can continue setup and install PsExec later.
    echo.
    choice /C YN /M "Continue without PsExec"
    if errorlevel 2 (
        echo Setup cancelled.
        pause
        exit /b 1
    )
)

echo.

REM ============================================================================
REM STEP 6: Create Scripts Directory
REM ============================================================================

echo.
echo [STEP 6/9] Creating scripts directory...
echo.

if not exist "C:\WISP" (
    echo Creating C:\WISP...
    mkdir "C:\WISP"
)

if not exist "C:\WISP\scripts" (
    echo Creating C:\WISP\scripts...
    mkdir "C:\WISP\scripts"
)

echo [SUCCESS] Scripts directory created: C:\WISP\scripts
echo.

REM ============================================================================
REM STEP 7: Set NTFS Permissions
REM ============================================================================

echo.
echo [STEP 7/9] Setting NTFS permissions on scripts directory...
echo.

echo Restricting access to Administrators only...
icacls "C:\WISP\scripts" /inheritance:r >nul 2>&1
icacls "C:\WISP\scripts" /grant:r Administrators:(OI)(CI)F >nul 2>&1

if %errorlevel% equ 0 (
    echo [SUCCESS] Permissions set successfully
) else (
    echo [WARNING] Failed to set permissions - you may need to set them manually
)

echo.

REM ============================================================================
REM STEP 8: Verify scripts directory structure
REM ============================================================================

echo.
echo [STEP 8/9] Verifying local scripts directory...
echo.

REM Check if scripts directory exists
if not exist "%SCRIPT_DIR%scripts" (
    echo Creating scripts directory...
    mkdir "%SCRIPT_DIR%scripts"
)

REM Verify SystemReport.bat is in scripts directory
if exist "%SCRIPT_DIR%scripts\SystemReport.bat" (
    echo [PASS] SystemReport.bat found in scripts directory
) else if exist "%SCRIPT_DIR%SystemReport.bat" (
    echo Moving SystemReport.bat to scripts directory...
    move /Y "%SCRIPT_DIR%SystemReport.bat" "%SCRIPT_DIR%scripts\SystemReport.bat" >nul
    echo [SUCCESS] SystemReport.bat moved to scripts\
) else (
    echo [WARNING] SystemReport.bat not found
)

REM Verify PowerShell scripts exist in assests
if exist "%SCRIPT_DIR%assests\generate_json.ps1" (
    echo [PASS] PowerShell scripts found in assests directory
) else (
    echo [WARNING] PowerShell scripts not found in assests directory
)

echo.

REM ============================================================================
REM STEP 9: Verify Configuration
REM ============================================================================

echo.
echo [STEP 9/9] Verifying configuration...
echo.

if exist "%SCRIPT_DIR%system_report.html" (
    echo [PASS] system_report.html found
    echo.
    echo NOTE: system_report.html will automatically load the security token
    echo from the WISP Companion service when you open it in your browser.
    echo.
    echo Your security token has been saved to .env:
    echo %WISP_TOKEN%
    echo.
) else (
    echo [WARNING] system_report.html not found
)

if exist "%SCRIPT_DIR%.env" (
    echo [PASS] .env configuration file created
) else (
    echo [WARNING] .env file not found
)

echo.

REM ============================================================================
REM SETUP COMPLETE
REM ============================================================================

cls
echo.
echo ============================================================================
echo                        SETUP COMPLETED SUCCESSFULLY!
echo ============================================================================
echo.
echo Your WISP Companion service is now configured.
echo.
echo Security Token has been saved to .env file
echo.
echo NOTE: The security token will be automatically loaded from the server
echo when you open system_report.html in your browser. No manual configuration needed!
echo.
echo ============================================================================
echo NEXT STEPS:
echo ============================================================================
echo.
echo 1. Start the service:
echo    npm start   (or run start-service.bat)
echo.
echo 2. Test the health endpoint:
echo    Open browser: http://127.0.0.1:8765/health
echo.
echo 3. Open system_report.html in your browser
echo    The configuration will load automatically!
echo.
echo 4. Use the Remote Actions section to execute tasks
echo.
echo 5. Load JSON reports or generate new ones
echo.
echo ============================================================================
echo SECURITY CHECKLIST:
echo ============================================================================
echo.
echo [ ] Token saved to .env file (automatic)
echo [ ] PsExec installed and EULA accepted
echo [ ] Scripts copied to C:\WISP\scripts
echo [ ] NTFS permissions set (Administrators only)
echo [ ] Service starts without errors
echo [ ] Firewall configured to restrict SMB access
echo [ ] Audit logging enabled on target endpoints
echo.
echo ============================================================================
echo DOCUMENTATION:
echo ============================================================================
echo.
echo - Full setup guide: SETUP.md
echo - API documentation: README.md
echo - Audit logs: logs\audit.log
echo.
echo ============================================================================
echo.
echo Press any key to start the service now, or close this window to exit.
pause >nul

REM Start the service
echo.
echo Starting WISP Companion service...
echo.
start start-service.bat

endlocal
