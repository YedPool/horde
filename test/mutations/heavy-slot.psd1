# Mutations of tools/HeavySlot.ps1, the local gate. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\heavy-slot.psd1
# Each breaks one rule of the gate; test\test-heavy-slot.ps1 must fail for every one of them. The wait
# for memory that never gives up is not a mutant here: it would hang the suite rather than fail a check.
@{
    Target = "tools\HeavySlot.ps1"
    Suite  = "test\test-heavy-slot.ps1"
    Mutations = @(
        @{ Name = "slot-never-released"
           Find = '    if ($held) { $mutex.ReleaseMutex() }'
           Replace = '    if ($false) { $mutex.ReleaseMutex() }' }
        @{ Name = "slot-waited-for-ever"
           Find = 'try { $script:held = $script:mutex.WaitOne($ms) }'
           Replace = 'try { $script:held = $script:mutex.WaitOne() }' }
        @{ Name = "killed-holder-run-not-waited-for"
           Find = '    if ($null -ne $orphan) {'
           Replace = '    if ($false) {' }
        @{ Name = "reused-id-taken-for-the-run"
           Find = 'try { if ($p.StartTime.ToUniversalTime().Ticks -ne $ticks) { return $null } } catch { return $null }'
           Replace = 'try { $null = $p.StartTime } catch { return $null }' }
        @{ Name = "memory-given-up-in-the-wrong-words"
           Find = '" GB of free memory (now "'
           Replace = '" GB of memory (now "' }
        @{ Name = "idle-timeout-not-coded"
           Find = 'if ($got.blocker -ceq "idle") { $script:code = 128;'
           Replace = 'if ($got.blocker -ceq "idle") { $script:code = 125;' }
        @{ Name = "job-does-not-kill-on-close"
           Find = 'l.basic.flags = KILL_ON_JOB_CLOSE;'
           Replace = 'l.basic.flags = 0;' }
        @{ Name = "job-not-ended-in-finally"
           Find = '        $null = [HordeHeavySlotJobV1]::Terminate($job.job)'
           Replace = '        $null = $true'
           Expect = "survives"
           Reason = "closing the job's last handle in finally ends every process of it anyway (kill on close), so ending the job first and waiting until none is alive is a second statement of the rule: it makes the processes gone BEFORE the slot is released rather than a moment after, which no check can time" }
        @{ Name = "unplanned-error-not-coded"
           Find = '    $script:code = 127'
           Replace = '    $script:code = 125' }
        @{ Name = "run-code-lost"
           Find = '    $script:code = [HordeHeavySlotJobV1]::ExitCode($job.process)'
           Replace = '    $script:code = 0' }
        @{ Name = "quotes-left-on-the-pieces"
           Find = '$_[0] -eq "''" -and $_[-1] -eq "''"'
           Replace = '$false' }
        @{ Name = "a-quoted-piece-passed-on"
           Find = 'if ($script:argsRefused -eq "" -and ($a.Contains(''"'') -or $a.StartsWith("''") -or $a.EndsWith("''")))'
           Replace = 'if ($false)' }
        @{ Name = "cmd-characters-passed-on"
           Find = 'if ($script:argsRefused -eq "" -and $a -match ''["&|<>^%]'')'
           Replace = 'if ($false)' }
        @{ Name = "control-characters-passed-on"
           Find = 'if ($script:argsRefused -eq "" -and $a -match ''[\x00-\x1F]'')'
           Replace = 'if ($false)' }
        @{ Name = "missing-argsfile-called-bad-json"
           Find = '" cannot be read: " + $_.Exception.Message'
           Replace = '" is not a JSON array of strings"' }
        @{ Name = "argsfile-not-an-array-taken"
           Find = 'if ($script:argsRefused -eq "" -and -not $raw.TrimStart().StartsWith("[")) {'
           Replace = 'if ($false) {' }
        @{ Name = "argsfile-non-string-taken"
           Find = 'if (@($items | Where-Object { $_ -isnot [string] }).Count -gt 0)'
           Replace = 'if ($false)' }
        @{ Name = "missing-script-run-anyway"
           Find = 'if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $script:code = 126;'
           Replace = 'if ($false) { $script:code = 126;' }
    )
}
