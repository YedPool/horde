# conversations/Port.ps1 - the conversation-source port: a Thrall's turns, in one shape, whatever runs it.
#
# WHAT IT IS FOR (relay design 2026-10-09, Q2 and PR plan item 9). The founder chats with every Thrall
# from one place, whatever account or agent CLI each runs on: one CLI under several accounts, other
# vendors' CLIs, other models through them, and more later. Vendor-neutral is the point. So reading a conversation is a
# port, and each harness is an ADAPTER in its own folder, agents/<name>/, holding Conversation.ps1 (its
# code), conversation.json (what it can do, as data, checked against
# schema/conversation-capabilities.v1) and test/ConversationFixture.ps1 (how
# test/test-conversation-conformance.ps1 drives it). This file names no harness: the next one is a new
# Conversation.ps1 in its folder, not an edit here.
#
# A THRALL-LEVEL CONVERSATION ONLY. Chat covers the orchestrator at the top of a horde - one Thrall per
# horde - and nothing below it (founder, 2026-10-09). A source is found by its horde and the role
# "warchief" (Horde's name for the session at the top; core/roles.json), never by a session id the
# caller guesses, because the Thrall's session changes when it is cleared.
#
# THE PORT NEVER BELIEVES AN ADAPTER. What an adapter hands back is checked and REBUILT here, the way
# relays/Port.ps1 rebuilds what a relay hands back:
#   - each turn is checked field by field: a role outside the closed list, an empty text, a bad or
#     repeated id, or a value that is not an object, drops that turn; a time that is not a time, or a
#     bad group id, drops that field. Each is an anomaly that says why and never repeats the bad value,
#     which may be the very text being kept out;
#   - the source (vendor, session, horde) on every turn is the port's, from the source it located;
#   - a batch larger than asked for, or an answer that does not hold together, is unknown: the adapter's
#     position may already be past turns the port would have to drop, so nothing of it is used;
#   - an adapter that throws, or answers with something that is not a core/tristate answer, is unknown
#     with the reason - redacted, because an exception can quote the line it failed on.
#
# REDACTION IS HERE, AND NEVER IN AN ADAPTER (design Q2). Every turn's text, every anomaly and every
# reason passes core/Secrets.ps1's Protect-HordeSecretText before it leaves this file, with the same
# list of shapes the decisions module refuses. One place to redact means one place to review, and an
# adapter cannot forget it: test/test-conversation-port.ps1 fails if any adapter so much as loads the
# detector. Redacted FIRST, then cut to the ceiling: cut first, a secret across the cut would no longer
# match and its first part would leak.
#
# TEXT ONLY (design decision 8, founder 2026-10-09: the phone shows user and assistant text). Tool calls
# and their output are not turns; showing them is a later option with its own redaction and paging.
# THE ROLES: user (a person typed it), assistant (the model wrote it), system (the harness reported
# something), and delivered - text a messenger HANDED to the Thrall, not typed into it (the fleet's mail,
# the founder's chat lines). Who sent a delivered turn is not the port's to say: it is the delivering
# side's, which knows what it delivered (channels/chat binds a founder's line to the hash of the line he
# signed). A reader that cannot tell drops delivered turns rather than show them as anyone's.
#
# THE CURSOR is the caller's to keep and hand back: { schemaVersion = 1; vendor; session; position },
# plain data that survives being written as JSON. position is the adapter's own, opaque here: printable
# ASCII, at most 1024 characters. $null means "from the start of the conversation". A cursor of another
# session - the Thrall was cleared, or restarted - is not an error: the read starts the new session from
# its beginning and says reset "session". What the old session wrote after the cursor is not read by
# that call: its file is no longer the Thrall's.
#
# A PAST SESSION BY ITS ID (the chat channel, PR plan item 10, answering this port's open question 1).
# After a clear, the old session may hold turns written after the cursor and before the clear - the
# Thrall's last words before it was cleared. Find-HordeConversationSource -Session <id> locates THAT
# session of the horde's Thrall, retired or not, so a caller can read it to its end before it moves on.
# The adapter is asked as for the Thrall now, with the id in the request; it answers known for the
# session it was asked for, absent when that session was never this horde's Thrall (or is gone), and the
# port refuses an answer about any other session: an adapter that ignores the id would hand back the NEW
# session under the old cursor.
#
# THE OPERATIONS, each a tristate answer:
#   Find-HordeConversationSource -Fleet [-Vendor] [-Session] -Require -Refuse [-Options]
#                                 -> known source | absent (no adapter locates a Thrall) | unknown
#   Read-HordeConversationTurns  -Source -Cursor [-MaxTurns] [-MaxBytes]
#                                 -> known { source; since; next; turns; anomalies; reset; more }
# reset is "none", "session" (a new session) or "rotated" (the adapter found its history rewritten and
# read it again from the start). more says the batch or byte limit stopped the read before the end.
#   Get-HordeConversationSession -Fleet -SessionId [-Vendor] [-Options]
#                                 -> known { vendor; session; fleet; label; role; parent } | unknown
#
# A SESSION DESCRIBED BY ITS ID (the files channel, T-0115: a file is sent by a session, and the reader is
# shown its label, which only the fleet's own records hold). ANY session of the horde, not only its
# Thrall, and read-only. It is for an id the caller ALREADY HOLDS: which session is asking is
# core/Identity.ps1's to say (Get-HordeSelfSessionId), never this port's. The answer is known or unknown,
# never absent: an id no adapter has a record of is unknown with that reason, because "there is no such
# session" is more than a store that names no horde can say (the adapter's WHICH HORDE). Inside a known
# answer, label, role and parent are EACH an answer of their own:
#   label   known (the fleet's short handle, the shape of schema/session-record.v1's label), absent (the
#           record holds none: 58 of 92 records of a live registry, 2026-10-13), or unknown (it is there
#           and is not a label). A session is never given a label it does not hold: a caller shows
#           the id, or says the label is not known.
#   role    known (warchief, orc or warg: core/roles.json) or unknown (83 of the same 92 records name no
#           role, and a missing role is never read as the humblest one: core/Roles.ps1).
#   parent  known (the parent's session id; describe it with a second call), absent (the record names
#           none), or unknown.
# A label is a HANDLE, NEVER IDENTITY: it is reissued by design (schema/session-record.v1), so two
# answers with one label are two sessions, and the session id is the key. Nothing is kept between calls:
# every call reads the records again, so a label given since the last call is in the next answer.
#
# CAPABILITIES ARE CLAIMS, AND ONLY "yes" COUNTS (the vocabulary of the host, transport, messenger and
# relay ports). Four are features a caller may -Require: incremental, stableTurnIds, timestamps, roles.
# Two are HAZARDS a caller that cannot cope with them -Refuses: partialTurns, mutableHistory; a hazard
# passes -Refuse only when it is a plain "no", so an unverified hazard counts as present. A seventh,
# sessionLookup, is the claim behind Get-HordeConversationSession: only an adapter that says yes is asked.
#
# ADAPTER CONTRACT. agents/<name>/Conversation.ps1 is dot-sourced at script level and calls
# Register-HordeConversationAdapter with two script blocks, each answering with a core/tristate answer:
#   Locate param($Request)  Request is { fleet; role; session; options }: the horde, "warchief", the
#          session asked for ("" for the one holding the role now; an id for that past or present session
#          of the role, A PAST SESSION BY ITS ID above), and the caller's options (a hashtable; an adapter
#          reads only the keys it knows, and uses its defaults for the rest). -> known { session; locator }
#          for the session asked for, absent when there is none, unknown when that cannot be told.
#          locator is the adapter's own (a path), never shown.
#   Read   param($Source, [string]$Position, [int]$MaxTurns, [long]$MaxBytes)  Source is
#          { vendor; session; locator }; Position "" means from the start.
#          -> known { turns; position; more; reset; anomalies } where each turn is
#          { role; text; turnId; time (optional, ISO 8601 with a zone); groupId (optional) }, at most
#          MaxTurns of them, read from at most MaxBytes of new input; reset is "" or "rotated".
#   Describe param($Request)  OPTIONAL: given by an adapter that declares sessionLookup yes (one that
#          declares it and gives none makes every lookup unknown, saying so). Request is { fleet; session; options }: the horde, the id asked about, the caller's
#          options. -> known { session; role; label; parent } for THAT session, where role, label and
#          parent are each a core/tristate answer holding what the record says, as text; absent when the
#          adapter read its records whole and has none of that id; unknown when it cannot tell. The port
#          checks each of the three and rebuilds it (A SESSION DESCRIBED BY ITS ID): an adapter only reads.
# The adapter reads by allowlist and keeps nothing but what a turn needs (core/Transcript.ps1's rule for
# metrics forbids keeping text at all; this is the one reader that keeps it, and only these fields).
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Schema.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Secrets.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Transcript.ps1")
# For Get-HordeRoleTable: the roles a described session may hold are core/roles.json's, read, not repeated.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Roles.ps1")

if ($null -eq (Get-Variable -Name HordeConversationAdapters -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeConversationAdapters = @{} }
if ($null -eq (Get-Variable -Name HordeConversationSources -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeConversationSources = @{} }
$script:HordeConversationCapabilityNames = @("incremental", "stableTurnIds", "timestamps", "roles", "partialTurns", "mutableHistory", "sessionLookup")
$script:HordeConversationHazardNames = @("partialTurns", "mutableHistory")
$script:HordeConversationRoles = @("user", "assistant", "system", "delivered")
# THE CEILINGS. maxTurns: a phone shows tens of turns at a time; 1000 is a whole working day of a busy
# Thrall's (measured: 485 human prompts and 739 assistant text blocks in a 27 MB transcript, 2026-10-10).
# maxBytes: 32 MiB is more than the largest live Thrall transcript (27.3 MB, S4) in one read, so a first
# read never has to be split for size alone; the default of 4 MiB read the last 2 MB of that file in
# 241 ms (S4). textChars: a turn longer than 100,000 characters is a pasted file, not a chat line; it is
# cut there and marked. positionChars: an adapter's position is a few numbers and a hash.
$script:HordeConversationMaxTurns = 1000
$script:HordeConversationDefaultTurns = 200
$script:HordeConversationMaxBytes = [long]33554432
$script:HordeConversationDefaultBytes = [long]4194304
$script:HordeConversationTextChars = 100000
$script:HordeConversationPositionChars = 1024
# THE SAME PATTERNS AS schema/conversation-turn.v1, kept here because the port checks every field before
# the schema could, and names what failed without repeating it.
$script:HordeConversationIdPattern = '\A[\x21-\x7E]{1,200}\z'
$script:HordeConversationSessionPattern = '\A[A-Za-z0-9._:-]{1,128}\z'
$script:HordeConversationFleetPattern = '\A[a-z0-9][a-z0-9-]{0,62}\z'
$script:HordeConversationPositionPattern = '\A[\x20-\x7E]*\z'
# THE SAME PATTERN AS schema/session-record.v1's label (one or two capitals, then a number from 1 to 9999
# or nothing), kept here as the turn patterns are; test/test-conversation-port.ps1 holds the two equal.
# 34 of 34 labels in a live registry of 92 records have this shape (2026-10-13).
$script:HordeConversationLabelPattern = '\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z'
# A message the port passes on from an adapter (an anomaly, an unknown's reason) is cut here: it is a
# line in a log, not a document.
$script:HordeConversationNoteChars = 300

function Get-HordeConversationRoot {
    # Where the adapters live: the agents folder beside this one.
    return (Join-Path (Split-Path -Parent $PSScriptRoot) "agents")
}

function Get-HordeConversationAdapterFiles {
    # Every harness's Conversation.ps1, for the caller to dot-source at script level:
    #   foreach ($f in @(Get-HordeConversationAdapterFiles)) { . $f }
    param([string]$Root = (Get-HordeConversationRoot))
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Conversation.ps1" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Get-HordeConversationCapabilityNames { return @($script:HordeConversationCapabilityNames) }
function Get-HordeConversationHazardNames { return @($script:HordeConversationHazardNames) }

function Get-HordeConversationCeilings {
    return [pscustomobject]@{ maxTurns = $script:HordeConversationMaxTurns; defaultTurns = $script:HordeConversationDefaultTurns
        maxBytes = $script:HordeConversationMaxBytes; defaultBytes = $script:HordeConversationDefaultBytes
        textChars = $script:HordeConversationTextChars; positionChars = $script:HordeConversationPositionChars }
}

function Protect-HordeConversationNote {
    # An adapter's words, fit to pass on: redacted, on one line, and cut short.
    param($Text)
    $t = (Protect-HordeSecretText -Text ("" + $Text)).text -replace '[\x00-\x1F\x7F]', ' '
    if ($t.Length -gt $script:HordeConversationNoteChars) { $t = $t.Substring(0, $script:HordeConversationNoteChars) + "..." }
    return $t
}

function Register-HordeConversationAdapter {
    # Called by a harness's own Conversation.ps1. Throws, naming every finding, when its
    # conversation.json is missing or invalid: an adapter that cannot say what it does is not one.
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][scriptblock]$Locate,
        [Parameter(Mandatory = $true)][scriptblock]$Read,
        [scriptblock]$Describe = $null
    )
    $capPath = Join-Path $Folder "conversation.json"
    if (-not (Test-Path -LiteralPath $capPath -PathType Leaf)) { throw ("adapter folder '" + $Folder + "' has no conversation.json") }
    $caps = [System.IO.File]::ReadAllText($capPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $findings = @(Test-HordeSchema -Value $caps -Schema (Get-HordeSchema -Name "conversation-capabilities.v1"))
    $leaf = Split-Path -Leaf $Folder
    if ($findings.Count -eq 0 -and "$($caps.vendor)" -cne $leaf) { $findings = @("conversation.json names the vendor '" + $caps.vendor + "' but sits in the folder '" + $leaf + "'") }
    if ($findings.Count -gt 0) { throw ("conversation adapter '" + $leaf + "' refused: " + ($findings -join "; ")) }
    # Once per name: a second registration would silently swap the adapter every caller resolves by that
    # name (the transport port's review of PR #42 found exactly that).
    if ($script:HordeConversationAdapters.ContainsKey("$($caps.vendor)")) {
        throw ("conversation adapter '" + $caps.vendor + "' is already registered, from " + $script:HordeConversationAdapters["$($caps.vendor)"].folder + "; the first registration stands")
    }
    $a = [pscustomobject]@{ PSTypeName = "Horde.ConversationAdapter"; name = "$($caps.vendor)"; folder = $Folder; capabilities = $caps; locate = $Locate; read = $Read; describe = $Describe }
    $script:HordeConversationAdapters[$a.name] = $a
    return $a
}

function Get-HordeConversationAdapterNames { return @($script:HordeConversationAdapters.Keys | Sort-Object) }

function Get-HordeConversationAdapter {
    # A registered adapter by name. Throws for a name nobody registered: a programming error.
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not $script:HordeConversationAdapters.ContainsKey($Name)) { throw ("no conversation adapter named '" + $Name + "' is loaded") }
    return $script:HordeConversationAdapters[$Name]
}

function Get-HordeConversationSupport {
    # The support word an adapter declares for one capability: yes, no, declined or unverified.
    param([Parameter(Mandatory = $true)]$Adapter, [Parameter(Mandatory = $true)][string]$Capability)
    if ($script:HordeConversationCapabilityNames -cnotcontains $Capability) { throw ("'" + $Capability + "' is not a conversation capability") }
    return "$($Adapter.capabilities.capabilities.$Capability.support)"
}

function Get-HordeConversationShortfall {
    # Why an adapter does not meet -Require and -Refuse, or "" when it does.
    param($Adapter, [string[]]$Require, [string[]]$Refuse)
    foreach ($c in @($Require)) {
        $sup = Get-HordeConversationSupport -Adapter $Adapter -Capability $c
        if ($sup -cne "yes") { return ("adapter '" + $Adapter.name + "' does not offer " + $c + " (it says " + $sup + ": " + $Adapter.capabilities.capabilities.$c.evidence + ")") }
    }
    foreach ($c in @($Refuse)) {
        if ($script:HordeConversationHazardNames -cnotcontains $c) { throw ("'" + $c + "' is not a hazard; only " + ($script:HordeConversationHazardNames -join " and ") + " can be refused") }
        $sup = Get-HordeConversationSupport -Adapter $Adapter -Capability $c
        if ($sup -cne "no") { return ("adapter '" + $Adapter.name + "' may have the hazard " + $c + " (it says " + $sup + ", and only no rules it out)") }
    }
    return ""
}

function Resolve-HordeConversationAdapter {
    # An adapter by name that has every capability in -Require and no hazard in -Refuse, as an answer.
    # Both are mandatory so a caller states what it needs; @() means nothing.
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Refuse)
    if (-not $script:HordeConversationAdapters.ContainsKey($Name)) { return (New-HordeUnknown -Reason ("no conversation adapter named '" + $Name + "' is loaded")) }
    $a = $script:HordeConversationAdapters[$Name]
    $why = Get-HordeConversationShortfall -Adapter $a -Require $Require -Refuse $Refuse
    if ($why -ne "") { return (New-HordeUnknown -Reason $why) }
    return (New-HordeKnown -Value $a)
}

function Find-HordeConversationAdapter {
    # Every loaded adapter that meets -Require and -Refuse: known, the names in order, or unknown naming
    # each adapter and why it was passed over.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require, [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Refuse)
    foreach ($c in @($Require)) { if ($script:HordeConversationCapabilityNames -cnotcontains $c) { throw ("'" + $c + "' is not a conversation capability") } }
    $fit = New-Object System.Collections.ArrayList
    $why = New-Object System.Collections.ArrayList
    foreach ($n in @(Get-HordeConversationAdapterNames)) {
        $s = Get-HordeConversationShortfall -Adapter $script:HordeConversationAdapters[$n] -Require $Require -Refuse $Refuse
        if ($s -eq "") { [void]$fit.Add($n) } else { [void]$why.Add($s) }
    }
    if ($fit.Count -eq 0) { return (New-HordeUnknown -Reason ("no loaded conversation adapter fits: " + $(if ($why.Count) { $why -join "; " } else { "none is loaded" }))) }
    return (New-HordeKnown -Value @($fit.ToArray()))
}

function Get-HordeConversationMember {
    # A member of a parsed object or a dictionary, and whether it is there, without dereferencing it.
    param($Object, [string]$Name)
    if ($Object -is [System.Collections.IDictionary]) { return [pscustomobject]@{ has = $Object.Contains($Name); value = $(if ($Object.Contains($Name)) { $Object[$Name] } else { $null }) } }
    if ($Object -isnot [System.Management.Automation.PSCustomObject]) { return [pscustomobject]@{ has = $false; value = $null } }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return [pscustomobject]@{ has = $false; value = $null } }
    return [pscustomobject]@{ has = $true; value = $p.Value }
}

function Invoke-HordeConversationAdapter {
    # Run one of an adapter's script blocks; its answer, or unknown when it threw or answered with
    # something that is not an answer. absent passes only with -AllowAbsent, where the caller has said what it means.
    param($Adapter, [string]$Op, [object[]]$Arguments, [string]$What, [switch]$AllowAbsent)
    try { $a = & $Adapter.$Op @Arguments }
    catch { return (New-HordeUnknown -Reason ("adapter '" + $Adapter.name + "' failed the " + $What + ": " + (Protect-HordeConversationNote $_.Exception.Message))) }
    if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown -Reason ("adapter '" + $Adapter.name + "' answered the " + $What + " with something that is not an answer")) }
    if ($a.state -ceq "absent" -and -not $AllowAbsent) { return (New-HordeUnknown -Reason ("adapter '" + $Adapter.name + "' answered the " + $What + " absent, which says nothing")) }
    if ($a.state -ceq "unknown") { return (New-HordeUnknown -Reason ("adapter '" + $Adapter.name + "' could not do the " + $What + ": " + (Protect-HordeConversationNote $a.reason))) }
    return $a
}

function Find-HordeConversationSource {
    # The conversation of -Fleet's Thrall, as a source to read: known when exactly one adapter (of those
    # meeting -Require and -Refuse, or only -Vendor when given) locates it; absent when none does; unknown
    # when any could not tell, or more than one says it holds the Thrall - one is never chosen over another.
    # -Session names a past (or the present) session of the Thrall instead of the one holding the role now.
    param(
        [Parameter(Mandatory = $true)][string]$Fleet,
        [string]$Vendor = "",
        [string]$Session = "",
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Require,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Refuse,
        [System.Collections.IDictionary]$Options = @{}
    )
    if ($Fleet -cnotmatch $script:HordeConversationFleetPattern) { return (New-HordeUnknown -Reason "the horde name is not 1 to 63 of a-z, 0-9 and -, starting with a letter or digit") }
    if ($Session -ne "" -and $Session -cnotmatch $script:HordeConversationSessionPattern) { return (New-HordeUnknown -Reason "the session asked for is not 1 to 128 of A-Z, a-z, 0-9 and . _ : -") }
    if ($Vendor -ne "") {
        $one = Resolve-HordeConversationAdapter -Name $Vendor -Require $Require -Refuse $Refuse
        if ($one.state -cne "known") { return $one }
        $names = @($Vendor)
    } else {
        $fit = Find-HordeConversationAdapter -Require $Require -Refuse $Refuse
        if ($fit.state -cne "known") { return $fit }
        $names = @($fit.value)
    }
    $request = [pscustomobject]@{ fleet = $Fleet; role = "warchief"; session = $Session; options = $Options }
    $found = New-Object System.Collections.ArrayList
    $unsure = New-Object System.Collections.ArrayList
    foreach ($n in $names) {
        $adapter = $script:HordeConversationAdapters[$n]
        $a = Invoke-HordeConversationAdapter -Adapter $adapter -Op "locate" -Arguments @($request) -What "locate" -AllowAbsent
        if ($a.state -ceq "absent") { continue }
        if ($a.state -cne "known") { [void]$unsure.Add($a.reason); continue }
        $located = Get-HordeConversationMember $a.value "session"
        $locator = Get-HordeConversationMember $a.value "locator"
        if (-not $located.has -or $located.value -isnot [string] -or $located.value -cnotmatch $script:HordeConversationSessionPattern) { [void]$unsure.Add("adapter '" + $n + "' located a session whose id is not 1 to 128 of A-Z, a-z, 0-9 and . _ : -"); continue }
        if (-not $locator.has -or $locator.value -isnot [string] -or $locator.value -eq "") { [void]$unsure.Add("adapter '" + $n + "' located a session without saying where it is"); continue }
        # ASKED FOR ONE SESSION, ANSWERED ABOUT IT (A PAST SESSION BY ITS ID): another session here is the
        # adapter not knowing the request, and its answer would put the new session under the old cursor.
        if ($Session -ne "" -and $located.value -cne $Session) { [void]$unsure.Add("adapter '" + $n + "' was asked for a session by its id and located another one"); continue }
        [void]$found.Add([pscustomobject]@{ adapter = $adapter; session = $located.value; locator = $locator.value })
    }
    if ($found.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $found.Count + " adapters each locate the Thrall of horde '" + $Fleet + "' (" + (@($found | ForEach-Object { $_.adapter.name }) -join ", ") + "); one is never chosen over another")) }
    if ($unsure.Count -gt 0) { return (New-HordeUnknown -Reason ("the Thrall of horde '" + $Fleet + "' could not be located: " + ($unsure -join "; "))) }
    if ($found.Count -eq 0) { return (New-HordeAbsent -Note $(if ($Session -ne "") { "no adapter locates that session of the Thrall of horde '" + $Fleet + "'" } else { "no adapter locates a Thrall for horde '" + $Fleet + "'" })) }
    $f = $found[0]
    $src = [pscustomobject]@{ PSTypeName = "Horde.ConversationSource"; id = [guid]::NewGuid().ToString("N"); vendor = $f.adapter.name; session = $f.session; fleet = $Fleet; locator = $f.locator; adapter = $f.adapter }
    $script:HordeConversationSources[$src.id] = $src
    return (New-HordeKnown -Value $src)
}

function Test-HordeConversationSource {
    # Is this the very source object Find-HordeConversationSource made, of an adapter still registered
    # as the one it was made with? A look-alike carrying the same id is not (relays/Port.ps1's rule).
    param($Source)
    if ($null -eq $Source -or $Source -isnot [System.Management.Automation.PSCustomObject]) { return $false }
    if (@($Source.PSObject.TypeNames) -notcontains "Horde.ConversationSource") { return $false }
    $id = $Source.PSObject.Properties["id"]
    if ($null -eq $id -or $id.Value -isnot [string] -or -not $script:HordeConversationSources.ContainsKey($id.Value)) { return $false }
    if (-not [object]::ReferenceEquals($script:HordeConversationSources[$id.Value], $Source)) { return $false }
    $a = $Source.adapter
    return ($script:HordeConversationAdapters.ContainsKey($a.name) -and [object]::ReferenceEquals($script:HordeConversationAdapters[$a.name], $a))
}

function Get-HordeConversationCursorFinding {
    # Why -Cursor cannot be read from -Source, or "" when it can. $null is the start, and always can.
    param($Cursor, $Source)
    if ($null -eq $Cursor) { return "" }
    if (-not ($Cursor -is [System.Management.Automation.PSCustomObject] -or $Cursor -is [System.Collections.IDictionary])) { return "the cursor is not an object" }
    $v = Get-HordeConversationMember $Cursor "schemaVersion"
    if (-not $v.has -or -not ($v.value -is [int] -or $v.value -is [long]) -or $v.value -ne 1) { return "the cursor is not schemaVersion 1" }
    $vendor = Get-HordeConversationMember $Cursor "vendor"
    if (-not $vendor.has -or $vendor.value -isnot [string] -or $vendor.value -cne $Source.vendor) { return ("the cursor is not one of adapter '" + $Source.vendor + "'") }
    $session = Get-HordeConversationMember $Cursor "session"
    if (-not $session.has -or $session.value -isnot [string] -or $session.value -cnotmatch $script:HordeConversationSessionPattern) { return "the cursor names no session" }
    $p = Get-HordeConversationMember $Cursor "position"
    if (-not $p.has -or $p.value -isnot [string] -or $p.value.Length -gt $script:HordeConversationPositionChars -or $p.value -cnotmatch $script:HordeConversationPositionPattern) { return ("the cursor's position is not printable ASCII of at most " + $script:HordeConversationPositionChars + " characters") }
    return ""
}

function New-HordeConversationCursor {
    param([string]$Vendor, [string]$Session, [string]$Position)
    return [pscustomobject]@{ schemaVersion = 1; vendor = $Vendor; session = $Session; position = $Position }
}

function ConvertTo-HordeConversationTurn {
    # One turn an adapter handed over, checked and rebuilt, or the reason it is dropped. Returns
    # { turn; drop; notes }: notes are anomalies about a field dropped from a turn that is kept.
    param($Raw, [int]$N, $Source, [bool]$ClaimsTime)
    $at = "turn " + $N
    $notes = New-Object System.Collections.ArrayList
    if (-not ($Raw -is [System.Management.Automation.PSCustomObject] -or $Raw -is [System.Collections.IDictionary])) { return [pscustomobject]@{ turn = $null; drop = ($at + " is not an object; dropped"); notes = @() } }
    $role = Get-HordeConversationMember $Raw "role"
    if (-not $role.has -or $role.value -isnot [string] -or $script:HordeConversationRoles -cnotcontains $role.value) { return [pscustomobject]@{ turn = $null; drop = ($at + " has no role of " + ($script:HordeConversationRoles -join ", ") + "; dropped"); notes = @() } }
    $text = Get-HordeConversationMember $Raw "text"
    if (-not $text.has -or $text.value -isnot [string] -or $text.value -notmatch '\S') { return [pscustomobject]@{ turn = $null; drop = ($at + " has no text; dropped"); notes = @() } }
    $id = Get-HordeConversationMember $Raw "turnId"
    if (-not $id.has -or $id.value -isnot [string] -or $id.value -cnotmatch $script:HordeConversationIdPattern) { return [pscustomobject]@{ turn = $null; drop = ($at + " has no turnId of 1 to 200 printable characters; dropped"); notes = @() } }
    $t = [ordered]@{ role = $role.value }
    $protected = Protect-HordeSecretText -Text $text.value
    $words = $protected.text
    $cut = $false
    if ($words.Length -gt $script:HordeConversationTextChars) { $words = $words.Substring(0, $script:HordeConversationTextChars); $cut = $true }
    $t["text"] = $words
    $time = Get-HordeConversationMember $Raw "time"
    $utc = $null
    if ($time.has -and $time.value -is [string]) { $utc = ConvertTo-HordeUtcTime $time.value }
    if ($null -ne $utc) { $t["time"] = $utc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture) }
    elseif ($time.has) { [void]$notes.Add($at + " (" + $id.value + ") has a time that is not a time with a zone; kept without it") }
    elseif ($ClaimsTime) { [void]$notes.Add($at + " (" + $id.value + ") has no time, though the adapter declares timestamps") }
    $t["turnId"] = $id.value
    $g = Get-HordeConversationMember $Raw "groupId"
    if ($g.has) {
        if ($g.value -is [string] -and $g.value -cmatch $script:HordeConversationIdPattern) { $t["groupId"] = $g.value }
        else { [void]$notes.Add($at + " (" + $id.value + ") has a groupId that is not 1 to 200 printable characters; kept without it") }
    }
    if ($cut) { $t["truncated"] = $true }
    if ($protected.count -gt 0) { $t["redactions"] = [int]$protected.count }
    $t["source"] = [pscustomobject]@{ vendor = $Source.vendor; session = $Source.session; fleet = $Source.fleet }
    return [pscustomobject]@{ turn = [pscustomobject]$t; drop = ""; notes = @($notes) }
}

function Read-HordeConversationTurns {
    # The Thrall's turns after -Cursor ($null: from the start), at most -MaxTurns of them, from at most
    # -MaxBytes of new input. See the header for the answer.
    param($Source, $Cursor = $null, $MaxTurns = $script:HordeConversationDefaultTurns, $MaxBytes = $script:HordeConversationDefaultBytes)
    if (-not (Test-HordeConversationSource $Source)) { return (New-HordeUnknown -Reason "the read was not made: the source is not one Find-HordeConversationSource made") }
    $cf = Get-HordeConversationCursorFinding -Cursor $Cursor -Source $Source
    if ($cf -ne "") { return (New-HordeUnknown -Reason ("the read was not made: " + $cf)) }
    if (-not ($MaxTurns -is [int] -or $MaxTurns -is [long]) -or $MaxTurns -lt 1 -or $MaxTurns -gt $script:HordeConversationMaxTurns) { return (New-HordeUnknown -Reason ("the read was not made: the batch " + $MaxTurns + " is not from 1 to " + $script:HordeConversationMaxTurns)) }
    if (-not ($MaxBytes -is [int] -or $MaxBytes -is [long]) -or $MaxBytes -lt 1 -or $MaxBytes -gt $script:HordeConversationMaxBytes) { return (New-HordeUnknown -Reason ("the read was not made: the byte limit " + $MaxBytes + " is not from 1 to " + $script:HordeConversationMaxBytes)) }
    $position = ""
    $reset = "none"
    $anomalies = New-Object System.Collections.ArrayList
    if ($null -ne $Cursor) {
        if ((Get-HordeConversationMember $Cursor "session").value -ceq $Source.session) { $position = (Get-HordeConversationMember $Cursor "position").value }
        else { $reset = "session"; [void]$anomalies.Add("the Thrall's session changed since the cursor: the new session is read from its start, and what the old one wrote after the cursor is not read") }
    }
    $adapter = $Source.adapter
    $view = [pscustomobject]@{ vendor = $Source.vendor; session = $Source.session; locator = $Source.locator }
    $a = Invoke-HordeConversationAdapter -Adapter $adapter -Op "read" -Arguments @($view, $position, [int]$MaxTurns, [long]$MaxBytes) -What "read"
    if ($a.state -cne "known") { return $a }
    $name = $adapter.name
    $turnsM = Get-HordeConversationMember $a.value "turns"
    if (-not $turnsM.has) { return (New-HordeUnknown -Reason ("adapter '" + $name + "' answered the read without turns")) }
    # A one-element list arrives unrolled, and an empty one as $null: both are lists here.
    $raw = @()
    if ($null -ne $turnsM.value) { $raw = @($turnsM.value) }
    if ($raw.Count -gt $MaxTurns) { return (New-HordeUnknown -Reason ("adapter '" + $name + "' answered a read of " + $MaxTurns + " turns with " + $raw.Count + "; its position may be past turns that cannot be kept, so none is used")) }
    $posM = Get-HordeConversationMember $a.value "position"
    if (-not $posM.has -or $posM.value -isnot [string] -or $posM.value.Length -gt $script:HordeConversationPositionChars -or $posM.value -cnotmatch $script:HordeConversationPositionPattern) { return (New-HordeUnknown -Reason ("adapter '" + $name + "' answered the read without a position of printable ASCII, at most " + $script:HordeConversationPositionChars + " characters")) }
    $moreM = Get-HordeConversationMember $a.value "more"
    if (-not $moreM.has -or $moreM.value -isnot [bool]) { return (New-HordeUnknown -Reason ("adapter '" + $name + "' answered the read without saying, true or false, whether there is more")) }
    $resetM = Get-HordeConversationMember $a.value "reset"
    if (-not $resetM.has -or $resetM.value -isnot [string] -or @("", "rotated") -cnotcontains $resetM.value) { return (New-HordeUnknown -Reason ("adapter '" + $name + "' answered the read with a reset that is not empty or rotated")) }
    if ($resetM.value -ceq "rotated") {
        # A ROTATION FROM NO POSITION is not one: there was nothing read to be rewritten.
        if ($position -eq "") { return (New-HordeUnknown -Reason ("adapter '" + $name + "' reported a rotation on a read from the start")) }
        $reset = "rotated"
        [void]$anomalies.Add("the conversation's history was rewritten since the cursor: it is read again from its start")
    }
    $anM = Get-HordeConversationMember $a.value "anomalies"
    if ($anM.has -and $null -ne $anM.value) { foreach ($x in @($anM.value)) { [void]$anomalies.Add("adapter '" + $name + "': " + (Protect-HordeConversationNote $x)) } }
    $claimsTime = (Get-HordeConversationSupport -Adapter $adapter -Capability "timestamps") -ceq "yes"
    $out = New-Object System.Collections.ArrayList
    $ids = @{}
    $n = 0
    foreach ($r in $raw) {
        $n++
        $c = ConvertTo-HordeConversationTurn -Raw $r -N $n -Source $Source -ClaimsTime $claimsTime
        if ($c.drop -ne "") { [void]$anomalies.Add($c.drop); continue }
        foreach ($note in $c.notes) { [void]$anomalies.Add($note) }
        if ($ids.ContainsKey($c.turn.turnId)) { [void]$anomalies.Add("turn " + $n + " repeats the turnId of an earlier turn of this read; dropped"); continue }
        $ids[$c.turn.turnId] = $true
        [void]$out.Add($c.turn)
    }
    $since = $Cursor
    $next = New-HordeConversationCursor -Vendor $Source.vendor -Session $Source.session -Position $posM.value
    $value = [pscustomobject]@{ source = [pscustomobject]@{ vendor = $Source.vendor; session = $Source.session; fleet = $Source.fleet }; since = $since; next = $next
        turns = @($out.ToArray()); anomalies = @($anomalies.ToArray()); reset = $reset; more = [bool]$moreM.value }
    return (New-HordeKnown -Value $value -ObservedAt $a.observedAt)
}

function ConvertTo-HordeConversationSessionFact {
    # One of the three things an adapter says about a session - its role, label or parent - checked and
    # rebuilt as an answer of the port's own. A value that is not text of the shape asked for is unknown,
    # in words that never repeat it: it would be shown on a phone as the session's name.
    param($Fact, [string]$What, [string]$Pattern, [string]$Shape)
    if (-not (Test-HordeAnswer $Fact)) { return (New-HordeUnknown -Reason ("the adapter did not say, as an answer, what the session's " + $What + " is")) }
    if ($Fact.state -ceq "absent") { return (New-HordeAbsent -Note ("the session's record holds no " + $What)) }
    if ($Fact.state -cne "known") { return (New-HordeUnknown -Reason ("the session's " + $What + " could not be told: " + (Protect-HordeConversationNote $Fact.reason))) }
    if ($Fact.value -isnot [string] -or $Fact.value -cnotmatch $Pattern) { return (New-HordeUnknown -Reason ("the session's record holds a " + $What + " that is not " + $Shape + "; it is not shown")) }
    return (New-HordeKnown -Value $Fact.value)
}

function Get-HordeConversationSession {
    # The session -SessionId of horde -Fleet, described: known { vendor; session; fleet; label; role;
    # parent } when exactly one adapter (of those declaring sessionLookup yes, or only -Vendor when given)
    # has a record of it, and unknown otherwise, with the reason. label, role and parent are each an
    # answer of their own. See the header, A SESSION DESCRIBED BY ITS ID.
    param(
        [Parameter(Mandatory = $true)][string]$Fleet,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$SessionId,
        [string]$Vendor = "",
        [System.Collections.IDictionary]$Options = @{}
    )
    if ($Fleet -cnotmatch $script:HordeConversationFleetPattern) { return (New-HordeUnknown -Reason "the horde asked about is not named in 1 to 63 of a-z, 0-9 and -, starting with a letter or digit") }
    if ($SessionId -cnotmatch $script:HordeConversationSessionPattern) { return (New-HordeUnknown -Reason "the session id asked about is not 1 to 128 of A-Z, a-z, 0-9 and . _ : -") }
    if ($Vendor -ne "") {
        $one = Resolve-HordeConversationAdapter -Name $Vendor -Require @("sessionLookup") -Refuse @()
        if ($one.state -cne "known") { return $one }
        $names = @($Vendor)
    } else {
        $fit = Find-HordeConversationAdapter -Require @("sessionLookup") -Refuse @()
        if ($fit.state -cne "known") { return $fit }
        $names = @($fit.value)
    }
    $request = [pscustomobject]@{ fleet = $Fleet; session = $SessionId; options = $Options }
    $describers = New-Object System.Collections.ArrayList
    $doubts = New-Object System.Collections.ArrayList
    foreach ($n in $names) {
        $adapter = $script:HordeConversationAdapters[$n]
        # A CLAIM IT CANNOT KEEP: sessionLookup yes and nothing to ask. Said in the words of the cause, not as a failed call.
        if ($null -eq $adapter.describe) { [void]$doubts.Add("adapter '" + $n + "' declares sessionLookup yes and gave no Describe to ask"); continue }
        $a = Invoke-HordeConversationAdapter -Adapter $adapter -Op "describe" -Arguments @($request) -What "session lookup" -AllowAbsent
        if ($a.state -ceq "absent") { continue }
        if ($a.state -cne "known") { [void]$doubts.Add($a.reason); continue }
        # ASKED ABOUT ONE SESSION, ANSWERED ABOUT IT: another id here would put one session's label on
        # another's file (the rule of A PAST SESSION BY ITS ID).
        $described = Get-HordeConversationMember $a.value "session"
        if (-not $described.has -or $described.value -isnot [string] -or $described.value -cne $SessionId) { [void]$doubts.Add("adapter '" + $n + "' was asked about one session and answered about another"); continue }
        [void]$describers.Add([pscustomobject]@{ adapter = $adapter; value = $a.value; observedAt = $a.observedAt })
    }
    if ($describers.Count -gt 1) { return (New-HordeUnknown -Reason ("" + $describers.Count + " adapters each describe session '" + $SessionId + "' (" + (@($describers | ForEach-Object { $_.adapter.name }) -join ", ") + "); one is never chosen over another")) }
    if ($doubts.Count -gt 0) { return (New-HordeUnknown -Reason ("session '" + $SessionId + "' of horde '" + $Fleet + "' could not be described: " + ($doubts -join "; "))) }
    if ($describers.Count -eq 0) { return (New-HordeUnknown -Reason ("no adapter has a record of session '" + $SessionId + "' for horde '" + $Fleet + "'")) }
    $f = $describers[0]
    $rolePattern = '\A(?:' + (@((Get-HordeRoleTable).native | ForEach-Object { [regex]::Escape($_) }) -join "|") + ')\z'
    $value = [pscustomobject]@{ vendor = $f.adapter.name; session = $SessionId; fleet = $Fleet
        label = (ConvertTo-HordeConversationSessionFact -Fact (Get-HordeConversationMember $f.value "label").value -What "label" -Pattern $script:HordeConversationLabelPattern -Shape "one or two capital letters, then a number from 1 to 9999 or nothing")
        role = (ConvertTo-HordeConversationSessionFact -Fact (Get-HordeConversationMember $f.value "role").value -What "role" -Pattern $rolePattern -Shape "a role of this horde")
        parent = (ConvertTo-HordeConversationSessionFact -Fact (Get-HordeConversationMember $f.value "parent").value -What "parent" -Pattern $script:HordeConversationSessionPattern -Shape "a session id") }
    return (New-HordeKnown -Value $value -ObservedAt $f.observedAt)
}
