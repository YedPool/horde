# Mutations of core/MetricsStore.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\metrics-store.psd1
# Each breaks one rule of consent or placement; test\test-metrics-store.ps1 must fail for every one.
@{
    Target = "core\MetricsStore.ps1"
    Suite  = "test\test-metrics-store.ps1"
    Mutations = @(
        @{ Name = "no-gate-file-is-on"
           Find = 'if ($Gate.state -eq "absent") { return [pscustomobject]@{ write = $false;'
           Replace = 'if ($Gate.state -eq "absent") { return [pscustomobject]@{ write = $true;' }
        @{ Name = "unreadable-gate-is-on"
           Find = 'if ($Gate.state -eq "unknown") { return [pscustomobject]@{ write = $false;'
           Replace = 'if ($Gate.state -eq "unknown") { return [pscustomobject]@{ write = $true;' }
        @{ Name = "backfill-allowed"
           Find = 'if ($FirstEventAt.value -lt $Gate.value.enabledAt) {'
           Replace = 'if ($false) {' }
        @{ Name = "store-roots-ignored"
           Find = 'if (Test-HordePathInside -Path $dir -Root $root) {'
           Replace = 'if ($false) {' }
        @{ Name = "level-case-ignored"
           Find = 'if ($level -isnot [string] -or $script:HordeMetricsLevels -cnotcontains $level) {'
           Replace = 'if ($level -isnot [string] -or $script:HordeMetricsLevels -notcontains $level) {' }
        @{ Name = "windowed-recorded"
           Find = 'if ($Windowed) { return [pscustomobject]@{ write = $false;'
           Replace = 'if ($false) { return [pscustomobject]@{ write = $false;' }
        @{ Name = "no-enabledAt-accepted"
           Find = 'if ($level -ceq "usage" -and $null -eq $at) {'
           Replace = 'if ($false) {' }
        @{ Name = "prefix-is-inside"
           Find = '$r = [System.IO.Path]::GetFullPath($Root).TrimEnd(''\'') + ''\'''
           Replace = '$r = [System.IO.Path]::GetFullPath($Root).TrimEnd(''\'')' }
        @{ Name = "record-name-unchecked"
           Find = 'if ($Name -cnotmatch ''\A[A-Za-z0-9][A-Za-z0-9._-]{0,200}\z'' -or $Name -match ''\.\.'') {'
           Replace = 'if ($false) {' }
        @{ Name = "dates-in-powershell-form"
           Find = 'if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture) }'
           Replace = '' }
        @{ Name = "engine-without-stores-unguarded"
           Find = '        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return (New-HordeUnknown'
           Replace = '        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue; return (New-HordeUnknown' }
        @{ Name = "moved-store-unguarded"
           Find = '                if ("$v".Trim() -ne "") { [void]$out.Add("$v") }'
           Replace = '                $null = $v' }
        @{ Name = "unknown-roots-allow-writing"
           Find = '    if ($roots.state -ne "known") { return [pscustomobject]@{ write = $false;'
           Replace = '    if ($roots.state -ne "known") { $roots = New-HordeKnown -Value @(); } if ($false) { return [pscustomobject]@{ write = $false;' }
    )
}
