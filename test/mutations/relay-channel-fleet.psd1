# Mutations of the fleet channel (channels/fleet/Channel.ps1): the founder's tier, hibernate and wake requests
# in, read strictly and acted on once; the fleet snapshot out, in the contract's shape. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-fleet.psd1
# test\test-relay-channel-fleet.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\fleet\Channel.ps1"
    Suite  = "test\test-relay-channel-fleet.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-proof-is-taken"
           Find = 'if (@("webauthn", "session") -cnotcontains $proof) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-unlocked-session-is-not-taken"
           Find = 'if (@("webauthn", "session") -cnotcontains $proof) {'
           Replace = 'if (@("webauthn") -cnotcontains $proof) {' }
        @{ Name = "a-body-with-members-added-or-missing-is-taken"
           Find = 'if (($sorted -join ",") -cne ($want -join ",")) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-member-twice-is-taken"
           Find = 'if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { $fail.reason = "the request has a member more than once"; return $fail }'
           Replace = '' }
        @{ Name = "a-request-for-another-machine-is-taken"
           Find = 'elseif ($r.value.machine -cne $Context.signKeyId) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "a-tier-of-3-is-taken"
           Find = 'if ($Kind -ceq "tier" -and @(1, 2) -notcontains $a.tier) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-hibernate-of-tier-1-is-taken"
           Find = 'if ($Kind -ceq "hibernate" -and $a.tier -ne 2) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-version-that-is-no-whole-number-is-taken"
           Find = 'if (-not (Test-HordeFleetChannelWhole $a.version)) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-orc-that-is-no-id-is-taken"
           Find = 'if ($a.orc -isnot [string] -or $a.orc -cnotmatch $script:HordeFleetChannelOrcPattern) {'
           Replace = 'if ($a.orc -isnot [string]) {' }
        @{ Name = "a-hibernation-id-that-is-no-time-is-taken"
           Find = 'if ($a.hibernationId -isnot [string] -or $a.hibernationId -cnotmatch $script:HordeFleetChannelIdPattern) {'
           Replace = 'if ($a.hibernationId -isnot [string]) {' }
        @{ Name = "a-tier-for-a-stale-version-is-written"
           Find = 'if ([long]$reg.value.version -ne [long]$Request.version) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the Orc registry is at version "'
           Replace = 'if ($false) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the Orc registry is at version "' }
        @{ Name = "a-hibernate-for-a-stale-version-starts"
           Find = 'if ([long]$reg.value.version -ne [long]$Request.version) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the registry is at version "'
           Replace = 'if ($false) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason ("the registry is at version "' }
        @{ Name = "the-write-forgets-the-version-it-was-drawn-from"
           Find = '([int]$Request.tier) ([long]$Request.version)'
           Replace = '([int]$Request.tier) ([long]-1)' }
        @{ Name = "a-never-orc-gets-a-tier"
           Find = 'if ($hit.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-lost-race-is-not-retry"
           Find = 'if ($o -ceq "stale") {'
           Replace = 'if ($false) {' }
        @{ Name = "an-unchanged-tier-is-not-done"
           Find = 'if ($o -ceq "unchanged") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-hibernate-while-one-runs-starts-another"
           Find = 'if ($busy.value.hibernating) { return (New-HordeFleetChannelAnswer -Answer "retry" -Reason "a hibernation is running; ask again when it is done") }'
           Replace = '' }
        @{ Name = "a-wake-of-no-hibernation-starts"
           Find = 'if (@($recs.value.records | Where-Object { "" + $_.id -ceq $id }).Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-wake-of-a-hibernation-being-woken-starts-again"
           Find = 'if (@($busy.value.waking) -ccontains $id) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-retry-is-handed-over-again-by-the-port"
           Find = '$port = $(if ($A.transient) { "retry" }'
           Replace = '$port = $(if ($A.transient -or $A.answer -ceq "retry") { "retry" }' }
        @{ Name = "the-same-setid-is-acted-on-again"
           Find = 'if ($seen.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-retry-is-remembered-as-answered"
           Find = 'if (@("done", "refused") -ccontains $A.answer) {'
           Replace = 'if ($true) {' }
        @{ Name = "the-answer-is-not-kept-for-the-snapshot"
           Find = '$D.lastResult = $result'
           Replace = '$D.lastResult = $D.lastResult' }
        @{ Name = "the-process-started-is-forgotten"
           Find = 'if ($null -ne $A.child) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-word-that-is-not-plain-reaches-the-command-line"
           Find = 'if ($w -cnotmatch ''\A[A-Za-z0-9-]{1,32}\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "the-snapshot-is-sent-every-turn"
           Find = 'if ($hash -ceq $d.hash -and $sameKeys) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-phone-key-trusted-since-is-sent-nothing"
           Find = 'if ($hash -ceq $d.hash -and $sameKeys) {'
           Replace = 'if ($hash -ceq $d.hash) {' }
        @{ Name = "an-orc-in-never-stays-in-tiers"
           Find = 'if ($neverIds -ccontains $id) { continue }'
           Replace = '' }
        @{ Name = "a-dead-run-is-shown-as-running"
           Find = 'if ($Busy) { $runningRecord ='
           Replace = 'if ($true) { $runningRecord =' }
        @{ Name = "a-record-with-no-phase-is-a-hibernation"
           Find = 'Where-Object { @("asking", "parking", "done") -ccontains ("" + (Get-HordeFleetChannelMember $_ "phase")) }'
           Replace = 'Where-Object { $true }' }
        @{ Name = "a-hibernation-is-both-running-and-finished"
           Find = 'if ($null -ne $runningRecord -and "" + $r.id -ceq "" + $runningRecord.id) { continue }'
           Replace = '' }
        @{ Name = "more-than-ten-hibernations-are-listed"
           Find = 'if ($done.Count -ge $script:HordeFleetChannelMostHibernations) { break }'
           Replace = '' }
        @{ Name = "an-exited-session-of-a-finished-hibernation-says-exited"
           Find = '"exited" { return "asleep" }'
           Replace = '"exited" { return "exited" }' }
        @{ Name = "a-parked-session-of-a-dead-run-is-asleep"
           Find = '"parked" { return "still-awake" }'
           Replace = '"parked" { return "asleep" }' }
        @{ Name = "the-reader-checks-the-union-of-the-two-state-lists"
           Find = 'if ($x.state -isnot [string] -or $States -cnotcontains $x.state) {'
           Replace = 'if ($x.state -isnot [string] -or (@($script:HordeFleetChannelRunningStates) + @($script:HordeFleetChannelFinishedStates)) -cnotcontains $x.state) {' }
        @{ Name = "the-reader-lets-tiers-and-never-overlap"
           Find = 'if ($tierIds -ccontains $n.orc) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-reader-lets-a-hibernation-be-listed-twice-or-out-of-order"
           Find = 'if ($previous -ne "" -and [string]::CompareOrdinal($h.id, $previous) -ge 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-reader-lets-a-member-be-added"
           Find = 'if (($have -join ",") -cne ($Want -join ",")) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-snapshot-that-breaks-the-contract-is-sent"
           Find = 'if (-not $ok.ok) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-lock-held-by-a-live-owner-is-not-a-run"
           Find = 'return (-not $o.stale)'
           Replace = 'return $false' }
        @{ Name = "a-reused-pid-is-the-child"
           Find = 'return ([Math]::Abs($a - $b) -le 10000000)'
           Replace = 'return $true' }
    )
}
