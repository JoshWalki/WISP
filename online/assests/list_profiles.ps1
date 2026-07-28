param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

try {
    $profiles = Get-CimInstance Win32_UserProfile -ErrorAction Stop |
        Where-Object { -not $_.Special }

    $results = @()
    foreach ($p in $profiles) {
        $username = $null
        try {
            $username = (New-Object System.Security.Principal.SecurityIdentifier($p.SID)).
                Translate([System.Security.Principal.NTAccount]).Value
        } catch {
            $username = if ($p.LocalPath) { Split-Path $p.LocalPath -Leaf } else { $p.SID }
        }

        $sizeBytes = 0
        if ($p.LocalPath -and (Test-Path $p.LocalPath)) {
            try {
                $measured = Get-ChildItem -Path $p.LocalPath -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
                if ($measured -and $measured.Sum) {
                    $sizeBytes = [int64]$measured.Sum
                }
            } catch {
                $sizeBytes = 0
            }
        }

        $lastUse = $null
        if ($p.LastUseTime) {
            $lastUse = ([DateTime]$p.LastUseTime).ToString("o")
        }

        $folderName = if ($p.LocalPath) { Split-Path $p.LocalPath -Leaf } else { "" }

        $results += [PSCustomObject]@{
            sid         = $p.SID
            username    = $username
            path        = $p.LocalPath
            folderName  = $folderName
            sizeBytes   = $sizeBytes
            lastUseTime = $lastUse
            roaming     = [bool]$p.RoamingConfigured
            loaded      = [bool]$p.Loaded
        }
    }

    # ConvertTo-Json's well-known "won't wrap a single-element array in [ ]"
    # quirk only applies when piping into it (unwraps element-by-element) -
    # passing -InputObject explicitly, as here, already preserves array-ness
    # correctly regardless of element count, so no extra wrapping is needed
    # (an earlier version of this script added one anyway, producing an
    # incorrectly double-nested [[ ]] array).
    if ($results.Count -eq 0) {
        $json = "[]"
    } else {
        $json = ConvertTo-Json -InputObject $results -Depth 3
    }

    $json | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "[*] Wrote $($results.Count) profile(s) to $OutputPath"
} catch {
    Write-Error "Failed to list profiles: $($_.Exception.Message)"
    exit 1
}
