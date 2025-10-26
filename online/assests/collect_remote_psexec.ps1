param(
    [string]$ComputerName,
    [string]$OutputDir,
    [string]$PsExecPath
)

Write-Host "[*] Using PsExec for remote data collection from $ComputerName..."

# Check if PsExec exists
if (-not (Test-Path $PsExecPath)) {
    Write-Host "[ERROR] PsExec not found at: $PsExecPath"
    Write-Host "[INFO] Please download Sysinternals Suite and place PsExec.exe in the application directory"
    Write-Host "[INFO] Download from: https://docs.microsoft.com/en-us/sysinternals/downloads/psexec"
    exit 1
}

Write-Host "[SUCCESS] PsExec found at $PsExecPath"
Write-Host ""

# Test PsExec connectivity first with a simple command
Write-Host "[*] Testing PsExec connection to $ComputerName..."
$testOutput = & $PsExecPath "\\$ComputerName" -accepteula -nobanner cmd /c "echo CONNECTION_TEST" 2>&1 | Out-String

if ($testOutput -match "CONNECTION_TEST") {
    Write-Host "[SUCCESS] PsExec connection established"
    Write-Host ""
} elseif ($testOutput -match "Couldn't access" -or $testOutput -match "handle is invalid" -or $testOutput -match "Access is denied") {
    Write-Host ""
    Write-Host "[ERROR] Cannot establish PsExec connection to $ComputerName"
    Write-Host ""
    Write-Host "Common causes:"
    Write-Host "  1. You don't have administrative rights on $ComputerName"
    Write-Host "  2. File and Printer Sharing is disabled on $ComputerName"
    Write-Host "  3. Admin$ share is not accessible on $ComputerName"
    Write-Host "  4. Windows Firewall is blocking the connection"
    Write-Host "  5. User Account Control (UAC) is preventing remote admin access"
    Write-Host ""
    Write-Host "Solutions to try:"
    Write-Host "  - Ensure you're logged in with domain admin credentials"
    Write-Host "  - Enable File and Printer Sharing on $ComputerName"
    Write-Host "  - Verify admin$ share: net view \\$ComputerName"
    Write-Host "  - Check Windows Firewall rules on $ComputerName"
    Write-Host "  - For workgroup computers, you may need to:"
    Write-Host "    Set: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\LocalAccountTokenFilterPolicy=1"
    Write-Host ""
    Write-Host "Error details:"
    Write-Host $testOutput
    exit 1
} else {
    Write-Host "[WARNING] Unexpected response from PsExec, attempting to continue..."
    Write-Host $testOutput
    Write-Host ""
}

try {
    Write-Host "[*] Step 1/10: Collecting system information..."
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s systeminfo 2>&1 | Out-File "$OutputDir\systeminfo.txt" -Encoding UTF8
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" 2>&1 | Out-File "$OutputDir\winbuild.txt" -Encoding UTF8

    Write-Host "[*] Step 2/10: Collecting storage information..."
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s powershell -Command "Get-WmiObject Win32_LogicalDisk | Select-Object DeviceID, VolumeName, FileSystem, Size, FreeSpace, DriveType | Export-Csv -Path 'C:\Windows\Temp\disks_temp.csv' -NoTypeInformation; Get-Content 'C:\Windows\Temp\disks_temp.csv'; Remove-Item 'C:\Windows\Temp\disks_temp.csv' -Force" 2>&1 | Out-File "$OutputDir\disks.csv" -Encoding UTF8
    "Remote mountvol not supported via PsExec" | Out-File "$OutputDir\mountvol.txt"

    Write-Host "[*] Step 3/10: Collecting hardware information..."
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s driverquery /v /fo csv 2>&1 | Out-File "$OutputDir\drivers.csv" -Encoding UTF8

    Write-Host "[*] Step 4/10: Collecting software information..."
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s wmic qfe get HotFixID,Description,InstalledBy,InstalledOn /format:csv 2>&1 | Out-File "$OutputDir\hotfixes.csv" -Encoding UTF8
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" 2>&1 | Out-File "$OutputDir\startup_hklm.txt" -Encoding UTF8
    "Remote HKCU not accessible via PsExec" | Out-File "$OutputDir\startup_hkcu.txt"

    Write-Host "[*] Step 5/10: Collecting process information..."
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s tasklist /fo csv 2>&1 | Out-File "$OutputDir\processes.csv" -Encoding UTF8

    Write-Host "[*] Step 6/10: Collecting service information..."
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s sc query type= service state= all 2>&1 | Out-File "$OutputDir\services.txt" -Encoding UTF8

    Write-Host "[*] Step 7/10: Collecting scheduled tasks..."
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s schtasks /query /fo LIST 2>&1 | Out-File "$OutputDir\scheduled_tasks.txt" -Encoding UTF8

    Write-Host "[*] Step 8/10: Collecting network information..."
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s ipconfig /all 2>&1 | Out-File "$OutputDir\ipconfig_all.txt" -Encoding UTF8
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s getmac /v /fo csv 2>&1 | Out-File "$OutputDir\getmac.csv" -Encoding UTF8
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s arp -a 2>&1 | Out-File "$OutputDir\arp.txt" -Encoding UTF8
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s route print 2>&1 | Out-File "$OutputDir\routes.txt" -Encoding UTF8
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s netsh interface ipv4 show config 2>&1 | Out-File "$OutputDir\ipv4_config.txt" -Encoding UTF8
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s netsh interface ipv6 show interface 2>&1 | Out-File "$OutputDir\ipv6_interfaces.txt" -Encoding UTF8
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s netsh wlan show interfaces 2>&1 | Out-File "$OutputDir\wlan_interfaces.txt" -Encoding UTF8
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s netsh wlan show profiles 2>&1 | Out-File "$OutputDir\wlan_profiles.txt" -Encoding UTF8
    nslookup $ComputerName 2>&1 | Out-File "$OutputDir\dns_test.txt" -Encoding UTF8

    Write-Host "[*] Step 9/10: Collecting power information..."
    "Remote power commands not supported via PsExec" | Out-File "$OutputDir\battery_report.html"
    "Remote power commands not supported via PsExec" | Out-File "$OutputDir\energy_report.html"

    Write-Host "[*] Step 10/10: Collecting Group Policy and events..."
    & $PsExecPath "\\$ComputerName" -accepteula -nobanner -s gpresult /r /v 2>&1 | Out-File "$OutputDir\gpresult.txt" -Encoding UTF8

    Write-Host ""
    Write-Host "[SUCCESS] All remote data collected successfully via PsExec"
    exit 0

} catch {
    Write-Host ""
    Write-Host "[ERROR] Failed to collect data via PsExec: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
}
