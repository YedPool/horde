# Mutations of core/Wake.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake.psd1
# Each breaks one rule the wake watcher exists for - one of the six conditions of a nudge, the back-off,
# the fleet's rate limit and its order, and shadow doing nothing; test\test-wake.ps1 must fail for every one.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "mail-handed-over-is-read-as-mail-taken"
           Find = '$a.value.unreadCount -le 0 -and (Get-HordeWakeHandedOver $a.value) -eq 0) }'
           Replace = '$a.value.unreadCount -le 0) }' }
        @{ Name = "the-attempt-is-not-recorded-before-the-waker-is-asked"
           Find = '$nextLedger = Set-HordeWakeLedgerAsked -Ledger $nextLedger -Id $d.id -Now $Now -State'
           Replace = '$null = Set-HordeWakeLedgerAsked -Ledger $nextLedger -Id $d.id -Now $Now -State' }
        @{ Name = "a-pass-that-throws-after-a-nudge-throws-the-nudge-away"
           Find = 'if ($asked.Count -eq 0) { throw }'
           Replace = 'throw' }
        @{ Name = "a-throw-before-any-nudge-is-swallowed"
           Find = 'if ($asked.Count -eq 0) { throw }'
           Replace = '' }
        @{ Name = "the-failure-after-a-nudge-is-not-journaled"
           Find = '[void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id "pass-after-nudge"'
           Replace = '$null = ((New-HordeWakeEntry -At $Now -Kind "skip-unknown" -Id "pass-after-nudge"' }
        @{ Name = "the-recorded-attempt-forgets-the-ones-before"
           Find = 'if ($null -ne $had) { $count = [int]$had.attempts + 1 }'
           Replace = '' }
        @{ Name = "the-recorded-attempt-is-held-against-another-mail"
           Find = '$had = Get-HordeWakeLedgerEntry -Ledger $next -Id $Id -State $State'
           Replace = '$had = Get-HordeWakeLedgerEntry -Ledger $next -Id $Id' }
        @{ Name = "the-recorded-free-knock-is-not-marked"
           Find = 'if ($Free) { $freeAt = $Now }'
           Replace = '' }
        @{ Name = "the-pass-does-not-say-its-nudge-was-a-free-knock"
           Find = '-Free:((Get-HordeWakeEntryValue $d "free") -eq $true)'
           Replace = '' }
        @{ Name = "the-recorded-attempt-names-no-mail"
           Find = '    $mailAt = Get-HordeWakeEntryValue $State "oldestUnreadAt"'
           Replace = '    $mailAt = $null' }
        @{ Name = "the-record-writes-into-the-table-it-was-handed"
           Find = '$next[$Id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "unknown"'
           Replace = 'if ($null -ne $Ledger) { $Ledger[$Id] = $null }; $next[$Id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "unknown"' }
        @{ Name = "a-free-knock-is-not-bounded-by-the-hour"
           Find = 'if ($free -and $FreeAt -is [datetime] -and ($Now - $FreeAt).TotalSeconds -lt [double]$Settings.freeKnockSeconds) { $free = $false }'
           Replace = '' }
        @{ Name = "when-a-free-knock-was-sent-is-not-recorded"
           Find = '-Probes 0 -FreeFor $limitNow.until -FreeAt $Now'
           Replace = '-Probes 0 -FreeFor $limitNow.until' }
        @{ Name = "the-ledger-counts-a-bounded-knock-as-free"
           Find = '-and $wasFree -eq $limitNow.until) -and -not $recent) {'
           Replace = '-and $wasFree -eq $limitNow.until)) {' }
        @{ Name = "the-decision-is-not-told-when-the-last-free-knock-was"
           Find = '-FreeAt $(if ($null -ne $Ledger -and $Ledger.ContainsKey($id)) { Get-HordeWakeEntryValue $Ledger[$id] "freeAt" } else { $null })'
           Replace = '' }
        @{ Name = "when-a-free-knock-was-sent-is-not-saved"
           Find = 'if ($freeAt -is [datetime]) { $row["freeAt"] = ConvertTo-HordeWakeTimeText $freeAt }'
           Replace = '' }
        @{ Name = "when-a-free-knock-was-sent-is-not-read-back"
           Find = 'if ($null -ne $freeAt) { $entry["freeAt"] = $freeAt }'
           Replace = '' }
        @{ Name = "when-a-free-knock-was-sent-is-lost-with-the-row"
           Find = 'if ($kept -is [datetime] -and (Get-HordeWakeEntryValue $next[$id] "freeAt") -isnot [datetime]) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-free-knock-is-owed-again-after-a-minute"
           Find = '$recent = ($freeWas -is [datetime] -and ($Now - $freeWas).TotalSeconds -lt [double]$Settings.freeKnockSeconds)'
           Replace = '$recent = ($freeWas -is [datetime] -and ($Now - $freeWas).TotalSeconds -lt 60)' }
        @{ Name = "silent-probes-are-never-capped"
           Find = 'if ($SilentProbes -ge [int]$Settings.maxSilentProbes) {'
           Replace = 'if ($false) {' }
        @{ Name = "after-the-cap-the-slow-probe-is-never-sent"
           Find = 'if ($lastSlow -is [datetime] -and ($Now - $lastSlow).TotalSeconds -lt $slow) {'
           Replace = 'if ($true) {' }
        @{ Name = "after-the-cap-the-slow-probe-does-not-wait"
           Find = 'if ($lastSlow -is [datetime] -and ($Now - $lastSlow).TotalSeconds -lt $slow) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-slow-probe-ignores-the-silences-own-time"
           Find = 'if ($SilentProbeAt -is [datetime] -and $SilentProbeAt -le $Now -and ($lastSlow -isnot [datetime] -or $SilentProbeAt -gt $lastSlow)) { $lastSlow = $SilentProbeAt }'
           Replace = '' }
        @{ Name = "the-end-of-the-stretched-probes-is-not-told"
           Find = '$condition = [pscustomobject]@{ kind = "silent-probes-ended"'
           Replace = '$null = [pscustomobject]@{ kind = "silent-probes-ended"' }
        @{ Name = "the-time-of-the-last-probe-is-not-kept"
           Find = 'if ($probedNow -gt 0) { $lastProbe = $Now }'
           Replace = '' }
        @{ Name = "silent-probes-are-not-stretched"
           Find = 'for ($i = 1; $i -lt $Probes -and $wait -lt $most; $i++) { $wait = $wait * [System.Math]::Max(1.0, [double]$Settings.silentProbeStretch) }'
           Replace = '' }
        @{ Name = "the-stretch-has-no-ceiling"
           Find = '    return [int][System.Math]::Min($wait, $most)'
           Replace = '    return [int]$wait' }
        @{ Name = "a-ceiling-below-the-first-step-shortens-the-wait"
           Find = '$most = [System.Math]::Max([double]$first, [double]$Settings.silentProbeMaxSeconds)'
           Replace = '$most = [double]$Settings.silentProbeMaxSeconds' }
        @{ Name = "a-stretch-below-one-shortens-the-wait"
           Find = '$wait = $wait * [System.Math]::Max(1.0, [double]$Settings.silentProbeStretch) }'
           Replace = '$wait = $wait * [double]$Settings.silentProbeStretch }' }
        @{ Name = "the-silences-probes-are-not-counted"
           Find = '$next.probes = $sent + $probedNow'
           Replace = '$next.probes = 0 + $probedNow' }
        @{ Name = "the-end-of-the-probes-is-said-every-pass"
           Find = 'if ($sent -lt $most -and $next.probes -ge $most) {'
           Replace = 'if ($next.probes -ge $most) {' }
        @{ Name = "the-end-of-the-probes-is-never-said"
           Find = 'if ($sent -lt $most -and $next.probes -ge $most) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-count-of-probes-is-not-saved"
           Find = 'quietSince = $since; probes = $sent; probeAt = $lastProbe }'
           Replace = 'quietSince = $since; probes = 0; probeAt = $lastProbe }' }
        @{ Name = "a-count-of-probes-that-is-none-is-read"
           Find = 'if (-not ($pp.Value -is [int] -or $pp.Value -is [long]) -or $pp.Value -lt 0 -or $pp.Value -gt 1000000) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "the-pass-is-not-told-the-count"
           Find = '$longest = Get-HordeWakeSilentProbeSeconds -Probes $SilentProbes -Settings $Settings'
           Replace = '$longest = Get-HordeWakeSilentProbeSeconds -Probes 0 -Settings $Settings' }
        @{ Name = "an-old-quiet-is-read-back-with-no-history"
           Find = 'if (-not [bool]$j.silent) { $since = $null }'
           Replace = '' }
        @{ Name = "handed-over-mail-is-not-named-in-the-decision"
           Find = 'if ($handed -gt 0) { return [pscustomobject]@{ action = "skip"; reason = ("no unread mail: " + $handed'
           Replace = 'if ($false) { return [pscustomobject]@{ action = "skip"; reason = ("no unread mail: " + $handed' }
        @{ Name = "handed-over-mail-is-not-held-by-name"
           Find = 'elseif ($a.value.unreadCount -le 0 -and (Get-HordeWakeHandedOver $a.value) -gt 0 -and'
           Replace = 'elseif ($false -and' }
        @{ Name = "handed-over-mail-is-held-beside-unread-mail"
           Find = 'elseif ($a.value.unreadCount -le 0 -and (Get-HordeWakeHandedOver $a.value) -gt 0 -and'
           Replace = 'elseif ((Get-HordeWakeHandedOver $a.value) -gt 0 -and' }
        @{ Name = "a-retired-sessions-handed-over-mail-is-held"
           Find = '(Get-HordeWakeHandedOver $a.value) -gt 0 -and "$($t.retired)" -ceq "no" -and'
           Replace = '(Get-HordeWakeHandedOver $a.value) -gt 0 -and' }
        @{ Name = "a-reserved-labels-handed-over-mail-is-held"
           Find = '-and "$($t.retired)" -ceq "no" -and -not (Test-HordeLabelReserved "$($t.label)") -and ($Self'
           Replace = '-and "$($t.retired)" -ceq "no" -and ($Self' }
        @{ Name = "the-watchers-own-handed-over-mail-is-held"
           Find = '-and ($Self -ceq "" -or "$($t.id)" -cne $Self)) { $held[$t.id] = "handed-over mail: "'
           Replace = ') { $held[$t.id] = "handed-over mail: "' }
        @{ Name = "a-handed-over-count-nobody-knows-is-a-count"
           Find = 'if (($n -is [int] -or $n -is [long]) -and $n -gt 0) { return [long]$n }'
           Replace = 'if ($null -eq $n) { return [long]1 }; if (($n -is [int] -or $n -is [long]) -and $n -gt 0) { return [long]$n }' }
        @{ Name = "the-between-turns-rule-is-not-named-in-a-nudges-reason"
           Find = 'if ($ready[$i].between) { $ready[$i].reason ='
           Replace = 'if ($false) { $ready[$i].reason =' }
        @{ Name = "every-nudge-is-said-to-be-by-the-between-turns-rule"
           Find = 'between = ("$(Get-HordeWakeEntryValue $stateNow "betweenTurns")" -ceq "yes") }'
           Replace = 'between = $true }' }
        @{ Name = "the-rule-the-waker-names-is-not-journaled"
           Find = 'if ($rule -ne "") { $told ='
           Replace = 'if ($false) { $told =' }
        @{ Name = "why-a-between-turns-nudge-was-sent-is-not-journaled"
           Find = 'if ($d.reason -clike "*between-turns*") { $told ='
           Replace = 'if ($false) { $told =' }
        @{ Name = "a-sessions-own-acknowledgement-is-evidence-for-itself"
           Find = 'if ("$who" -ceq $self) { continue }'
           Replace = '' }
        @{ Name = "an-acknowledgement-its-waker-could-not-read-is-evidence"
           Find = 'if ($a.state -ceq "known" -and "$($t.reachable)" -ceq "yes" -and "$(Get-HordeWakeEntryValue $a.value "acked")" -ceq "known") { $Acks[$t.id] = Get-HordeWakeEntryValue $a.value "lastAckedAt" }'
           Replace = 'if ($a.state -ceq "known" -and "$($t.reachable)" -ceq "yes") { $Acks[$t.id] = Get-HordeWakeEntryValue $a.value "lastAckedAt" }' }
        @{ Name = "an-unreachable-sessions-acknowledgement-is-evidence"
           Find = 'if ($a.state -ceq "known" -and "$($t.reachable)" -ceq "yes" -and "$(Get-HordeWakeEntryValue $a.value "acked")" -ceq "known") { $Acks[$t.id] = Get-HordeWakeEntryValue $a.value "lastAckedAt" }'
           Replace = 'if ($a.state -ceq "known" -and "$(Get-HordeWakeEntryValue $a.value "acked")" -ceq "known") { $Acks[$t.id] = Get-HordeWakeEntryValue $a.value "lastAckedAt" }' }
        @{ Name = "the-pass-reads-no-acknowledgements"
           Find = 'if ($a.state -ceq "known" -and "$($t.reachable)" -ceq "yes" -and "$(Get-HordeWakeEntryValue $a.value "acked")" -ceq "known") { $Acks[$t.id] = Get-HordeWakeEntryValue $a.value "lastAckedAt" }'
           Replace = '' }
        @{ Name = "a-session-seen-for-the-first-time-ends-a-silence"
           Find = 'if ($acksNow.ContainsKey("$id") -and $shown -is [datetime] -and $shown -le $Now -and ($acksNow["$id"] -isnot [datetime] -or $shown -gt $acksNow["$id"])) { $moved = $true; $rose["$id"] = $shown }'
           Replace = 'if ($shown -is [datetime] -and $shown -le $Now -and ($acksNow["$id"] -isnot [datetime] -or $shown -gt $acksNow["$id"])) { $moved = $true; $rose["$id"] = $shown }' }
        @{ Name = "an-acknowledgement-seen-again-ends-a-silence"
           Find = 'if ($acksNow.ContainsKey("$id") -and $shown -is [datetime] -and $shown -le $Now -and ($acksNow["$id"] -isnot [datetime] -or $shown -gt $acksNow["$id"])) { $moved = $true; $rose["$id"] = $shown }'
           Replace = 'if ($acksNow.ContainsKey("$id") -and $shown -is [datetime] -and $shown -le $Now -and ($acksNow["$id"] -isnot [datetime] -or $shown -ge $acksNow["$id"])) { $moved = $true; $rose["$id"] = $shown }' }
        @{ Name = "an-acknowledgement-from-the-future-ends-a-silence"
           Find = 'if ($acksNow.ContainsKey("$id") -and $shown -is [datetime] -and $shown -le $Now -and ($acksNow["$id"] -isnot [datetime] -or $shown -gt $acksNow["$id"])) { $moved = $true; $rose["$id"] = $shown }'
           Replace = 'if ($acksNow.ContainsKey("$id") -and $shown -is [datetime] -and ($acksNow["$id"] -isnot [datetime] -or $shown -gt $acksNow["$id"])) { $moved = $true; $rose["$id"] = $shown }' }
        @{ Name = "an-acknowledgement-never-ends-a-silence"
           Find = 'if ($acksNow.ContainsKey("$id") -and $shown -is [datetime] -and $shown -le $Now -and ($acksNow["$id"] -isnot [datetime] -or $shown -gt $acksNow["$id"])) { $moved = $true; $rose["$id"] = $shown }'
           Replace = '' }
        @{ Name = "a-recent-acknowledgement-releases-an-unknown-limit"
           Find = 'foreach ($who in @($heard.rose.Keys)) { if ($Acks.ContainsKey("$who")) { $moving["$who"] = $heard.rose[$who] } }'
           Replace = 'foreach ($who in @($Acks.Keys)) { $moving["$who"] = $Acks[$who] }' }
        @{ Name = "a-rise-out-of-reach-now-is-evidence"
           Find = 'foreach ($who in @($heard.rose.Keys)) { if ($Acks.ContainsKey("$who")) { $moving["$who"] = $heard.rose[$who] } }'
           Replace = 'foreach ($who in @($heard.rose.Keys)) { $moving["$who"] = $heard.rose[$who] }' }
        @{ Name = "the-pass-is-given-no-reading-before-it"
           Find = '$heard = Update-HordeWakeAcksRose -Seen $AcksSeen -Acks $Acks -Now $Now'
           Replace = '$heard = Update-HordeWakeAcksRose -Seen $null -Acks $Acks -Now $Now' }
        @{ Name = "a-sessions-own-rise-marks-its-own-probe-due"
           Find = 'if ($null -ne $Risen -and @(@($Risen) | Where-Object { "$_" -cne "$id" }).Count -eq 0) { continue }'
           Replace = '' }
        @{ Name = "a-rise-is-forgotten-on-the-next-pass"
           Find = 'if ($wasRose -is [System.Collections.IDictionary]) { foreach ($id in @($wasRose.Keys)) { $rose["$id"] = $wasRose[$id] } }'
           Replace = '' }
        @{ Name = "a-session-not-read-this-pass-is-forgotten"
           Find = 'if ($wasAcks -is [System.Collections.IDictionary]) { foreach ($id in @($wasAcks.Keys)) { $acksNow["$id"] = $wasAcks[$id] } }'
           Replace = '' }
        @{ Name = "a-fleet-is-called-silent-where-its-end-cannot-be-seen"
           Find = 'if ($acksNow.Count -gt 0 -and $quietSince -is [datetime] -and'
           Replace = 'if ($quietSince -is [datetime] -and' }
        @{ Name = "a-session-given-up-on-is-forgotten-after-a-day"
           Find = '$drop = $false'
           Replace = '$drop = $old' }
        @{ Name = "a-gave-up-entry-is-dropped-when-its-state-was-not-known"
           Find = 'if ("$($a.state)" -ceq "known" -and $null -eq (Get-HordeWakeLedgerEntry -Ledger $next -Id $id -State $a.value)) { $drop = $true }'
           Replace = 'if ("$($a.state)" -cne "known" -or $null -eq (Get-HordeWakeLedgerEntry -Ledger $next -Id $id -State $a.value)) { $drop = $true }' }
        @{ Name = "a-gave-up-entry-with-another-mail-now-is-kept-for-ever"
           Find = 'if ("$($a.state)" -ceq "known" -and $null -eq (Get-HordeWakeLedgerEntry -Ledger $next -Id $id -State $a.value)) { $drop = $true }'
           Replace = '' }
        @{ Name = "a-session-is-gone-without-a-listing-to-say-so"
           Find = 'if ($old -and $null -ne $Listed -and @($Listed) -cnotcontains "$id") { $drop = $true }'
           Replace = 'if ($old -and @($Listed) -cnotcontains "$id") { $drop = $true }' }
        @{ Name = "a-session-gone-from-a-whole-listing-is-kept-for-ever"
           Find = 'if ($old -and $null -ne $Listed -and @($Listed) -cnotcontains "$id") { $drop = $true }'
           Replace = '' }
        @{ Name = "gone-is-judged-against-the-one-session-of-a-proof"
           Find = '$listedIds = @($targets | ForEach-Object { "$($_.id)" })'
           Replace = '$listedIds = $null' }
        @{ Name = "a-young-gave-up-entry-of-a-session-not-listed-is-dropped"
           Find = 'if ($old -and $null -ne $Listed -and @($Listed) -cnotcontains "$id") { $drop = $true }'
           Replace = 'if ($null -ne $Listed -and @($Listed) -cnotcontains "$id") { $drop = $true }' }
        @{ Name = "mail-taken-does-not-reset"
           Find = 'if ($taken -or $drop) { $next.Remove($id) }'
           Replace = 'if ($drop) { $next.Remove($id) }' }
        @{ Name = "stale-ledger-entry-kept"
           Find = 'if ($taken -or $drop) { $next.Remove($id) }'
           Replace = 'if ($taken) { $next.Remove($id) }' }
        @{ Name = "every-session-of-a-silent-fleet-is-probed"
           Find = 'if ($lastOfAny -is [datetime] -and ($Now - $lastOfAny).TotalSeconds -lt $longest) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-silent-probe-always-goes-to-the-same-session"
           Find = '$ready = @($ready | Sort-Object -Property probed, nothing, attempts, rank, oldest, id)'
           Replace = '$ready = @($ready)' }
        @{ Name = "the-silent-probe-is-timed-per-session-not-per-fleet"
           Find = 'if ($p -is [datetime] -and $p -le $Now -and ($null -eq $lastOfAny -or $p -gt $lastOfAny)) { $lastOfAny = $p }'
           Replace = 'if ($p -is [datetime] -and $p -le $Now -and ($null -eq $lastOfAny -or $p -lt $lastOfAny)) { $lastOfAny = $p }' }
        @{ Name = "a-limit-that-is-over-is-plain-not-limited"
           Find = 'if ($until -is [datetime] -and $until -le $Now) { return [pscustomobject]@{ kind = "over"; text = ""; until = $until } }'
           Replace = 'if ($until -is [datetime] -and $until -le $Now) { return [pscustomobject]@{ kind = "none"; text = "" } }' }
        @{ Name = "the-free-knock-is-held-by-the-cap"
           Find = '$free = ($limit.kind -ceq "over" -and -not ($freeFor -is [datetime] -and $freeFor -eq $limit.until))'
           Replace = '$free = $false' }
        @{ Name = "every-knock-under-a-past-limit-is-free"
           Find = '$free = ($limit.kind -ceq "over" -and -not ($freeFor -is [datetime] -and $freeFor -eq $limit.until))'
           Replace = '$free = ($limit.kind -ceq "over")' }
        @{ Name = "the-free-knock-is-counted"
           Find = 'if ($limitNow.kind -ceq "over" -and -not ($wasFree -is [datetime] -and $wasFree -eq $limitNow.until) -and -not $recent) {'
           Replace = 'if ($false) {' }
        @{ Name = "no-wait-after-the-free-knock"
           Find = 'if ($freeFor -is [datetime] -and $steps -lt 1) { $steps = 1 }'
           Replace = '' }
        @{ Name = "the-free-knock-is-not-saved"
           Find = 'if ($freeFor -is [datetime]) { $row["freeFor"] = ConvertTo-HordeWakeTimeText $freeFor }'
           Replace = '' }
        @{ Name = "a-counted-attempt-forgets-the-free-knock"
           Find = '-Probes 0 -FreeFor (Get-HordeWakeEntryValue $had "freeFor")'
           Replace = '-Probes 0' }
        @{ Name = "a-limited-session-is-knocked-for-without-end"
           Find = '-and $knocks -ge [int]$Settings.maxLimitProbesPerMail) { return'
           Replace = '-and $false) { return' }
        @{ Name = "a-knock-at-a-limited-session-is-not-counted-as-one"
           Find = 'if ($limitNow.kind -ceq "open") { $knocks++ }'
           Replace = '' }
        @{ Name = "the-cap-on-knocks-is-seven"
           Find = 'maxLimitProbesPerMail = 6'
           Replace = 'maxLimitProbesPerMail = 7' }
        @{ Name = "giving-up-on-a-limited-session-is-never-said"
           Find = '$probedOut = ($knocks -ge [int]$Settings.maxLimitProbesPerMail)'
           Replace = '$probedOut = $false' }
        @{ Name = "a-gave-up-for-probes-outlives-the-limit"
           Find = '$stood = ($null -ne $had -and (Get-HordeWakeEntryValue $had "gaveUp") -eq $true -and [int]$had.attempts -ge [int]$Settings.maxNudgesPerMail)'
           Replace = '$stood = ($null -ne $had -and (Get-HordeWakeEntryValue $had "gaveUp") -eq $true)' }
        @{ Name = "the-knocks-are-not-saved"
           Find = 'if (($knocks -is [int] -or $knocks -is [long]) -and $knocks -gt 0) { $row["probes"] = [int]$knocks }'
           Replace = '' }
        @{ Name = "a-release-forgets-the-knocks"
           Find = '-ProbeAt $script:HordeWakeProbeDue -Carry $e'
           Replace = '-ProbeAt $script:HordeWakeProbeDue' }
        @{ Name = "evidence-a-second-inside-the-edge-only"
           Find = 'if ($latest -is [datetime] -and ($Now - $latest).TotalSeconds -le $window) { return'
           Replace = 'if ($latest -is [datetime] -and ($Now - $latest).TotalSeconds -lt $window) { return' }
        @{ Name = "evidence-never-grows-old"
           Find = 'if ($latest -is [datetime] -and ($Now - $latest).TotalSeconds -le $window) { return'
           Replace = 'if ($latest -is [datetime]) { return' }
        @{ Name = "a-time-that-has-not-come-is-evidence"
           Find = 'if ($when -is [datetime] -and $when -le $Now -and'
           Replace = 'if ($when -is [datetime] -and' }
        @{ Name = "a-session-wearing-a-senders-label-is-nudged"
           Find = 'if (Test-HordeLabelReserved $worn) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "the-watchers-own-session-is-nudged"
           Find = 'if ($Self -cne "" -and "$(Get-HordeWakeEntryValue $Target "id")" -ceq $Self) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-watcher-from-no-session-skips-everybody"
           Find = 'if ($Self -cne "" -and "$(Get-HordeWakeEntryValue $Target "id")" -ceq $Self) { return'
           Replace = 'if ($Self -ceq "" -or "$(Get-HordeWakeEntryValue $Target "id")" -ceq $Self) { return' }
        @{ Name = "the-pass-does-not-say-it-holds-a-senders-label"
           Find = 'elseif ($a.value.unreadCount -gt 0 -and (Test-HordeLabelReserved "$($t.label)")) { $never[$t.id] ='
           Replace = 'elseif ($false) { $never[$t.id] =' }
        @{ Name = "own-session-does-not-reach-the-decisions"
           Find = '-Acks $Acks -NoProbe:$NoProbe -Self $Self'
           Replace = '-Acks $Acks -NoProbe:$NoProbe' }
        @{ Name = "a-pass-given-one-session-sends-a-probe"
           Find = 'if ($probe -and $NoProbe) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-pass-sends-unless-told-not-to"
           Find = '$shadowPass = (-not $Send)'
           Replace = '$shadowPass = $false' }
        @{ Name = "a-limit-nobody-could-read-is-read-as-not-limited"
           Find = 'if ($word -ceq "unknown") {'
           Replace = 'if ($false) {' }
        @{ Name = "the-evidence-does-not-reach-the-decisions"
           Find = '-CanLook:($CanLook -and -not $looked) -Silent:$Silent -Acks $Acks'
           Replace = '-CanLook:($CanLook -and -not $looked) -Silent:$Silent' }
        @{ Name = "a-limit-is-said-of-a-session-that-cannot-be-reached"
           Find = 'if ($a.value.unreadCount -gt 0 -and "$($t.reachable)" -ceq "yes" -and "$($t.retired)" -ceq "no" -and @("until", "open") -ccontains $limit.kind) {'
           Replace = 'if ($a.value.unreadCount -gt 0 -and @("until", "open") -ccontains $limit.kind) {' }
        @{ Name = "the-evidence-window-is-five-minutes"
           Find = 'movingEvidenceSeconds = 600'
           Replace = 'movingEvidenceSeconds = 300' }
        @{ Name = "a-retired-session-is-nudged"
           Find = 'if ($retired -ceq "yes") { return [pscustomobject]@{ action = "skip"; reason = "retired: a retired session is never nudged" } }'
           Replace = '' }
        @{ Name = "a-session-that-may-be-retired-is-nudged"
           Find = 'if ($retired -cne "no") { return [pscustomobject]@{ action = "wait"; reason = "retired is unknown'
           Replace = 'if ($false) { return [pscustomobject]@{ action = "wait"; reason = "retired is unknown' }
        @{ Name = "a-retired-session-waits-for-ever-instead-of-being-nothing"
           Find = 'if ($retired -ceq "yes") { return [pscustomobject]@{ action = "skip"; reason = "retired: a retired session is never nudged" } }'
           Replace = 'if ($retired -ceq "yes") { return [pscustomobject]@{ action = "wait"; reason = "retired: a retired session is never nudged" } }' }
        @{ Name = "the-pass-does-not-say-whom-it-holds-as-retired"
           Find = 'if ($a.value.unreadCount -gt 0 -and "$($t.retired)" -ceq "yes") { $never[$t.id] ='
           Replace = 'if ($false) { $never[$t.id] =' }
        @{ Name = "a-standing-fact-is-journaled-every-pass"
           Find = 'if ($null -ne $Seen -and $Seen.ContainsKey("$id") -and "$($Seen[$id])" -ceq $text) { continue }'
           Replace = '' }
        @{ Name = "a-pass-given-one-session-runs-over-them-all"
           Find = 'if ($Only -cne "") { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "proof-target-absent" -Id $Only -Outcome "absent" -Reason "the fleet'
           Replace = 'if ($false) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "proof-target-absent" -Id $Only -Outcome "absent" -Reason "the fleet' }
        @{ Name = "the-one-session-is-whoever-is-first"
           Find = '$targets = @($targets | Where-Object { $_.id -ceq $Only })'
           Replace = '$targets = @($targets | Select-Object -First 1)' }
        @{ Name = "the-one-session-matched-in-any-casing"
           Find = '$targets = @($targets | Where-Object { $_.id -ceq $Only })'
           Replace = '$targets = @($targets | Where-Object { $_.id -eq $Only })' }
        @{ Name = "the-pass-is-not-cut-to-its-one-session"
           Find = '$targets = @($targets | Where-Object { $_.id -ceq $Only })'
           Replace = '$targets = @($targets | Where-Object { $_.id -ceq $Only }); if ($targets.Count -eq 1) { $targets = @($listing.value) }' }
        @{ Name = "a-session-limited-until-later-is-nudged"
           Find = 'if ($limit.kind -ceq "until") { return [pscustomobject]@{ action = "wait"; reason = $limit.text } }'
           Replace = '' }
        @{ Name = "a-limit-that-is-over-still-holds"
           Find = 'if ($until -is [datetime] -and $until -le $Now) { return [pscustomobject]@{ kind = "over"; text = ""; until = $until } }'
           Replace = '' }
        @{ Name = "a-limit-ends-a-moment-late"
           Find = 'if ($until -is [datetime] -and $until -le $Now) { return'
           Replace = 'if ($until -is [datetime] -and $until -lt $Now) { return' }
        @{ Name = "every-session-read-as-limited"
           Find = 'if ($word -cne "yes") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "limited-with-no-end-knocked-every-pass"
           Find = 'if (($Now - $last).TotalSeconds -lt $every) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "the-hourly-knock-is-counted"
           Find = 'if ($Silent -or $limitNow.kind -ceq "open") {'
           Replace = 'if ($Silent) {' }
        @{ Name = "a-silent-fleets-probes-are-counted"
           Find = 'if ($Silent -or $limitNow.kind -ceq "open") {'
           Replace = 'if ($limitNow.kind -ceq "open") {' }
        @{ Name = "the-hour-is-two"
           Find = 'limitedUnknownProbeSeconds = 3600'
           Replace = 'limitedUnknownProbeSeconds = 7200' }
        @{ Name = "first-seen-limited-never-noted"
           Find = 'if ((Get-HordeWakeEntryValue $had "probeAt") -is [datetime]) { continue }'
           Replace = 'continue' }
        @{ Name = "first-seen-limited-noted-anew-every-pass"
           Find = 'if ((Get-HordeWakeEntryValue $had "probeAt") -is [datetime]) { continue }'
           Replace = '' }
        @{ Name = "a-release-marks-nothing-due"
           Find = '-GaveUp ((Get-HordeWakeEntryValue $e "gaveUp") -eq $true) -ProbeAt $script:HordeWakeProbeDue'
           Replace = '-GaveUp ((Get-HordeWakeEntryValue $e "gaveUp") -eq $true) -ProbeAt (Get-HordeWakeEntryValue $e "probeAt")' }
        @{ Name = "a-release-makes-every-entry-a-probe"
           Find = 'if ((Get-HordeWakeEntryValue $e "probeAt") -isnot [datetime]) { continue }'
           Replace = '' }
        @{ Name = "a-changed-limit-not-journaled"
           Find = 'if ($null -ne $Seen -and $Seen.ContainsKey("$id") -and "$($Seen[$id])" -ceq $text) { continue }'
           Replace = 'if ($null -ne $Seen -and $Seen.ContainsKey("$id")) { continue }' }
        @{ Name = "an-unread-pass-makes-a-limit-news-again"
           Find = 'if (@($Known) -cnotcontains "$id") { $next["$id"] = $Seen[$id] }'
           Replace = '' }
        @{ Name = "a-limit-that-ended-is-remembered"
           Find = 'if (@($Known) -cnotcontains "$id") { $next["$id"] = $Seen[$id] }'
           Replace = '$next["$id"] = $Seen[$id]' }
        @{ Name = "a-fleet-is-never-silent"
           Find = '$notWoken = @($nudges | Where-Object { $_.outcome -cne "woken" })'
           Replace = '$notWoken = @(1)' }
        @{ Name = "a-busy-answer-does-not-count"
           Find = '$notWoken = @($nudges | Where-Object { $_.outcome -cne "woken" })'
           Replace = '$notWoken = @()' }
        @{ Name = "two-sessions-are-a-fleet"
           Find = 'fleetSilentSessions = 3'
           Replace = 'fleetSilentSessions = 2' }
        @{ Name = "silence-found-only-after-the-cap-is-spent"
           Find = 'fleetSilentMinutes = 5'
           Replace = 'fleetSilentMinutes = 10' }
        @{ Name = "silent-without-waiting"
           Find = 'if ($acksNow.Count -gt 0 -and $quietSince -is [datetime] -and ($Now - $quietSince).TotalSeconds -ge $window -and $who.Count'
           Replace = 'if ($acksNow.Count -gt 0 -and $quietSince -is [datetime] -and $who.Count' }
        @{ Name = "fleet-moving-not-said"
           Find = 'if ($before.silent -eq $true) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving"'
           Replace = 'if ($false) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving"' }
        @{ Name = "fleet-moving-said-of-a-fleet-never-silent"
           Find = 'if ($before.silent -eq $true) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving"'
           Replace = 'if ($true) { [void]$out.Add((New-HordeWakeEntry -At $Now -Kind "fleet-moving"' }
        @{ Name = "the-quiet-is-not-counted-anew-after-movement"
           Find = 'seen = [pscustomobject]@{ silent = $false; quietSince = $null; nudges = @(); acks = $acksNow; probes = 0; rose = $rose }'
           Replace = 'seen = [pscustomobject]@{ silent = $false; quietSince = $before.quietSince; nudges = @($before.nudges); acks = $acksNow; probes = 0; rose = $rose }' }
        @{ Name = "the-count-of-probes-outlives-the-silence"
           Find = 'seen = [pscustomobject]@{ silent = $false; quietSince = $null; nudges = @(); acks = $acksNow; probes = 0; rose = $rose }'
           Replace = 'seen = [pscustomobject]@{ silent = $false; quietSince = $null; nudges = @(); acks = $acksNow; probes = $before.probes; rose = $rose }' }
        @{ Name = "silent-found-again-every-pass"
           Find = '    if ($next.silent) {'
           Replace = '    if ($false) {' }
        @{ Name = "a-killed-nudge-is-not-seen"
           Find = 'if ($null -eq $e -or @("nudge", "nudge-killed") -cnotcontains "$($e.kind)") { continue }'
           Replace = 'if ($null -eq $e -or @("nudge") -cnotcontains "$($e.kind)") { continue }' }
        @{ Name = "a-silent-fleet-is-asked-at-any-step"
           Find = 'if ($last -is [datetime] -and ($Now - $last).TotalSeconds -lt $longest) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-probe-is-still-held-by-the-cap"
           Find = 'if (-not $probe -and -not $free -and $null -ne $Entry -and [int]$Entry.attempts -ge [int]$Settings.maxNudgesPerMail)'
           Replace = 'if (-not $free -and $null -ne $Entry -and [int]$Entry.attempts -ge [int]$Settings.maxNudgesPerMail)' }
        @{ Name = "found-silent-the-attempts-are-kept"
           Find = '$next["$id"] = New-HordeWakeLedgerRow -Attempts 0 -LastAttemptAt $e.lastAttemptAt'
           Replace = '$next["$id"] = New-HordeWakeLedgerRow -Attempts ([int]$e.attempts) -LastAttemptAt $e.lastAttemptAt' }
        @{ Name = "when-it-was-probed-is-not-saved"
           Find = 'if ($probeAt -is [datetime]) { $row["probeAt"] = ConvertTo-HordeWakeTimeText $probeAt }'
           Replace = '' }
        @{ Name = "the-pass-does-not-say-who-is-limited"
           Find = '$limited[$t.id] = $limit.text'
           Replace = '' }
        @{ Name = "the-pass-counts-a-silent-fleets-nudges"
           Find = '-States $states -Now $Now -Settings $Settings -Silent:$Silent'
           Replace = '-States $states -Now $Now -Settings $Settings' }
        @{ Name = "reachable-unknown-is-permission"
           Find = 'if ("$($Target.reachable)" -cne "yes") {'
           Replace = 'if ("$($Target.reachable)" -ceq "no") {' }
        @{ Name = "reachable-not-required"
           Find = 'if ("$($Target.reachable)" -cne "yes") {'
           Replace = 'if ($false) {' }
        @{ Name = "mid-turn-unknown-is-permission"
           Find = 'if ("$($s.midTurn)" -cne "no") {'
           Replace = 'if ("$($s.midTurn)" -ceq "yes") {' }
        @{ Name = "mid-turn-not-checked"
           Find = 'if ("$($s.midTurn)" -cne "no") {'
           Replace = 'if ($false) {' }
        @{ Name = "idle-unknown-is-permission"
           Find = 'if ("$($s.idle)" -cne "yes") {'
           Replace = 'if ("$($s.idle)" -ceq "no") {' }
        @{ Name = "idle-not-required"
           Find = 'if ("$($s.idle)" -cne "yes") {'
           Replace = 'if ($false) {' }
        @{ Name = "box-unknown-is-permission"
           Find = 'if ("$($s.boxEmpty)" -cne "yes") {'
           Replace = 'if ("$($s.boxEmpty)" -ceq "no") {' }
        @{ Name = "box-not-required"
           Find = 'if ("$($s.boxEmpty)" -cne "yes") {'
           Replace = 'if ($false) {' }
        @{ Name = "no-mail-waits-instead-of-skips"
           Find = 'return [pscustomobject]@{ action = "skip"; reason = "no unread mail" }'
           Replace = 'return [pscustomobject]@{ action = "wait"; reason = "no unread mail" }' }
        @{ Name = "young-mail-nudged"
           Find = 'if ($age -lt $Settings.minUnreadSeconds) {'
           Replace = 'if ($false) {' }
        @{ Name = "mail-held-at-exactly-the-minimum"
           Find = 'if ($age -lt $Settings.minUnreadSeconds) {'
           Replace = 'if ($age -le $Settings.minUnreadSeconds) {' }
        @{ Name = "back-off-ignored"
           Find = 'if ($since -lt $wait) {'
           Replace = 'if ($false) {' }
        @{ Name = "back-off-never-grows"
           Find = '$index = [System.Math]::Min($Attempts, $steps.Count) - 1'
           Replace = '$index = 0' }
        @{ Name = "back-off-table-loses-its-cap"
           Find = 'backoffSeconds = @(5, 15, 45, 135, 300)'
           Replace = 'backoffSeconds = @(5, 15, 45, 135)' }
        @{ Name = "attempts-not-counted"
           Find = '$count = $before + 1'
           Replace = '$count = 1' }
        @{ Name = "outcome-counted-without-a-nudge"
           Find = 'if ($null -eq $d -or "$($d.action)" -cne "nudge") { continue }'
           Replace = 'if ($null -eq $d) { continue }' }
        @{ Name = "nothing-counted-as-an-attempt"
           Find = 'if ("$($Outcomes[$id])" -ceq "nothing") {'
           Replace = 'if ($false) {' }
        @{ Name = "nothing-holds-the-slot"
           Find = 'if (($Now - $nothingAt).TotalSeconds -lt $rest) {'
           Replace = 'if ($false) {' }
        @{ Name = "nothing-goes-first"
           Find = 'Sort-Object -Property nothing, attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property attempts, rank, oldest, id' }
        @{ Name = "nothing-journaled-every-pass"
           Find = 'if ($rang.value.outcome -ceq "nothing" -and $null -ne (Get-HordeWakeNothingAt (Get-HordeWakeLedgerEntry -Ledger $Ledger -Id $d.id))) { continue }'
           Replace = '' }
        @{ Name = "hold-outlives-a-real-attempt"
           Find = '$next[$id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt'
           Replace = '$next[$id] = New-HordeWakeLedgerRow -Attempts $count -LastAttemptAt $Now -LastOutcome "$($Outcomes[$id])" -MailAt $mailAt -NothingAt (Get-HordeWakeNothingAt $had)' }
        @{ Name = "shadow-ledger-written-where-live-reads"
           Find = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "ledger" -Shadow:$Shadow -Mode $Mode -HordeHome $HordeHome) -Text'
           Replace = 'Write-HordeWakeFile -Path (Get-HordeWakeStateFile -Name "ledger" -HordeHome $HordeHome) -Text' }
        @{ Name = "bad-mail-said-on-the-first-sighting"
           Find = 'if ($passes -ge 2 -and -not $told) {'
           Replace = 'if ($passes -ge 1 -and -not $told) {' }
        @{ Name = "bad-mail-said-every-pass"
           Find = 'if ($passes -ge 2 -and -not $told) {'
           Replace = 'if ($passes -ge 2) {' }
        @{ Name = "bad-mail-never-forgotten"
           Find = 'if ($count -le 0) { continue }'
           Replace = '' }
        @{ Name = "unreadable-count-not-handed-on"
           Find = '$states[$t.id].value.unreadableCount -gt 0) { $unreadable[$t.id] ='
           Replace = '$false) { $unreadable[$t.id] =' }
        @{ Name = "waker-not-told-a-pass-begins"
           Find = 'Start-HordeWakePass -Waker $Waker'
           Replace = '$null = 0' }
        @{ Name = "every-session-with-mail-is-looked-at"
           Find = 'if ($i -ge $allowed) { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }'
           Replace = 'if ($i -ge $allowed -and $ready[$i].action -ceq "ready") { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }' }
        @{ Name = "looks-in-a-pass-not-capped"
           Find = 'if ($looks -ge [int]$Settings.maxConfirmsPerPass) { break }'
           Replace = '' }
        @{ Name = "a-known-full-box-is-looked-at-anyway"
           Find = 'if ($CanLook -and $unseen -and "$($s.midTurn)" -cne "yes" -and "$($s.boxEmpty)" -cne "no") {'
           Replace = 'if ($CanLook) {' }
        @{ Name = "never-looks"
           Find = '$canLook = Test-HordeWakerConfirms $Waker'
           Replace = '$canLook = $false' }
        @{ Name = "a-session-already-looked-at-is-looked-at-again"
           Find = '-CanLook:($CanLook -and -not $looked)'
           Replace = '-CanLook:$CanLook' }
        @{ Name = "the-look-is-not-used"
           Find = 'if ($looked) { $answer = $Confirmed[$id] }'
           Replace = ''
           Expect = "survives"
           Reason = "the pass copies a look that is known into the states it decides from, so this line decides only for a look that itself failed, and then only the words of the wait: with it the session waits as unknown, without it as unread. It is what makes Get-HordeWakeDecisions right for a caller that hands it looks and leaves its states alone" }
        @{ Name = "killed-nudge-backs-off-like-any-other"
           Find = 'if ("$($Outcomes[$id])" -ceq "killed") { $count = [System.Math]::Max($count, @($Settings.backoffSeconds).Count) }'
           Replace = '' }
        @{ Name = "killed-nudge-sets-a-long-count-back"
           Find = '$count = [System.Math]::Max($count, @($Settings.backoffSeconds).Count) }'
           Replace = '$count = @($Settings.backoffSeconds).Count }' }
        @{ Name = "killed-nudge-journaled-as-a-nudge"
           Find = 'if ($rang.value.outcome -ceq "killed") { $kind = "nudge-killed" }'
           Replace = '' }
        @{ Name = "no-cap-on-nudges-for-one-mail"
           Find = 'if (-not $probe -and -not $free -and $null -ne $Entry -and [int]$Entry.attempts -ge [int]$Settings.maxNudgesPerMail) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "cap-of-seven"
           Find = 'maxNudgesPerMail = 6'
           Replace = 'maxNudgesPerMail = 7' }
        @{ Name = "gave-up-said-every-pass"
           Find = '-or (Get-HordeWakeEntryValue $e "gaveUp") -eq $true) { continue }'
           Replace = ') { continue }' }
        @{ Name = "gave-up-never-said"
           Find = '$gave = Update-HordeWakeGaveUp -Ledger $nextLedger -Now $Now -Settings $Settings'
           Replace = '$gave = [pscustomobject]@{ ledger = $nextLedger; entries = @(); sessions = @() }' }
        @{ Name = "a-new-oldest-mail-inherits-the-old-count"
           Find = '-and $State.oldestUnreadAt -ne $mailAt) { return $null }'
           Replace = '-and $false) { return $null }' }
        @{ Name = "given-up-on-forgotten-after-nothing"
           Find = '-NothingAt $Now -MailAt $mailAt -GaveUp ((Get-HordeWakeEntryValue $had "gaveUp") -eq $true) -ProbeAt (Get-HordeWakeEntryValue $had "probeAt") -Carry $had }'
           Replace = '-NothingAt $Now -MailAt $mailAt -Carry $had }' }
        @{ Name = "who-was-given-up-on-not-handed-on"
           Find = '$gaveUp = @($gave.sessions)'
           Replace = '$gaveUp = @()' }
        @{ Name = "a-failing-fleet-read-is-never-permanent"
           Find = 'if (-not $told -and $count -ge [int]$Settings.maxFleetReadFailures) {'
           Replace = 'if ($false) {' }
        @{ Name = "permanent-said-every-pass"
           Find = 'if (-not $told -and $count -ge [int]$Settings.maxFleetReadFailures) {'
           Replace = 'if ($count -ge [int]$Settings.maxFleetReadFailures) {' }
        @{ Name = "permanent-after-eleven"
           Find = 'maxFleetReadFailures = 10'
           Replace = 'maxFleetReadFailures = 11' }
        @{ Name = "the-wakers-own-count-ignored"
           Find = 'if ($given -is [int] -or $given -is [long]) { $count = [int]$given }'
           Replace = '' }
        @{ Name = "recovered-said-for-a-hiccup"
           Find = 'if ($before.told -eq $true) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "recovered"'
           Replace = 'if ($before.failures -gt 0) { [void]$entries.Add((New-HordeWakeEntry -At $Now -Kind "recovered"' }
        @{ Name = "failures-not-forgotten-when-it-works"
           Find = 'return [pscustomobject]@{ seen = [pscustomobject]@{ failures = 0; since = $null; told = $false }; entries = $entries.ToArray(); quiet = $false; condition = $null }'
           Replace = 'return [pscustomobject]@{ seen = $before; entries = $entries.ToArray(); quiet = $false; condition = $null }' }
        @{ Name = "listing-not-handed-on"
           Find = 'gaveUp = $gaveUp; listing = $listing; warchief = $warchief;'
           Replace = 'gaveUp = $gaveUp; listing = $null; warchief = $warchief;' }
        @{ Name = "one-of-two-warchiefs-chosen"
           Find = 'if ($chiefs.Count -eq 1) { $warchief = $chiefs[0].id }'
           Replace = 'if ($chiefs.Count -ge 1) { $warchief = $chiefs[0].id }' }
        @{ Name = "an-orc-taken-for-the-warchief"
           Find = '$chiefs = @($targets | Where-Object { $_.role -ceq "warchief" })'
           Replace = '$chiefs = @($targets)' }
        @{ Name = "rate-limit-ignored"
           Find = 'if ($i -ge $allowed) { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }'
           Replace = 'if ($false) { $ready[$i].action = "wait"; $ready[$i].reason = "rate limit" }' }
        @{ Name = "role-order-ignored"
           Find = 'Sort-Object -Property nothing, attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property nothing, attempts, oldest, id' }
        @{ Name = "fewest-attempts-not-first"
           Find = 'Sort-Object -Property nothing, attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property nothing, rank, oldest, id' }
        @{ Name = "oldest-mail-not-first"
           Find = 'Sort-Object -Property nothing, attempts, rank, oldest, id'
           Replace = 'Sort-Object -Property nothing, attempts, rank, id' }
        @{ Name = "shadow-nudges"
           Find = 'if ($shadowPass) { $outcomes[$d.id] = "would-nudge";'
           Replace = 'if ($false) { $outcomes[$d.id] = "would-nudge";' }
    )
}
