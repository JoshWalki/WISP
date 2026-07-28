param(
    [string]$TempDir,
    [string]$JsonFile,
    [string]$Machine,
    [string]$Username,
    [string]$UserDomain,
    [string]$Timestamp,
    [string]$IsAdminString,
    [string]$IsRemoteString
)

# Convert strings to booleans
$IsAdmin = $IsAdminString -eq "true"
$IsRemote = $IsRemoteString -eq "true"

try {
    Write-Host '[*] Starting JSON generation...'

    # Create main data structure
    $systemData = @{
        metadata = @{
            machine = $Machine
            user = $Username
            domain = $UserDomain
            generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            timestamp = $Timestamp
            isAdmin = $IsAdmin
            reportType = 'comprehensive'
        }
        system = @{}
        storage = @{}
        hardware = @{}
        software = @{}
        processes = @{}
        services = @{}
        network = @{}
        power = @{}
        events = @{}
        groupPolicy = @{}
        additional = @{}
        collectionInfo = @{}
    }

    Write-Host '[*] Processing system information...'
    # Parse systeminfo
    try {
        $systemInfoFile = Join-Path $TempDir 'systeminfo.txt'
        if (Test-Path $systemInfoFile) {
            $systemInfoRaw = Get-Content $systemInfoFile
            $systemInfo = @{}
            foreach ($line in $systemInfoRaw) {
                if ($line -match '^(.+?):\s+(.+)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    switch ($key) {
                        'Host Name' { $systemInfo.hostName = $value }
                        'OS Name' { $systemInfo.osName = $value }
                        'OS Version' { $systemInfo.osVersion = $value }
                        'System Manufacturer' { $systemInfo.manufacturer = $value }
                        'System Model' { $systemInfo.model = $value }
                        'System Type' { $systemInfo.systemType = $value }
                        'Total Physical Memory' { $systemInfo.totalMemory = $value }
                    }
                }
            }
            $systemData.system.systeminfo = $systemInfo
        } else {
            $systemData.system.systeminfo = @{ error = 'systeminfo.txt not found' }
        }
    } catch {
        $systemData.system.systeminfo = @{ error = $_.Exception.Message }
    }

    # Parse Windows build - get comprehensive version info
    try {
        $buildInfo = @{}

        # Get Windows version info directly from registry
        try {
            $versionKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
            if ($versionKey) {
                $buildInfo.rawProductName = $versionKey.ProductName
                $buildInfo.releaseId = $versionKey.ReleaseId
                $buildInfo.currentBuild = $versionKey.CurrentBuild
                $buildInfo.currentVersion = $versionKey.CurrentVersion
                $buildInfo.buildLabEx = $versionKey.BuildLabEx
                $buildInfo.displayVersion = $versionKey.DisplayVersion
                $buildInfo.edition = $versionKey.EditionID
                $buildInfo.ubr = $versionKey.UBR

                # Detect actual Windows version - Windows 11 detection
                $actualProductName = $buildInfo.rawProductName
                $buildNumber = [int]$buildInfo.currentBuild

                # Windows 11 was released with build 22000
                # Windows 11 builds: 22000+ (21H2), 22621+ (22H2), 22631+ (23H2), 26100+ (24H2)
                if ($buildNumber -ge 22000) {
                    # This is Windows 11, regardless of what the registry says
                    $actualProductName = $buildInfo.rawProductName -replace "Windows 10", "Windows 11"
                    $buildInfo.isWindows11 = $true

                    # Add Windows 11 version detection based on build
                    if ($buildNumber -ge 26100) { $buildInfo.detectedVersion = "24H2" }
                    elseif ($buildNumber -ge 22631) { $buildInfo.detectedVersion = "23H2" }
                    elseif ($buildNumber -ge 22621) { $buildInfo.detectedVersion = "22H2" }
                    elseif ($buildNumber -ge 22000) { $buildInfo.detectedVersion = "21H2" }
                } else {
                    $buildInfo.isWindows11 = $false
                    # Windows 10 version detection
                    if ($buildNumber -ge 19045) { $buildInfo.detectedVersion = "22H2" }
                    elseif ($buildNumber -ge 19044) { $buildInfo.detectedVersion = "21H2" }
                    elseif ($buildNumber -ge 19043) { $buildInfo.detectedVersion = "21H1" }
                    elseif ($buildNumber -ge 19042) { $buildInfo.detectedVersion = "20H2" }
                    elseif ($buildNumber -ge 19041) { $buildInfo.detectedVersion = "2004" }
                }

                $buildInfo.productName = $actualProductName

                # Use detected version if DisplayVersion is not available or seems wrong
                $versionToUse = $buildInfo.displayVersion
                if (-not $versionToUse -or ($buildInfo.isWindows11 -and $versionToUse -like "*10*")) {
                    $versionToUse = $buildInfo.detectedVersion
                }

                # Create a comprehensive version string
                $fullVersion = "$actualProductName"
                if ($versionToUse) { $fullVersion += " Version $versionToUse" }
                elseif ($buildInfo.releaseId) { $fullVersion += " Version $($buildInfo.releaseId)" }
                if ($buildInfo.currentBuild) { $fullVersion += " (Build $($buildInfo.currentBuild)" }
                if ($buildInfo.ubr) { $fullVersion += ".$($buildInfo.ubr)" }
                if ($buildInfo.currentBuild) { $fullVersion += ")" }
                if ($buildInfo.edition) { $fullVersion += " $($buildInfo.edition)" }

                $buildInfo.fullVersionString = $fullVersion
                $buildInfo.correctedVersion = $versionToUse
            }
        } catch {
            # Fallback: try to parse from the collected file
            $buildFile = Join-Path $TempDir 'winbuild.txt'
            if (Test-Path $buildFile) {
                $buildContent = Get-Content $buildFile
                foreach ($line in $buildContent) {
                    if ($line -match 'ProductName\s+REG_SZ\s+(.+)') { $buildInfo.productName = $matches[1].Trim() }
                    if ($line -match 'ReleaseId\s+REG_SZ\s+(.+)') { $buildInfo.releaseId = $matches[1].Trim() }
                    if ($line -match 'CurrentBuild\s+REG_SZ\s+(.+)') { $buildInfo.currentBuild = $matches[1].Trim() }
                    if ($line -match 'CurrentVersion\s+REG_SZ\s+(.+)') { $buildInfo.currentVersion = $matches[1].Trim() }
                    if ($line -match 'BuildLabEx\s+REG_SZ\s+(.+)') { $buildInfo.buildLabEx = $matches[1].Trim() }
                    if ($line -match 'DisplayVersion\s+REG_SZ\s+(.+)') { $buildInfo.displayVersion = $matches[1].Trim() }
                    if ($line -match 'EditionID\s+REG_SZ\s+(.+)') { $buildInfo.edition = $matches[1].Trim() }
                    if ($line -match 'UBR\s+REG_DWORD\s+(.+)') { $buildInfo.ubr = $matches[1].Trim() }
                }

                # Create version string from parsed data
                if ($buildInfo.productName) {
                    $fullVersion = $buildInfo.productName
                    if ($buildInfo.displayVersion) { $fullVersion += " Version $($buildInfo.displayVersion)" }
                    elseif ($buildInfo.releaseId) { $fullVersion += " Version $($buildInfo.releaseId)" }
                    if ($buildInfo.currentBuild) { $fullVersion += " (Build $($buildInfo.currentBuild)" }
                    if ($buildInfo.ubr) { $fullVersion += ".$($buildInfo.ubr)" }
                    if ($buildInfo.currentBuild) { $fullVersion += ")" }
                    if ($buildInfo.edition) { $fullVersion += " $($buildInfo.edition)" }
                    $buildInfo.fullVersionString = $fullVersion
                }
            }
        }

        # If we still don't have good data, try alternative methods
        if (-not $buildInfo.productName) {
            try {
                $osInfo = Get-CimInstance Win32_OperatingSystem
                $buildInfo.productName = $osInfo.Caption
                $buildInfo.currentVersion = $osInfo.Version
                $buildInfo.buildNumber = $osInfo.BuildNumber
                $buildInfo.servicePackMajorVersion = $osInfo.ServicePackMajorVersion

                $fullVersion = "$($osInfo.Caption) (Build $($osInfo.BuildNumber))"
                if ($osInfo.ServicePackMajorVersion -gt 0) {
                    $fullVersion += " SP$($osInfo.ServicePackMajorVersion)"
                }
                $buildInfo.fullVersionString = $fullVersion
            } catch {
                $buildInfo.error = 'Failed to get version info from multiple sources'
            }
        }

        $systemData.system.windowsBuild = $buildInfo
    } catch {
        $systemData.system.windowsBuild = @{ error = $_.Exception.Message }
    }

    # System uptime
    try {
        $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $uptime = (Get-Date) - $bootTime
        $systemData.system.uptime = @{
            days = $uptime.Days
            hours = $uptime.Hours
            minutes = $uptime.Minutes
            lastBoot = $bootTime.ToString()
        }
    } catch {
        $systemData.system.uptime = @{ error = $_.Exception.Message }
    }

    Write-Host '[*] Processing storage information...'
    # Parse disks
    try {
        $diskFile = Join-Path $TempDir 'disks.csv'
        if (Test-Path $diskFile) {
            # Read the file and filter out PsExec noise, keeping only CSV lines
            $fileContent = Get-Content $diskFile
            $csvLines = @()
            $foundHeader = $false

            foreach ($line in $fileContent) {
                # Look for the CSV header line (WMIC includes Node,Caption,... or DeviceID)
                if ($line -match '^"?(Node|Caption|DeviceID)"?') {
                    $foundHeader = $true
                    $csvLines += $line
                }
                # After finding header, collect all lines that look like CSV data
                # WMIC format: COMPUTERNAME,C:,3,...
                elseif ($foundHeader -and ($line -match '^"?[A-Z0-9\-_]+,"?[A-Z]:"?' -or $line -match '^"?[A-Z]:"?')) {
                    $csvLines += $line
                }
            }

            if ($csvLines.Count -gt 0) {
                # Create a temporary in-memory CSV from the filtered lines
                $csvContent = $csvLines -join "`n"
                $tempCsv = Join-Path $env:TEMP "temp_disks_$(Get-Random).csv"
                $csvContent | Out-File -FilePath $tempCsv -Encoding UTF8

                $rawData = Import-Csv $tempCsv
                Remove-Item $tempCsv -ErrorAction SilentlyContinue

                # Support both WMIC format (Caption) and PowerShell format (DeviceID)
                $diskData = $rawData | Where-Object {
                    ($_.Caption -and $_.Caption.Trim() -ne '') -or
                    ($_.DeviceID -and $_.DeviceID.Trim() -ne '')
                }

                $disks = @()
                foreach ($disk in $diskData) {
                    $disks += @{
                        caption = if ($disk.Caption) { $disk.Caption.Trim() } else { $disk.DeviceID.Trim() }
                        driveType = if ($disk.DriveType) { $disk.DriveType.Trim() } else { '' }
                        fileSystem = if ($disk.FileSystem) { $disk.FileSystem.Trim() } else { '' }
                        freeSpace = if ($disk.FreeSpace) { $disk.FreeSpace.Trim() } else { '0' }
                        size = if ($disk.Size) { $disk.Size.Trim() } else { '0' }
                        volumeName = if ($disk.VolumeName) { $disk.VolumeName.Trim() } else { '' }
                    }
                }

                if ($disks.Count -gt 0) {
                    $systemData.storage.logicalDisks = $disks
                } else {
                    $systemData.storage.logicalDisks = @{ error = 'No valid disk entries found in CSV data' }
                }
            } else {
                $systemData.storage.logicalDisks = @{ error = "No valid disk data found in CSV (found $($csvLines.Count) lines)" }
            }
        } else {
            $systemData.storage.logicalDisks = @{ error = 'disks.csv not found' }
        }
    } catch {
        $systemData.storage.logicalDisks = @{ error = "Failed to parse disks.csv: $($_.Exception.Message)" }
    }

    # Mount points
    try {
        $mountFile = Join-Path $TempDir 'mountvol.txt'
        if (Test-Path $mountFile) {
            $mountContent = Get-Content $mountFile -Raw
            $systemData.storage.mountPoints = @{ content = $mountContent }
        } else {
            $systemData.storage.mountPoints = @{ error = 'mountvol.txt not found' }
        }
    } catch {
        $systemData.storage.mountPoints = @{ error = $_.Exception.Message }
    }

    Write-Host '[*] Processing hardware information...'
    # Problem devices
    try {
        $problemDevices = Get-PnpDevice | Where-Object Status -ne 'OK' | Select-Object Name,Status,Class | ForEach-Object {
            @{
                name = $_.Name
                status = $_.Status
                class = $_.Class
            }
        }
        $systemData.hardware.problemDevices = $problemDevices
    } catch {
        $systemData.hardware.problemDevices = @{ error = $_.Exception.Message }
    }

    # Driver information
    try {
        $driverFile = Join-Path $TempDir 'drivers.csv'
        if (Test-Path $driverFile) {
            # Read the file and filter out PsExec noise, keeping only CSV lines
            $fileContent = Get-Content $driverFile
            $csvLines = @()
            $foundHeader = $false

            foreach ($line in $fileContent) {
                # Look for the CSV header line
                if ($line -match '^"?Module Name"?') {
                    $foundHeader = $true
                    $csvLines += $line
                }
                # After finding header, collect all lines that look like CSV data (start with quoted text)
                elseif ($foundHeader -and $line -match '^"[^"]+","') {
                    $csvLines += $line
                }
            }

            if ($csvLines.Count -gt 0) {
                # Create a temporary in-memory CSV from the filtered lines
                $csvContent = $csvLines -join "`n"
                $tempCsv = Join-Path $env:TEMP "temp_drivers_$(Get-Random).csv"
                $csvContent | Out-File -FilePath $tempCsv -Encoding UTF8

                $driverData = Import-Csv $tempCsv | ForEach-Object {
                    @{
                        moduleName = $_.'Module Name'
                        displayName = $_.'Display Name'
                        driverType = $_.'Driver Type'
                        startMode = $_.'Start Mode'
                        state = $_.'State'
                        status = $_.'Status'
                        acceptStop = $_.'Accept Stop'
                        acceptPause = $_.'Accept Pause'
                        memoryUsage = $_.'Paged Pool(bytes)'
                        path = $_.'Path'
                    }
                }
                Remove-Item $tempCsv -ErrorAction SilentlyContinue
                $systemData.hardware.drivers = @{ list = $driverData }
            } else {
                $systemData.hardware.drivers = @{ error = 'No valid driver data found in CSV' }
            }
        } else {
            $systemData.hardware.drivers = @{ error = 'drivers.csv not found' }
        }
    } catch {
        $systemData.hardware.drivers = @{ error = $_.Exception.Message }
    }

    Write-Host '[*] Processing software information...'
    # Parse hotfixes
    try {
        $hotfixFile = Join-Path $TempDir 'hotfixes.csv'
        if (Test-Path $hotfixFile) {
            # Read the file and filter out PsExec noise, keeping only CSV lines
            $fileContent = Get-Content $hotfixFile
            $csvLines = @()
            $foundHeader = $false

            foreach ($line in $fileContent) {
                # Look for the CSV header line (Node or HotFixID columns)
                if ($line -match '^"?(Node|HotFixID)"?' -or $line -match 'HotFixID') {
                    $foundHeader = $true
                    $csvLines += $line
                }
                # After finding header, collect all non-empty lines
                elseif ($foundHeader -and $line.Trim() -ne '' -and $line -notmatch '^PsExec' -and $line -notmatch 'wmic exited') {
                    $csvLines += $line
                }
            }

            if ($csvLines.Count -gt 1) {
                # Create a temporary in-memory CSV from the filtered lines
                $csvContent = $csvLines -join "`n"
                $tempCsv = Join-Path $env:TEMP "temp_hotfixes_$(Get-Random).csv"
                $csvContent | Out-File -FilePath $tempCsv -Encoding UTF8

                $hotfixData = Import-Csv $tempCsv | Where-Object { $_.HotFixID }
                Remove-Item $tempCsv -ErrorAction SilentlyContinue

                $hotfixes = @()
                foreach ($hf in $hotfixData) {
                    $hotfixes += @{
                        hotfixId = $hf.HotFixID
                        description = $hf.Description
                        installedBy = $hf.InstalledBy
                        installedOn = $hf.InstalledOn
                    }
                }
                $systemData.software.hotfixes = $hotfixes
            } else {
                $systemData.software.hotfixes = @{ error = 'No valid hotfix data found in CSV' }
            }
        } else {
            $systemData.software.hotfixes = @{ error = 'hotfixes.csv not found' }
        }
    } catch {
        $systemData.software.hotfixes = @{ error = $_.Exception.Message }
    }

    # Parse startup programs
    try {
        $startupHKLM = @()
        $startupHKCU = @()

        $hklmFile = Join-Path $TempDir 'startup_hklm.txt'
        if (Test-Path $hklmFile) {
            $hklmContent = Get-Content $hklmFile
            foreach ($line in $hklmContent) {
                if ($line -match '^\s+(.+?)\s+REG_SZ\s+(.+)$') {
                    $startupHKLM += @{ name = $matches[1]; value = $matches[2] }
                }
            }
        }

        $hkcuFile = Join-Path $TempDir 'startup_hkcu.txt'
        if (Test-Path $hkcuFile) {
            $hkcuContent = Get-Content $hkcuFile
            foreach ($line in $hkcuContent) {
                if ($line -match '^\s+(.+?)\s+REG_SZ\s+(.+)$') {
                    $startupHKCU += @{ name = $matches[1]; value = $matches[2] }
                }
            }
        }

        $systemData.software.startupPrograms = @{
            hklm = $startupHKLM
            hkcu = $startupHKCU
        }
    } catch {
        $systemData.software.startupPrograms = @{ error = $_.Exception.Message }
    }

    # Installed apps - comprehensive collection from all registry locations
    try {
        Write-Host '    Collecting installed applications from registry...'
        $registryPaths = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        $apps = @()
        $seenNames = @{}

        foreach ($path in $registryPaths) {
            try {
                $items = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' }

                foreach ($item in $items) {
                    $appName = $item.DisplayName.Trim()
                    # Avoid duplicates (same app may appear in multiple locations)
                    if (-not $seenNames.ContainsKey($appName)) {
                        $apps += @{
                            name = $appName
                            version = $item.DisplayVersion
                            publisher = $item.Publisher
                            installDate = $item.InstallDate
                        }
                        $seenNames[$appName] = $true
                    }
                }
            } catch {
                # Continue if one registry path fails
                Write-Host "    Warning: Could not read from $path"
            }
        }

        # Sort by name for better organization
        $apps = $apps | Sort-Object { $_.name }

        Write-Host "    Found $($apps.Count) installed applications"
        $systemData.software.installedApps = $apps
    } catch {
        $systemData.software.installedApps = @{ error = $_.Exception.Message }
    }

    Write-Host '[*] Processing processes and services...'
    # Parse processes
    try {
        $processFile = Join-Path $TempDir 'processes.csv'
        if (Test-Path $processFile) {
            # Read the file and filter out PsExec noise, keeping only CSV lines
            $fileContent = Get-Content $processFile
            $csvLines = @()
            $foundHeader = $false

            foreach ($line in $fileContent) {
                # Look for the CSV header line
                if ($line -match '^"?Image Name"?' -or $line -match '"PID"') {
                    $foundHeader = $true
                    $csvLines += $line
                }
                # After finding header, collect all lines that look like CSV data (start with quoted text)
                elseif ($foundHeader -and $line -match '^"[^"]+","') {
                    $csvLines += $line
                }
            }

            if ($csvLines.Count -gt 1) {
                # Create a temporary in-memory CSV from the filtered lines
                $csvContent = $csvLines -join "`n"
                $tempCsv = Join-Path $env:TEMP "temp_processes_$(Get-Random).csv"
                $csvContent | Out-File -FilePath $tempCsv -Encoding UTF8

                $processData = Import-Csv $tempCsv | Select-Object -First 20
                Remove-Item $tempCsv -ErrorAction SilentlyContinue

                $processes = @()
                foreach ($proc in $processData) {
                    $processes += @{
                        name = $proc.'Image Name'
                        pid = $proc.PID
                        memory = $proc.'Mem Usage'
                    }
                }
                $systemData.processes.topProcesses = $processes
            } else {
                $systemData.processes.topProcesses = @{ error = 'No valid process data found in CSV' }
            }
        } else {
            $systemData.processes.topProcesses = @{ error = 'processes.csv not found' }
        }
    } catch {
        $systemData.processes.topProcesses = @{ error = $_.Exception.Message }
    }

    # Parse services
    try {
        $serviceFile = Join-Path $TempDir 'services.txt'
        if (Test-Path $serviceFile) {
            $serviceContent = Get-Content $serviceFile
            $services = @()
            $currentService = ''

            foreach ($line in $serviceContent) {
                if ($line -match 'SERVICE_NAME: (.+)') {
                    $currentService = $matches[1]
                }
                if ($line -match 'STATE\s+:\s+\d+\s+(\w+)') {
                    if ($currentService) {
                        $services += @{
                            name = $currentService
                            state = $matches[1]
                        }
                        $currentService = ''
                    }
                }
            }
            $systemData.services.allServices = $services | Select-Object -First 50
        } else {
            $systemData.services.allServices = @{ error = 'services.txt not found' }
        }
    } catch {
        $systemData.services.allServices = @{ error = $_.Exception.Message }
    }

    Write-Host '[*] Processing network information...'
    # Network adapters - with WMI fallback
    try {
        $adapterFile = Join-Path $TempDir 'getmac.csv'
        $adapters = @()
        $usedWmiFallback = $false

        if (Test-Path $adapterFile) {
            $fileContent = Get-Content $adapterFile -Raw
            # Check if file contains actual data or error message
            if ($fileContent -match 'Remote|not supported|failed' -or $fileContent.Length -lt 50) {
                $usedWmiFallback = $true
                Write-Host '    Network data file incomplete, using WMI fallback...'
            } else {
                try {
                    # Remove empty lines from CSV before importing
                    $csvContent = Get-Content $adapterFile -Encoding Unicode | Where-Object { $_.Trim() -ne '' }
                    $tempCsv = Join-Path $env:TEMP "temp_adapters_$(Get-Random).csv"
                    $csvContent | Out-File -FilePath $tempCsv -Encoding Unicode

                    $adapterData = Import-Csv $tempCsv -Encoding Unicode | Select-Object -First 10
                    Remove-Item $tempCsv -ErrorAction SilentlyContinue
                    foreach ($adapter in $adapterData) {
                        $adapters += @{
                            name = $adapter.'Connection Name'
                            transport = $adapter.'Transport Name'
                            macAddress = $adapter.'Physical Address'
                        }
                    }
                } catch {
                    $usedWmiFallback = $true
                }
            }
        } else {
            $usedWmiFallback = $true
        }

        # WMI Fallback for network adapters
        if ($usedWmiFallback -or $adapters.Count -eq 0) {
            Write-Host '    Using WMI to retrieve network adapter information...'
            try {
                $wmiAdapters = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
                foreach ($adapter in $wmiAdapters) {
                    $ipAddresses = @()
                    if ($adapter.IPAddress) { $ipAddresses = $adapter.IPAddress }

                    $adapters += @{
                        name = $adapter.Description
                        macAddress = $adapter.MACAddress
                        ipAddresses = $ipAddresses
                        dhcpEnabled = $adapter.DHCPEnabled
                        dhcpServer = $adapter.DHCPServer
                        dnsServers = $adapter.DNSServerSearchOrder
                        defaultGateway = $adapter.DefaultIPGateway
                        subnetMask = $adapter.IPSubnet
                        source = 'WMI'
                    }
                }
                $systemData.network.adapters = $adapters
            } catch {
                $systemData.network.adapters = @{ error = "Failed to retrieve network data: $($_.Exception.Message)" }
            }
        } else {
            $systemData.network.adapters = $adapters
        }
    } catch {
        $systemData.network.adapters = @{ error = $_.Exception.Message }
    }

    # WiFi profiles
    try {
        $wifiFile = Join-Path $TempDir 'wlan_profiles.txt'
        if (Test-Path $wifiFile) {
            $wifiContent = Get-Content $wifiFile
            $wifiProfiles = @()
            foreach ($line in $wifiContent) {
                if ($line -match 'All User Profile\s+:\s*(.+)') {
                    $wifiProfiles += @{ name = $matches[1].Trim() }
                }
            }
            $systemData.network.wifiProfiles = $wifiProfiles
        } else {
            $systemData.network.wifiProfiles = @{ error = 'wlan_profiles.txt not found' }
        }
    } catch {
        $systemData.network.wifiProfiles = @{ error = $_.Exception.Message }
    }

    # Enhanced Network Configuration - with WMI fallback
    try {
        # Parse ipconfig for key network info
        $ipconfigFile = Join-Path $TempDir 'ipconfig_all.txt'
        $networkInterfaces = @()
        $useWmiForIpconfig = $false

        if (Test-Path $ipconfigFile) {
            $ipconfigContent = Get-Content $ipconfigFile -Raw
            # Check if file contains actual data
            if ($ipconfigContent -match 'Remote|not supported|failed' -or $ipconfigContent.Length -lt 50) {
                $useWmiForIpconfig = $true
                Write-Host '    IP configuration file incomplete, using WMI fallback...'
            } else {
                $ipconfigLines = $ipconfigContent -split "`n"
                $currentInterface = @{}

                foreach ($line in $ipconfigLines | Select-Object -First 150) {
                    if ($line -match '^(.+) adapter (.+):$') {
                        if ($currentInterface.name) { $networkInterfaces += $currentInterface }
                        $currentInterface = @{ name = $matches[2].Trim(); type = $matches[1].Trim() }
                    }
                    elseif ($line -match '^\s+Connection-specific DNS Suffix\s*\.\s*:\s*(.+)') { $currentInterface.dnsSuffix = $matches[1].Trim() }
                    elseif ($line -match '^\s+IPv4 Address\s*\.\s*:\s*(.+)') { $currentInterface.ipv4 = $matches[1].Trim() }
                    elseif ($line -match '^\s+Subnet Mask\s*\.\s*:\s*(.+)') { $currentInterface.subnetMask = $matches[1].Trim() }
                    elseif ($line -match '^\s+Default Gateway\s*\.\s*:\s*(.+)') { $currentInterface.gateway = $matches[1].Trim() }
                    elseif ($line -match '^\s+DHCP Enabled\s*\.\s*:\s*(.+)') { $currentInterface.dhcp = $matches[1].Trim() }
                    elseif ($line -match '^\s+Physical Address\s*\.\s*:\s*(.+)') { $currentInterface.macAddress = $matches[1].Trim() }
                    elseif ($line -match '^\s+Media State\s*\.\s*:\s*(.+)') { $currentInterface.mediaState = $matches[1].Trim() }
                }
                if ($currentInterface.name) { $networkInterfaces += $currentInterface }
            }
        } else {
            $useWmiForIpconfig = $true
        }

        # WMI Fallback for IP configuration
        if ($useWmiForIpconfig -or $networkInterfaces.Count -eq 0) {
            Write-Host '    Building IP configuration from WMI network adapters...'
            # Use the adapter data we already collected
            if ($systemData.network.adapters -and $systemData.network.adapters.Count -gt 0) {
                foreach ($adapter in $systemData.network.adapters) {
                    $interface = @{
                        name = $adapter.name
                        macAddress = $adapter.macAddress
                        dhcp = if ($adapter.dhcpEnabled) { 'Yes' } else { 'No' }
                        source = 'WMI'
                    }
                    if ($adapter.ipAddresses -and $adapter.ipAddresses.Count -gt 0) {
                        $interface.ipv4 = $adapter.ipAddresses[0]
                    }
                    if ($adapter.defaultGateway -and $adapter.defaultGateway.Count -gt 0) {
                        $interface.gateway = $adapter.defaultGateway[0]
                    }
                    if ($adapter.subnetMask -and $adapter.subnetMask.Count -gt 0) {
                        $interface.subnetMask = $adapter.subnetMask[0]
                    }
                    $networkInterfaces += $interface
                }
            }
        }

        if ($networkInterfaces.Count -gt 0) {
            $systemData.network.interfaces = $networkInterfaces | Select-Object -First 10
            $systemData.network.fullDetailsFile = 'ipconfig_all.txt'
        } else {
            $systemData.network.interfaces = @{ error = 'No network interfaces found' }
        }

        # Store raw ipconfig content for display in HTML
        if (Test-Path $ipconfigFile) {
            $ipconfigRawContent = [System.IO.File]::ReadAllText($ipconfigFile)
            if ($ipconfigRawContent -and $ipconfigRawContent.Length -gt 50) {
                $systemData.network.ipconfig = @{ content = $ipconfigRawContent }
            } else {
                $systemData.network.ipconfig = @{ error = 'ipconfig_all.txt is empty or incomplete' }
            }
        } else {
            $systemData.network.ipconfig = @{ error = 'ipconfig_all.txt not found' }
        }

        # Add route information
        $routeFile = Join-Path $TempDir 'routes.txt'
        if (Test-Path $routeFile) {
            $routeLines = Get-Content $routeFile | Select-Object -First 20
            $systemData.network.routes = @{
                summary = ($routeLines -join "`n")
                fullDetailsFile = 'routes.txt'
            }
        }

        # Add ARP table
        $arpFile = Join-Path $TempDir 'arp.txt'
        if (Test-Path $arpFile) {
            $arpLines = Get-Content $arpFile | Select-Object -First 15
            $systemData.network.arpTable = @{
                entries = ($arpLines -join "`n")
                fullDetailsFile = 'arp.txt'
            }
        }

    } catch {
        $systemData.network.enhanced = @{ error = $_.Exception.Message }
    }

    Write-Host '[*] Processing power information...'
    # Enhanced Power Information
    try {
        # Get power scheme information
        $powerSchemes = @()
        try {
            $powerOutput = powercfg /list 2>$null
            foreach ($line in $powerOutput) {
                if ($line -match 'Power Scheme GUID:\s+([a-f0-9-]+)\s+\((.+)\)\s*(\*)?') {
                    $powerSchemes += @{
                        guid = $matches[1]
                        name = $matches[2].Trim()
                        active = ($matches[3] -eq '*')
                    }
                }
            }
        } catch {
            $powerSchemes = @(@{ error = 'Could not retrieve power schemes' })
        }

        # Battery information
        try {
            $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($battery) {
                $batteryInfo = @{
                    name = $battery.Name
                    status = $battery.Status
                    batteryStatus = $battery.BatteryStatus
                    estimatedChargeRemaining = $battery.EstimatedChargeRemaining
                    estimatedRunTime = $battery.EstimatedRunTime
                    chemistry = $battery.Chemistry
                }
            } else {
                $batteryInfo = @{ status = 'No battery detected (likely desktop)' }
            }
        } catch {
            $batteryInfo = @{ error = 'Could not retrieve battery information' }
        }

        # Battery health (cycle count, capacity, expected life), parsed
        # directly out of the battery report itself (powercfg /batteryreport)
        # rather than running the separate, much slower /energy scan.
        $batteryReportPath = Join-Path $TempDir 'battery_report.html'
        $batteryHealth = $null
        if (Test-Path $batteryReportPath) {
            try {
                $reportHtml = Get-Content $batteryReportPath -Raw

                $designCapacity = $null
                $fullChargeCapacity = $null
                $cycleCount = $null

                if ($reportHtml -match 'DESIGN CAPACITY</span></td><td>([\d,]+)\s*mWh') {
                    $designCapacity = [int]($matches[1] -replace ',', '')
                }
                if ($reportHtml -match 'FULL CHARGE CAPACITY</span></td><td>([\d,]+)\s*mWh') {
                    $fullChargeCapacity = [int]($matches[1] -replace ',', '')
                }
                if ($reportHtml -match 'CYCLE COUNT</span></td><td>([\d,]+)') {
                    $cycleCount = [int]($matches[1] -replace ',', '')
                }

                $activeAtFullCharge = $null
                $activeAtDesignCapacity = $null
                if ($reportHtml -match 'Since OS install\s*</td>\s*<td class="hms">([\d:]+)</td>[\s\S]*?<td class="hms">([\d:]+)</td>\s*</tr>\s*</table>') {
                    $activeAtFullCharge = $matches[1]
                    $activeAtDesignCapacity = $matches[2]
                }

                $degradationPercent = $null
                if ($designCapacity -and $fullChargeCapacity) {
                    $degradationPercent = [math]::Round((1 - ($fullChargeCapacity / $designCapacity)) * 100, 1)
                }

                $batteryHealth = @{
                    designCapacityMWh = $designCapacity
                    fullChargeCapacityMWh = $fullChargeCapacity
                    cycleCount = $cycleCount
                    capacityDegradationPercent = $degradationPercent
                    estimatedActiveLifeAtCurrentCapacity = $activeAtFullCharge
                    estimatedActiveLifeAtDesignCapacity = $activeAtDesignCapacity
                }
            } catch {
                $batteryHealth = @{ error = "Failed to parse battery report: $($_.Exception.Message)" }
            }
        } else {
            $batteryHealth = @{ status = 'not_available'; reason = 'no_battery_or_generation_failed' }
        }

        $systemData.power = @{
            powerSchemes = $powerSchemes
            battery = $batteryInfo
            reports = @{
                batteryReport = if (Test-Path $batteryReportPath) {
                    @{ status = 'generated'; file = 'battery_report.html' }
                } else {
                    @{ status = 'not_available'; reason = 'no_battery_or_generation_failed' }
                }
                energyReport = $batteryHealth
            }
        }
    } catch {
        $systemData.power = @{ error = $_.Exception.Message }
    }

    Write-Host '[*] Processing events and final data...'
    # Recent events (optimized for speed)
    Write-Host '    Processing event logs (quick scan)...'
    try {
        $systemEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddHours(-6)} -MaxEvents 5 -ErrorAction SilentlyContinue | ForEach-Object {
            @{
                time = $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                id = $_.Id
                level = $_.LevelDisplayName
                source = $_.ProviderName
                message = if ($_.Message -and $_.Message.Length -gt 80) { $_.Message.Substring(0,80) + '...' } else { $_.Message }
            }
        }
        $systemData.events.systemErrors = if ($systemEvents) { $systemEvents } else { @(@{ info = 'No critical/error events in last 6 hours' }) }
    } catch {
        $systemData.events.systemErrors = @{ error = 'Event log access limited' }
    }

    try {
        $appEvents = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=(Get-Date).AddHours(-6)} -MaxEvents 5 -ErrorAction SilentlyContinue | ForEach-Object {
            @{
                time = $_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                id = $_.Id
                level = $_.LevelDisplayName
                source = $_.ProviderName
                message = if ($_.Message -and $_.Message.Length -gt 80) { $_.Message.Substring(0,80) + '...' } else { $_.Message }
            }
        }
        $systemData.events.applicationErrors = if ($appEvents) { $appEvents } else { @(@{ info = 'No critical/error events in last 6 hours' }) }
    } catch {
        $systemData.events.applicationErrors = @{ error = 'Event log access limited' }
    }

    # Enhanced Group Policy Results
    Write-Host '    Processing Group Policy results...'
    try {
        $gpFile = Join-Path $TempDir 'gpresult.txt'
        if (Test-Path $gpFile) {
            $gpContent = Get-Content $gpFile
            $gpInfo = @{
                computerConfiguration = @()
                userConfiguration = @()
                appliedGPOs = @()
                resultantPolicies = @()
            }

            $currentSection = ''
            foreach ($line in $gpContent | Select-Object -First 200) {
                if ($line -match 'COMPUTER CONFIGURATION') { $currentSection = 'computer' }
                elseif ($line -match 'USER CONFIGURATION') { $currentSection = 'user' }
                elseif ($line -match 'Applied Group Policy Objects') { $currentSection = 'gpos' }
                elseif ($line -match '^\s+(.+)$' -and $currentSection -eq 'gpos' -and $matches[1].Trim() -ne '') {
                    $gpInfo.appliedGPOs += $matches[1].Trim()
                }
                elseif ($line -match '^\s*Domain:\s*(.+)') { $gpInfo.domain = $matches[1].Trim() }
                elseif ($line -match '^\s*Type:\s*(.+)') { $gpInfo.type = $matches[1].Trim() }
                elseif ($line -match '^\s*Revision:\s*(.+)') { $gpInfo.revision = $matches[1].Trim() }
            }

            # Get summary information
            $gpSummaryLines = $gpContent | Select-Object -First 30
            $gpInfo.summary = ($gpSummaryLines -join "`n")
            $gpInfo.fullDetailsFile = 'gpresult.txt'
            $gpInfo.appliedGPOs = $gpInfo.appliedGPOs | Select-Object -First 10

            # Store raw content for display in HTML
            $gpInfo.content = [System.IO.File]::ReadAllText($gpFile)

            $systemData.groupPolicy = $gpInfo
        } else {
            $systemData.groupPolicy = @{ error = 'gpresult.txt not found' }
        }
    } catch {
        $systemData.groupPolicy = @{ error = $_.Exception.Message }
    }

    # Scheduled tasks (optimized)
    Write-Host '    Processing scheduled tasks...'
    try {
        $tasksFile = Join-Path $TempDir 'scheduled_tasks.txt'
        if (Test-Path $tasksFile) {
            # Parse scheduled tasks into structured data (limited for performance)
            $tasksLines = Get-Content $tasksFile | Select-Object -First 100
            $taskList = @()
            $currentTask = @{}

            foreach ($line in $tasksLines) {
                if ($line -match '^TaskName:\s*(.+)') {
                    if ($currentTask.taskName) { $taskList += $currentTask }
                    $currentTask = @{ taskName = $matches[1].Trim() }
                }
                elseif ($line -match '^Next Run Time:\s*(.+)') { $currentTask.nextRunTime = $matches[1].Trim() }
                elseif ($line -match '^Status:\s*(.+)') { $currentTask.status = $matches[1].Trim() }
                elseif ($line -match '^Last Run Time:\s*(.+)') { $currentTask.lastRunTime = $matches[1].Trim() }
                elseif ($line -match '^Task to Run:\s*(.+)') { $currentTask.taskToRun = $matches[1].Trim() }
            }
            if ($currentTask.taskName) { $taskList += $currentTask }

            $systemData.scheduledTasks = @{
                list = $taskList | Select-Object -First 30
                note = 'Limited to first 30 tasks for performance. Full details in scheduled_tasks.txt'
            }
        } else {
            $systemData.scheduledTasks = @{ error = 'scheduled_tasks.txt not found' }
        }
    } catch {
        $systemData.scheduledTasks = @{ error = $_.Exception.Message }
    }

    # Additional information
    $systemData.additional = @{
        environment = @{
            numberOfProcessors = $env:NUMBER_OF_PROCESSORS
            processorArchitecture = $env:PROCESSOR_ARCHITECTURE
            processorIdentifier = $env:PROCESSOR_IDENTIFIER
            pathExt = $env:PATHEXT
            comSpec = $env:ComSpec
        }
        userProfile = @{
            userProfile = $env:USERPROFILE
            appData = $env:APPDATA
            localAppData = $env:LOCALAPPDATA
            programData = $env:PROGRAMDATA
        }
        systemPaths = @{
            systemRoot = $env:SystemRoot
            programFiles = $env:ProgramFiles
            programFilesX86 = ${env:ProgramFiles(x86)}
            winDir = $env:windir
            temp = $env:TEMP
        }
    }

    # Collection info
    $systemData.collectionInfo = @{
        method = 'comprehensive_batch_powershell'
        version = '2.1'
        description = 'Comprehensive system information for IT support with JSON-safe generation'
        tempDirectory = Split-Path $TempDir -Leaf
        additionalFiles = @(
            'systeminfo.txt',
            'drivers.csv',
            'scheduled_tasks.txt',
            'ipconfig_all.txt',
            'arp.txt',
            'routes.txt',
            'gpresult.txt',
            'battery_report.html'
        )
    }

    Write-Host '[*] Writing JSON file...'
    Write-Host '    Converting to JSON (optimized for speed)...'

    # Add performance metadata
    $systemData.metadata.performanceOptimized = $true
    $systemData.metadata.optimizationNote = 'Some large data sections truncated for performance. Full details available in individual text files.'

    try {
        $json = $systemData | ConvertTo-Json -Depth 6 -Compress

        # Fix PowerShell boolean capitalization for proper JSON compatibility
        # PowerShell outputs "True"/"False" but JSON requires lowercase "true"/"false"
        $json = $json -replace '":True', '":true' -replace '":False', '":false'

        Write-Host '    Saving to file...'
        $json | Out-File -FilePath $JsonFile -Encoding UTF8
        Write-Host '[SUCCESS] JSON file created successfully'
    } catch {
        Write-Host "[ERROR] JSON conversion failed: $($_.Exception.Message)"
        Write-Host "Attempting simplified JSON generation..."

        # Fallback: create a simpler structure
        $simpleData = @{
            metadata = $systemData.metadata
            system = @{
                note = 'Simplified output due to JSON conversion issues'
                availableFiles = 'See temp directory for detailed files'
            }
        }
        $json = $simpleData | ConvertTo-Json -Depth 3
        $json | Out-File -FilePath $JsonFile -Encoding UTF8
        Write-Host '[SUCCESS] Simplified JSON file created successfully'
    }

} catch {
    Write-Host "[FATAL ERROR] PowerShell script failed: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}