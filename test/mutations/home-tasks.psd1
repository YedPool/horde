# Mutations of core/HomeTasks.ps1 (T-0299, round 1): the read-only check that names the scheduled tasks under \Horde\
# whose recorded or baked home is not the effective one, and the warning when HORDE_HOME overrides the pointer.
# test\test-home-tasks.ps1 must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\home-tasks.psd1
@{
    Target = "core\HomeTasks.ps1"
    Suite  = "test\test-home-tasks.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "trailing-separator-matters"
           Find = 'return $p.TrimEnd(''\'', ''/'')'
           Replace = 'return $p' }
        @{ Name = "marker-home-not-read"
           Find = 'if ($l.StartsWith("horde-home: ") -and $l.Length -gt 12)'
           Replace = 'if ($false)' }
        @{ Name = "baked-scheduler-form-not-read"
           Find = 'foreach ($m in [regex]::Matches($text, "SetEnvironmentVariable\(''HORDE_HOME'', \(& \`$d ''([A-Za-z0-9+/=]*)''\)")) {'
           Replace = 'foreach ($m in @()) {' }
        @{ Name = "baked-plain-form-not-read"
           Find = 'foreach ($m in [regex]::Matches($text, "\`$env:HORDE_HOME = ''((?:[^'']|'''')*)''")) {'
           Replace = 'foreach ($m in @()) {' }
        @{ Name = "every-task-reported"
           Find = 'if ($r.how -ceq "baked into its action" -and (ConvertTo-HordeHomeComparable $r.home) -ine $want -and -not $seen.ContainsKey($r.how)) {'
           Replace = 'if ($r.how -ceq "baked into its action" -and $true -and -not $seen.ContainsKey($r.how)) {' }
        @{ Name = "unbaked-task-flagged-by-its-marker"
           Find = 'if ($r.how -ceq "baked into its action" -and (ConvertTo-HordeHomeComparable $r.home) -ine $want -and -not $seen.ContainsKey($r.how)) {'
           Replace = 'if ((ConvertTo-HordeHomeComparable $r.home) -ine $want -and -not $seen.ContainsKey($r.how)) {' }
        @{ Name = "stale-heartbeat-counts-as-running"
           Find = 'if ($v.state -ceq "known" -and $v.value.fresh -eq $true) {'
           Replace = 'if ($v.state -ceq "known") {' }
        @{ Name = "disabled-service-counts-as-running"
           Find = 'if ($null -eq $d -or $d.enabled -ne $true -or $null -eq $d.alive) { continue }'
           Replace = 'if ($null -eq $d -or $null -eq $d.alive) { continue }' }
        @{ Name = "running-service-allowed"
           Find = 'if ($running.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "same-home-refused"
           Find = 'if ((ConvertTo-HordeHomeComparable $old) -ieq (ConvertTo-HordeHomeComparable $NewHome)) { return }'
           Replace = '' }
        @{ Name = "refusal-gives-no-wait"
           Find = 'Stopped just now? its heartbeat clears in about " + $wait + " s, then try again. '
           Replace = '' }
        @{ Name = "clear-target-is-not-the-default"
           Find = 'return (Join-Path (Get-HordeProfileDir) ".horde")'
           Replace = 'return $set' }
        @{ Name = "guard-uses-the-process-home"
           Find = '        $old = $read.home'
           Replace = '        $old = (Resolve-HordeHome).path' }
        @{ Name = "no-task-reported"
           Find = 'if ($r.how -ceq "baked into its action" -and (ConvertTo-HordeHomeComparable $r.home) -ine $want -and -not $seen.ContainsKey($r.how)) {'
           Replace = 'if ($false) {' }
        @{ Name = "refused-query-throws"
           Find = '        return [pscustomobject]@{ lines = @("tasks: not checked (the Task Scheduler query was refused or failed: " + $why + "; try from an elevated prompt)"); checked = $false }'
           Replace = '        throw $_' }
        @{ Name = "refused-query-says-checked"
           Find = '; try from an elevated prompt)"); checked = $false }'
           Replace = '; try from an elevated prompt)"); checked = $true }' }
        @{ Name = "warning-without-a-pointer"
           Find = 'if ("$env:HORDE_HOME".Trim() -ne "" -and $null -ne $pointer -and (Test-Path -LiteralPath $pointer)) {'
           Replace = 'if ("$env:HORDE_HOME".Trim() -ne "") {' }
        @{ Name = "no-warning"
           Find = 'if ("$env:HORDE_HOME".Trim() -ne "" -and $null -ne $pointer -and (Test-Path -LiteralPath $pointer)) {'
           Replace = 'if ($false) {' }
    )
}
