$json = Get-Content 'D:\GeneralSupportApp\reports\toaster_20251025_180250\comprehensive_report.json' -Raw | ConvertFrom-Json
Write-Host "=== DISK DATA CHECK ==="
Write-Host "Disk Count:" $json.storage.logicalDisks.Count
Write-Host ""
Write-Host "First 3 disks:"
$json.storage.logicalDisks | Select-Object -First 3 | Format-List
