# Mutations of core/MetricsCollect.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\metrics-collect.psd1
# Each breaks one rule collect exists to keep; test\test-metrics-collect.ps1 must fail for every one.
@{
    Target = "core\MetricsCollect.ps1"
    Suite  = "test\test-metrics-collect.ps1"
    Mutations = @(
        @{ Name = "gate-off-is-not-off"
           Find = 'if ($gate.state -eq "absent" -or ($gate.state -eq "known" -and $gate.value.level -cne "usage")) {'
           Replace = 'if ($gate.state -eq "absent") {' }
        @{ Name = "refused-gate-collects"
           Find = 'if ($gate.state -ne "known") { $res.state = "refused";'
           Replace = 'if ($false) { $res.state = "refused";' }
        @{ Name = "home-in-engine-folder-not-checked"
           Find = 'if (-not $probe.write) {'
           Replace = 'if ($false) {' }
        @{ Name = "index-ignored"
           Find = 'if ($null -ne $old -and $old.size -eq $size -and $old.modifiedTicks -eq $mod -and $old.enabledAtTicks -eq $enabledTicks) {'
           Replace = 'if ($false) {' }
        @{ Name = "size-not-compared"
           Find = '$old.size -eq $size -and $old.modifiedTicks -eq $mod'
           Replace = '$old.modifiedTicks -eq $mod' }
        @{ Name = "time-not-compared"
           Find = '$old.size -eq $size -and $old.modifiedTicks -eq $mod'
           Replace = '$old.size -eq $size' }
        @{ Name = "provisional-never-collected-again"
           Find = 'if ($old.outcome -ne "provisional" -or -not $settled) { $res.unchanged++; continue }'
           Replace = '$res.unchanged++; continue' }
        @{ Name = "provisional-not-said"
           Find = '                provisional = (-not $settled)'
           Replace = '                provisional = $false' }
        @{ Name = "settle-ignored"
           Find = '$settled = (($Now.Ticks - $mod) -ge $settleTicks)'
           Replace = '$settled = $true' }
        @{ Name = "written-before-consent-read-anyway"
           Find = 'if ($mod -lt $enabledTicks) {'
           Replace = 'if ($false) {' }
        @{ Name = "grown-before-consent-read-again"
           Find = 'if ($null -ne $old -and $old.outcome -eq "beforeConsent" -and'
           Replace = 'if ($false -and $null -ne $old -and $old.outcome -eq "beforeConsent" -and' }
        @{ Name = "deleted-kept-in-index"
           Find = 'if (-not $present.Contains($k)) {'
           Replace = 'if ($false) {' }
        @{ Name = "same-name-overwrites"
           Find = '            return ($name + "." + $hash)'
           Replace = '            return $name' }
        @{ Name = "index-written-every-run"
           Find = 'if ($dirty) { Write-HordeCollectIndex'
           Replace = 'if ($true) { Write-HordeCollectIndex' }
        @{ Name = "lock-ignored"
           Find = 'catch { $res.state = "busy";'
           Replace = 'catch { $lock = New-Object System.IO.MemoryStream }; if ($false) { $res.state = "busy";' }
    )
}
