# Mutations of core/Services.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services.psd1
# Each breaks one rule of how a service is read or decided; test\test-services.ps1 must fail for every one.
@{
    Target = "core\Services.ps1"
    Suite  = "test\test-services.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- the definition is read strictly ---
        @{ Name = "unknown-member-allowed"
           Find = 'if ($Allowed -cnotcontains $k) { [void]$Findings.Add($Where + " has the member '
           Replace = 'if ($false) { [void]$Findings.Add($Where + " has the member ' }
        @{ Name = "secret-allowed"
           Find = 'if ($kind -ne "") { [void]$Findings.Add($Where + " holds what looks like " + $kind'
           Replace = 'if ($false) { [void]$Findings.Add($Where + " holds what looks like " + $kind' }
        @{ Name = "secret-in-list-allowed"
           Find = 'if ($Value -is [array]) { $i = 0; foreach ($item in $Value) { Find-HordeServiceSecret -Value $item'
           Replace = 'if ($Value -is [array]) { return; $i = 0; foreach ($item in $Value) { Find-HordeServiceSecret -Value $item' }
        @{ Name = "dash-word-allowed"
           Find = '$script:HordeServiceWordPattern = ''\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'''
           Replace = '$script:HordeServiceWordPattern = ''\A[A-Za-z0-9-][A-Za-z0-9._-]{0,63}\z''' }
        @{ Name = "dash-value-allowed"
           Find = ' -or $script:HordeServiceDashes -contains ([string]$v)[0]) {'
           Replace = ') {' }
        @{ Name = "relative-checkout-allowed"
           Find = 'if ((Test-HordeServiceText -Value $have["checkout"]) -and (Test-HordeModuleSettingFolder -Path $have["checkout"])) {'
           Replace = 'if (Test-HordeServiceText -Value $have["checkout"]) {' }
        @{ Name = "heartbeat-may-climb"
           Find = ' -and ("" + $ah["heartbeat"]) -notmatch ''(\A|[\\/])\.\.?([\\/]|\z)'') { $relative = [string]$ah["heartbeat"] }'
           Replace = ') { $relative = [string]$ah["heartbeat"] }' }
        @{ Name = "heartbeat-may-be-rooted"
           Find = 'if ((Test-HordeServiceText -Value $ah["heartbeat"] -Pattern $script:HordeServiceRelativePattern) -and'
           Replace = 'if ((Test-HordeServiceText -Value $ah["heartbeat"]) -and' }
        @{ Name = "branch-unchecked"
           Find = 'if ((Test-HordeServiceText -Value $b -Pattern $script:HordeServiceBranchPattern) -and $b -notmatch ''\.\.'' -and'
           Replace = 'if ((Test-HordeServiceText -Value $b -Pattern $script:HordeServiceBranchPattern) -and'  }
        @{ Name = "remote-unchecked"
           Find = 'if (Test-HordeServiceText -Value $fh["remote"] -Pattern $script:HordeServiceRemotePattern) { $remote = [string]$fh["remote"] }'
           Replace = 'if (Test-HordeServiceText -Value $fh["remote"]) { $remote = [string]$fh["remote"] }' }
        @{ Name = "refused-hands-back-services"
           Find = '    $refuse = { param($Problems) return (& $answer "refused" @() @('
           Replace = '    $refuse = { param($Problems) return (& $answer "refused" @($services.ToArray()) @(' }
        @{ Name = "one-bad-service-skipped"
           Find = '    if ($problems.Count -gt 0) { return (& $refuse @($problems.ToArray())) }'
           Replace = '' }
        @{ Name = "too-many-allowed"
           Find = 'if ($given.Count -gt $script:HordeServiceMost) {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-file-is-no-services"
           Find = 'if ($trouble -ne "") { return [pscustomobject]@{ state = "refused"; services = @(); findings = [string[]]@("the service definitions file'
           Replace = 'if ($trouble -ne "") { return [pscustomobject]@{ state = "none"; services = @(); findings = [string[]]@("the service definitions file' }
        @{ Name = "restart-defaults-to-any"
           Find = '            $restart = "idle"'
           Replace = '            $restart = "any"' }
        # --- a pid alone is never the service ---
        @{ Name = "reused-pid-is-the-service"
           Find = 'if (-not (Test-HordeHeartbeatSameStart -One $Entry.value.startedAt -Other $Claim.startedAt)) { return (New-HordeAbsent'
           Replace = 'if ($false) { return (New-HordeAbsent' }
        @{ Name = "claim-without-start-trusted"
           Find = 'if ($Claim.startedAt -isnot [datetime]) { return (New-HordeUnknown -Reason ("process " + $Claim.pid + " is named without the time it started'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("process " + $Claim.pid + " is named without the time it started' }
        @{ Name = "unreadable-table-is-gone"
           Find = '    if ($Entry.state -ceq "unknown") { return $Entry }'
           Replace = '    if ($Entry.state -ceq "unknown") { return (New-HordeAbsent -Note "gone") }' }
        # --- liveness ---
        @{ Name = "foreign-heartbeat-counts"
           Find = '    if ($own -and $verdict.value.fresh) { return (& $result "yes"'
           Replace = '    if ($verdict.state -ceq "known" -and $verdict.value.fresh) { return (& $result "yes"' }
        @{ Name = "heartbeat-pid-alone-counts"
           Find = '[int]$beat.value.pid -eq [int]$process.pid -and (Test-HordeHeartbeatSameStart -One $beat.value.startedAt -Other $process.startedAt))'
           Replace = '[int]$beat.value.pid -eq [int]$process.pid)' }
        @{ Name = "unknown-process-is-not-running"
           Find = 'if ($Observed.started.state -ceq "unknown") { return (& $result "unknown" ("its process could not be checked: "'
           Replace = 'if ($false) { return (& $result "unknown" ("its process could not be checked: "' }
        @{ Name = "unreadable-heartbeat-ignored"
           Find = 'if ($beat.state -ceq "unknown") { return (& $result "unknown" ("its heartbeat could not be read: "'
           Replace = 'if ($false) { return (& $result "unknown" ("its heartbeat could not be read: "' }
        @{ Name = "young-process-is-hung"
           Find = '    if ($since -lt $Definition.confirmSeconds) { return (& $result "starting"'
           Replace = '    if ($false) { return (& $result "starting"' }
        @{ Name = "no-adoption"
           Find = 'if ($Observed.beater.state -ceq "known") { $process = $Observed.beater.value }'
           Replace = '' }
        # --- the decision ---
        @{ Name = "disabled-still-tended"
           Find = 'if (-not $Definition.enabled) { return (& $finish "nothing" "" "disabled"'
           Replace = 'if ($false) { return (& $finish "nothing" "" "disabled"' }
        @{ Name = "unknown-liveness-starts"
           Find = '        return (& $finish "wait" "" "cannot-tell" ("nothing is done: " + $live.why))'
           Replace = '        return (& $finish "start" "start" "start" ("nothing is done: " + $live.why))' }
        @{ Name = "no-backoff"
           Find = 'if ($s.nextStartAt -is [datetime] -and $at -lt $s.nextStartAt) {'
           Replace = 'if ($false) {' }
        @{ Name = "young-death-not-counted"
           Find = '        if ($s.proving) { $s.failures = [int]$s.failures + 1; $s.nextStartAt = $at.AddSeconds((Get-HordeServiceBackoffSeconds -Failures $s.failures -Policy $Policy)) }
        $s.started = $null; $s.proving = $false'
           Replace = '        $s.started = $null; $s.proving = $false' }
        @{ Name = "backoff-does-not-double"
           Find = '{ $wait = $wait * 2 }'
           Replace = '{ $wait = $wait }' }
        @{ Name = "backoff-uncapped"
           Find = '    return [int][System.Math]::Min($wait, [double]$Policy.startBackoffMaxSeconds)'
           Replace = '    return [int]$wait' }
        @{ Name = "failures-forgotten-at-once"
           Find = 'if ($s.proving -and ($null -eq $s.started -or ($at - $s.started.at).TotalSeconds -ge $Policy.stableSeconds)) {'
           Replace = 'if ($s.proving) {' }
        @{ Name = "never-escalates-failing"
           Find = '    if ($s.failures -ge $Policy.failuresBeforeEscalation) { [void]$troubles.Add((New-HordeServiceTrouble -Key "failing" -Text ("it has not stayed up after " + $s.failures + " starts in a row; it is still tried, slowly"))) }

    if ($live.alive -ceq "starting")'
           Replace = '    if ($live.alive -ceq "starting")' }
        @{ Name = "escalates-every-pass"
           Find = '$fresh = @($troubles | Where-Object { @($s.told) -cnotcontains $_.key })'
           Replace = '$fresh = @($troubles)' }
        @{ Name = "recovery-never-said"
           Find = '} elseif ($troubles.Count -eq 0 -and @($s.told).Count -gt 0 -and $Healthy) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "recovery-claimed-before-stable"
           Find = '    $stable = (-not $s.proving)'
           Replace = '    $stable = $true' }
        @{ Name = "hung-left-alone"
           Find = '        $s.phase = "stopping"; $s.intent = "heal"; $s.phaseSince = $at
        return (& $finish "start" "stop" "hung"'
           Replace = '        return (& $finish "wait" "" "hung"' }
        @{ Name = "stop-never-overdue"
           Find = 'if ($asked -lt $Definition.stop.waitSeconds) { return (& $finish "wait" "" "stopping"'
           Replace = 'if ($true) { return (& $finish "wait" "" "stopping"' }
        @{ Name = "stuck-not-told"
           Find = 'if ($s.stuck -ne "") { [void]$troubles.Add((New-HordeServiceTrouble -Key "stuck"'
           Replace = 'if ($false) { [void]$troubles.Add((New-HordeServiceTrouble -Key "stuck"' }
        # --- updates ---
        @{ Name = "unverified-revision-restarted"
           Find = 'if ($s.verifiedRevision -cne $wanted) { return (& $finish "restart-for-update" "verify" "verify"'
           Replace = 'if ($false) { return (& $finish "restart-for-update" "verify" "verify"' }
        @{ Name = "unknown-idle-is-idle"
           Find = 'if ($Observed.idleSeconds.state -cne "known") { return (& $finish "wait" "" "idle-unknown"'
           Replace = 'if ($false) { return (& $finish "wait" "" "idle-unknown"' }
        @{ Name = "idle-threshold-ignored"
           Find = 'if ([long]$Observed.idleSeconds.value -lt $Definition.follow.idleSeconds) { return (& $finish "wait" "" "not-idle"'
           Replace = 'if ($false) { return (& $finish "wait" "" "not-idle"' }
        @{ Name = "idle-asked-of-any"
           Find = 'if ($Definition.follow.restart -ceq "idle" -and -not $IgnoreIdle) {'
           Replace = 'if (-not $IgnoreIdle) {' }
        @{ Name = "now-not-honoured"
           Find = 'if ($Definition.follow.restart -ceq "idle" -and -not $IgnoreIdle) {'
           Replace = 'if ($Definition.follow.restart -ceq "idle") {' }
        @{ Name = "dirty-checkout-updated"
           Find = '    if (-not $Observed.checkout.value.clean) {'
           Replace = '    if ($false) {' }
        @{ Name = "diverged-checkout-updated"
           Find = '    if (-not $Observed.wanted.value.fastForward) {'
           Replace = '    if ($false) {' }
        @{ Name = "branch-checkout-updated"
           Find = '    if (-not $Observed.checkout.value.detached) {'
           Replace = '    if ($false) {' }
        @{ Name = "pinned-revision-retried"
           Find = '    if ($wanted -ceq $s.pinnedRevision) {'
           Replace = '    if ($false) {' }
        @{ Name = "refused-revision-retried-at-once"
           Find = '        if ($at -lt $again) {'
           Replace = '        if ($false) {' }
        @{ Name = "refused-revision-never-retried"
           Find = '        $again = $s.refused.at.AddMinutes($Policy.retryRefusedMinutes)'
           Replace = '        $again = $s.refused.at.AddYears(50)' }
        @{ Name = "old-heartbeat-confirms"
           Find = '            if ($null -ne $Definition.alive -or $left -le 0) {'
           Replace = '            if ($true) {' }
        @{ Name = "never-rolls-back-on-silence"
           Find = '        elseif ($left -le 0) { $rollback = "the new revision gave no fresh heartbeat within "'
           Replace = '        elseif ($false) { $rollback = "the new revision gave no fresh heartbeat within "' }
        @{ Name = "never-rolls-back-on-death"
           Find = '        if ($live.alive -ceq "no") { $rollback = "the new revision''s process ended before it proved itself" }'
           Replace = '' }
        @{ Name = "rollback-not-told"
           Find = '        $s.phase = "stopping"; $s.intent = "rollback"; $s.phaseSince = $at; $s.confirmBy = $null
        [void]$troubles.Add('
           Replace = '        $s.phase = "stopping"; $s.intent = "rollback"; $s.phaseSince = $at; $s.confirmBy = $null
        [void]@(' }
        @{ Name = "bad-revision-not-pinned"
           Find = '            $s.pinnedRevision = $s.target; $s.verifiedRevision = ""'
           Replace = '            $s.verifiedRevision = ""' }
        @{ Name = "failed-check-not-recorded"
           Find = '            else { $s.verifiedRevision = ""; $s.refused = [pscustomobject]@{ revision = $Decision.revision; kind = "verify"; reason = $detail; at = $at } }'
           Replace = '            else { $s.verifiedRevision = $Decision.revision }' }
        @{ Name = "failed-start-not-counted"
           Find = '                $s.failures = [int]$s.failures + 1
                $s.nextStartAt = $at.AddSeconds((Get-HordeServiceBackoffSeconds -Failures $s.failures -Policy $Policy))'
           Replace = '' }
        @{ Name = "new-revision-start-failure-not-rolled-back"
           Find = '                $s.intent = "rollback"; $s.phase = "stopping"; $s.phaseSince = $at; $s.started = $null'
           Replace = '                $s.phase = "steady"; $s.intent = ""; $s.started = $null' }
        @{ Name = "update-not-confirmed-before-steady"
           Find = 'if ($s.phase -ceq "launching" -and $s.intent -ceq "update") { $s.phase = "confirming"; $s.phaseSince = $at; $s.confirmBy = $at.AddSeconds($Definition.confirmSeconds) }'
           Replace = 'if ($s.phase -ceq "launching" -and $s.intent -ceq "update") { $s.phase = "steady"; $s.intent = ""; $s.runningRevision = $s.target }' }
        @{ Name = "decision-changes-its-input"
           Find = '    $s = Copy-HordeServiceState -State $State
    $live = Get-HordeServiceLiveness'
           Replace = '    $s = $State
    $live = Get-HordeServiceLiveness' }
        @{ Name = "notices-unbounded"
           Find = 'at = $Now.ToUniversalTime() }) | Select-Object -Last $script:HordeServiceNoticesMost)'
           Replace = 'at = $Now.ToUniversalTime() }))' }
        @{ Name = "fetch-every-pass"
           Find = '    return [bool]($since -ge $IntervalSeconds -or $since -lt 0)'
           Replace = '    return $true' }
        @{ Name = "future-fetch-waits"
           Find = '    return [bool]($since -ge $IntervalSeconds -or $since -lt 0)'
           Replace = '    return [bool]($since -ge $IntervalSeconds)' }
    )
}
