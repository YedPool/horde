# wakers/Port.ps1 - the waker port: how the wake watcher sees which sessions have unread mail, and rings.
#
# WHY THIS EXISTS: POSTING AND WAKING ARE TWO RESPONSIBILITIES, AND THEY WERE ONE. A message sender put
# the message in the target's mailbox and, in the same breath, tried to wake the target. Every sender
# then said "took it" - true of the mailbox - while the receiver slept on, because a mailbox is not a
# doorbell (messengers/Port.ps1, THE WAKE WORD: on 2026-10-12 lines and answers sat in a session's
# mailbox within seconds, every caller reported success, and the session never took a turn). A wake
# tied to the post is tried ONCE, by whoever happened to post: a knock that lands while the target is
# mid-turn, or while somebody's unsent text sits in its input box, is lost, and nobody tries again.
# After a restore of every session it is worse - no post is in flight at all, so nothing knocks.
#
# SO ONE WATCHER OWNS THE DOORBELL. Senders only post. One always-on, model-free process (core/Wake.ps1,
# `horde wake run`) re-reads the state every pass and nudges any session that has unread mail and is
# idle with an empty input box, until the mail is taken. It is LEVEL-triggered: it acts on what is true
# now, not on an event it might have missed, so a lost wake heals on the next pass and "every session
# was restored" is the same case as "one message arrived".
#
# WHAT A WAKER IS. The watcher is told three things by an adapter, and decides everything itself:
#   Targets  the sessions there are to wake, each { id; label; role; parent; reachable }
#   State    one session's { unreadCount; oldestUnreadAt; idle; boxEmpty; midTurn }
#   Nudge    ring one session's doorbell, answering { outcome; reason; at }
# Each waker is a folder, wakers/<name>/, holding Waker.ps1 (its code), capabilities.json (what it can
# do, as data, checked against schema/waker-capabilities.v1) and test/Fixture.ps1 (how
# test/test-waker-conformance.ps1 observes it). This file names no waker, no terminal and no agent
# program: the next one is a new folder, not an edit here.
#
# YES, NO, AND "I CANNOT TELL" ARE THREE ANSWERS. reachable, idle, boxEmpty and midTurn are each exactly
# yes, no or unknown, and the port refuses anything else. unknown is NEVER read as permission by the
# watcher: a waker that cannot see the input box says unknown, and the session is left alone. That one
# rule is what stops a nudge being typed into somebody's half-written text.
#
# CAPABILITIES ARE CLAIMS, AND ONLY "yes" COUNTS for a live run (unverified, declined and no all read as
# "does not have it"). UNVERIFIED IS A CLAIM NOBODY HAS YET SHOWN AGAINST THE REAL THING: the adapter
# does it, and says in its evidence what is still to be run. Such a waker may be READ through by a run
# that nudges nobody, and rung through by the one run whose purpose is to show the claim
# (Resolve-HordeProductionWaker -AllowUnverified; core/WakeRun.ps1 says which runs those are) - and by
# no other. declined and no are never either.
#   nudge.pointer-only  the nudge types one fixed pointer line and never any part of a message body
#   state.box           it can read whether a session's input box is empty
#   state.turn          it can read whether a session is in the middle of a turn
#   reach.unseen        it can nudge a session that has not taken a turn since a restore
#   nudge.guarded       the nudge itself looks again, and rings only a session that still has an empty
#                       input box and is not mid-turn (below)
#   state.between-turns it can tell that a session is idle between turns though its own status still
#                       says busy (background work holds the status). Not required for a live run
#   state.limit         it can tell whether a session is under a usage limit, and so cannot answer a
#                       knock. Not one of the five the production path requires: a waker for a harness
#                       that has no such thing declares no, and its sessions are read as not limited
# The production path (Resolve-HordeProductionWaker) requires all five. The in-process test waker
# declines reach.unseen, so no production path can pick it.
#
# THE NUDGE GUARDS ITSELF, BECAUSE THE STATE THE WATCHER READ IS OLD BY THEN. The watcher reads a state,
# decides, and asks for a nudge; between the read and the keystroke a person can begin to type, or the
# session can begin a turn. The watcher cannot close that gap from where it stands - only the adapter is
# next to the session when the line is typed - so the contract puts the last look there (review of
# PR #207): a waker that offers nudge.guarded checks the box and the turn itself, at the moment it
# would type, and when the box is not empty or a turn is under way it types nothing and answers busy,
# with the reason. The watcher's own reading of the state stays: it is what keeps a nudge from being
# asked for at all, and what an unknown stops.
#
# THE PORT NEVER GUESSES AND NEVER THROWS FOR THE FAR END. Only a waker registered through
# Register-HordeWaker is called: a look-alike object is refused. An adapter that throws, answers with
# something that is not a core/tristate answer, answers about another session than the one asked about,
# uses a word outside the lists, reports unread mail with no time for the oldest, gives a time with no
# zone or a count that is no count, or lists one session twice, comes back unknown with the reason. A caller reads the answer's state and never has to catch.
#
# ADAPTER CONTRACT. wakers/<name>/Waker.ps1 is dot-sourced at script level and calls Register-HordeWaker
# with its name and three script blocks:
#   Targets  param()             -> known: a list of { id; label; role; parent; reachable; retired }, or
#            unknown. reachable and retired are each yes, no or unknown.
#            An unknown may carry failures, a whole number: how many readings in a row have failed. A
#            waker that backs its readings off knows that count and the watcher cannot - its passes are
#            not the waker's readings - and the watcher uses it to tell a hiccup from a fleet that
#            cannot be read at all (core/Wake.ps1, Update-HordeWakeFleetRead).
#   State    param([string]$Id)  -> known { id; unreadCount; oldestUnreadAt; idle; boxEmpty; midTurn },
#            and unreadableCount when the waker can count mail it could not read, or unknown
#   Nudge    param([string]$Id)  -> known { id; outcome; reason; at }, and elapsedMs when it timed the
#            nudge, or unknown. It looks at the box
#            and the turn itself before it types (THE NUDGE GUARDS ITSELF, above).
# and, when it has a use for them, three more:
#   Confirm  param([string]$Id)  -> a state, as State answers it, READ AS FULLY AS THE WAKER CAN. For a
#            waker whose State is cheap - one reading of the whole fleet, with the box and the turn
#            unknown because they cost a look at the session itself - Confirm is that look. The watcher
#            asks for it only for a session it is about to nudge (Get-HordeWakeState -Full), so a pass
#            pays for a look per nudge, not per session. A waker whose State already says everything
#            registers none, and -Full is then State.
#   Source   param()             -> known { fixed; how }: where the program this waker runs comes from.
#            fixed is true when a person NAMED the place in a setting, false when the waker found it
#            by looking (on PATH); how is one line saying which. A waker that runs no program of
#            anybody's registers none (Get-HordeWakerSource).
#   Begin    param()             a pass begins. A waker that answers a pass's many questions from one
#            reading of the fleet throws that reading away here, and nowhere else by the clock: the
#            watcher says when a pass begins (Start-HordeWakePass), so a reading is never reused across
#            two passes and never repeated inside one, however slow the fleet was to answer.
# role is warchief, orc, warg or unknown; parent is a session id or "". unreadCount is a whole number,
# 0 or more; oldestUnreadAt is a [datetime] of kind Utc or Local, required when unreadCount is above 0. outcome is woken, busy,
# unreachable, nothing (the mail was taken before the nudge, so nobody was rung) or killed (the waker
# stopped its own nudge part-way, and the box may hold text); reason is one line and
# required unless the outcome is woken; at is a [datetime]. A session the waker does not know is unknown,
# with the reason - never a state of zeros.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Roles.ps1")

if ($null -eq (Get-Variable -Name HordeWakers -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeWakers = @{} }
$script:HordeWakerCapabilityNames = @("nudge.pointer-only", "state.box", "state.turn", "reach.unseen", "nudge.guarded", "state.limit", "state.between-turns")
# What the production path requires: every one. A waker without all five is never picked there.
$script:HordeProductionWakerRequires = @("nudge.pointer-only", "state.box", "state.turn", "reach.unseen", "nudge.guarded")
# Horde's roles as core/Roles.ps1 lists them (core\roles.json), then unknown for a session whose role
# nobody recorded: one list of roles, not a copy (review of PR #207). It is also the order the watcher
# serves them in when more qualify than one pass may nudge (core/Wake.ps1).
$script:HordeWakerRoles = @(@((Get-HordeRoleTable).native) + "unknown")
$script:HordeWakerWords = @("yes", "no", "unknown")
# nothing: asked to nudge, the waker found the session had no unread mail by then - it was taken between
# the state read and the nudge - and rang nobody. It is not a failure, and the watcher counts no attempt
# for it (core/Wake.ps1).
# killed: the waker had to stop its own nudge part-way - it hung past the waker's last deadline. NOBODY
# KNOWS WHAT THE SESSION'S BOX HOLDS NOW: the stop may have fallen between the line being typed and its
# being sent, and text left in a box is a box that is never empty, so that session would never be woken
# again. It is the one outcome that may have made things worse, and the watcher treats it as that: its
# own loud journal line, and the longest back-off (core/Wake.ps1).
$script:HordeWakerOutcomes = @("woken", "busy", "unreachable", "nothing", "killed")
# The outcomes that must say why: woken needs no account, and the others have no other.
$script:HordeWakerReasonOutcomes = @("busy", "unreachable", "nothing", "killed")
$script:HordeWakerTargetMembers = @("id", "label", "role", "parent", "reachable")
$script:HordeWakerSessionPattern = $null

function Get-HordeWakerRoot {
    return $PSScriptRoot
}

function Get-HordeWakerFiles {
    # Every waker's Waker.ps1, for the caller to dot-source at script level:
    #   foreach ($f in @(Get-HordeWakerFiles)) { . $f }
    param([string]$Root = (Get-HordeWakerRoot))
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Waker.ps1" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Get-HordeWakerCapabilityNames {
    return @($script:HordeWakerCapabilityNames)
}

function Get-HordeWakerRoles {
    # The roles a target may carry, in the order the watcher serves them.
    return @($script:HordeWakerRoles)
}

function Test-HordeWakerCapabilities {
    # Findings for a parsed capabilities.json read from -Folder: the schema's, plus the rule the schema
    # cannot say - the waker it names is its own folder.
    param($Capabilities, [string]$Folder)
    $schema = Get-HordeSchema -Name "waker-capabilities.v1"
    $findings = @(Test-HordeSchema -Value $Capabilities -Schema $schema)
    if ($findings.Count -gt 0) { return $findings }
    $leaf = Split-Path -Leaf $Folder
    if ("$($Capabilities.waker)" -cne $leaf) { return @("capabilities.json names the waker '" + $Capabilities.waker + "' but sits in the folder '" + $leaf + "'") }
    return @()
}

function Register-HordeWaker {
    # Called by a waker's own Waker.ps1. Throws, naming every finding, when its capabilities.json is
    # missing or invalid, or names another waker than -Name: a waker that cannot say what it does is
    # not one. -Folder is where its capabilities.json is; left out, it is wakers/<Name>/, which is
    # where every shipped waker lives (a suite registers fixtures from a folder of its own).
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Targets,
        [Parameter(Mandatory = $true)][scriptblock]$State,
        [Parameter(Mandatory = $true)][scriptblock]$Nudge,
        [scriptblock]$Begin = $null,
        [scriptblock]$Confirm = $null,
        [scriptblock]$Source = $null,
        [string]$Folder = ""
    )
    $from = $Folder
    if ($from -eq "") { $from = Join-Path (Get-HordeWakerRoot) $Name }
    $capPath = Join-Path $from "capabilities.json"
    if (-not (Test-Path -LiteralPath $capPath -PathType Leaf)) { throw ("waker folder '" + $from + "' has no capabilities.json") }
    $caps = [System.IO.File]::ReadAllText($capPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $findings = @(Test-HordeWakerCapabilities -Capabilities $caps -Folder $from)
    if ($findings.Count -gt 0) { throw ("waker '" + (Split-Path -Leaf $from) + "' refused: " + ($findings -join "; ")) }
    if ("$($caps.waker)" -cne $Name) { throw ("waker '" + $Name + "' refused: its capabilities.json names the waker '" + $caps.waker + "'") }
    # Once per name: a second registration would silently swap the waker every caller resolves by that
    # name (the transport port's review of PR #42 found exactly that).
    if ($script:HordeWakers.ContainsKey($Name)) {
        throw ("waker '" + $Name + "' is already registered, from " + $script:HordeWakers[$Name].folder + "; the first registration stands")
    }
    $w = [pscustomobject]@{ PSTypeName = "Horde.Waker"; name = $Name; folder = $from; capabilities = $caps; targets = $Targets; state = $State; nudge = $Nudge; begin = $Begin; confirm = $Confirm; source = $Source }
    $script:HordeWakers[$Name] = $w
    return $w
}

function Get-HordeWakerNames {
    return @($script:HordeWakers.Keys | Sort-Object)
}

function Get-HordeWaker {
    # A registered waker by name. Throws for a name nobody registered: asking for one that is not loaded
    # is a programming error, not a state of the world.
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not $script:HordeWakers.ContainsKey($Name)) { throw ("no waker named '" + $Name + "' is loaded") }
    return $script:HordeWakers[$Name]
}

function Get-HordeWakerSupport {
    # The support word a waker declares for one capability: yes, no, declined or unverified.
    param([Parameter(Mandatory = $true)]$Waker, [Parameter(Mandatory = $true)][string]$Capability)
    if ($script:HordeWakerCapabilityNames -cnotcontains $Capability) { throw ("'" + $Capability + "' is not a waker capability") }
    return "$($Waker.capabilities.capabilities.$Capability.support)"
}

function Test-HordeWakerCapability {
    # True only for "yes". unverified is treated as no, and so are no and declined.
    param([Parameter(Mandatory = $true)]$Waker, [Parameter(Mandatory = $true)][string]$Capability)
    return ((Get-HordeWakerSupport -Waker $Waker -Capability $Capability) -ceq "yes")
}

function Test-HordeWakerClaims {
    # True for "yes" and for "unverified": the waker says it does this, shown or not yet. What an
    # answer may SAY rests on this - a waker that claims to read the box may answer about the box -
    # while what a live run may DO rests on Test-HordeWakerCapability.
    param([Parameter(Mandatory = $true)]$Waker, [Parameter(Mandatory = $true)][string]$Capability)
    return (@("yes", "unverified") -ccontains (Get-HordeWakerSupport -Waker $Waker -Capability $Capability))
}

function Get-HordeWakerUnverified {
    # The capabilities a waker declares unverified, in the port's own order: what a banner names, and
    # what a live run is refused for.
    param([Parameter(Mandatory = $true)]$Waker)
    return @($script:HordeWakerCapabilityNames | Where-Object { (Get-HordeWakerSupport -Waker $Waker -Capability $_) -ceq "unverified" })
}

function Resolve-HordeWaker {
    # A waker by name that has every capability in -Require, as a tristate answer. -Require is mandatory
    # so a caller states what it needs; @() means nothing.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require)
    if (-not $script:HordeWakers.ContainsKey($Name)) { return (New-HordeUnknown -Reason ("no waker named '" + $Name + "' is loaded")) }
    $w = $script:HordeWakers[$Name]
    foreach ($c in $Require) {
        if (-not (Test-HordeWakerCapability -Waker $w -Capability $c)) {
            $cap = $w.capabilities.capabilities.$c
            return (New-HordeUnknown -Reason ("waker '" + $Name + "' does not offer " + $c + " (it says " + $cap.support + ": " + $cap.evidence + ")"))
        }
    }
    return (New-HordeKnown -Value $w)
}

function Resolve-HordeProductionWaker {
    # THE ONE way the watcher picks the waker it rings through: the one loaded waker that offers all
    # five capabilities, so the in-process test waker, which declines one, is never chosen.
    #   known    exactly one loaded waker offers all five
    #   absent   none does; the note says, for each loaded waker, the first capability it lacks
    #   unknown  two or more do - one is never chosen over another (core/SessionSeat.ps1 holds the same
    #            rule for two holders of a role)
    # -AllowUnverified is for a run that nudges nobody, or whose purpose is to show the claims: when NO
    # loaded waker offers all five, the one that CLAIMS all five - each yes or unverified - is picked,
    # and two of those are unknown as two are. A waker that offers all five is always preferred, and
    # one that declines or lacks a capability is never picked either way. The caller reads which
    # capabilities are unverified from the waker (Get-HordeWakerUnverified) and says so.
    param([switch]$AllowUnverified)
    $able = New-Object System.Collections.ArrayList
    $claims = New-Object System.Collections.ArrayList
    $lacks = New-Object System.Collections.ArrayList
    foreach ($name in @(Get-HordeWakerNames)) {
        $w = $script:HordeWakers[$name]
        $missing = @($script:HordeProductionWakerRequires | Where-Object { -not (Test-HordeWakerCapability -Waker $w -Capability $_) }) | Select-Object -First 1
        if ($null -ne $missing -and @($script:HordeProductionWakerRequires | Where-Object { -not (Test-HordeWakerClaims -Waker $w -Capability $_) }).Count -eq 0) { [void]$claims.Add($w) }
        if ($null -eq $missing) { [void]$able.Add($w) } else { [void]$lacks.Add($name + ": does not offer " + $missing + " (it says " + (Get-HordeWakerSupport -Waker $w -Capability $missing) + ")") }
    }
    if ($able.Count -eq 1) { return (New-HordeKnown -Value $able[0]) }
    if ($able.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $able.Count + " wakers each offer every capability (" + (@($able | ForEach-Object { $_.name }) -join ", ") + "); one is never chosen over another")) }
    if ($AllowUnverified -and $claims.Count -eq 1) { return (New-HordeKnown -Value $claims[0]) }
    if ($AllowUnverified -and $claims.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $claims.Count + " wakers each claim every capability, unverified (" + (@($claims | ForEach-Object { $_.name }) -join ", ") + "); one is never chosen over another")) }
    $loaded = "no waker is loaded"
    if ($lacks.Count -gt 0) { $loaded = $lacks -join "; " }
    return (New-HordeAbsent -Note ("no loaded waker offers " + ($script:HordeProductionWakerRequires -join ", ") + ": " + $loaded))
}

function Get-HordeWakerSessionPattern {
    # The session-id pattern of schema/link-verbs.v1, read once: a target's id is the id a message is
    # addressed to, so it is checked by the same pattern, never a copy of it.
    if ($null -eq $script:HordeWakerSessionPattern) { $script:HordeWakerSessionPattern = "$((Get-HordeSchema -Name 'link-verbs.v1').definitions.'session-id'.pattern)" }
    return $script:HordeWakerSessionPattern
}

function Test-HordeWakerSessionId {
    # Is this a session id: a string, on one line, matching the pattern? A pattern ending in $ also
    # matches before a final LF, so a line break is refused on its own.
    param($Value)
    return ($Value -is [string] -and $Value -cnotmatch "[`r`n]" -and $Value -cmatch (Get-HordeWakerSessionPattern))
}

function Get-HordeWakerMember {
    # A member of a parsed object or a dictionary, and whether it is there. Looked up, never
    # dereferenced, so a missing member under strict mode is not an error.
    param($Object, [string]$Name)
    if ($Object -is [System.Collections.IDictionary]) { return [pscustomobject]@{ has = $Object.Contains($Name); value = $(if ($Object.Contains($Name)) { $Object[$Name] } else { $null }) } }
    if ($null -eq $Object) { return [pscustomobject]@{ has = $false; value = $null } }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return [pscustomobject]@{ has = $false; value = $null } }
    return [pscustomobject]@{ has = $true; value = $p.Value }
}

function ConvertTo-HordeWakerUtc {
    # An adapter's time as UTC, or $null when it cannot be placed. A [datetime] whose kind is Unspecified
    # carries no zone, and ToUniversalTime() silently reads it as LOCAL time: the first version did that
    # (review of PR #207), so a mail's age was wrong by this machine's offset from UTC - hours - and
    # "younger than 3 s" or "old enough" was decided on a guess. core/WakeFiles.ps1 refuses the same
    # thing in text (ConvertFrom-HordeWakeTimeText); a time with no zone is not a time here either.
    param($Value)
    if ($Value -isnot [datetime] -or $Value.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
    return $Value.ToUniversalTime()
}

function Test-HordeWakerRecord {
    # Is this something with members: a parsed object or a dictionary?
    param($Value)
    return ($null -ne $Value -and ($Value -is [System.Management.Automation.PSCustomObject] -or $Value -is [System.Collections.IDictionary]))
}

function Test-HordeWakerRegistered {
    # Is this the very object Register-HordeWaker made under its name? A look-alike carrying the same
    # name and script blocks is not: it never passed the capability check (messengers/Port.ps1 holds the
    # same rule, from the review of #102).
    param($Waker)
    if ($null -eq $Waker -or $Waker -isnot [System.Management.Automation.PSCustomObject]) { return $false }
    if (@($Waker.PSObject.TypeNames) -notcontains "Horde.Waker") { return $false }
    $n = $Waker.PSObject.Properties["name"]
    if ($null -eq $n -or $n.Value -isnot [string] -or -not $script:HordeWakers.ContainsKey($n.Value)) { return $false }
    return [object]::ReferenceEquals($script:HordeWakers[$n.Value], $Waker)
}

function Get-HordeWakerLabel {
    # The name to put in a refusal, for an object that may not be a waker at all.
    param($Waker)
    if ($null -eq $Waker) { return "(none)" }
    $n = $Waker.PSObject.Properties["name"]
    if ($null -eq $n) { return "(unnamed)" }
    return "$($n.Value)"
}

function ConvertFrom-HordeWakerAnswer {
    # The first check of every adapter answer: it is a core/tristate answer, and a known one. An unknown
    # is passed on as it is; absent says nothing of what was asked and becomes unknown. Returns
    # { ok; answer }: ok means the answer is known and its value is the caller's to check.
    param($Answer, [string]$What, [string]$Waker)
    if (-not (Test-HordeAnswer $Answer)) { return [pscustomobject]@{ ok = $false; answer = (New-HordeUnknown -Reason ("waker '" + $Waker + "' answered " + $What + " with something that is not an answer")) } }
    if ($Answer.state -ceq "unknown") { return [pscustomobject]@{ ok = $false; answer = $Answer } }
    if ($Answer.state -ceq "absent") { return [pscustomobject]@{ ok = $false; answer = (New-HordeUnknown -Reason ("waker '" + $Waker + "' answered " + $What + " absent, which says nothing of what it was asked")) } }
    return [pscustomobject]@{ ok = $true; answer = $Answer }
}

function Get-HordeWakerSource {
    # WHERE THE PROGRAM THIS WAKER RUNS COMES FROM, and whether a person named it (ADAPTER CONTRACT,
    # Source): known { fixed; how }, absent for a waker that runs no program of anybody's (it registered
    # no Source), or unknown with the reason - one that cannot say where its program is, answers with
    # something else, or throws. fixed is true only when the place was NAMED in a setting; a program
    # found by looking for it - on PATH - is not fixed: whatever is first on PATH that day is what would
    # be run. The port only carries it: that a run which sends refuses a program nobody named is the
    # watcher's rule (core/WakeRun.ps1, Get-HordeWakeRunPlan).
    param($Waker)
    if (-not (Test-HordeWakerRegistered $Waker)) { return (New-HordeUnknown -Reason ("waker '" + (Get-HordeWakerLabel $Waker) + "' is not registered through Register-HordeWaker, so where its program comes from was not asked")) }
    if ($null -eq $Waker.source) { return (New-HordeAbsent -Note ("waker '" + $Waker.name + "' runs no program whose place has to be named")) }
    try { $a = & $Waker.source }
    catch { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' failed to say where its program comes from") -ErrorRecord $_) }
    $first = ConvertFrom-HordeWakerAnswer -Answer $a -What "where its program comes from" -Waker $Waker.name
    if (-not $first.ok) { return $first.answer }
    $v = $a.value
    if (-not (Test-HordeWakerRecord $v)) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered where its program comes from with something that is not an object")) }
    $fixed = Get-HordeWakerMember $v "fixed"
    if (-not $fixed.has -or $fixed.value -isnot [bool]) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered where its program comes from without saying, true or false, whether the place was named")) }
    $how = Get-HordeWakerMember $v "how"
    if (-not $how.has -or $how.value -isnot [string] -or $how.value.Trim() -eq "" -or $how.value -cmatch "[`r`n]") { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered where its program comes from without one line saying how it was found")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ fixed = [bool]$fixed.value; how = [string]$how.value }) -ObservedAt $a.observedAt)
}

function Test-HordeWakerConfirms {
    # Does this waker have a fuller reading than its State (ADAPTER CONTRACT, Confirm)? The watcher asks,
    # so that an unknown box is something to look into for such a waker and something to wait on for one
    # that has already said all it can.
    param($Waker)
    return ((Test-HordeWakerRegistered $Waker) -and $null -ne $Waker.confirm)
}

function Start-HordeWakePass {
    # Tell -Waker a pass begins (ADAPTER CONTRACT, Begin). Returns nothing, and never throws for the far
    # end: a waker with no Begin has nothing to be told, and one whose Begin throws has only failed to
    # forget, which its next reading answers for.
    param($Waker)
    if (-not (Test-HordeWakerRegistered $Waker)) { return }
    if ($null -eq $Waker.begin) { return }
    try { $null = & $Waker.begin } catch { }
}

function Get-HordeWakeTargets {
    # The sessions -Waker can see, as a known list of { id; label; role; parent; reachable; retired }, or unknown
    # with the reason. A tristate answer, never a throw for the far end. One bad entry makes the whole
    # listing unknown: a listing is complete or it says why not (core/Identity.ps1's first rule).
    param($Waker)
    if (-not (Test-HordeWakerRegistered $Waker)) { return (New-HordeUnknown -Reason ("waker '" + (Get-HordeWakerLabel $Waker) + "' is not registered through Register-HordeWaker, so its targets were not asked")) }
    try { $a = & $Waker.targets }
    catch { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' failed to list its targets") -ErrorRecord $_) }
    $first = ConvertFrom-HordeWakerAnswer -Answer $a -What "its targets" -Waker $Waker.name
    if (-not $first.ok) { return $first.answer }
    $raw = $a.value
    # A list, and nothing that merely enumerates: a string or a single record is not a listing.
    if ($raw -is [string] -or (Test-HordeWakerRecord $raw) -or $raw -isnot [System.Collections.IEnumerable]) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered its targets with something that is not a list")) }
    $out = New-Object System.Collections.ArrayList
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($t in $raw) {
        if (-not (Test-HordeWakerRecord $t)) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' listed a target that is not an object")) }
        $id = Get-HordeWakerMember $t "id"
        if (-not $id.has -or -not (Test-HordeWakerSessionId $id.value)) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' listed a target whose id is not a session id")) }
        if (-not $seen.Add($id.value)) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' listed the session " + $id.value + " twice")) }
        $label = Get-HordeWakerMember $t "label"
        if (-not $label.has -or $label.value -isnot [string] -or $label.value -cmatch "[`r`n]") { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' listed " + $id.value + " with a label that is not one line of text")) }
        $role = Get-HordeWakerMember $t "role"
        if (-not $role.has -or $role.value -isnot [string] -or $script:HordeWakerRoles -cnotcontains $role.value) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' listed " + $id.value + " with a role that is not one of " + ($script:HordeWakerRoles -join ", "))) }
        $parent = Get-HordeWakerMember $t "parent"
        if (-not $parent.has -or $parent.value -isnot [string] -or ($parent.value -cne "" -and -not (Test-HordeWakerSessionId $parent.value))) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' listed " + $id.value + " with a parent that is neither a session id nor empty")) }
        $reach = Get-HordeWakerMember $t "reachable"
        if (-not $reach.has -or $reach.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $reach.value) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' listed " + $id.value + " with reachable that is not one of " + ($script:HordeWakerWords -join ", "))) }
        # retired: has the session been retired - told its work is over, its seat given up? yes, no or
        # unknown, REQUIRED, like reachable: a waker that left it out would be read as "not retired", and
        # a retired session would be typed into. The port only carries it; that a retired session is
        # never nudged, and one that may be is held, is the watcher's rule (core/Wake.ps1, Get-HordeWakeHold).
        $retired = Get-HordeWakerMember $t "retired"
        if (-not $retired.has -or $retired.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $retired.value) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' listed " + $id.value + " with retired that is not one of " + ($script:HordeWakerWords -join ", "))) }
        [void]$out.Add([pscustomobject]@{ id = [string]$id.value; label = [string]$label.value; role = [string]$role.value; parent = [string]$parent.value; reachable = [string]$reach.value; retired = [string]$retired.value })
    }
    return (New-HordeKnown -Value $out.ToArray() -ObservedAt $a.observedAt)
}

function Get-HordeWakeState {
    # One session's state as -Waker sees it: known { id; unreadCount; unreadableCount; oldestUnreadAt;
    # idle; boxEmpty; midTurn; limited; limitedUntil }, or unknown with the reason. oldestUnreadAt is UTC, and $null when nothing is unread.
    # -Full asks for the waker's fullest reading (ADAPTER CONTRACT, Confirm): the look at the session
    # itself that says what is in its box and whether it is in a turn. Held to the same checks.
    param($Waker, [string]$Id, [switch]$Full)
    if (-not (Test-HordeWakerRegistered $Waker)) { return (New-HordeUnknown -Reason ("waker '" + (Get-HordeWakerLabel $Waker) + "' is not registered through Register-HordeWaker, so the state was not asked")) }
    if (-not (Test-HordeWakerSessionId $Id)) { return (New-HordeUnknown -Reason ("'" + $Id + "' is not a session id, so waker '" + $Waker.name + "' was not asked")) }
    try {
        if ($Full -and $null -ne $Waker.confirm) { $a = & $Waker.confirm $Id }
        else { $a = & $Waker.state $Id }
    }
    catch { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' failed to read the state of " + $Id) -ErrorRecord $_) }
    $first = ConvertFrom-HordeWakerAnswer -Answer $a -What ("the state of " + $Id) -Waker $Waker.name
    if (-not $first.ok) { return $first.answer }
    $v = $a.value
    if (-not (Test-HordeWakerRecord $v)) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with something that is not an object")) }
    # BOUND TO ITS SESSION: an adapter that mis-read its store would otherwise report another session's
    # empty box as this one's, and the nudge would be typed over this one's text.
    $said = Get-HordeWakerMember $v "id"
    if (-not $said.has -or $said.value -isnot [string]) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " without naming the session it is about")) }
    if ($said.value -cne $Id) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' was asked about " + $Id + " and answered about " + $said.value)) }
    $count = Get-HordeWakerMember $v "unreadCount"
    if (-not $count.has -or -not ($count.value -is [int] -or $count.value -is [long]) -or $count.value -lt 0) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with an unreadCount that is not a whole number, 0 or more")) }
    $oldest = Get-HordeWakerMember $v "oldestUnreadAt"
    $oldestAt = $null
    # A COUNT THAT DOES NOT FIT IS REFUSED, NOT CAST: [int] of a long past 2,147,483,647 throws, and the
    # port never throws for the far end (review of PR #207).
    if ($count.value -gt [int]::MaxValue) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with an unreadCount of " + $count.value + ", which is no count of mail")) }
    if ($count.value -gt 0) {
        if (-not $oldest.has -or $oldest.value -isnot [datetime]) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' says " + $Id + " has unread mail and gives no time for the oldest")) }
        $oldestAt = ConvertTo-HordeWakerUtc $oldest.value
        if ($null -eq $oldestAt) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' gave the oldest unread mail of " + $Id + " a time with no zone, which cannot be placed")) }
    }
    # unreadableCount IS OPTIONAL: how many records of the session's mail could not be read at all. A
    # waker that does not report it leaves it out, and that is 0. One that reports it gives a whole
    # number, 0 or more; null there is "I could not count", which is not a count (the same rule as
    # unreadCount). The port only carries it: what a mailbox with bad records needs is the watcher's to
    # say (core/Wake.ps1, bad-mail), and it never stops the good mail beside it from being knocked for.
    $unreadable = 0
    $bad = Get-HordeWakerMember $v "unreadableCount"
    if ($bad.has) {
        if (-not ($bad.value -is [int] -or $bad.value -is [long]) -or $bad.value -lt 0 -or $bad.value -gt [int]::MaxValue) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with an unreadableCount that is not a whole number, 0 or more")) }
        $unreadable = [int]$bad.value
    }
    # limited AND limitedUntil: is the session under a usage limit - its last turn ended in one - so that
    # it cannot answer a knock until the limit resets? limited is yes, no or unknown, LIKE EVERY OTHER
    # FACT HERE, and UNKNOWN IS NEVER READ AS NO: it was first carried as true or false, and a waker
    # that could not tell - a row with no such member, a transcript it could not read - was read as
    # "not limited", so the session was nudged and its nudges counted (safety review of PR 220).
    #   A waker that claims state.limit and leaves limited out has not said: unknown.
    #   A WAKER THAT DOES NOT CLAIM state.limit CANNOT TELL AT ALL, and for it alone the answer is no:
    #   there is nothing to wait for from a harness that has no way to say. It may leave limited out
    #   or say no; anything else from it is a claim it says it cannot make, and the state is unknown.
    # limitedUntil is a time with a zone, read only beside limited yes; with none, nobody knows until
    # when. The port only carries them: what a limited session is owed is the watcher's to say
    # (core/Wake.ps1, Get-HordeWakeLimit).
    $limited = "no"
    $limitedUntil = $null
    $lim = Get-HordeWakerMember $v "limited"
    if (-not (Test-HordeWakerClaims -Waker $Waker -Capability "state.limit")) {
        if ($lim.has -and $null -ne $lim.value -and "$($lim.value)" -cne "no") { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' does not offer state.limit and still answered limited " + $lim.value + " for " + $Id)) }
    } else {
        $limited = "unknown"
        if ($lim.has -and $null -ne $lim.value) {
            if ($lim.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $lim.value) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with a limited that is not one of " + ($script:HordeWakerWords -join ", "))) }
            $limited = [string]$lim.value
        }
    }
    $until = Get-HordeWakerMember $v "limitedUntil"
    if ($limited -ceq "yes" -and $until.has -and $null -ne $until.value) {
        $limitedUntil = ConvertTo-HordeWakerUtc $until.value
        if ($null -eq $limitedUntil) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with a limitedUntil that is not a time with a zone")) }
    }
    # betweenTurns: is idle "yes" BY THE BETWEEN-TURNS RULE - the session's own status still says busy,
    # because background work holds it, and its turn has in fact ended? yes, no or unknown, on the rule
    # of limited: a waker that claims state.between-turns and leaves it out has not said (unknown); one
    # that does not claim it cannot tell, reads as no, and may not say otherwise. The port only carries
    # it, so the journal can say which rule let a nudge through (core/Wake.ps1).
    $between = "no"
    $bt = Get-HordeWakerMember $v "betweenTurns"
    if (-not (Test-HordeWakerClaims -Waker $Waker -Capability "state.between-turns")) {
        if ($bt.has -and $null -ne $bt.value -and "$($bt.value)" -cne "no") { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' does not offer state.between-turns and still answered betweenTurns " + $bt.value + " for " + $Id)) }
    } else {
        $between = "unknown"
        if ($bt.has -and $null -ne $bt.value) {
            if ($bt.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $bt.value) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with a betweenTurns that is not one of " + ($script:HordeWakerWords -join ", "))) }
            $between = [string]$bt.value
        }
    }
    # WHAT THE SESSION HAS TAKEN, AND WHAT WAS HANDED TO IT, all optional and all "unknown" when left out
    # ($null) - never 0, never "never":
    #   acked, lastAckedAt   could the waker read what the session has acknowledged (known, unknown), and
    #                        when it last acknowledged any mail (a time with a zone, or $null for never).
    #                        A session acknowledges mail only by taking a turn, so this is the evidence
    #                        that it could take one then (core/Wake.ps1). lastAckedAt is read only
    #                        beside acked known.
    #   handedOverCount,     mail that is in the session's inbox but was HANDED to it by its own side and
    #   oldestHandedOverAt   is not yet acknowledged: not waiting for a knock, so not in unreadCount.
    #                        A whole number, 0 or more, and the time of the oldest; $null for unknown.
    $acked = "unknown"
    $lastAcked = $null
    $ak = Get-HordeWakerMember $v "acked"
    if ($ak.has -and $null -ne $ak.value) {
        if ($ak.value -isnot [string] -or @("known", "unknown") -cnotcontains $ak.value) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with an acked that is not known or unknown")) }
        $acked = [string]$ak.value
    }
    $la = Get-HordeWakerMember $v "lastAckedAt"
    if ($acked -ceq "known" -and $la.has -and $null -ne $la.value) {
        $lastAcked = ConvertTo-HordeWakerUtc $la.value
        if ($null -eq $lastAcked) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with a lastAckedAt that is not a time with a zone")) }
    }
    $handed = $null
    $handedAt = $null
    $ho = Get-HordeWakerMember $v "handedOverCount"
    if ($ho.has -and $null -ne $ho.value) {
        if (-not ($ho.value -is [int] -or $ho.value -is [long]) -or $ho.value -lt 0 -or $ho.value -gt [int]::MaxValue) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with a handedOverCount that is not a whole number, 0 or more")) }
        $handed = [int]$ho.value
    }
    $hoAt = Get-HordeWakerMember $v "oldestHandedOverAt"
    if ($null -ne $handed -and $handed -gt 0 -and $hoAt.has -and $null -ne $hoAt.value) {
        $handedAt = ConvertTo-HordeWakerUtc $hoAt.value
        if ($null -eq $handedAt) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with an oldestHandedOverAt that is not a time with a zone")) }
    }
    $words = [ordered]@{}
    foreach ($n in @("idle", "boxEmpty", "midTurn")) {
        $m = Get-HordeWakerMember $v $n
        if (-not $m.has -or $m.value -isnot [string] -or $script:HordeWakerWords -cnotcontains $m.value) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the state of " + $Id + " with " + $n + " that is not one of " + ($script:HordeWakerWords -join ", "))) }
        $words[$n] = [string]$m.value
    }
    # WHAT IT CANNOT READ, IT CANNOT CLAIM: a waker that does not offer state.box may only say unknown
    # of the box, and likewise state.turn of the turn. Its yes would be a guess, and a guess here is a
    # nudge typed into somebody's text.
    if (-not (Test-HordeWakerClaims -Waker $Waker -Capability "state.box") -and $words["boxEmpty"] -cne "unknown") { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' does not offer state.box and still answered boxEmpty " + $words["boxEmpty"] + " for " + $Id)) }
    if (-not (Test-HordeWakerClaims -Waker $Waker -Capability "state.turn") -and $words["midTurn"] -cne "unknown") { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' does not offer state.turn and still answered midTurn " + $words["midTurn"] + " for " + $Id)) }
    return (New-HordeKnown -Value ([pscustomobject]@{ id = $Id; unreadCount = [int]$count.value; unreadableCount = $unreadable; oldestUnreadAt = $oldestAt; idle = $words["idle"]; boxEmpty = $words["boxEmpty"]; midTurn = $words["midTurn"]; limited = $limited; limitedUntil = $limitedUntil; betweenTurns = $between; acked = $acked; lastAckedAt = $lastAcked; handedOverCount = $handed; oldestHandedOverAt = $handedAt }) -ObservedAt $a.observedAt)
}

function Send-HordeWakeNudge {
    # Ring one session's doorbell through -Waker: known { id; outcome; reason; at }, or unknown with the
    # reason. WHETHER to ring is not decided here - that is core/Wake.ps1's, from the state - and the
    # port passes the outcome through exactly as the adapter said it.
    param($Waker, [string]$Id)
    if (-not (Test-HordeWakerRegistered $Waker)) { return (New-HordeUnknown -Reason ("waker '" + (Get-HordeWakerLabel $Waker) + "' is not registered through Register-HordeWaker, so nobody was nudged")) }
    if (-not (Test-HordeWakerSessionId $Id)) { return (New-HordeUnknown -Reason ("'" + $Id + "' is not a session id, so waker '" + $Waker.name + "' was not asked to nudge it")) }
    try { $a = & $Waker.nudge $Id }
    catch { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' failed to nudge " + $Id) -ErrorRecord $_) }
    $first = ConvertFrom-HordeWakerAnswer -Answer $a -What ("the nudge of " + $Id) -Waker $Waker.name
    if (-not $first.ok) { return $first.answer }
    $v = $a.value
    if (-not (Test-HordeWakerRecord $v)) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the nudge of " + $Id + " with something that is not an object")) }
    $said = Get-HordeWakerMember $v "id"
    if (-not $said.has -or $said.value -isnot [string]) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the nudge of " + $Id + " without naming the session it is about")) }
    if ($said.value -cne $Id) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' was asked to nudge " + $Id + " and answered about " + $said.value)) }
    $outcome = Get-HordeWakerMember $v "outcome"
    if (-not $outcome.has -or $outcome.value -isnot [string] -or $script:HordeWakerOutcomes -cnotcontains $outcome.value) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the nudge of " + $Id + " with an outcome that is not one of " + ($script:HordeWakerOutcomes -join ", "))) }
    $at = Get-HordeWakerMember $v "at"
    if (-not $at.has -or $at.value -isnot [datetime]) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the nudge of " + $Id + " with a time that is not a time")) }
    $rangAt = ConvertTo-HordeWakerUtc $at.value
    if ($null -eq $rangAt) { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the nudge of " + $Id + " with a time with no zone, which cannot be placed")) }
    $reason = Get-HordeWakerMember $v "reason"
    $why = ""
    if ($reason.has -and $null -ne $reason.value) { $why = "$($reason.value)" }
    if ($why -cmatch "[`r`n]") { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the nudge of " + $Id + " with a reason holding a line break")) }
    if ($script:HordeWakerReasonOutcomes -ccontains $outcome.value -and $why.Trim() -eq "") { return (New-HordeUnknown -Reason ("waker '" + $Waker.name + "' answered the nudge of " + $Id + " " + $outcome.value + " without saying why")) }
    $value = [ordered]@{ id = $Id; outcome = [string]$outcome.value; reason = $why; at = $rangAt }
    # elapsedMs IS OPTIONAL: how long the nudge took, by the waker's own measure, as a whole number of
    # milliseconds. Carried when it is one; anything else there is left out, never a reason to refuse an
    # outcome that is otherwise sound.
    $took = Get-HordeWakerMember $v "elapsedMs"
    if ($took.has -and ($took.value -is [int] -or $took.value -is [long]) -and $took.value -ge 0) { $value["elapsedMs"] = [long]$took.value }
    return (New-HordeKnown -Value ([pscustomobject]$value) -ObservedAt $a.observedAt)
}
