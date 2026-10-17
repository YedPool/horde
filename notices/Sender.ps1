# notices/Sender.ps1 - WHO is running `horde notify`, PROVEN, and the name the founder sees for it.
#
# THE RULE (brief of 2026-10-14): the sender of a notice is the session's own label, and a caller must
# never be able to claim to be another session. So `horde notify` takes NO name from its caller - it
# has no -From and no -Label - and the name is worked out here, from facts the caller cannot choose.
#
# HOW IT IS PROVEN, three steps, each one a reader the repository already has:
#   1. THE CLAIM. core/Identity.ps1's Get-HordeSelfSessionId: the agent's own export of its session id
#      in this process's environment. ONLY A CLAIM: a caller can set that variable to any session's id
#      before it runs the command.
#   2. THAT SESSION'S PROCESS. core/Identity.ps1's Get-HordeIdentity reads every agent's own control
#      files and verifies the process behind each (its pid, and that the pid's start time is the one
#      the file names). The claimed session must be among the verified running ones; its pid is then
#      the process of THAT session, whoever is asking.
#   3. THAT PROCESS IS AN ANCESTOR OF THIS ONE. From this process up through each parent (the process
#      table's parent pid, core/Platform.ps1), until that pid is reached. A session's own commands run
#      below its own process; another session's process is never above them. So a caller who sets the
#      variable to another session's id names a process that is not its ancestor, and is refused.
#      EACH PARENT MUST HAVE STARTED NO LATER THAN ITS CHILD: Windows records the parent's pid when a
#      process starts and never updates it, so after the parent ends the number may name a process
#      started since, under the same pid - a stranger, not a parent. Such a step ends the walk.
#      The walk stops after 64 steps; a deeper chain is no session's.
# THE NAME, once proven: the session's label in the fleet's registry (core/WezfleetState.ps1's
# Read-HordeRegistry, the record of that session id - an Orc's letter, say), else the agent's own name
# for the session (Get-HordeIdentity's name field), else refused: a notice from nobody the founder can
# name is the "id without its name" the brief forbids.
#
# WHAT THIS DOES NOT STOP, said plainly: a program running as the same Windows user can write the agent's
# control files or the registry itself. Sessions are not adversaries with the user's own power; the
# danger this closes is a session naming another BY MISTAKE or by an argument, which is now impossible.
# An agent that writes no pid in its control files cannot be proven, and its sessions are refused in
# words.
#
# EVERY SOURCE IS A PARAMETER (as core/Identity.ps1's are), so a suite hands in its own environment,
# process table and registry, and its own control folders as -Identity (Get-HordeIdentity's own
# parameters, handed on as they are: this file names no agent), and never reads this machine's.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Identity.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\WezfleetState.ps1")

$script:HordeNoticeAncestorSteps = 64

function Test-HordeNoticeAncestor {
    # Is -Ancestor this process's ancestor (step 3, in the header)? { ok; reason }. -Table is the process
    # table's value (pid -> { pid; parent; created }); -Self the process to walk up from.
    param([Parameter(Mandatory = $true)][hashtable]$Table, [Parameter(Mandatory = $true)][int]$Self, [Parameter(Mandatory = $true)][int]$Ancestor)
    if (-not $Table.ContainsKey($Self)) { return [pscustomobject]@{ ok = $false; reason = ("this process (" + $Self + ") is not in the process table") } }
    $child = $Table[$Self]
    for ($i = 0; $i -lt $script:HordeNoticeAncestorSteps; $i++) {
        $up = $child.PSObject.Properties["parent"]
        if ($null -eq $up -or $up.Value -isnot [int] -or $up.Value -le 0) { return [pscustomobject]@{ ok = $false; reason = ("the process table does not say what started process " + $child.pid) } }
        $parentPid = [int]$up.Value
        if (-not $Table.ContainsKey($parentPid)) { return [pscustomobject]@{ ok = $false; reason = ("the session's process is not above this one: the walk up ended at process " + $child.pid + ", whose parent has ended") } }
        $parent = $Table[$parentPid]
        # A PARENT NEVER STARTED AFTER ITS CHILD (the header): such a pid was taken again by a stranger.
        if ($null -eq $parent.created -or $null -eq $child.created -or $parent.created -gt $child.created) { return [pscustomobject]@{ ok = $false; reason = ("the session's process is not above this one: process " + $parentPid + " started after process " + $child.pid + ", so it is not the one that started it") } }
        if ($parentPid -eq $Ancestor) { return [pscustomobject]@{ ok = $true; reason = "" } }
        $child = $parent
    }
    return [pscustomobject]@{ ok = $false; reason = ("the session's process is not within " + $script:HordeNoticeAncestorSteps + " processes above this one") }
}

function Get-HordeNoticeConfusables {
    # THE ONE TABLE: what each printable ASCII character reads as when a label is skeletonised. Letters read as themselves
    # (lower-cased); the look-alikes of letters read as the letter; every other printable ASCII character reads as nothing.
    # A function, not a $script: variable, because this file is dot-sourced inside command blocks (core/Tristate.ps1).
    $map = @{}
    foreach ($code in 97..122) { $c = [string][char]$code; $map[$c] = $c }   # not 'a'..'z': Windows PowerShell 5.1 has no character ranges
    foreach ($c in '|', '!', '1', 'l') { $map["$c"] = 'i' }
    foreach ($c in '$', '5') { $map["$c"] = 's' }
    foreach ($c in '(', '<', '[', '{') { $map["$c"] = 'c' }
    $map['u'] = 'v'
    $map['0'] = 'o'
    $map['3'] = 'e'
    $map['7'] = 't'
    return $map
}

function Test-HordeWithinOneEdit {
    # Is -A within edit distance 1 of -B: equal, or one substitution, one insertion or one deletion?
    param([string]$A, [string]$B)
    if ($A -ceq $B) { return $true }
    if ([Math]::Abs($A.Length - $B.Length) -gt 1) { return $false }
    $i = 0
    while ($i -lt $A.Length -and $i -lt $B.Length -and $A[$i] -ceq $B[$i]) { $i++ }
    if ($A.Length -eq $B.Length) { return ($A.Substring($i + 1) -ceq $B.Substring($i + 1)) }
    if ($A.Length -gt $B.Length) { return ($A.Substring($i + 1) -ceq $B.Substring($i)) }
    return ($A.Substring($i) -ceq $B.Substring($i + 1))
}

function Test-HordeNoticeServiceForm {
    # Does -Label read as a service's? Labels that READ LIKE "service" at their start are reserved for registered services,
    # whatever follows. TWO LAYERS, because a list of spellings is never finished:
    #   (a) the label is skeletonised through the one table above (look-alikes read as their letter, every other character is dropped);
    #   (b) it is refused when a prefix of that skeleton of 6, 7 or 8 letters is within one edit of "service" (one letter changed,
    #       added or missing: "servce", "serrvice", "sxrvice", "servise"). "server" and "serene" are more than one edit away.
    # ASCII only: a label that is not printable ASCII is never shown as itself (Get-HordeNoticeShownLabel).
    param([AllowEmptyString()][string]$Label)
    $map = Get-HordeNoticeConfusables
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $Label.ToLowerInvariant().ToCharArray()) {
        $k = "$c"
        if ($map.ContainsKey($k)) { [void]$sb.Append($map[$k]) }
    }
    $sk = $sb.ToString()
    foreach ($n in 6, 7, 8) {
        if ($sk.Length -ge $n -and (Test-HordeWithinOneEdit -A $sk.Substring(0, $n) -B "service")) { return $true }
    }
    return $false
}
function Get-HordeNoticeShownLabel {
    # The label as the founder may see it: only if it is printable ASCII (0x20-0x7E) - every real fleet label is. Anything else (a
    # look-alike script, a filler, another alphabet) is shown as the neutral "a session": the proof of WHICH session it is stays,
    # only its text is not displayed (PR 332, third review: no end to Unicode look-alikes, so none is shown).
    param([AllowEmptyString()][string]$Label)
    if ($Label -cmatch '[^\x20-\x7E]') { return "a session" }
    return $Label
}
function Remove-HordeNoticeInvisible {
    # -Text without what the founder cannot see: control and format characters, combining marks and variation selectors - by
    # code point, so the supplementary tag characters go too.
    param([AllowEmptyString()][string]$Text)
    $bad = @([System.Globalization.UnicodeCategory]::Control, [System.Globalization.UnicodeCategory]::Format, [System.Globalization.UnicodeCategory]::NonSpacingMark, [System.Globalization.UnicodeCategory]::EnclosingMark)
    $sb = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $Text.Length) {
        $step = $(if ([char]::IsHighSurrogate($Text[$i]) -and ($i + 1) -lt $Text.Length -and [char]::IsLowSurrogate($Text[$i + 1])) { 2 } else { 1 })
        $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($Text, $i)
        if ($cat -eq [System.Globalization.UnicodeCategory]::Control) { [void]$sb.Append(" ") }
        elseif ($bad -notcontains $cat) { [void]$sb.Append($Text.Substring($i, $step)) }
        $i += $step
    }
    return $sb.ToString()
}
function Resolve-HordeNoticeSender {
    # The proven sender of a notice: { ok; reason; sessionId; label }. ok $false with the reason in words
    # whenever any step of the header does not hold - never a guess and never another session's name.
    param(
        [System.Collections.IDictionary]$Environment = [System.Environment]::GetEnvironmentVariables(),
        [hashtable]$Identity = @{},
        $Processes = $null,
        [string]$RegistryRoot = (Get-HordeWezfleetRoot),
        [int]$Self = $PID
    )
    $no = { param([string]$Why) return [pscustomobject]@{ ok = $false; reason = $Why; sessionId = ""; label = "" } }
    $claim = Get-HordeSelfSessionId -Environment $Environment
    if ($claim.state -cne "known") { return (& $no ("no notice was sent: this is not run from inside a session (" + $claim.reason + "). A notice is sent by the session the founder asked to tell him.")) }
    $sid = "$($claim.value)"
    if ($null -eq $Processes) { $Processes = Get-HordeProcessTable }
    if ($Processes.state -cne "known") { return (& $no ("no notice was sent: the process table could not be read, so which session is asking cannot be proven (" + $Processes.reason + ")")) }
    $id = Get-HordeIdentity @Identity -Processes $Processes
    if (-not $id.records.ContainsKey($sid)) { return (& $no ("no notice was sent: no running session's own file names the session " + $sid + ", so it cannot be proven to be the one asking")) }
    $verified = $(if ($id.verifiedLive.state -ceq "known") { @($id.verifiedLive.value) } else { @() })
    if (@($verified | Where-Object { "$_" -ieq $sid }).Count -eq 0) { return (& $no ("no notice was sent: the process of session " + $sid + " could not be verified as running (" + $(if ($id.verifiedLive.state -ceq "known") { "its file names a process that is gone or is another now" } else { $id.verifiedLive.reason }) + ")")) }
    $pidAnswer = $id.records[$sid].fields["pid"]
    if ($pidAnswer.state -cne "known") { return (& $no ("no notice was sent: the session " + $sid + " has no process this machine can check (" + $pidAnswer.reason + ")")) }
    $up = Test-HordeNoticeAncestor -Table $Processes.value -Self $Self -Ancestor ([int]$pidAnswer.value)
    if (-not $up.ok) { return (& $no ("no notice was sent: this command does not run inside session " + $sid + " - " + $up.reason + ". A session sends notices only as itself.")) }
    # THE NAME (the header): the registry's label, else the agent's own name for the session.
    $label = ""
    $labelSource = ""
    $reg = Read-HordeRegistry -Root $RegistryRoot
    if ($reg.records.ContainsKey($sid)) {
        $l = Get-HordeStoredField -Record $reg.records[$sid].record -Name "label"
        if ($l.state -ceq "known" -and $l.value -is [string]) { $label = $l.value.Trim(); if ($label -cne "") { $labelSource = "registry" } }
    }
    if ($label -ceq "") {
        $n = $id.records[$sid].fields["name"]
        if ($n.state -ceq "known" -and $n.value -is [string]) { $label = $n.value.Trim(); $labelSource = "agent-name" }
    }
    # Format characters are not part of any name the founder reads (they are invisible): dropped from what is shown, too.
    $label = (Remove-HordeNoticeInvisible -Text $label).Trim()
    if ($label -ceq "") { return (& $no ("no notice was sent: session " + $sid + " has no label in the fleet's registry and no name of its own, so the founder could not tell who it is from. Give the session a name first.")) }
    # A SERVICE'S LABEL IS NOT A SESSION'S TO TAKE (notices/Services.ps1): a session labelled "service: x"
    # would look to the founder like the service x.
    $label = Get-HordeNoticeShownLabel -Label $label
    if (Test-HordeNoticeServiceForm -Label $label) { return (& $no ("no notice was sent: session " + $sid + " has a label that starts with ''service'': labels starting with ''service'' are reserved for registered services, which are shown as ''service: <name>''")) }
    if ($label.Length -gt 40) { $label = $label.Substring(0, 40).TrimEnd() }
    # labelSource: "registry" (a fleet label) or "agent-name" (the agent's own name for the session). A registrar must have the first (notices/Services.ps1).
    return [pscustomobject]@{ ok = $true; reason = ""; sessionId = $sid; label = $label; labelSource = $labelSource }
}
