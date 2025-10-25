$json = Get-Content 'D:\GeneralSupportApp\reports\toaster_20251025_180600\comprehensive_report.json' -Raw | ConvertFrom-Json

Write-Host "=== VERIFICATION OF FIX ==="
Write-Host ""
Write-Host "Disk Count:" $json.storage.logicalDisks.Count
Write-Host ""

if ($json.storage.logicalDisks.Count -gt 0) {
    Write-Host "SUCCESS! Disks are now being parsed correctly!"
    Write-Host ""
    Write-Host "Sample disk data:"
    $json.storage.logicalDisks | Select-Object -First 3 | ForEach-Object {
        Write-Host "  Drive:" $_.caption
        Write-Host "    Type:" $_.driveType
        Write-Host "    File System:" $_.fileSystem
        Write-Host "    Size:" $_.size "bytes"
        Write-Host "    Free:" $_.freeSpace "bytes"
        Write-Host "    Volume:" $_.volumeName
        Write-Host ""
    }
} else {
    Write-Host "FAILED - Still no disk data"
    Write-Host "Error:" $json.storage.logicalDisks.error
}

Write-Host ""
Write-Host "=== CHECKING OTHER CSV DATA ==="
Write-Host "Hotfixes Count:" $json.software.hotfixes.Count
Write-Host "Drivers Count:" $json.hardware.drivers.list.Count
Write-Host "Top Processes Count:" $json.processes.topProcesses.Count
