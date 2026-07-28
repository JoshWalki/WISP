@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ===============================
:: Comprehensive System Report Generator (JSON-Safe)
:: Creates detailed JSON data for IT support analysis
:: Supports local and remote computer analysis
:: ===============================

:: --- Display initial header ---
cls
echo ===============================
echo  Comprehensive System Report
echo ===============================
echo.

:: --- Check for hostname parameter (required when called from WISP) ---
set "TARGET_HOSTNAME=%1"
if "%TARGET_HOSTNAME%"=="" (
    echo [ERROR] No hostname parameter provided
    echo.
    echo Usage: SystemReport.bat [HOSTNAME]
    echo   HOSTNAME can be a computer name or IP address
    echo   Use "%COMPUTERNAME%" for local computer
    echo.
    echo Example: SystemReport.bat %COMPUTERNAME%
    echo Example: SystemReport.bat PC-001
    echo Example: SystemReport.bat 192.168.1.100
    echo.
    exit /b 1
)

:: --- Resolve 'localhost' to actual computer name ---
if /i "%TARGET_HOSTNAME%"=="localhost" (
    set "TARGET_HOSTNAME=%COMPUTERNAME%"
    echo [*] Resolved 'localhost' to: %COMPUTERNAME%
)
if /i "%TARGET_HOSTNAME%"=="127.0.0.1" (
    set "TARGET_HOSTNAME=%COMPUTERNAME%"
    echo [*] Resolved '127.0.0.1' to: %COMPUTERNAME%
)

:: Determine if this is a local or remote analysis
if /i "%TARGET_HOSTNAME%"=="%COMPUTERNAME%" (
    set "IS_REMOTE=false"
    set "REMOTE_PREFIX="
    echo ===============================
    echo    Local System Analysis
    echo ===============================
    echo Target: %TARGET_HOSTNAME%
    echo ===============================
    echo.
) else (
    set "IS_REMOTE=true"
    set "REMOTE_PREFIX=\\%TARGET_HOSTNAME%\"
    echo ===============================
    echo    Remote System Analysis
    echo ===============================
    echo Target: %TARGET_HOSTNAME%
    echo Source: %COMPUTERNAME%
    echo ===============================
    echo.
    echo [*] Testing connectivity to %TARGET_HOSTNAME%...

    :: Test if target is reachable
    ping -n 1 -w 2000 -4 %TARGET_HOSTNAME% >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Cannot reach %TARGET_HOSTNAME%
        echo.
        echo Possible issues:
        echo - Computer is offline or powered off
        echo - Hostname/IP address is incorrect
        echo - Network connectivity issues
        echo - Firewall blocking ping requests
        echo.
        echo Please verify:
        echo 1. The computer name is correct: %TARGET_HOSTNAME%
        echo 2. The target computer is powered on and connected
        echo 3. You have network access to the target
        echo.
        exit /b 1
    )

    echo [SUCCESS] %TARGET_HOSTNAME% is reachable
    echo.
)

:: --- Get the directory where this script is located ---
set "SCRIPT_DIR=%~dp0"
:: Go up one level to root directory since script is in /scripts folder
cd /d "%SCRIPT_DIR%.."
set "ROOT_DIR=%CD%"

:: --- Timestamp ---
for /f "delims=" %%a in ('powershell -NoProfile -Command "(Get-Date).ToString(\"yyyyMMdd_HHmmss\")"') do set TS=%%a
set MACHINE=%TARGET_HOSTNAME%

:: --- Create report directory structure ---
set REPORT_DIR=%ROOT_DIR%\reports\%TARGET_HOSTNAME%_%TS%
set JSON_FILE=%REPORT_DIR%\comprehensive_report.json
set TEMP_DIR=%REPORT_DIR%\details

:: --- Admin check (local only) ---
if "!IS_REMOTE!"=="false" (
    net session >NUL 2>&1
    if !errorlevel!==0 (set IS_ADMIN=true) else (set IS_ADMIN=false)
) else (
    set IS_ADMIN=false
    echo [INFO] Running remote analysis - some admin-only features disabled
    echo.
)

:: --- Create report directories ---
mkdir "%REPORT_DIR%" 2>nul
mkdir "%TEMP_DIR%" 2>nul

:: --- Display execution header ---
echo ===============================
echo  Starting System Report Collection
echo ===============================
echo Machine: !MACHINE!
echo User: %USERNAME%
echo Admin: !IS_ADMIN!
echo Report Directory: reports\!TARGET_HOSTNAME!_!TS!
echo Output File: comprehensive_report.json
echo Timestamp: !TS!
echo ===============================
echo.
echo [*] Collecting comprehensive system information...
echo [*] This will take 3-5 minutes to gather all data...
echo.

:: ===============================
:: COLLECT RAW DATA TO TEMP FILES
:: ===============================

:: For remote systems, try PowerShell remoting first, then fall back to PsExec
if "!IS_REMOTE!"=="true" (
    echo [*] Attempting PowerShell remoting for data collection...
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\assests\collect_remote_data.ps1" -ComputerName "!TARGET_HOSTNAME!" -OutputDir "%TEMP_DIR%" 2>nul

    if !errorlevel! equ 0 (
        echo [SUCCESS] Remote data collection complete via PowerShell remoting
        echo.
        goto :skip_local_collection
    )

    echo [WARNING] PowerShell remoting not available on !TARGET_HOSTNAME!
    echo [*] Attempting to use PsExec instead...
    echo.

    :: Check if PsExec exists in SysinternalsSuite directory or root directory
    set "PSEXEC_PATH="
    if exist "%ROOT_DIR%\SysinternalsSuite\PsExec.exe" (
        set "PSEXEC_PATH=%ROOT_DIR%\SysinternalsSuite\PsExec.exe"
    ) else if exist "%ROOT_DIR%\PsExec.exe" (
        set "PSEXEC_PATH=%ROOT_DIR%\PsExec.exe"
    )

    if defined PSEXEC_PATH (
        echo [SUCCESS] PsExec found, using for remote collection...
        echo [*] This will collect all 10 steps of data from !TARGET_HOSTNAME!...
        echo.
        powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\assests\collect_remote_psexec.ps1" -ComputerName "!TARGET_HOSTNAME!" -OutputDir "%TEMP_DIR%" -PsExecPath "!PSEXEC_PATH!"

        if !errorlevel! neq 0 (
            echo.
            echo [ERROR] Remote data collection failed via PsExec
            echo Please ensure:
            echo 1. You have administrative access to !TARGET_HOSTNAME!
            echo 2. File and Printer Sharing is enabled
            echo 3. Remote Registry service is running
            echo.
            exit /b 1
        )
        echo [SUCCESS] Remote data collection complete via PsExec
        echo.
        goto :skip_local_collection
    ) else (
        echo [ERROR] Neither PowerShell remoting nor PsExec is available
        echo.
        echo To use PowerShell remoting:
        echo   Run on !TARGET_HOSTNAME!: Enable-PSRemoting -Force
        echo.
        echo To use PsExec:
        echo   1. Download Sysinternals Suite from:
        echo      https://docs.microsoft.com/en-us/sysinternals/downloads/psexec
        echo   2. Place in: %ROOT_DIR%\SysinternalsSuite\PsExec.exe
        echo      OR: %ROOT_DIR%\PsExec.exe
        echo.
        exit /b 1
    )
)

:: For local systems, collect data using standard commands
echo [*] Step 1/10: Collecting system information...
systeminfo > "%TEMP_DIR%\systeminfo.txt" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" > "%TEMP_DIR%\winbuild.txt" 2>&1

echo [*] Step 2/10: Collecting storage information...
powershell -NoProfile -Command "Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID,Size,FreeSpace,DriveType,FileSystem,VolumeName | Export-Csv -NoTypeInformation -Path '%TEMP_DIR%\disks.csv'" > nul 2>&1
mountvol > "%TEMP_DIR%\mountvol.txt" 2>&1

echo [*] Step 3/10: Collecting hardware information...
driverquery /v /fo csv > "%TEMP_DIR%\drivers.csv" 2>&1

echo [*] Step 4/10: Collecting software information...
powershell -NoProfile -Command "Get-HotFix | Select-Object HotFixID,Description,InstalledBy,InstalledOn | Export-Csv -NoTypeInformation -Path '%TEMP_DIR%\hotfixes.csv'" > nul 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" > "%TEMP_DIR%\startup_hklm.txt" 2>&1
reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" > "%TEMP_DIR%\startup_hkcu.txt" 2>&1

echo [*] Step 5/10: Collecting process information...
tasklist /fo csv > "%TEMP_DIR%\processes.csv" 2>&1

echo [*] Step 6/10: Collecting service information...
sc query type= service state= all > "%TEMP_DIR%\services.txt" 2>&1

echo [*] Step 7/10: Collecting scheduled tasks...
schtasks /query /fo LIST > "%TEMP_DIR%\scheduled_tasks.txt" 2>&1

echo [*] Step 8/10: Collecting network information...
ipconfig /all > "%TEMP_DIR%\ipconfig_all.txt" 2>&1
getmac /v /fo csv > "%TEMP_DIR%\getmac.csv" 2>&1
arp -a > "%TEMP_DIR%\arp.txt" 2>&1
route print > "%TEMP_DIR%\routes.txt" 2>&1
netsh interface ipv4 show config > "%TEMP_DIR%\ipv4_config.txt" 2>&1
netsh interface ipv6 show interface > "%TEMP_DIR%\ipv6_interfaces.txt" 2>&1
netsh wlan show interfaces > "%TEMP_DIR%\wlan_interfaces.txt" 2>&1
netsh wlan show profiles > "%TEMP_DIR%\wlan_profiles.txt" 2>&1
nslookup google.com > "%TEMP_DIR%\dns_test.txt" 2>&1

echo [*] Step 9/10: Collecting power information...
powercfg /batteryreport /output "%TEMP_DIR%\battery_report.html" >nul 2>&1
echo     Battery report generated - capacity, cycle count, and life estimates parsed from it

echo [*] Step 10/10: Collecting Group Policy and events...
gpresult /r /v > "%TEMP_DIR%\gpresult.txt" 2>&1

:skip_local_collection

:: ===============================
:: GENERATE JSON USING SEPARATE POWERSHELL SCRIPT
:: ===============================

echo.
echo ===============================
echo   DATA COLLECTION COMPLETE
echo ===============================
echo All detailed files saved to: !REPORT_DIR!\details\
echo.
echo [*] Now generating comprehensive JSON report using PowerShell...
echo [*] Processing system information...
echo [*] This may take several minutes...

:: Call the separate PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\assests\generate_json.ps1" -TempDir "%TEMP_DIR%" -JsonFile "%JSON_FILE%" -Machine "!MACHINE!" -Username "%USERNAME%" -UserDomain "%USERDOMAIN%" -Timestamp "!TS!" -IsAdminString "!IS_ADMIN!" -IsRemoteString "!IS_REMOTE!"

echo [*] JSON generation complete

set PS_EXIT_CODE=%errorlevel%

:: ===============================
:: VALIDATION & COMPLETION
:: ===============================
echo.
echo [*] Validating JSON file...

powershell -NoProfile -Command "try { $json = Get-Content '%JSON_FILE%' -Raw | ConvertFrom-Json; Write-Host '[JSON VALID] Successfully parsed - Machine: ' $json.metadata.machine } catch { Write-Host '[JSON ERROR] Parse failed: ' $_.Exception.Message; exit 1 }" 2>nul

set JSON_VALID=%errorlevel%

echo.
echo ===============================
if %JSON_VALID% equ 0 if exist "%JSON_FILE%" (
    echo [SUCCESS] Comprehensive system report generated!
    echo.
    echo Report Location: !REPORT_DIR!
    echo   Main Report: comprehensive_report.json
    for %%A in ("%JSON_FILE%") do echo   Size: %%~zA bytes
    echo   Detailed Files: details\ subfolder
    echo.
    echo NEXT STEPS:
    echo 1. Open system_report.html in your web browser
    echo 2. Click "Choose File" and select: !REPORT_DIR!\comprehensive_report.json
    echo 3. Search and analyze all collected data
    echo 4. Review detailed files in the details\ subfolder if needed
    echo.
) else (
    echo [ERROR] Failed to create valid JSON file
    echo Check the errors above for details.
    echo.
)

if not exist "system_report.html" (
    echo [WARNING] HTML viewer 'system_report.html' not found.
    echo Ensure both files are in the same directory.
    echo.
)

echo ===============================
echo Collection Summary:
echo - System Info: Complete ^(OS, hardware, uptime^)
echo - Storage: Disks, mount points, file systems
echo - Hardware: Problem devices, driver inventory
echo - Software: Installed apps, updates, startup programs
echo - Processes: Top processes, all services
echo - Network: Full config, adapters, WiFi, routes
echo - Power: Battery/energy reports ^(if available^)
echo - Events: 24h critical/error logs
echo - Group Policy: Complete results
echo - Additional: Environment vars, paths, system details
echo ===============================
echo.

endlocal
exit /b 0