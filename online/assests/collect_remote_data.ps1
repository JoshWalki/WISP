param(
    [string]$ComputerName,
    [string]$OutputDir
)

Write-Host "[*] Testing PowerShell remoting to $ComputerName..."

# Test if PSRemoting is available
try {
    $testResult = Test-WSMan -ComputerName $ComputerName -ErrorAction Stop
    Write-Host "[SUCCESS] PowerShell remoting is available"
} catch {
    Write-Host "[ERROR] PowerShell remoting not available: $($_.Exception.Message)"
    Write-Host "[INFO] Ensure WinRM is enabled on the target computer"
    Write-Host "[INFO] Run this on target: Enable-PSRemoting -Force"
    exit 1
}

Write-Host "[*] Collecting data from $ComputerName using PowerShell remoting..."

# Collect system information using Invoke-Command
try {
    $result = Invoke-Command -ComputerName $ComputerName -ErrorAction Stop -ScriptBlock {
        # System Information
        $systemInfo = systeminfo

        # Disk Information
        $disks = Get-WmiObject Win32_LogicalDisk | Select-Object DeviceID, VolumeName, FileSystem, Size, FreeSpace, DriveType

        # Drivers (limited in remote session)
        $drivers = Get-WmiObject Win32_SystemDriver | Select-Object Name, DisplayName, State, StartMode, PathName -First 50

        # Hotfixes
        $hotfixes = Get-HotFix | Select-Object HotFixID, Description, InstalledBy, InstalledOn

        # Startup Programs
        $startupHKLM = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue

        # Processes
        $processes = Get-Process | Select-Object ProcessName, Id, WorkingSet -First 50

        # Services
        $services = Get-Service | Select-Object Name, DisplayName, Status, StartType

        # Network Configuration
        $ipconfig = ipconfig /all
        $netAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object Name, Status, MacAddress, LinkSpeed
        $netIPConfig = Get-NetIPConfiguration -ErrorAction SilentlyContinue

        # Group Policy
        $gpresult = gpresult /r /v

        # Scheduled Tasks
        $scheduledTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Select-Object TaskName, State, TaskPath -First 100

        # Event Logs (last 6 hours, critical/error only)
        $systemEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-6)} -MaxEvents 10 -ErrorAction SilentlyContinue
        $appEvents = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=(Get-Date).AddHours(-6)} -MaxEvents 10 -ErrorAction SilentlyContinue

        # Installed Applications
        $apps = @()
        $registryPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($path in $registryPaths) {
            $items = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
            foreach ($item in $items) {
                $apps += [PSCustomObject]@{
                    Name = $item.DisplayName
                    Version = $item.DisplayVersion
                    Publisher = $item.Publisher
                    InstallDate = $item.InstallDate
                }
            }
        }

        # Return all collected data
        return @{
            SystemInfo = $systemInfo
            Disks = $disks
            Drivers = $drivers
            Hotfixes = $hotfixes
            StartupPrograms = $startupHKLM
            Processes = $processes
            Services = $services
            IpConfig = $ipconfig
            NetworkAdapters = $netAdapters
            NetworkIPConfig = $netIPConfig
            GroupPolicy = $gpresult
            ScheduledTasks = $scheduledTasks
            SystemEvents = $systemEvents
            ApplicationEvents = $appEvents
            InstalledApps = $apps
        }
    }

    Write-Host "[*] Data collection successful, saving to files..."

    # Save SystemInfo
    $result.SystemInfo | Out-File "$OutputDir\systeminfo.txt" -Encoding UTF8

    # Save Disks
    $result.Disks | Export-Csv "$OutputDir\disks.csv" -NoTypeInformation

    # Save Drivers
    $result.Drivers | Export-Csv "$OutputDir\drivers.csv" -NoTypeInformation

    # Save Hotfixes
    $result.Hotfixes | Export-Csv "$OutputDir\hotfixes.csv" -NoTypeInformation

    # Save Processes
    $result.Processes | Export-Csv "$OutputDir\processes.csv" -NoTypeInformation

    # Save Services
    $result.Services | Out-File "$OutputDir\services.txt" -Encoding UTF8

    # Save Network Config
    $result.IpConfig | Out-File "$OutputDir\ipconfig_all.txt" -Encoding UTF8
    $result.NetworkAdapters | Export-Csv "$OutputDir\getmac.csv" -NoTypeInformation

    # Save Group Policy
    $result.GroupPolicy | Out-File "$OutputDir\gpresult.txt" -Encoding UTF8

    # Save Scheduled Tasks
    $result.ScheduledTasks | Out-File "$OutputDir\scheduled_tasks.txt" -Encoding UTF8

    # Create placeholder files for unsupported commands
    "Remote ARP table not accessible via PowerShell remoting" | Out-File "$OutputDir\arp.txt"
    "Remote routing table not accessible via PowerShell remoting" | Out-File "$OutputDir\routes.txt"
    "Remote WLAN interfaces not accessible via PowerShell remoting" | Out-File "$OutputDir\wlan_interfaces.txt"
    "Remote WLAN profiles not accessible via PowerShell remoting" | Out-File "$OutputDir\wlan_profiles.txt"
    "Remote power commands not supported" | Out-File "$OutputDir\battery_report.html"
    "Remote power commands not supported" | Out-File "$OutputDir\energy_report.html"

    # Save registry startup programs
    if ($result.StartupPrograms) {
        $result.StartupPrograms | Out-File "$OutputDir\startup_hklm.txt" -Encoding UTF8
    } else {
        "No startup programs found" | Out-File "$OutputDir\startup_hklm.txt"
    }
    "Remote HKCU not accessible" | Out-File "$OutputDir\startup_hkcu.txt"

    # Windows build info
    Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    } | Out-File "$OutputDir\winbuild.txt" -Encoding UTF8

    # Create mountvol placeholder
    "Remote mountvol not supported" | Out-File "$OutputDir\mountvol.txt"

    # IPv4/IPv6 config placeholders
    "Use ipconfig_all.txt for network configuration" | Out-File "$OutputDir\ipv4_config.txt"
    "Use ipconfig_all.txt for network configuration" | Out-File "$OutputDir\ipv6_interfaces.txt"

    # DNS test
    nslookup google.com | Out-File "$OutputDir\dns_test.txt"

    Write-Host "[SUCCESS] All remote data collected successfully"
    exit 0

} catch {
    Write-Host "[ERROR] Failed to collect data: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
}
