# Mutations of cli/ServicesAct.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services-act.psd1
# Each takes away one safety of the supervisor's hands - on a checkout, a new revision or a process;
# test\test-services-tend.ps1 must fail for every one.
@{
    Target = "cli\ServicesAct.ps1"
    Suite  = "test\test-services-tend.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- the fetch, and what is wanted ---
        @{ Name = "fetch-brings-every-branch"
           Find = '@("fetch", "--no-tags", "--quiet", $Definition.follow.remote, ("+refs/heads/" + $Definition.follow.branch + ":" + $ref))'
           Replace = '@("fetch", "--no-tags", "--quiet", $Definition.follow.remote, "+refs/heads/*:refs/remotes/origin/*")' }
        @{ Name = "wanted-read-from-head"
           Find = '    if ($tip.ok -and $tip.out -cmatch ''\A[0-9a-f]{40}\z'') { $wanted = $tip.out } else { $wantedWhy ='
           Replace = '    if ($true) { $wanted = $head } else { $wantedWhy =' }
        @{ Name = "dirty-reads-as-clean"
           Find = 'clean = [bool]($status.out -eq "");'
           Replace = 'clean = $true;' }
        @{ Name = "branch-reads-as-detached"
           Find = 'detached = [bool](-not $branch.ok);'
           Replace = 'detached = $true;' }
        @{ Name = "diverged-reads-as-fast-forward"
           Find = '        wanted = (New-HordeKnown -Value ([pscustomobject]@{ revision = $wanted; fastForward = [bool]$forward.ok }))'
           Replace = '        wanted = (New-HordeKnown -Value ([pscustomobject]@{ revision = $wanted; fastForward = $true }))' }
        # --- the self-check ---
        @{ Name = "check-any-revision"
           Find = 'if (-not $tip.ok -or $tip.out -cne $Revision) { return (& $fail ("it is no longer what '
           Replace = 'if ($false) { return (& $fail ("it is no longer what ' }
        @{ Name = "unparsed-file-accepted"
           Find = '        if ($unparsed -ne "") { return (& $fail $unparsed) }'
           Replace = '' }
        @{ Name = "test-folders-parsed"
           Find = '        if (@($rel -split ''/'') -contains "test") { continue }'
           Replace = '' }
        @{ Name = "version-failure-accepted"
           Find = 'if ($ran.code -ne 0) { return (& $fail ("horde version failed from it with exit "'
           Replace = 'if ($false) { return (& $fail ("horde version failed from it with exit "' }
        @{ Name = "own-command-failure-accepted"
           Find = 'if ($own.code -ne 0) { return (& $fail ("horde services status failed from it with exit "'
           Replace = 'if ($false) { return (& $fail ("horde services status failed from it with exit "' }
        @{ Name = "scratch-left-behind"
           Find = '        try { if ([System.IO.Directory]::Exists($scratch)) { [System.IO.Directory]::Delete($scratch, $true) } } catch { }'
           Replace = '' }
        @{ Name = "check-writes-the-live-index"
           Find = '        $index = @{ GIT_INDEX_FILE = [System.IO.Path]::Combine($scratch, "index") }'
           Replace = '        $index = @{}' }
        # --- the move ---
        @{ Name = "move-over-local-changes"
           Find = '    if ($status.out -ne "") { return (& $fail "its checkout has local changes; they are never written over") }'
           Replace = '' }
        @{ Name = "move-a-branch"
           Find = '    if ($branch.ok) { return (& $fail ("its checkout is on the branch " + $branch.out + "; only a detached checkout is moved")) }'
           Replace = '' }
        @{ Name = "move-to-any-revision"
           Find = 'if (-not $tip.ok -or $tip.out -cne $Revision) { return (& $fail ("the remote has moved on'
           Replace = 'if ($false) { return (& $fail ("the remote has moved on' }
        @{ Name = "move-not-fast-forward"
           Find = '        if (-not $forward.ok) { return (& $fail "it is not a fast-forward of what is checked out") }'
           Replace = '' }
        @{ Name = "back-to-anywhere"
           Find = '        if (-not $behind.ok) { return (& $fail "the revision to go back to is not in the history of what is checked out") }'
           Replace = '' }
        @{ Name = "move-attaches"
           Find = '@("checkout", "--detach", "--quiet", $Revision)'
           Replace = '@("checkout", "--quiet", "-B", "moved", $Revision)' }
        # --- processes ---
        @{ Name = "kill-by-pid-alone"
           Find = 'if (-not (Test-HordeHeartbeatSameStart -One $started -Other $Process.startedAt)) { return [pscustomobject]@{ ok = $true; detail = ("process " + $Process.pid + " is another process now'
           Replace = 'if ($false) { return [pscustomobject]@{ ok = $true; detail = ("process " + $Process.pid + " is another process now' }
        @{ Name = "missing-pid-is-unknown"
           Find = '    catch [System.ArgumentException] { return (New-HordeAbsent -Note ("no process has the number " + $ProcessId)) }'
           Replace = '    catch [System.ArgumentException] { return (New-HordeUnknown -Reason ("no process has the number " + $ProcessId)) }' }
        @{ Name = "no-time-limit"
           Find = '        if (-not $p.WaitForExit([System.Math]::Max(1, $TimeoutSeconds) * 1000)) {'
           Replace = '        if (-not $p.WaitForExit(600000)) {' }
        @{ Name = "window-closed-for-another-process"
           Find = 'if ([int]$report.value.pid -ne [int]$Process.pid) { return [pscustomobject]@{ ok = $false; detail = ("its window could not be asked to close: the report file is about process "'
           Replace = 'if ($false) { return [pscustomobject]@{ ok = $false; detail = ("its window could not be asked to close: the report file is about process "' }
        @{ Name = "report-without-window-accepted"
           Find = '-or ($handle -isnot [int] -and $handle -isnot [long]) -or $handle -le 0) { return (New-HordeUnknown -Reason "its report file names no process and window") }'
           Replace = ') { return (New-HordeUnknown -Reason "its report file names no process and window") }' }
        @{ Name = "command-failure-is-ok"
           Find = '    if ($r.code -ne 0) { return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("horde " + ($Words -join " ") + " failed with exit "'
           Replace = '    if ($false) { return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("horde " + ($Words -join " ") + " failed with exit "' }
        @{ Name = "command-loses-its-home"
           Find = '-WorkingDirectory $Checkout -Environment @{ HORDE_HOME = $HordeHome } -TimeoutSeconds $TimeoutSeconds'
           Replace = '-WorkingDirectory $Checkout -Environment @{} -TimeoutSeconds $TimeoutSeconds' }
        @{ Name = "start-without-entry-point"
           Find = '            if (-not [System.IO.File]::Exists($entry)) { return (& $fail ("there is no horde entry point in its checkout " + $Definition.checkout)) }'
           Replace = '' }
        @{ Name = "git-may-prompt"
           Find = '    $env2 = @{ GIT_TERMINAL_PROMPT = "0"; GCM_INTERACTIVE = "never" }'
           Replace = '    $env2 = @{}'
           Expect = "survives"
           Reason = "no fixture remote asks for a credential, and a suite must not wait on a prompt to prove one would appear; the rule is in the header and in this line" }
        # --- safety review of the first build ---
        @{ Name = "callers-git-environment-inherited"
           Find = ' -TimeoutSeconds $TimeoutSeconds -DropEnvironment @("GIT_")'
           Replace = ' -TimeoutSeconds $TimeoutSeconds' }
        @{ Name = "repository-above-is-used"
           Find = '    if ($named.ToUpperInvariant() -cne $full.ToUpperInvariant()) {'
           Replace = '    if ($false) {' }
        @{ Name = "repository-check-skipped"
           Find = '    if (-not $Unchecked) {'
           Replace = '    if ($false) {' }
        @{ Name = "revision-tool-by-bare-name"
           Find = '        $script:HordeServiceGitProgram = $found'
           Replace = '        $script:HordeServiceGitProgram = "git"' }
        @{ Name = "file-in-the-way-not-asked"
           Find = 'if ([System.IO.File]::Exists($there) -or [System.IO.Directory]::Exists($there)) { return (& $fail ("it adds "'
           Replace = 'if ($false) { return (& $fail ("it adds "' }
        @{ Name = "moved-file-not-asked"
           Find = '@("diff", "--no-renames", "--name-only", "--diff-filter=A", "-z", "HEAD", $Revision)'
           Replace = '@("diff", "--name-only", "--diff-filter=A", "-z", "HEAD", $Revision)' }
        @{ Name = "cut-move-says-untouched"
           Find = '{ return (& $fail ("the checkout did not move, or not wholly (" + $moved.detail + ")") $true) }'
           Replace = '{ return (& $fail ("the checkout did not move, or not wholly (" + $moved.detail + ")")) }' }
        @{ Name = "refused-move-says-touched"
           Find = '    $fail = { param([string]$Why, [bool]$Touched = $false) return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText $Why); touched = $Touched } }'
           Replace = '    $fail = { param([string]$Why, [bool]$Touched = $false) return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText $Why); touched = $true } }' }
        @{ Name = "full-look-is-the-cheap-look"
           Find = 'spotless = [bool]($all.out -eq "") })'
           Replace = 'spotless = $true })' }
        @{ Name = "window-start-time-not-checked"
           Find = 'if ($still.state -cne "known") { return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("its window was not asked to close: "'
           Replace = 'if ($false) { return [pscustomobject]@{ ok = $false; detail = (Protect-HordeServiceText ("its window was not asked to close: "' }
        @{ Name = "exit-record-not-asked-for"
           Find = '        $exitFile = Get-HordeServiceExitPath -Name $Definition.name -HordeHome $SupervisorHome'
           Replace = '        $exitFile = ""' }
        @{ Name = "old-exit-record-left"
           Find = '        try { if ([System.IO.File]::Exists($exitFile)) { [System.IO.File]::Delete($exitFile) } } catch { }'
           Replace = '' }
        @{ Name = "exit-record-asked-of-every-service"
           Find = '    if ($null -ne $deliberate -and @($deliberate.Value).Count -gt 0) {'
           Replace = '    if ($true) {' }
        @{ Name = "kill-without-holding-the-process"
           Find = 'try { $null = $p.Handle; if ($p.HasExited)'
           Replace = 'try { if ($p.HasExited)'
           Expect = "survives"
           Reason = "what the held handle prevents is a pid passing to another process in the instant between the start-time proof and the kill; no suite can make Windows reuse a pid in that instant, so the line is held by its comment and by review" }
    )
}
