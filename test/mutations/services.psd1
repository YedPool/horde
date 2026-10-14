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
        @{ Name = "heartbeat-may-be-rooted-or-climb"
           Find = 'if (Test-HordeServiceText -Value $ah["heartbeat"] -Pattern $script:HordeServiceRelativePattern) {'
           Replace = 'if (Test-HordeServiceText -Value $ah["heartbeat"]) {' }
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
           Find = '    if ($since -lt $Definition.confirmSeconds) { return (& $result "starting" ("its process "'
           Replace = '    if ($false) { return (& $result "starting" ("its process "' }
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
           Find = 'if ($s.proving) { $s.failures = [int]$s.failures + 1; $s.nextStartAt = $at.AddSeconds((Get-HordeServiceBackoffSeconds -Failures $s.failures -Policy $Policy)) }'
           Replace = '' }
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
           Find = 'if ([int]$State.failures -lt [int]$Policy.failuresBeforeEscalation) { return $null }'
           Replace = 'if ($true) { return $null }' }
        @{ Name = "escalates-at-the-first-failure"
           Find = 'if ([int]$State.failures -lt [int]$Policy.failuresBeforeEscalation) { return $null }'
           Replace = 'if ([int]$State.failures -lt 1) { return $null }' }
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
           Find = 'return (& $finish "start" "stop" "hung"'
           Replace = 'return (& $finish "wait" "" "hung"' }
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
           Find = '        $again = $s.refused.at.AddMinutes((Get-HordeServiceRefusedWaitMinutes -Count (Get-HordeServiceRefusedCount -Refused $s.refused) -Policy $Policy))'
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
           Find = '[void]$troubles.Add((New-HordeServiceTrouble -Key ("rolled-back:" + $s.target) -Text ("revision " + (ConvertTo-HordeServiceShortRevision $s.target) + " did not prove itself after its restart (" + $rollback'
           Replace = '[void]@((New-HordeServiceTrouble -Key ("rolled-back:" + $s.target) -Text ("revision " + (ConvertTo-HordeServiceShortRevision $s.target) + " did not prove itself after its restart (" + $rollback' }
        @{ Name = "bad-revision-not-pinned"
           Find = '            $s.pinnedRevision = $s.target; $s.verifiedRevision = ""'
           Replace = '            $s.verifiedRevision = ""' }
        @{ Name = "failed-check-not-recorded"
           Find = '            else { $s.verifiedRevision = ""; $s.refused = [pscustomobject]@{ revision = $Decision.revision; kind = "verify"; reason = $detail; at = $at; count = (& $times $Decision.revision "verify") } }'
           Replace = '            else { $s.verifiedRevision = $Decision.revision }' }
        @{ Name = "failed-start-not-counted"
           Find = '                $s.failures = [int]$s.failures + 1'
           Replace = '' }
        @{ Name = "new-revision-start-failure-not-rolled-back"
           Find = '                $s.intent = "rollback"; $s.phase = "stopping"; $s.phaseSince = $at; $s.started = $null'
           Replace = '                $s.phase = "steady"; $s.intent = ""; $s.started = $null' }
        @{ Name = "update-not-confirmed-before-steady"
           Find = 'if ($s.phase -ceq "launching" -and $s.intent -ceq "update") { $s.phase = "confirming"; $s.phaseSince = $at; $s.confirmBy = $at.AddSeconds($Definition.confirmSeconds) }'
           Replace = 'if ($s.phase -ceq "launching" -and $s.intent -ceq "update") { $s.phase = "steady"; $s.intent = ""; $s.runningRevision = $s.target }' }
        @{ Name = "decision-changes-its-input"
           Find = '    $s = Copy-HordeServiceState -State $State'
           Replace = '    $s = $State' }
        @{ Name = "notices-unbounded"
           Find = 'what = (Get-HordeServiceNoticeWhat -Notice $Decision) }) | Select-Object -Last $script:HordeServiceNoticesMost)'
           Replace = 'what = (Get-HordeServiceNoticeWhat -Notice $Decision) }))' }
        @{ Name = "fetch-every-pass"
           Find = '    return [bool]($since -ge $IntervalSeconds -or $since -lt 0)'
           Replace = '    return $true' }
        @{ Name = "future-fetch-waits"
           Find = '    return [bool]($since -ge $IntervalSeconds -or $since -lt 0)'
           Replace = '    return [bool]($since -ge $IntervalSeconds)' }
        # --- safety review of the first build ---
        # 1. a checkout left part way through a move is never started from
        @{ Name = "half-moved-checkout-started"
           Find = '            if ($broken -ne "") {'
           Replace = '            if ($false) {' }
        @{ Name = "move-not-marked"
           Find = 'if ($Step -ceq "advance" -or $Step -ceq "retreat") { $freshMove = [bool]($null -eq $s.moving); $s.moving ='
           Replace = 'if ($false) { $freshMove = [bool]($null -eq $s.moving); $s.moving =' }
        @{ Name = "any-revision-is-whole"
           Find = 'if (@(("" + $s.moving.from), ("" + $s.moving.target)) -cnotcontains ("" + $seen.head)) {'
           Replace = 'if ($false) {' }
        @{ Name = "unasked-is-spotless"
           Find = 'if ($null -eq $whole -or $whole.Value -ne $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "unread-checkout-is-whole"
           Find = 'if ($Observed.checkout.state -cne "known") { return ("its checkout could not be read after a move'
           Replace = 'if ($false) { return ("its checkout could not be read after a move' }
        @{ Name = "unsaid-is-untouched"
           Find = 'return [bool]($null -ne $said -and $said.Value -is [bool] -and $said.Value -eq $false -and $null -ne $fresh -and $fresh.Value -eq $true) }'
           Replace = 'return $true }' }
        @{ Name = "later-refusal-clears-an-earlier-mark"
           Find = 'return [bool]($null -ne $said -and $said.Value -is [bool] -and $said.Value -eq $false -and $null -ne $fresh -and $fresh.Value -eq $true) }'
           Replace = 'return [bool]($null -ne $said -and $said.Value -is [bool] -and $said.Value -eq $false) }' }
        @{ Name = "mark-kept-after-a-proven-start"
           Find = '                $s.moving = $null; $s.launchingAt = $at'
           Replace = '                $s.launchingAt = $at' }
        # 2. two services that follow a revision may not share a checkout
        @{ Name = "shared-checkout-allowed"
           Find = '        if ($owners.ContainsKey($key)) {'
           Replace = '        if ($false) {' }
        @{ Name = "shared-checkout-compared-as-written"
           Find = 'try { $key = [System.IO.Path]::GetFullPath($def.checkout).TrimEnd(''\'', ''/'').ToUpperInvariant() }'
           Replace = 'try { $key = $def.checkout }' }
        @{ Name = "non-following-service-counted"
           Find = '        if ($null -eq $def.follow -or $def.checkout -eq "") { continue }'
           Replace = '        if ($def.checkout -eq "") { continue }' }
        # 3. a machine that slept does not read as hung services
        @{ Name = "gap-ignored"
           Find = '    if ($SupervisorGapSeconds -gt 0) {'
           Replace = '    if ($false) {' }
        @{ Name = "allowance-for-one-pass-only"
           Find = 'elseif ($live.alive -ceq "hung") { $live.alive = "starting";'
           Replace = 'elseif ($live.alive -ceq "hung" -and $SupervisorGapSeconds -gt 0) { $live.alive = "starting";' }
        @{ Name = "allowance-for-ever"
           Find = 'if ($live.alive -ceq "yes" -or ($at - $s.resumedAt).TotalSeconds -ge (Get-HordeHeartbeatStaleSeconds -TickSeconds $tick)) { $s.resumedAt = $null }'
           Replace = 'if ($live.alive -ceq "yes") { $s.resumedAt = $null }' }
        @{ Name = "confirm-time-not-given-back"
           Find = '        if ($s.confirmBy -is [datetime]) { $s.confirmBy = $s.confirmBy.AddSeconds($SupervisorGapSeconds) }'
           Replace = '' }
        # 4. an update that will not go in backs off
        @{ Name = "refusals-do-not-back-off"
           Find = '{ $minutes = $minutes * 2 }'
           Replace = '{ }' }
        @{ Name = "refusal-wait-uncapped"
           Find = '    return [int][System.Math]::Min($minutes, 1440)'
           Replace = '    return [int]$minutes' }
        @{ Name = "refusal-not-counted"
           Find = '{ return ((Get-HordeServiceRefusedCount -Refused $s.refused) + 1) } return 1 }'
           Replace = '{ return 1 } return 1 }' }
        @{ Name = "passed-check-forgets-the-refused-move"
           Find = 'if ($ok) { $s.verifiedRevision = $Decision.revision; if ($null -ne $s.refused -and $s.refused.kind -ceq "verify") { $s.refused = $null } }'
           Replace = 'if ($ok) { $s.verifiedRevision = $Decision.revision; if ($null -ne $s.refused -and $s.refused.kind -cne "retreat") { $s.refused = $null } }' }
        # 6. a start whose outcome was never recorded is not made twice
        @{ Name = "start-not-marked-before-it-is-made"
           Find = '                $s.moving = $null; $s.launchingAt = $at'
           Replace = '                $s.moving = $null' }
        @{ Name = "unrecorded-start-made-again"
           Find = '        if ($s.launchingAt -isnot [datetime]) { return $null }'
           Replace = '        if ($true) { return $null }' }
        @{ Name = "unrecorded-start-not-waited-for"
           Find = 'if ($ago -lt $Definition.confirmSeconds) { return (& $finish "wait" "" "start-unrecorded"'
           Replace = 'if ($false) { return (& $finish "wait" "" "start-unrecorded"' }
        @{ Name = "unrecorded-start-not-told"
           Find = '[void]$troubles.Add((New-HordeServiceTrouble -Key "start-unrecorded"'
           Replace = '[void]@((New-HordeServiceTrouble -Key "start-unrecorded"' }
        @{ Name = "found-start-not-adopted"
           Find = '        if ($s.launchingAt -is [datetime] -and $null -ne $live.process) {'
           Replace = '        if ($false) {' }
        # 11 and 12. held, by a person or by its own deliberate exit
        @{ Name = "held-service-tended"
           Find = 'if ($s.held -eq $true) { return (& $finish "nothing" "" "held"'
           Replace = 'if ($false) { return (& $finish "nothing" "" "held"' }
        @{ Name = "deliberate-exit-restarted"
           Find = 'if ($codes.Count -gt 0 -and $Observed.exitCode.state -ceq "known" -and $codes -contains [int]$Observed.exitCode.value) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-exit-read-as-deliberate"
           Find = 'if ($codes.Count -gt 0 -and $Observed.exitCode.state -ceq "known" -and $codes -contains [int]$Observed.exitCode.value) {'
           Replace = 'if ($codes.Count -gt 0) {' }
        @{ Name = "any-exit-code-is-deliberate"
           Find = 'if ($codes.Count -gt 0 -and $Observed.exitCode.state -ceq "known" -and $codes -contains [int]$Observed.exitCode.value) {'
           Replace = 'if ($codes.Count -gt 0 -and $Observed.exitCode.state -ceq "known") {' }
        @{ Name = "deliberate-exit-not-held"
           Find = '$s.held = $true; $s.heldWhy = "it ended itself with code " + $code'
           Replace = '$s.heldWhy = "it ended itself with code " + $code' }
        @{ Name = "deliberate-exit-not-told"
           Find = '[void]$troubles.Add((New-HordeServiceTrouble -Key "ended-itself"'
           Replace = '[void]@((New-HordeServiceTrouble -Key "ended-itself"' }
        @{ Name = "exit-codes-may-be-words"
           Find = '($_ -isnot [int] -and $_ -isnot [long]) -or $_ -lt -2147483648'
           Replace = '$false -or $_ -lt -2147483648' }
        @{ Name = "exit-codes-need-not-be-a-list"
           Find = 'if ($listed -isnot [array] -or @($listed).Count -gt 16 -or'
           Replace = 'if (@($listed).Count -gt 16 -or' }
        @{ Name = "batch-file-taken-as-a-program"
           Find = 'if ($program -match ''\.(cmd|bat)\s*\z'') {'
           Replace = 'if ($false) {' }
        # 9. a notice is told by its kind
        @{ Name = "kind-not-carried"
           Find = '$what = (@($fresh | ForEach-Object { ("" + $_.key).Split(":")[0] } | Select-Object -Unique) -join ",")'
           Replace = '$what = ""' }
        @{ Name = "kind-carries-the-revision"
           Find = '$what = (@($fresh | ForEach-Object { ("" + $_.key).Split(":")[0] } | Select-Object -Unique) -join ",")'
           Replace = '$what = (@($fresh | ForEach-Object { "" + $_.key }) -join ",")' }
        @{ Name = "notice-kept-without-its-kind"
           Find = 'at = $Now.ToUniversalTime(); what = (Get-HordeServiceNoticeWhat -Notice $Decision) })'
           Replace = 'at = $Now.ToUniversalTime(); what = "" })' }
        # --- the supervisor runs whether or not anyone is signed in (2026-10-14) ---
        @{ Name = "needs-desktop-member-refused"
           Find = '"confirmSeconds", "needsDesktop") -Where $at'
           Replace = '"confirmSeconds") -Where $at' }
        @{ Name = "window-service-needs-no-desktop"
           Find = '$desktop = ($null -ne $stop -and $stop.kind -ceq "window")'
           Replace = '$desktop = $false' }
        @{ Name = "needs-desktop-not-read"
           Find = '{ if ($have["needsDesktop"] -is [bool]) { $desktop = [bool]$have["needsDesktop"] } else {'
           Replace = '{ if ($have["needsDesktop"] -is [bool]) { } else {' }
        @{ Name = "needs-desktop-any-value"
           Find = '} else { [void]$found.Add($at + ".needsDesktop must be true or false") } }'
           Replace = '} else { } }' }
        @{ Name = "nobody-needs-the-desktop"
           Find = 'if ($null -eq $needs -or $needs.Value -ne $true) { return "" }'
           Replace = 'if ($true) { return "" }' }
        @{ Name = "unlooked-desktop-is-here"
           Find = 'if ($Observed.desktop.state -ceq "known") { return "" }'
           Replace = 'if ($Observed.desktop.state -ceq "known" -or ("" + $Observed.desktop.reason) -like "nobody looked*") { return "" }' }
        @{ Name = "start-without-the-desktop"
           Find = '            } elseif ($blind -ne "") {'
           Replace = '            } elseif ($false) {' }
        @{ Name = "hung-stopped-without-the-desktop"
           Find = '        if ($blind -ne "") { return (& $finish "wait" "" "no-desktop" (& $noDesktop $blind "stopped and started again")) }'
           Replace = '' }
        @{ Name = "update-begun-without-the-desktop"
           Find = '    if ($blind -ne "") { return (& $finish "wait" "" "no-desktop" (& $noDesktop $blind ("restarted for the update to " + $short))) }'
           Replace = '' }
        @{ Name = "no-desktop-not-told"
           Find = '[void]$troubles.Add((New-HordeServiceTrouble -Key "no-desktop"'
           Replace = '$null = ((New-HordeServiceTrouble -Key "no-desktop"' }
        @{ Name = "stopped-service-waits-on-idle"
           Find = '        return (& $finish "start" "start" "start" ($live.why +'
           Replace = '        if ($Observed.idleSeconds.state -cne "known") { return (& $finish "wait" "" "idle-unknown" "waits on idle") }; return (& $finish "start" "start" "start" ($live.why +' }
        @{ Name = "idle-wait-says-nothing-of-rollout"
           Find = ', and unknown is never read as idle; horde rollout -Now takes it")'
           Replace = ', and unknown is never read as idle")' }
            # --- review of PR 249 ---
        @{ Name = "unwell-is-alive"
           Find = 'if ($own -and $verdict.value.fresh -and $null -ne $named -and "" + $named.Value -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "unwell-given-no-time"
           Find = 'if ($since -lt $Definition.confirmSeconds) { return (& $result "starting" ($says'
           Replace = 'if ($false) { return (& $result "starting" ($says' }
        @{ Name = "unwell-not-told"
           Find = '[void]$troubles.Add((New-HordeServiceTrouble -Key ("" + $live.condition)'
           Replace = '$null = ((New-HordeServiceTrouble -Key ("" + $live.condition)' }
        @{ Name = "unwell-restarted-without-back-off"
           Find = 'if ($s.proving -eq $true) { $s.failures = [int]$s.failures + 1;'
           Replace = 'if ($false) { $s.failures = [int]$s.failures + 1;' }
        @{ Name = "unwell-left-running"
           Find = 'return (& $finish "start" "stop" "unwell"'
           Replace = 'return (& $finish "wait" "" "unwell"' }
    )
}
