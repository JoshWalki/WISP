$json = Get-Content 'D:\GeneralSupportApp\reports\toaster_20251025_180250\comprehensive_report.json' -Raw | ConvertFrom-Json
Write-Host "=== STORAGE SECTION CHECK ==="
Write-Host "logicalDisks type:" $json.storage.logicalDisks.GetType().Name
Write-Host "logicalDisks value:"
$json.storage.logicalDisks | ConvertTo-Json
Write-Host ""
Write-Host "=== Checking if it's an error object ==="
if ($json.storage.logicalDisks.error) {
    Write-Host "ERROR FOUND:" $json.storage.logicalDisks.error
}
