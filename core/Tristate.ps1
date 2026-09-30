# core/tristate - one way, for all of Horde, to say "I know", "I know there is none", and "I do not know".
#
# WHY THIS EXISTS. The system Horde replaces said "unknown" at least nine different ways - the word
# "unknown", $null, an empty map, -1, "", "?" against "-", reasons prefixed unknown-, found=$false,
# and named outcomes like "unsure" (planning/ledger/core-tristate.md). And it resolved the SAME unknown
# four different ways: "wezterm did not answer" was refused in one place, permitted in another, and
# read as false in two more. Every time an unknown was silently read as "none", something went wrong:
# live sessions called dead, a kill reported done that killed nothing, six panes reported closed that
# were not, a founder's typed text spliced with a message.
#
# So there is exactly one shape, and the two decisions that went wrong are made impossible to skip:
#   - An answer is { state; value; reason; observedAt } with state known, absent or unknown. Nothing
#     else is an answer: not $null, not @(), not -1, not "".
#   - There is no value to read out of absent or unknown. Get-HordeValue throws on both.
#   - Unknown always says why. New-HordeUnknown refuses an empty reason.
#   - What an unknown COSTS is the caller's decision, and the caller must state it:
#     Resolve-HordeAnswer has a mandatory -OnUnknown and no default.
#
# ONE TRAP THIS CANNOT REMOVE, and says so: an answer is an object, and every object is true to `if`.
# `if ($answer)` is always taken, whatever the state. Test the state, or resolve it.
#
# POWERSHELL 5.1 SHAPE RULES, measured (see the ledger, L-004 and L-005): a function returning @()
# delivers $null, and one returning @(5) delivers 5. A collection held in a PROPERTY survives, so the
# value lives in .value, and Get-HordeValue returns it with the unary comma so it arrives as it went in.
#
# NO Set-StrictMode HERE. This file is dot-sourced, so a file-scope Set-StrictMode sets the CALLER's
# mode: an earlier `Set-StrictMode -Off` switched strict mode off for everything that loaded it. The
# functions are written to run under -Version Latest, and test/test-tristate.ps1 runs under it.

$script:HordeAnswerStates = @("known", "absent", "unknown")
# How far in the future an observation time may be before Limit-HordeAge stops believing it.
$script:HordeClockSkewSeconds = 5

function New-HordeAnswer {
    param([string]$State, $Value, [string]$Reason, $ObservedAt)
    return [pscustomobject]@{ PSTypeName = "Horde.Answer"; state = $State; value = $Value; reason = $Reason; observedAt = $ObservedAt }
}

function New-HordeKnown {
    # A known value. Zero, false, "" and an empty collection are all real values and stay known.
    # $null is not a value: "known, and it is nothing" is New-HordeAbsent.
    #
    # -Value is NOT mandatory on purpose. A mandatory parameter refuses an empty collection and an
    # empty string at binding, and both are legitimate known answers.
    param($Value, $ObservedAt = $null)
    # [DBNull]::Value is not $null to PowerShell, but it means nothing just the same.
    if (-not $PSBoundParameters.ContainsKey("Value") -or $null -eq $Value -or $Value -is [System.DBNull]) {
        throw "a known answer needs a value; a known nothing is New-HordeAbsent"
    }
    return (New-HordeAnswer -State "known" -Value $Value -Reason "" -ObservedAt $ObservedAt)
}

function New-HordeAbsent {
    # Known to be none: the source was read, and what was asked for is not there.
    param([string]$Note = "", $ObservedAt = $null)
    return (New-HordeAnswer -State "absent" -Value $null -Reason $Note -ObservedAt $ObservedAt)
}

function New-HordeUnknown {
    # Not known, and why. The reason is mandatory and may not be blank: an unknown that cannot say
    # why is how a reader failure gets mistaken for the target's state (the old system's exit 4 was
    # reworded for exactly that). With -ErrorRecord, the exception's own message is kept, so a
    # swallowed error is never turned into an anonymous unknown.
    param([string]$Reason, $ErrorRecord = $null)
    if ("$Reason".Trim() -eq "") { throw "an unknown needs a reason" }
    $why = $Reason
    if ($ErrorRecord) {
        $msg = "$ErrorRecord"
        # Looked up, not dereferenced: under strict mode `.Exception` on a plain string throws.
        $exProp = $ErrorRecord.PSObject.Properties["Exception"]
        if ($null -ne $exProp -and $null -ne $exProp.Value) { $msg = $exProp.Value.Message }
        $why = $Reason + ": " + $msg
    }
    return (New-HordeAnswer -State "unknown" -Value $null -Reason $why -ObservedAt $null)
}

function Test-HordeAnswer {
    # Is this a well-formed answer? Anything else - $null, @(), -1, "" - is not one.
    param($Answer)
    if ($null -eq $Answer -or $Answer -isnot [System.Management.Automation.PSCustomObject]) { return $false }
    if (@($Answer.PSObject.TypeNames) -notcontains "Horde.Answer") { return $false }
    # All four fields must exist. Checked by lookup, because under strict mode reading a missing
    # property throws instead of giving $null.
    foreach ($field in @("state", "value", "reason", "observedAt")) {
        if ($null -eq $Answer.PSObject.Properties[$field]) { return $false }
    }
    # Case-sensitive, like the stored form: "KNOWN" is not a state Horde writes, and -notcontains
    # would have accepted it.
    if ($script:HordeAnswerStates -cnotcontains "$($Answer.state)") { return $false }
    if ($Answer.state -ceq "unknown" -and "$($Answer.reason)".Trim() -eq "") { return $false }
    # New-HordeKnown refuses $null; a hand-built "known" holding $null is refused here for the same
    # reason - a known nothing is New-HordeAbsent.
    if ($Answer.state -ceq "known" -and ($null -eq $Answer.value -or $Answer.value -is [System.DBNull])) { return $false }
    # NOT DONE, on purpose: .value is an ordinary property, so `$answer.value` reads it without the
    # state check Get-HordeValue makes. Hiding it would break Resolve-HordeAnswer and the stored form;
    # the rule is carried by review and by this comment (ledger L-040).
    return $true
}

function Assert-HordeAnswer {
    param($Answer)
    if (-not (Test-HordeAnswer $Answer)) { throw "not a Horde answer: a value must be wrapped as known, absent or unknown" }
}

function Get-HordeValue {
    # The value of a KNOWN answer. Throws on absent and on unknown: there is nothing to read, and
    # reading "nothing" out of an unreadable source is how the old registry wrote empty skeletons over
    # records it merely could not parse.
    #
    # ASSIGN IT, THEN WRAP IT: `$v = Get-HordeValue $a; @($v)`. The value comes back with the unary
    # comma so a collection keeps its shape, which means `@(Get-HordeValue $a)` wraps the whole
    # collection as ONE element - measured while writing this module's own test.
    param($Answer)
    Assert-HordeAnswer $Answer
    if ($Answer.state -eq "unknown") { throw ("the value is unknown (" + $Answer.reason + "); there is nothing to read") }
    if ($Answer.state -eq "absent") { throw "the value is absent; there is nothing to read" }
    return ,$Answer.value
}

function Invoke-HordeRead {
    # Run a reader and wrap what it returns. A reader that throws gives UNKNOWN carrying the message;
    # one that returns an answer is passed through; any other value that ARRIVES is known - zero,
    # false and "" included. A reader that returns $null (or nothing) has not said which of absent or
    # unknown it means, so that is unknown too: only the reader can say "none", by returning
    # New-HordeAbsent.
    #
    # WHAT ARRIVES IS NOT ALWAYS WHAT THE READER WROTE (measured, PS 5.1, 2026-09-29): a reader ending
    # in a bare @() delivers nothing, so it reads as UNKNOWN; one ending in @(5) delivers the bare 5,
    # so it reads as known Int32, not a list. A reader that means a collection must return it with
    # the unary comma - `, @()` or `, $list` - or return an answer itself.
    param([Parameter(Mandatory = $true)][string]$What, [Parameter(Mandatory = $true)][scriptblock]$Read)
    $got = $null
    # Most cmdlet failures are non-terminating: they write an error and the reader carries on to its
    # fallback, which came back KNOWN - { Write-Error boom; 0 } read as known 0 (review, 2026-09-29).
    # Stop, set here, is local to this call and reaches the reader's scope, so any error it writes
    # ends the read as unknown. The caller's own preference is untouched.
    $ErrorActionPreference = "Stop"
    try { $got = & $Read }
    catch { return (New-HordeUnknown -Reason ("could not read " + $What) -ErrorRecord $_) }
    if (Test-HordeAnswer $got) { return $got }
    # A reader that returns an answer AND writes anything else to the pipeline delivers an array
    # holding both. Wrapping that as known turned an absent or unknown answer into a known Object[]
    # (found in review, 2026-09-29). Which element the reader meant cannot be told, so it is unknown.
    if ($got -is [System.Collections.IEnumerable] -and $got -isnot [string]) {
        foreach ($item in $got) {
            if (Test-HordeAnswer $item) { return (New-HordeUnknown -Reason ($What + ": the reader emitted an answer plus other output")) }
        }
    }
    if ($null -eq $got) { return (New-HordeUnknown -Reason ($What + " returned nothing, which says neither none nor what it found")) }
    return (New-HordeKnown -Value $got)
}

function Get-HordeField {
    # A field of a record, as an answer. A field that is not there is UNKNOWN - never the happy
    # default. In the old system, 94 of 369 roster entries predated a field; defaulting them to
    # "fresh" was rejected, because unknown is not fresh.
    param($Record, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Record) { return (New-HordeUnknown -Reason ("no record to read '" + $Name + "' from")) }
    $prop = $Record.PSObject.Properties[$Name]
    if ($Record -is [System.Collections.IDictionary]) {
        if (-not $Record.Contains($Name)) { return (New-HordeUnknown -Reason ("the record has no '" + $Name + "' field")) }
        if ($null -eq $Record[$Name]) { return (New-HordeUnknown -Reason ("the record's '" + $Name + "' field is null")) }
        return (New-HordeKnown -Value $Record[$Name])
    }
    if ($null -eq $prop) { return (New-HordeUnknown -Reason ("the record has no '" + $Name + "' field")) }
    if ($null -eq $prop.Value) { return (New-HordeUnknown -Reason ("the record's '" + $Name + "' field is null")) }
    return (New-HordeKnown -Value $prop.Value)
}

function Resolve-HordeAnswer {
    # Decide what an answer means FOR THIS CALLER. -OnUnknown is mandatory and has no default, so the
    # call site states its policy where a reviewer can see it:
    #   Refuse    do not act; outcome "refused", with the reason. Destructive acts use this.
    #   Permit    act anyway; outcome "permitted", with the reason. Only for acts that are harmless
    #             if wrong, and the caller should say so.
    #   AsAbsent  treat as none; outcome "absent". The old system's commonest mistake, now only
    #             possible by writing it down.
    #   Throw     stop.
    # Returns { outcome; value; reason } with outcome known, absent, refused or permitted.
    param(
        $Answer,
        [Parameter(Mandatory = $true)][ValidateSet("Refuse", "Permit", "AsAbsent", "Throw")][string]$OnUnknown
    )
    Assert-HordeAnswer $Answer
    switch ($Answer.state) {
        "known"  { return [pscustomobject]@{ outcome = "known"; value = $Answer.value; reason = "" } }
        "absent" { return [pscustomobject]@{ outcome = "absent"; value = $null; reason = $Answer.reason } }
    }
    switch ($OnUnknown) {
        "Refuse"   { return [pscustomobject]@{ outcome = "refused"; value = $null; reason = $Answer.reason } }
        "Permit"   { return [pscustomobject]@{ outcome = "permitted"; value = $null; reason = $Answer.reason } }
        "AsAbsent" { return [pscustomobject]@{ outcome = "absent"; value = $null; reason = $Answer.reason } }
        "Throw"    { throw ("unknown: " + $Answer.reason) }
    }
}

function Limit-HordeAge {
    # A known or absent answer older than its TTL becomes UNKNOWN. Both, not only the worrying one:
    # the old system noticed that a session killed while idle "would then read idle forever" if only
    # busy readings expired. An answer with no observation time cannot be aged, so it is unknown too.
    # A TTL that is not a positive number is REFUSED rather than honoured - a typo that set it to zero
    # would make everything read unknown forever.
    param($Answer, $TtlSeconds, [datetime]$Now = (Get-Date))
    Assert-HordeAnswer $Answer
    $ttl = 0.0
    # Invariant culture, no thousands separators: in the current culture "1,5" parsed as 15 here and
    # would be 1.5 in a comma-decimal one. NaN and Infinity parse as doubles but are refused: NaN
    # compares false with everything, so a NaN TTL kept a 400-day-old answer known (review, 2026-09-29).
    $parsedTtl = [double]::TryParse("$TtlSeconds", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ttl)
    if (-not $parsedTtl -or [double]::IsNaN($ttl) -or [double]::IsInfinity($ttl) -or $ttl -le 0) { throw ("a TTL must be a positive number of seconds, not '" + $TtlSeconds + "'") }
    if ($Answer.state -eq "unknown") { return $Answer }
    if ($null -eq $Answer.observedAt) { return (New-HordeUnknown -Reason "the answer has no observation time, so its age cannot be checked") }
    # Both sides in UTC. A stored answer reads back with a UTC observedAt (RoundtripKind) and -Now
    # defaults to local time; subtracting them as they stand ignores the Kind, so in a UTC- zone every
    # stored answer looked observed in the future and never expired (measured at UTC-4, 2026-09-29).
    $age = ($Now.ToUniversalTime() - ([datetime]$Answer.observedAt).ToUniversalTime()).TotalSeconds
    # A future observation has a negative age, which is never past any TTL, so it would never go stale.
    # 5 seconds of skew is allowed: an allowance for writers' clocks disagreeing slightly, not a
    # measured figure - no Horde writer runs off-machine yet. Beyond that the time is not believed.
    if ($age -lt -$script:HordeClockSkewSeconds) {
        return (New-HordeUnknown -Reason ("observed " + [int](-$age) + "s in the future, past the " + $script:HordeClockSkewSeconds + "s skew allowance, so its age cannot be trusted"))
    }
    if ($age -gt $ttl) {
        return (New-HordeUnknown -Reason ("stale: observed " + [int]$age + "s ago, past its " + $ttl + "s TTL"))
    }
    return $Answer
}

function ConvertTo-HordeAnswerText {
    # One line for a human. Each state leads with its own word, so no rendering can round three
    # values to two - "a three-valued trust that prints as two values would be a lie by rounding".
    param($Answer)
    Assert-HordeAnswer $Answer
    switch ($Answer.state) {
        "known"   { return ("known: " + (@($Answer.value) -join ", ")) }
        "absent"  { if ($Answer.reason) { return ("absent (" + $Answer.reason + ")") } else { return "absent" } }
        "unknown" { return ("unknown (" + $Answer.reason + ")") }
    }
}

function ConvertTo-HordeAnswerRecord {
    # The stored form: { state; value; reason; observedAt }. The state is always written, never
    # implied by an empty value.
    param($Answer)
    Assert-HordeAnswer $Answer
    $at = $null
    if ($null -ne $Answer.observedAt) { $at = ([datetime]$Answer.observedAt).ToUniversalTime().ToString("o") }
    return [ordered]@{ state = $Answer.state; value = $Answer.value; reason = $Answer.reason; observedAt = $at }
}

function ConvertFrom-HordeAnswerRecord {
    # Read a stored answer. No record, no state, an unrecognised state, or a "known" with no value
    # all read as UNKNOWN - never as known, and never as absent.
    param($Record)
    if ($null -eq $Record) { return (New-HordeUnknown -Reason "no record was found; silence is not a report") }
    $state = Get-HordeField -Record $Record -Name "state"
    if ($state.state -ne "known") { return (New-HordeUnknown -Reason "the record has no state") }
    $word = "$($state.value)"
    if ($script:HordeAnswerStates -cnotcontains $word) { return (New-HordeUnknown -Reason ("the record's state '" + $word + "' is not one Horde knows")) }
    $at = $null
    $atField = Get-HordeField -Record $Record -Name "observedAt"
    if ($atField.state -eq "known") {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse("$($atField.value)", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { $at = $parsed }
    }
    $reason = ""
    $rField = Get-HordeField -Record $Record -Name "reason"
    if ($rField.state -eq "known") { $reason = "$($rField.value)" }
    switch ($word) {
        "known" {
            $v = Get-HordeField -Record $Record -Name "value"
            if ($v.state -ne "known") { return (New-HordeUnknown -Reason "the record says known but carries no value") }
            return (New-HordeKnown -Value $v.value -ObservedAt $at)
        }
        "absent"  { return (New-HordeAbsent -Note $reason -ObservedAt $at) }
        "unknown" {
            if ($reason.Trim() -eq "") { $reason = "the record says unknown and gives no reason" }
            return (New-HordeUnknown -Reason $reason)
        }
    }
}
