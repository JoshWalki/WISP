@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ===============================
:: Comprehensive System Report Generator (Self-Contained)
:: Creates detailed JSON data for IT support analysis
:: This version embeds all PowerShell dependencies inline for PsExec compatibility
:: ===============================

:: --- Display initial header ---
cls
echo ===============================
echo  Comprehensive System Report
echo  (Self-Contained Version)
echo ===============================
echo.

:: --- Check for hostname parameter (required when called from WISP) ---
set "TARGET_HOSTNAME=%1"
if "%TARGET_HOSTNAME%"=="" (
    echo [ERROR] No hostname parameter provided
    echo.
    echo Usage: SystemReport_Standalone.bat [HOSTNAME]
    echo   HOSTNAME can be a computer name or IP address
    echo   Use "%COMPUTERNAME%" for local computer
    echo.
    echo Example: SystemReport_Standalone.bat %COMPUTERNAME%
    echo Example: SystemReport_Standalone.bat PC-001
    echo Example: SystemReport_Standalone.bat 192.168.1.100
    echo.
    exit /b 1
)

:: Determine if this is a local or remote analysis
if /i "%TARGET_HOSTNAME%"=="%COMPUTERNAME%" (
    set "IS_REMOTE=false"
    echo ===============================
    echo    Local System Analysis
    echo ===============================
    echo Target: %TARGET_HOSTNAME%
    echo ===============================
    echo.
) else (
    set "IS_REMOTE=true"
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

:: --- Determine root directory ---
:: When copied by PsExec, script runs from System32, so we need to create reports in a standard location
set "ROOT_DIR=%SystemDrive%\WISP_Reports"
if not exist "%ROOT_DIR%" mkdir "%ROOT_DIR%" 2>nul

:: --- Timestamp ---
for /f "delims=" %%a in ('powershell -NoProfile -Command "(Get-Date).ToString(\"yyyyMMdd_HHmmss\")"') do set TS=%%a
set MACHINE=%TARGET_HOSTNAME%

:: --- Create report directory structure ---
set REPORT_DIR=%ROOT_DIR%\%TARGET_HOSTNAME%_%TS%
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
echo Report Directory: %REPORT_DIR%
echo Output File: comprehensive_report.json
echo Timestamp: !TS!
echo ===============================
echo.
echo [*] Collecting comprehensive system information...
echo [*] This will take 3-5 minutes to gather all data...
echo.

:: ===============================
:: COLLECT RAW DATA TO TEMP FILES (LOCAL EXECUTION ONLY)
:: ===============================

:: This self-contained version only supports LOCAL execution
:: Remote data collection requires external PowerShell scripts which cannot be embedded

if "!IS_REMOTE!"=="true" (
    echo [ERROR] This self-contained version only supports LOCAL execution
    echo.
    echo For remote analysis, use the full SystemReport.bat with supporting scripts
    echo or deploy this script to the target machine and run locally.
    echo.
    exit /b 1
)

:: For local systems, collect data using standard commands
echo [*] Step 1/10: Collecting system information...
systeminfo > "%TEMP_DIR%\systeminfo.txt" 2>&1
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" > "%TEMP_DIR%\winbuild.txt" 2>&1

echo [*] Step 2/10: Collecting storage information...
wmic logicaldisk get Size,FreeSpace,Caption,DriveType,FileSystem,VolumeName /format:csv > "%TEMP_DIR%\disks.csv" 2>&1
mountvol > "%TEMP_DIR%\mountvol.txt" 2>&1

echo [*] Step 3/10: Collecting hardware information...
driverquery /v /fo csv > "%TEMP_DIR%\drivers.csv" 2>&1

echo [*] Step 4/10: Collecting software information...
wmic qfe get HotFixID,Description,InstalledBy,InstalledOn /format:csv > "%TEMP_DIR%\hotfixes.csv" 2>&1
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
echo Energy report skipped ^(takes 60 seconds to run^) > "%TEMP_DIR%\energy_report.html" 2>&1
echo     Battery report generated, energy report skipped for performance

echo [*] Step 10/10: Collecting Group Policy and events...
gpresult /r /v > "%TEMP_DIR%\gpresult.txt" 2>&1

:: ===============================
:: GENERATE JSON USING EMBEDDED POWERSHELL
:: ===============================

echo.
echo ===============================
echo   DATA COLLECTION COMPLETE
echo ===============================
echo All detailed files saved to: !REPORT_DIR!\details\
echo.
echo [*] Now generating comprehensive JSON report...

:: Call embedded PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -Command "& {$TempDir='%TEMP_DIR%';$JsonFile='%JSON_FILE%';$Machine='!MACHINE!';$Username='%USERNAME%';$UserDomain='%USERDOMAIN%';$Timestamp='!TS!';$IsAdminString='!IS_ADMIN!';$IsRemoteString='!IS_REMOTE!';$IsAdmin = $IsAdminString -eq 'true';$IsRemote = $IsRemoteString -eq 'true';try{Write-Host '[*] Starting JSON generation...';$systemData=@{metadata=@{machine=$Machine;user=$Username;domain=$UserDomain;generated=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');timestamp=$Timestamp;isAdmin=$IsAdmin;reportType='comprehensive'};system=@{};storage=@{};hardware=@{};software=@{};processes=@{};services=@{};network=@{};power=@{};events=@{};groupPolicy=@{};additional=@{};collectionInfo=@{}};Write-Host '[*] Processing system information...';try{$systemInfoFile=Join-Path $TempDir 'systeminfo.txt';if(Test-Path $systemInfoFile){$systemInfoRaw=Get-Content $systemInfoFile;$systemInfo=@{};foreach($line in $systemInfoRaw){if($line -match '^(.+?):\s+(.+)$'){$key=$matches[1].Trim();$value=$matches[2].Trim();switch($key){'Host Name'{$systemInfo.hostName=$value}'OS Name'{$systemInfo.osName=$value}'OS Version'{$systemInfo.osVersion=$value}'System Manufacturer'{$systemInfo.manufacturer=$value}'System Model'{$systemInfo.model=$value}'System Type'{$systemInfo.systemType=$value}'Total Physical Memory'{$systemInfo.totalMemory=$value}}}};$systemData.system.systeminfo=$systemInfo}else{$systemData.system.systeminfo=@{error='systeminfo.txt not found'}}}catch{$systemData.system.systeminfo=@{error=$_.Exception.Message}};try{$buildInfo=@{};try{$versionKey=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue;if($versionKey){$buildInfo.rawProductName=$versionKey.ProductName;$buildInfo.releaseId=$versionKey.ReleaseId;$buildInfo.currentBuild=$versionKey.CurrentBuild;$buildInfo.currentVersion=$versionKey.CurrentVersion;$buildInfo.buildLabEx=$versionKey.BuildLabEx;$buildInfo.displayVersion=$versionKey.DisplayVersion;$buildInfo.edition=$versionKey.EditionID;$buildInfo.ubr=$versionKey.UBR;$actualProductName=$buildInfo.rawProductName;$buildNumber=[int]$buildInfo.currentBuild;if($buildNumber -ge 22000){$actualProductName=$buildInfo.rawProductName -replace 'Windows 10','Windows 11';$buildInfo.isWindows11=$true;if($buildNumber -ge 26100){$buildInfo.detectedVersion='24H2'}elseif($buildNumber -ge 22631){$buildInfo.detectedVersion='23H2'}elseif($buildNumber -ge 22621){$buildInfo.detectedVersion='22H2'}elseif($buildNumber -ge 22000){$buildInfo.detectedVersion='21H2'}}else{$buildInfo.isWindows11=$false;if($buildNumber -ge 19045){$buildInfo.detectedVersion='22H2'}elseif($buildNumber -ge 19044){$buildInfo.detectedVersion='21H2'}elseif($buildNumber -ge 19043){$buildInfo.detectedVersion='21H1'}elseif($buildNumber -ge 19042){$buildInfo.detectedVersion='20H2'}elseif($buildNumber -ge 19041){$buildInfo.detectedVersion='2004'}};$buildInfo.productName=$actualProductName;$versionToUse=$buildInfo.displayVersion;if(-not $versionToUse -or($buildInfo.isWindows11 -and $versionToUse -like '*10*')){$versionToUse=$buildInfo.detectedVersion};$fullVersion=\"$actualProductName\";if($versionToUse){$fullVersion+=\" Version $versionToUse\"}elseif($buildInfo.releaseId){$fullVersion+=\" Version $($buildInfo.releaseId)\"};if($buildInfo.currentBuild){$fullVersion+=\" (Build $($buildInfo.currentBuild)\"};if($buildInfo.ubr){$fullVersion+=\".$($buildInfo.ubr)\"};if($buildInfo.currentBuild){$fullVersion+=\")\"};if($buildInfo.edition){$fullVersion+=\" $($buildInfo.edition)\"};$buildInfo.fullVersionString=$fullVersion;$buildInfo.correctedVersion=$versionToUse}}catch{$buildFile=Join-Path $TempDir 'winbuild.txt';if(Test-Path $buildFile){$buildContent=Get-Content $buildFile;foreach($line in $buildContent){if($line -match 'ProductName\s+REG_SZ\s+(.+)'){$buildInfo.productName=$matches[1].Trim()};if($line -match 'ReleaseId\s+REG_SZ\s+(.+)'){$buildInfo.releaseId=$matches[1].Trim()};if($line -match 'CurrentBuild\s+REG_SZ\s+(.+)'){$buildInfo.currentBuild=$matches[1].Trim()};if($line -match 'CurrentVersion\s+REG_SZ\s+(.+)'){$buildInfo.currentVersion=$matches[1].Trim()};if($line -match 'BuildLabEx\s+REG_SZ\s+(.+)'){$buildInfo.buildLabEx=$matches[1].Trim()};if($line -match 'DisplayVersion\s+REG_SZ\s+(.+)'){$buildInfo.displayVersion=$matches[1].Trim()};if($line -match 'EditionID\s+REG_SZ\s+(.+)'){$buildInfo.edition=$matches[1].Trim()};if($line -match 'UBR\s+REG_DWORD\s+(.+)'){$buildInfo.ubr=$matches[1].Trim()}};if($buildInfo.productName){$fullVersion=$buildInfo.productName;if($buildInfo.displayVersion){$fullVersion+=\" Version $($buildInfo.displayVersion)\"}elseif($buildInfo.releaseId){$fullVersion+=\" Version $($buildInfo.releaseId)\"};if($buildInfo.currentBuild){$fullVersion+=\" (Build $($buildInfo.currentBuild)\"};if($buildInfo.ubr){$fullVersion+=\".$($buildInfo.ubr)\"};if($buildInfo.currentBuild){$fullVersion+=\")\"};if($buildInfo.edition){$fullVersion+=\" $($buildInfo.edition)\"};$buildInfo.fullVersionString=$fullVersion}}};if(-not $buildInfo.productName){try{$osInfo=Get-CimInstance Win32_OperatingSystem;$buildInfo.productName=$osInfo.Caption;$buildInfo.currentVersion=$osInfo.Version;$buildInfo.buildNumber=$osInfo.BuildNumber;$buildInfo.servicePackMajorVersion=$osInfo.ServicePackMajorVersion;$fullVersion=\"$($osInfo.Caption) (Build $($osInfo.BuildNumber))\";if($osInfo.ServicePackMajorVersion -gt 0){$fullVersion+=\" SP$($osInfo.ServicePackMajorVersion)\"};$buildInfo.fullVersionString=$fullVersion}catch{$buildInfo.error='Failed to get version info from multiple sources'}};$systemData.system.windowsBuild=$buildInfo}catch{$systemData.system.windowsBuild=@{error=$_.Exception.Message}};try{$bootTime=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime;$uptime=(Get-Date)-$bootTime;$systemData.system.uptime=@{days=$uptime.Days;hours=$uptime.Hours;minutes=$uptime.Minutes;lastBoot=$bootTime.ToString()}}catch{$systemData.system.uptime=@{error=$_.Exception.Message}};Write-Host '[*] Processing storage, hardware, software, processes...';try{$diskFile=Join-Path $TempDir 'disks.csv';if(Test-Path $diskFile){$fileContent=Get-Content $diskFile;$csvLines=@();$foundHeader=$false;foreach($line in $fileContent){if($line -match '^\"?(Caption|DeviceID)\"?'){$foundHeader=$true;$csvLines+=$line}elseif($foundHeader -and $line -match '^\"?[A-Z]:\"?'){$csvLines+=$line}};if($csvLines.Count -gt 0){$csvContent=$csvLines -join \"`n\";$tempCsv=Join-Path $env:TEMP \"temp_disks_$(Get-Random).csv\";$csvContent|Out-File -FilePath $tempCsv -Encoding UTF8;$rawData=Import-Csv $tempCsv;Remove-Item $tempCsv -ErrorAction SilentlyContinue;$diskData=$rawData|Where-Object{$_.Caption -or $_.DeviceID};$disks=@();foreach($disk in $diskData){$disks+=@{caption=if($disk.Caption){$disk.Caption}else{$disk.DeviceID};driveType=$disk.DriveType;fileSystem=$disk.FileSystem;freeSpace=$disk.FreeSpace;size=$disk.Size;volumeName=$disk.VolumeName}};$systemData.storage.logicalDisks=$disks}else{$systemData.storage.logicalDisks=@{error='No valid disk data found in CSV'}}}else{$systemData.storage.logicalDisks=@{error='disks.csv not found'}}}catch{$systemData.storage.logicalDisks=@{error=$_.Exception.Message}};try{$mountFile=Join-Path $TempDir 'mountvol.txt';if(Test-Path $mountFile){$mountContent=Get-Content $mountFile -Raw;$systemData.storage.mountPoints=@{content=$mountContent}}else{$systemData.storage.mountPoints=@{error='mountvol.txt not found'}}}catch{$systemData.storage.mountPoints=@{error=$_.Exception.Message}};try{$problemDevices=Get-PnpDevice|Where-Object Status -ne 'OK'|Select-Object Name,Status,Class|ForEach-Object{@{name=$_.Name;status=$_.Status;class=$_.Class}};$systemData.hardware.problemDevices=$problemDevices}catch{$systemData.hardware.problemDevices=@{error=$_.Exception.Message}};try{$systemData.software.installedApps=@();Write-Host '    Collecting installed applications...';$registryPaths=@('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*');$apps=@();$seenNames=@{};foreach($path in $registryPaths){try{$items=Get-ItemProperty $path -ErrorAction SilentlyContinue|Where-Object{$_.DisplayName -and $_.DisplayName.Trim() -ne ''};foreach($item in $items){$appName=$item.DisplayName.Trim();if(-not $seenNames.ContainsKey($appName)){$apps+=@{name=$appName;version=$item.DisplayVersion;publisher=$item.Publisher;installDate=$item.InstallDate};$seenNames[$appName]=$true}}}catch{}};$apps=$apps|Sort-Object{$_.name};Write-Host \"    Found $($apps.Count) installed applications\";$systemData.software.installedApps=$apps}catch{$systemData.software.installedApps=@{error=$_.Exception.Message}};Write-Host '[*] Processing network information...';try{$adapterFile=Join-Path $TempDir 'getmac.csv';$adapters=@();$usedWmiFallback=$false;if(Test-Path $adapterFile){$fileContent=Get-Content $adapterFile -Raw;if($fileContent -match 'Remote|not supported|failed' -or $fileContent.Length -lt 50){$usedWmiFallback=$true}else{try{$csvContent=Get-Content $adapterFile -Encoding Unicode|Where-Object{$_.Trim() -ne ''};$tempCsv=Join-Path $env:TEMP \"temp_adapters_$(Get-Random).csv\";$csvContent|Out-File -FilePath $tempCsv -Encoding Unicode;$adapterData=Import-Csv $tempCsv -Encoding Unicode|Select-Object -First 10;Remove-Item $tempCsv -ErrorAction SilentlyContinue;foreach($adapter in $adapterData){$adapters+=@{name=$adapter.'Connection Name';transport=$adapter.'Transport Name';macAddress=$adapter.'Physical Address'}}}catch{$usedWmiFallback=$true}}}else{$usedWmiFallback=$true};if($usedWmiFallback -or $adapters.Count -eq 0){try{$wmiAdapters=Get-CimInstance Win32_NetworkAdapterConfiguration|Where-Object{$_.IPEnabled -eq $true};foreach($adapter in $wmiAdapters){$ipAddresses=@();if($adapter.IPAddress){$ipAddresses=$adapter.IPAddress};$adapters+=@{name=$adapter.Description;macAddress=$adapter.MACAddress;ipAddresses=$ipAddresses;dhcpEnabled=$adapter.DHCPEnabled;dhcpServer=$adapter.DHCPServer;dnsServers=$adapter.DNSServerSearchOrder;defaultGateway=$adapter.DefaultIPGateway;subnetMask=$adapter.IPSubnet;source='WMI'}};$systemData.network.adapters=$adapters}catch{$systemData.network.adapters=@{error=\"Failed to retrieve network data: $($_.Exception.Message)\"}}}else{$systemData.network.adapters=$adapters}}catch{$systemData.network.adapters=@{error=$_.Exception.Message}};Write-Host '[*] Processing events and power...';try{$systemEvents=Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddHours(-6)} -MaxEvents 5 -ErrorAction SilentlyContinue|ForEach-Object{@{time=$_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss');id=$_.Id;level=$_.LevelDisplayName;source=$_.ProviderName;message=if($_.Message -and $_.Message.Length -gt 80){$_.Message.Substring(0,80)+'...'}else{$_.Message}}};$systemData.events.systemErrors=if($systemEvents){$systemEvents}else{@(@{info='No critical/error events in last 6 hours'})}}catch{$systemData.events.systemErrors=@{error='Event log access limited'}};try{$gpFile=Join-Path $TempDir 'gpresult.txt';if(Test-Path $gpFile){$gpContent=Get-Content $gpFile;$gpInfo=@{appliedGPOs=@()};$currentSection='';foreach($line in $gpContent|Select-Object -First 200){if($line -match 'Applied Group Policy Objects'){$currentSection='gpos'}elseif($line -match '^\s+(.+)$' -and $currentSection -eq 'gpos' -and $matches[1].Trim() -ne ''){$gpInfo.appliedGPOs+=$matches[1].Trim()}};$gpSummaryLines=$gpContent|Select-Object -First 30;$gpInfo.summary=($gpSummaryLines -join \"`n\");$gpInfo.content=[System.IO.File]::ReadAllText($gpFile);$systemData.groupPolicy=$gpInfo}else{$systemData.groupPolicy=@{error='gpresult.txt not found'}}}catch{$systemData.groupPolicy=@{error=$_.Exception.Message}};$systemData.additional=@{environment=@{numberOfProcessors=$env:NUMBER_OF_PROCESSORS;processorArchitecture=$env:PROCESSOR_ARCHITECTURE;processorIdentifier=$env:PROCESSOR_IDENTIFIER};userProfile=@{userProfile=$env:USERPROFILE;appData=$env:APPDATA};systemPaths=@{systemRoot=$env:SystemRoot;programFiles=$env:ProgramFiles;temp=$env:TEMP}};$systemData.collectionInfo=@{method='self_contained_batch';version='1.0';description='Self-contained version for PsExec compatibility'};Write-Host '[*] Writing JSON file...';$systemData.metadata.performanceOptimized=$true;try{$json=$systemData|ConvertTo-Json -Depth 6 -Compress;$json=$json -replace '\":True','\":true' -replace '\":False','\":false';$json|Out-File -FilePath $JsonFile -Encoding UTF8;Write-Host '[SUCCESS] JSON file created successfully'}catch{Write-Host \"[ERROR] JSON conversion failed: $($_.Exception.Message)\";$simpleData=@{metadata=$systemData.metadata;system=@{note='Simplified output due to JSON conversion issues'}};$json=$simpleData|ConvertTo-Json -Depth 3;$json|Out-File -FilePath $JsonFile -Encoding UTF8;Write-Host '[SUCCESS] Simplified JSON file created successfully'}}catch{Write-Host \"[FATAL ERROR] PowerShell script failed: $($_.Exception.Message)\";exit 1}}"

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

echo ===============================
echo Collection Summary:
echo - System Info: Complete ^(OS, hardware, uptime^)
echo - Storage: Disks, mount points, file systems
echo - Hardware: Problem devices
echo - Software: Installed apps, updates, startup programs
echo - Processes: Top processes, all services
echo - Network: Full config, adapters, WiFi, routes
echo - Power: Battery/energy reports ^(if available^)
echo - Events: 6h critical/error logs
echo - Group Policy: Complete results
echo - Additional: Environment vars, paths, system details
echo ===============================
echo.
echo [NOTE] This is the self-contained version
echo Reports saved to: %ROOT_DIR%
echo.

endlocal
exit /b 0
