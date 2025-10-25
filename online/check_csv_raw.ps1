$diskFile = 'D:\GeneralSupportApp\reports\toaster_20251025_180250\details\disks.csv'

Write-Host "=== RAW CSV CONTENT (first 500 bytes) ==="
$bytes = [System.IO.File]::ReadAllBytes($diskFile) | Select-Object -First 500
$hex = ($bytes | ForEach-Object { $_.ToString("X2") }) -join " "
Write-Host "HEX:" $hex
Write-Host ""

Write-Host "=== READING WITH DIFFERENT ENCODINGS ==="
Write-Host "UTF8:"
$content = [System.IO.File]::ReadAllLines($diskFile, [System.Text.Encoding]::UTF8) | Select-Object -First 3
$content | ForEach-Object { Write-Host "  $_" }
Write-Host ""

Write-Host "Unicode (UTF-16 LE):"
$content = [System.IO.File]::ReadAllLines($diskFile, [System.Text.Encoding]::Unicode) | Select-Object -First 3
$content | ForEach-Object { Write-Host "  $_" }
Write-Host ""

Write-Host "Default:"
$content = Get-Content $diskFile | Select-Object -First 3
$content | ForEach-Object { Write-Host "  $_" }
