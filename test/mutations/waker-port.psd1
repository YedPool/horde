# Mutations of wakers/Port.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\waker-port.psd1
# Each breaks one thing the waker port exists for - a waker registered only with valid capabilities, only
# yes counting, the production path requiring every capability and never choosing, only a registered
# waker being called, and no answer of an adapter passed on unchecked; test\test-wake-port.ps1 must fail
# for every one. (The review of PR #207 found the port had no spec of its own.)
@{
    Target = "wakers\Port.ps1"
    Suite  = "test\test-wake-port.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "any-duplicate-word-counts"
           Find = '$dup.value -ceq "yes") { $dupWord'
           Replace = '$dup.value -cne "zzz") { $dupWord' }
        @{ Name = "duplicate-is-not-carried"
           Find = 'retired = [string]$retired.value; duplicate = $dupWord'
           Replace = 'retired = [string]$retired.value; duplicate = "no"' }
        @{ Name = "a-fleet-that-could-not-be-asked-is-a-known-empty-list"
           Find = 'return (New-HordeAbsent -Note ("waker ''" + $Waker.name + "'' could not ask its fleet which labels it reserves: " + $why.value))'
           Replace = 'return (New-HordeKnown -Value ([pscustomobject]@{ labels = @() }))' }
        @{ Name = "a-waker-with-no-fleet-reserves-nothing-known"
           Find = 'if ($null -eq $Waker.reserved) { return (New-HordeAbsent -Note'
           Replace = 'if ($null -eq $Waker.reserved) { return (New-HordeKnown -Value ([pscustomobject]@{ labels = @() })) }; if ($false) { return (New-HordeAbsent -Note' }
        @{ Name = "an-answer-that-does-not-say-whether-it-asked-is-read"
           Find = 'if (-not $answered.has -or $answered.value -isnot [bool]) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-reserved-label-that-is-no-label-is-carried"
           Find = 'if ($l -isnot [string] -or $l.Trim() -eq "" -or $l -cmatch "\s") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "reserved-labels-without-a-list-are-read"
           Find = 'if (-not $labels.has -or $null -eq $labels.value -or $labels.value -is [string] -or $labels.value -is [System.ValueType]) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "not-asked-without-a-why-is-absent"
           Find = 'if (-not $why.has -or $why.value -isnot [string] -or $why.value.Trim() -eq "" -or $why.value -cmatch "[`r`n]") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "the-rule-a-waker-names-is-not-carried"
           Find = 'if ($ruled.has -and $ruled.value -is [string] -and $ruled.value.Trim() -ne "" -and $ruled.value -cnotmatch "[`r`n]") { $value["rule"] ='
           Replace = 'if ($false) { $value["rule"] =' }
        @{ Name = "a-rule-of-two-lines-is-carried"
           Find = '-and $ruled.value.Trim() -ne "" -and $ruled.value -cnotmatch "[`r`n]") { $value["rule"] ='
           Replace = '-and $ruled.value.Trim() -ne "") { $value["rule"] =' }
        @{ Name = "a-waker-that-says-nothing-of-betweenturns-reads-as-no"
           Find = '        $between = "unknown"'
           Replace = '        $between = "no"' }
        @{ Name = "a-waker-that-cannot-tell-may-say-between-turns"
           Find = 'if ($bt.has -and $null -ne $bt.value -and "$($bt.value)" -cne "no") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-betweenturns-outside-the-three-words-accepted"
           Find = 'if ($bt.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $bt.value) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "acked-left-out-reads-as-known"
           Find = '    $acked = "unknown"'
           Replace = '    $acked = "known"' }
        @{ Name = "an-acked-outside-its-two-words-accepted"
           Find = 'if ($ak.value -isnot [string] -or @("known", "unknown") -cnotcontains $ak.value) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-time-beside-acked-unknown-is-carried"
           Find = 'if ($acked -ceq "known" -and $la.has -and $null -ne $la.value) {'
           Replace = 'if ($la.has -and $null -ne $la.value) {' }
        @{ Name = "a-lastackedat-with-no-zone-accepted"
           Find = 'if ($null -eq $lastAcked) { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "a-handed-over-count-that-is-no-count-accepted"
           Find = 'if (-not ($ho.value -is [int] -or $ho.value -is [long]) -or $ho.value -lt 0 -or $ho.value -gt [int]::MaxValue) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "an-oldest-handed-over-with-no-zone-accepted"
           Find = 'if ($null -eq $handedAt) { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "betweenturns-is-not-carried"
           Find = 'betweenTurns = $between; acked = $acked;'
           Replace = 'betweenTurns = "no"; acked = $acked;' }
        @{ Name = "when-it-last-acknowledged-is-not-carried"
           Find = 'acked = $acked; lastAckedAt = $lastAcked;'
           Replace = 'acked = $acked; lastAckedAt = $null;' }
        @{ Name = "what-was-handed-over-is-not-carried"
           Find = 'handedOverCount = $handed; oldestHandedOverAt = $handedAt })'
           Replace = 'handedOverCount = $null; oldestHandedOverAt = $handedAt })' }
        @{ Name = "a-source-that-does-not-say-fixed-is-accepted"
           Find = 'if (-not $fixed.has -or $fixed.value -isnot [bool]) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-source-with-no-how-is-accepted"
           Find = 'if (-not $how.has -or $how.value -isnot [string] -or $how.value.Trim() -eq "" -or $how.value -cmatch "[`r`n]") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-source-that-says-found-is-carried-as-named"
           Find = 'fixed = [bool]$fixed.value; how = [string]$how.value })'
           Replace = 'fixed = $true; how = [string]$how.value })' }
        @{ Name = "a-waker-that-says-nothing-of-the-limit-reads-as-not-limited"
           Find = '        $limited = "unknown"'
           Replace = '        $limited = "no"' }
        @{ Name = "a-waker-that-cannot-tell-may-say-limited"
           Find = 'if ($lim.has -and $null -ne $lim.value -and "$($lim.value)" -cne "no") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-waker-that-cannot-tell-is-read-as-unknown"
           Find = 'if (-not (Test-HordeWakerClaims -Waker $Waker -Capability "state.limit")) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-limited-outside-the-three-words-accepted"
           Find = 'if ($lim.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $lim.value) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "an-end-read-beside-a-limit-that-is-not-yes"
           Find = 'if ($limited -ceq "yes" -and $until.has -and $null -ne $until.value) {'
           Replace = 'if ($until.has -and $null -ne $until.value) {' }
        @{ Name = "retired-left-out-reads-as-a-listing"
           Find = 'if (-not $retired.has -or $retired.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $retired.value) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "retired-is-not-carried"
           Find = 'reachable = [string]$reach.value; retired = [string]$retired.value; duplicate = $dupWord })'
           Replace = 'reachable = [string]$reach.value; retired = "no"; duplicate = $dupWord })' }
        @{ Name = "limited-not-carried"
           Find = 'midTurn = $words["midTurn"]; limited = $limited; limitedUntil = $limitedUntil; betweenTurns'
           Replace = 'midTurn = $words["midTurn"]; limited = "no"; limitedUntil = $limitedUntil; betweenTurns' }
        @{ Name = "the-end-of-a-limit-not-carried"
           Find = 'midTurn = $words["midTurn"]; limited = $limited; limitedUntil = $limitedUntil; betweenTurns'
           Replace = 'midTurn = $words["midTurn"]; limited = $limited; limitedUntil = $null; betweenTurns' }
        @{ Name = "a-limit-ending-at-a-time-with-no-zone-accepted"
           Find = 'if ($null -eq $limitedUntil) { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "invalid-capabilities-registered"
           Find = 'if ($findings.Count -gt 0) { throw ("waker ''" + (Split-Path -Leaf $from) + "'' refused: "'
           Replace = 'if ($false) { throw ("waker ''" + (Split-Path -Leaf $from) + "'' refused: "' }
        @{ Name = "folder-name-not-checked"
           Find = 'if ("$($Capabilities.waker)" -cne $leaf) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "name-not-held-to-its-capabilities"
           Find = 'if ("$($caps.waker)" -cne $Name) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "second-registration-replaces-the-first"
           Find = 'if ($script:HordeWakers.ContainsKey($Name)) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-capabilities-file-not-refused"
           Find = 'if (-not (Test-Path -LiteralPath $capPath -PathType Leaf)) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "anything-but-no-counts-as-yes"
           Find = 'return ((Get-HordeWakerSupport -Waker $Waker -Capability $Capability) -ceq "yes")'
           Replace = 'return ((Get-HordeWakerSupport -Waker $Waker -Capability $Capability) -cne "no")' }
        @{ Name = "capability-outside-the-list-answered"
           Find = 'if ($script:HordeWakerCapabilityNames -cnotcontains $Capability) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "production-does-not-require-reach-unseen"
           Find = '$script:HordeProductionWakerRequires = @("nudge.pointer-only", "state.box", "state.turn", "reach.unseen", "nudge.guarded")'
           Replace = '$script:HordeProductionWakerRequires = @("nudge.pointer-only", "state.box", "state.turn", "nudge.guarded")' }
        @{ Name = "production-does-not-require-the-guard"
           Find = '$script:HordeProductionWakerRequires = @("nudge.pointer-only", "state.box", "state.turn", "reach.unseen", "nudge.guarded")'
           Replace = '$script:HordeProductionWakerRequires = @("nudge.pointer-only", "state.box", "state.turn", "reach.unseen")' }
        @{ Name = "unverified-picked-without-being-allowed"
           Find = 'if ($AllowUnverified -and $claims.Count -eq 1) { return (New-HordeKnown -Value $claims[0]) }'
           Replace = 'if ($claims.Count -eq 1) { return (New-HordeKnown -Value $claims[0]) }' }
        @{ Name = "unverified-never-picked"
           Find = 'if ($AllowUnverified -and $claims.Count -eq 1) { return (New-HordeKnown -Value $claims[0]) }'
           Replace = '' }
        @{ Name = "one-of-two-unverified-chosen"
           Find = 'if ($AllowUnverified -and $claims.Count -gt 1) { return (New-HordeUnknown'
           Replace = 'if ($AllowUnverified -and $claims.Count -gt 1) { return (New-HordeKnown -Value $claims[0]) }; if ($false) { return (New-HordeUnknown' }
        @{ Name = "declined-counts-as-a-claim"
           Find = 'return (@("yes", "unverified") -ccontains (Get-HordeWakerSupport'
           Replace = 'return (@("yes", "unverified", "declined") -ccontains (Get-HordeWakerSupport' }
        @{ Name = "unverified-may-not-answer"
           Find = 'return (@("yes", "unverified") -ccontains (Get-HordeWakerSupport'
           Replace = 'return (@("yes") -ccontains (Get-HordeWakerSupport' }
        @{ Name = "unverified-capabilities-not-named"
           Find = 'Where-Object { (Get-HordeWakerSupport -Waker $Waker -Capability $_) -ceq "unverified" })'
           Replace = 'Where-Object { $false })' }
        @{ Name = "production-chooses-between-two"
           Find = 'if ($able.Count -gt 1) { return (New-HordeUnknown'
           Replace = 'if ($able.Count -gt 1) { return (New-HordeKnown -Value $able[0]) }; if ($false) { return (New-HordeUnknown' }
        @{ Name = "full-reading-never-asked"
           Find = 'if ($Full -and $null -ne $Waker.confirm) { $a = & $Waker.confirm $Id }'
           Replace = 'if ($false) { $a = & $Waker.confirm $Id }' }
        @{ Name = "every-reading-is-the-full-one"
           Find = 'if ($Full -and $null -ne $Waker.confirm) { $a = & $Waker.confirm $Id }'
           Replace = 'if ($null -ne $Waker.confirm) { $a = & $Waker.confirm $Id }' }
        @{ Name = "begin-never-told"
           Find = 'try { $null = & $Waker.begin } catch { }'
           Replace = '' }
        @{ Name = "begin-that-throws-is-a-throw"
           Find = 'try { $null = & $Waker.begin } catch { }'
           Replace = '$null = & $Waker.begin' }
        @{ Name = "look-alike-waker-called"
           Find = 'return [object]::ReferenceEquals($script:HordeWakers[$n.Value], $Waker)'
           Replace = 'return $true' }
        @{ Name = "bad-id-reaches-the-state"
           Find = 'if (-not (Test-HordeWakerSessionId $Id)) { return (New-HordeUnknown -Reason ("''" + $Id + "'' is not a session id, so waker ''" + $Waker.name + "'' was not asked"))'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("''" + $Id + "'' is not a session id, so waker ''" + $Waker.name + "'' was not asked"))' }
        @{ Name = "bad-id-reaches-the-nudge"
           Find = 'if (-not (Test-HordeWakerSessionId $Id)) { return (New-HordeUnknown -Reason ("''" + $Id + "'' is not a session id, so waker ''" + $Waker.name + "'' was not asked to nudge it"))'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("''" + $Id + "'' is not a session id, so waker ''" + $Waker.name + "'' was not asked to nudge it"))' }
        @{ Name = "line-break-in-an-id-accepted"
           Find = 'return ($Value -is [string] -and $Value -cnotmatch "[`r`n]" -and $Value -cmatch (Get-HordeWakerSessionPattern))'
           Replace = 'return ($Value -is [string] -and $Value -cmatch (Get-HordeWakerSessionPattern))' }
        @{ Name = "absent-passed-on"
           Find = 'if ($Answer.state -ceq "absent") { return [pscustomobject]@{ ok = $false;'
           Replace = 'if ($false) { return [pscustomobject]@{ ok = $false;' }
        @{ Name = "session-listed-twice-accepted"
           Find = 'if (-not $seen.Add($id.value)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "role-outside-the-list-accepted"
           Find = '$role.value -isnot [string] -or $script:HordeWakerRoles -cnotcontains $role.value) { return'
           Replace = '$role.value -isnot [string]) { return' }
        @{ Name = "role-matched-ignoring-case"
           Find = '$role.value -isnot [string] -or $script:HordeWakerRoles -cnotcontains $role.value) { return'
           Replace = '$role.value -isnot [string] -or $script:HordeWakerRoles -notcontains $role.value) { return' }
        @{ Name = "parent-not-checked"
           Find = '-or ($parent.value -cne "" -and -not (Test-HordeWakerSessionId $parent.value))) { return'
           Replace = ') { return' }
        @{ Name = "reachable-word-not-checked"
           Find = '$reach.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $reach.value) { return'
           Replace = '$reach.value -isnot [string]) { return' }
        @{ Name = "state-of-another-session-passed-on"
           Find = 'if ($said.value -cne $Id) { return (New-HordeUnknown -Reason ("waker ''" + $Waker.name + "'' was asked about " + $Id'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("waker ''" + $Waker.name + "'' was asked about " + $Id' }
        @{ Name = "nudge-of-another-session-passed-on"
           Find = 'if ($said.value -cne $Id) { return (New-HordeUnknown -Reason ("waker ''" + $Waker.name + "'' was asked to nudge " + $Id'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("waker ''" + $Waker.name + "'' was asked to nudge " + $Id' }
        @{ Name = "negative-unread-count-accepted"
           Find = '-or -not ($count.value -is [int] -or $count.value -is [long]) -or $count.value -lt 0) { return'
           Replace = '-or -not ($count.value -is [int] -or $count.value -is [long])) { return' }
        @{ Name = "count-that-does-not-fit-is-cast"
           Find = 'if ($count.value -gt [int]::MaxValue) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "time-with-no-zone-read-as-local"
           Find = 'if ($Value -isnot [datetime] -or $Value.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }'
           Replace = 'if ($Value -isnot [datetime]) { return $null }' }
        @{ Name = "unreadable-count-not-checked"
           Find = 'if (-not ($bad.value -is [int] -or $bad.value -is [long]) -or $bad.value -lt 0 -or $bad.value -gt [int]::MaxValue) { return'
           Replace = 'if ($bad.value -isnot [int]) { $bad.value = 0 }; if ($false) { return' }
        @{ Name = "unreadable-count-dropped"
           Find = 'unreadableCount = $unreadable; oldestUnreadAt'
           Replace = 'unreadableCount = 0; oldestUnreadAt' }
        @{ Name = "state-word-not-checked"
           Find = '$m.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $m.value) { return'
           Replace = '$m.value -isnot [string]) { return' }
        @{ Name = "box-claimed-without-the-capability"
           Find = 'if (-not (Test-HordeWakerClaims -Waker $Waker -Capability "state.box") -and $words["boxEmpty"] -cne "unknown") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "turn-claimed-without-the-capability"
           Find = 'if (-not (Test-HordeWakerClaims -Waker $Waker -Capability "state.turn") -and $words["midTurn"] -cne "unknown") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "outcome-outside-the-list-accepted"
           Find = '$outcome.value -isnot [string] -or $script:HordeWakerOutcomes -cnotcontains $outcome.value) { return'
           Replace = '$outcome.value -isnot [string]) { return' }
        @{ Name = "nothing-is-not-an-outcome"
           Find = '$script:HordeWakerOutcomes = @("woken", "busy", "unreachable", "nothing", "killed")'
           Replace = '$script:HordeWakerOutcomes = @("woken", "busy", "unreachable", "killed")' }
        @{ Name = "elapsed-time-not-carried"
           Find = '-and $took.value -ge 0) { $value["elapsedMs"] = [long]$took.value }'
           Replace = '-and $false) { $value["elapsedMs"] = [long]$took.value }' }
        @{ Name = "killed-is-not-an-outcome"
           Find = '$script:HordeWakerOutcomes = @("woken", "busy", "unreachable", "nothing", "killed")'
           Replace = '$script:HordeWakerOutcomes = @("woken", "busy", "unreachable", "nothing")' }
        @{ Name = "killed-without-a-reason-accepted"
           Find = '$script:HordeWakerReasonOutcomes = @("busy", "unreachable", "nothing", "killed")'
           Replace = '$script:HordeWakerReasonOutcomes = @("busy", "unreachable", "nothing")' }
        @{ Name = "busy-without-a-reason-accepted"
           Find = 'if ($script:HordeWakerReasonOutcomes -ccontains $outcome.value -and $why.Trim() -eq "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "reason-of-two-lines-accepted"
           Find = 'if ($why -cmatch "[`r`n]") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "roles-not-in-serving-order"
           Find = '$script:HordeWakerRoles = @(@((Get-HordeRoleTable).native) + "unknown")'
           Replace = '$script:HordeWakerRoles = @(@("unknown") + @((Get-HordeRoleTable).native))' }
    )
}
