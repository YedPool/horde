# Mutations of core/MetricsCollect.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\metrics-collect.psd1
# Each breaks one rule collect exists to keep; test\test-metrics-collect.ps1 must fail for every one.
# SECTIONS (tools\Mutate.ps1; issue #82). test\test-metrics-collect.ps1's parts share one fake home and
# run in order, so a map names every part, less "giant": most of a run's time, and it removes all it
# makes. The mutants first caught in "giant" stay unmapped and run the whole suite. Each map is from a
# whole-suite run of this spec on the always-on box (bd6cdb5, 2026-10-07).
@{
    Target = "core\MetricsCollect.ps1"
    Suite  = "test\test-metrics-collect.ps1"
    # Stop at the first failed check: a caught mutant needs nothing more.
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "gate-off-is-not-off"
           Find = 'if ($gate.state -eq "absent" -or ($gate.state -eq "known" -and $gate.value.level -cne "usage")) {'
           Replace = 'if ($gate.state -eq "absent") {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "refused-gate-read-as-off"
           Find = 'if ($gate.state -ne "known") { $res.state = "refused"; $res.reason = ("the gate is refused'
           Replace = 'if ($gate.state -ne "known") { $res.state = "off"; $res.reason = ("the gate is refused'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "home-in-engine-folder-not-checked"
           Find = 'if (-not $probe.write) {'
           Replace = 'if ($false) {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "index-ignored"
           Find = 'if ($null -ne $old -and $old.size -eq $size -and $old.modifiedTicks -eq $mod -and $old.enabledAtTicks -eq $enabledTicks) {'
           Replace = 'if ($false) {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "size-not-compared"
           Find = '$old.size -eq $size -and $old.modifiedTicks -eq $mod -and $old.enabledAtTicks -eq $enabledTicks'
           Replace = '$old.modifiedTicks -eq $mod -and $old.enabledAtTicks -eq $enabledTicks'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "time-not-compared"
           Find = '$old.size -eq $size -and $old.modifiedTicks -eq $mod -and $old.enabledAtTicks -eq $enabledTicks'
           Replace = '$old.size -eq $size -and $old.enabledAtTicks -eq $enabledTicks'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "provisional-never-collected-again"
           Find = 'if (($old.outcome -ne "provisional" -or -not $settled) -and $old.outcome -ne "deferred" -and -not ($IncludeLarge -and $old.outcome -eq "tooLarge")) { $res.unchanged++; continue }'
           Replace = 'if ($old.outcome -ne "deferred") { $res.unchanged++; continue }'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "deferred-never-tried-again"
           Find = 'if (($old.outcome -ne "provisional" -or -not $settled) -and $old.outcome -ne "deferred" -and -not ($IncludeLarge -and $old.outcome -eq "tooLarge")) { $res.unchanged++; continue }'
           Replace = 'if ($old.outcome -ne "provisional" -or -not $settled) { $res.unchanged++; continue }' }
        @{ Name = "include-large-skips-unchanged"
           Find = 'if (($old.outcome -ne "provisional" -or -not $settled) -and $old.outcome -ne "deferred" -and -not ($IncludeLarge -and $old.outcome -eq "tooLarge")) { $res.unchanged++; continue }'
           Replace = 'if (($old.outcome -ne "provisional" -or -not $settled) -and $old.outcome -ne "deferred") { $res.unchanged++; continue }' }
        @{ Name = "no-deadline-inside-a-file"
           Find = '                if (-not $IncludeLarge) { Set-HordeReadDeadline -At ([datetime]::UtcNow.AddSeconds([Math]::Max(0, $MaxSeconds - $started.Elapsed.TotalSeconds))) }'
           Replace = '' }
        @{ Name = "deferred-read-first"
           Find = '        $all = @(@($all | Where-Object { $null -eq $entries[$_.key] -or $entries[$_.key].outcome -ne "deferred" }) + @($all | Where-Object { $null -ne $entries[$_.key] -and $entries[$_.key].outcome -eq "deferred" }))'
           Replace = '' }
        @{ Name = "never-too-large"
           Find = 'if ($entry.deferrals -ge $script:HordeCollectMaxDeferrals) {'
           Replace = 'if ($false) {' }
        @{ Name = "too-large-read-again"
           Find = 'if ($null -ne $old -and $old.outcome -eq "tooLarge" -and $old.size -eq $size -and $old.modifiedTicks -eq $mod -and -not $IncludeLarge) { $res.tooLarge++; continue }'
           Replace = '' }
        @{ Name = "too-large-forever"
           Find = 'if ($null -ne $old -and $old.outcome -eq "tooLarge" -and $old.size -eq $size -and $old.modifiedTicks -eq $mod -and -not $IncludeLarge) { $res.tooLarge++; continue }'
           Replace = 'if ($null -ne $old -and $old.outcome -eq "tooLarge" -and -not $IncludeLarge) { $res.tooLarge++; continue }' }
        @{ Name = "older-temps-left"
           Find = 'foreach ($tmp in $temps) { if ($tmp.LastWriteTimeUtc -lt $at) { Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue } }'
           Replace = 'foreach ($tmp in $temps) { if ($tmp.LastWriteTimeUtc -lt $at) { $null = $tmp } }'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "newer-temps-removed"
           Find = 'foreach ($tmp in $temps) { if ($tmp.LastWriteTimeUtc -lt $at) {'
           Replace = 'foreach ($tmp in $temps) { if ($true) {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "recovery-warning-forever"
           Find = '        if ($res.wroteIndex -and $res.recovered -eq "") { Remove-Item -LiteralPath (Join-Path $dir "collect-recovered.json")'
           Replace = '        if ($false) { Remove-Item -LiteralPath (Join-Path $dir "collect-recovered.json")'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "recovery-skipped"
           Find = '        if (-not (Test-HordeMetricsFileValid -Path $target -Name $name)) {'
           Replace = '        if ($false) {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "invalid-temp-adopted"
           Find = '                if (Test-HordeMetricsFileValid -Path $tmp.FullName -Name $name) {'
           Replace = '                if ($true) {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "provisional-not-said"
           Find = '                    provisional = (-not $final)'
           Replace = '                    provisional = $false'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "settle-ignored"
           Find = '$settled = (($Now.Ticks - $mod) -ge $settleTicks)'
           Replace = '$settled = $true'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "change-while-read-ignored"
           Find = '$changedWhileRead = ($null -eq $after -or $after.Length -ne $size -or $after.LastWriteTimeUtc.Ticks -ne $mod)'
           Replace = '$changedWhileRead = $false'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "written-before-consent-read-anyway"
           Find = 'if ($mod -lt $enabledTicks -and ($null -eq $old -or $old.record -eq "")) {'
           Replace = 'if ($false) {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "recorded-file-dropped-as-pre-consent"
           Find = 'if ($mod -lt $enabledTicks -and ($null -eq $old -or $old.record -eq "")) {'
           Replace = 'if ($mod -lt $enabledTicks) {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "grown-before-consent-read-again"
           Find = 'if ($null -ne $old -and $old.outcome -eq "beforeConsent" -and'
           Replace = 'if ($false -and $null -ne $old -and $old.outcome -eq "beforeConsent" -and'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "pre-consent-path-kept"
           Find = '                        $entries[$hashKey] = $entry; $dirty = $true; continue'
           Replace = '                        $entries[$plainKey] = $entry; $dirty = $true; continue'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "bad-name-aborts-the-run"
           Find = '                if (-not (Test-HordeMetricsRecordName $name)) {'
           Replace = '                if ($false) {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "write-failure-aborts-the-run"
           Find = '$entry.outcome = "failed"; $entry.reason = ("collecting it failed: "'
           Replace = 'throw; $entry.outcome = "failed"; $entry.reason = ("collecting it failed: "'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "record-named-by-file"
           Find = '                $name = $mv.read.recordKey'
           Replace = '                $name = [System.IO.Path]::GetFileNameWithoutExtension($path) + "-" + $plainKey.Length'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "deleted-kept-in-index"
           Find = '            if ($present.Contains($k)) { continue }'
           Replace = '            continue'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "gone-provisional-not-flagged"
           Find = '                try { Set-HordeRecordSourceGone -Record $gone.record } catch { $res.failed++ }'
           Replace = ''
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "index-written-every-run"
           Find = '        if ($dirty) { Write-HordeCollectIndex -Entries $entries; $res.wroteIndex = $true }'
           Replace = '        if ($true) { Write-HordeCollectIndex -Entries $entries; $res.wroteIndex = $true }'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "committed-only-at-the-end"
           Find = '            if ($dirty) { Write-HordeCollectIndex -Entries $entries; $res.wroteIndex = $true; $dirty = $false }'
           Replace = ''
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "budget-ignored"
           Find = 'if (($MaxFiles -gt 0 -and $res.read -ge $MaxFiles) -or ($started.Elapsed.TotalSeconds -ge $MaxSeconds)) {'
           Replace = 'if ($false) {'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "unreached-files-forgotten"
           Find = '        foreach ($item in $all) { [void]$present.Add($item.key);'
           Replace = '        foreach ($item in @()) { [void]$present.Add($item.key);'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "project-folder-kept"
           Find = '                if ($cut -ge 0) { $shown ='
           Replace = '                if ($false) { $shown ='
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "lock-ignored"
           Find = '        if ($inner -is [System.IO.IOException] -and $inner.HResult -eq $script:HordeSharingViolation) { $res.state = "busy";'
           Replace = '        $lock = New-Object System.IO.MemoryStream; if ($false) { $res.state = "busy";'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
        @{ Name = "broken-lock-is-busy"
           Find = '$inner -is [System.IO.IOException] -and $inner.HResult -eq $script:HordeSharingViolation'
           Replace = '$true'
           Sections = @("gate", "consent", "changes", "provisional", "lock", "bad-files", "backlog", "recovery", "command") }
    )
}
