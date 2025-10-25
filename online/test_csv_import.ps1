$diskFile = 'D:\GeneralSupportApp\reports\toaster_20251025_180250\details\disks.csv'

Write-Host "=== TESTING CSV IMPORT ==="
Write-Host "File exists:" (Test-Path $diskFile)
Write-Host "File size:" (Get-Item $diskFile).Length "bytes"
Write-Host ""

Write-Host "=== Trying with -Encoding Unicode ==="
try {
    $diskData = Import-Csv $diskFile -Encoding Unicode
    Write-Host "Rows imported:" $diskData.Count
    if ($diskData.Count -gt 0) {
        Write-Host "First row properties:"
        $diskData[0].PSObject.Properties | ForEach-Object { Write-Host "  -" $_.Name }
        Write-Host ""
        Write-Host "First row:"
        $diskData[0] | Format-List
    }
} catch {
    Write-Host "ERROR:" $_.Exception.Message
}

Write-Host ""
Write-Host "=== After filtering with Caption ==="
$filtered = $diskData | Where-Object { $_.Caption }
Write-Host "Filtered rows:" $filtered.Count
if ($filtered.Count -gt 0) {
    Write-Host "First filtered row:"
    $filtered[0] | Format-List
}
