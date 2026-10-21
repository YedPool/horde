# core/identity - every agent's own control files, read into one record shape. No terminal in it.
#
# WHAT THIS IS. Each agent keeps a file per running session that it writes itself: Claude Code keeps
# ~/.claude/sessions/<pid>.json, and wezfleet's codex hook keeps <wezfleet root>\codex-sessions\
# <sessionId>.json. Those files are the agent's own account of the session - its id, directory,
# name and live status - so they are the authoritative source for every field core/ownership.json
# gives to the agent (planning/ledger/core-identity.md). This module reads them, one reader per
# agent, and returns records keyed by session id whose fields are all core/tristate answers.
#
# WHAT IT NEVER DOES. It writes no file, opens none for writing, and never stops a process. Files are
# read through Read-HordeSharedText, which shares read, write and delete so the agent writing a
# file is never blocked by Horde reading it. The process table is read through CIM, read-only.
#
# THREE RULES THE OLD READERS BROKE, and this module is built around:
#   - A LISTING IS COMPLETE OR IT SAYS WHY NOT. wezfleet's readers returned the same empty map for a
#     missing directory as for an idle fleet, and skipped an unparseable file silently, so one bad
#     file made the fleet shorter instead of unknown (lib/MailPump.ps1:58-60). Here every file that
#     is unreadable or refused makes that agent's listing unknown, naming the file.
#   - A PID IS THE SAME PROCESS ONLY WHILE ITS START TIME IS. Windows reuses pids. Claude writes
#     procStart, the process's creation time in file-time ticks, and on 2026-09-30 it equalled the
#     live process's start time in 10 of 10 files. wezfleet never compared it (0 hits for procStart).
#     So a live field - status, pid, procStart, messaging address - is known only when the pid is
#     running AND its creation time equals procStart at microsecond precision, the precision CIM
#     reports it in. Otherwise it is unknown and says whether the process is gone or the pid reused.
#   - TWO FILES NAMING ONE SESSION IS A FINDING, NEVER A CHOICE. wezfleet's two readers kept the
#     first and the last file respectively (lib/Mail.ps1:106-108, lib/MailPump.ps1:62). Here neither
#     is kept; both are reported, and the listing is incomplete because it omits that session.
#
# THE KEY IS THE SESSION ID. Measured 2026-09-30: 12 compactions inside 7 live processes kept the
# id, and 51 compaction boundaries across 265 transcripts show no second id (core-ownership L-047).
# Whether /clear gives the process a new id is unmeasured, so a former name naming another id is
# reported, not merged, and formerNames is marked provisional on the record.
#
# EVERY SOURCE IS A PARAMETER. Each reader takes its directory, and the process table, as
# parameters, so a test injects both and never reads this machine (YedPool/wezfleet lib/Protocol.ps1
# once had four assertions change answer with the live process list). The defaults read the real box.

# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1). The functions run under -Version Latest.
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
# The process table is the platform's (core/Platform.ps1): the one place the operating system is asked.
. (Join-Path $PSScriptRoot "Platform.ps1")
# Where a pid belongs (remote plan R11): the process check never looks up another device's pid.
. (Join-Path $PSScriptRoot "Namespace.ps1")
# For Get-HordeWezfleetRoot: one definition of where wezfleet's store is, shared with core/roles.
. (Join-Path $PSScriptRoot "Roles.ps1")

# The fields core/ownership.json gives to the agent, sessionId aside (it is the record's key). Every
# record carries exactly these, as answers; test/test-identity.ps1 checks the list against the table.
$script:HordeIdentityFields = @("agent", "pid", "procStart", "cwd", "transcriptPath", "resumeCommand", "name", "nameSource",
    "nameSince", "formerNames", "liveStatus", "waitingFor", "startedAt", "messagingAddress", "bridgeSessionId", "agentVersion",
    "peerProtocol", "peerFeatures", "sessionKind", "entrypoint", "pidDomain")
# How long a codex status reading is believed: wezfleet's default, lib/CodexStatus.ps1:68.
$script:HordeCodexTtlDefault = 900
# The statuses each agent is seen to write. Anything else is not guessed at. waiting is Claude's
# status while it waits on the user: 1 of 10 control files on 2026-09-30, beside waitingFor
# (core-identity L-055). The 2.1.285 binary can also write shell to its terminal-tab status; no
# control file has shown it, so it stays unknown.
$script:HordeClaudeStatuses = @("idle", "busy", "waiting")
$script:HordeCodexStatuses = @("idle", "busy", "ended")
# The process names an orphan is looked for under, and the names of a host Claude Code can run
# inside. PROVISIONAL: claude.exe is the only name seen (11 claude.exe processes on 2026-09-30, all
# the census found); a Claude run under node is not named claude, so a node process no file verifies
# makes the orphan answer unknown rather than a list that may be short (review finding 2 of PR #19).
$script:HordeClaudeProcessNames = @("claude.exe", "claude")
$script:HordeClaudeHostNames = @("node.exe", "node")
$script:HordeOrphanProvisional = "an orphan is looked for under the process names claude.exe and claude, the only ones seen; Claude Code can also run under node, which the name does not identify, so a node process no control file verifies makes the answer unknown"
$script:HordeFormerNamesProvisional = "compaction keeps the session id (core-ownership L-047), but whether /clear gives the process a new id is unmeasured, so a former name's sessionId is carried as written and never merged"

function Get-HordeClaudeSessionsDir { return (Join-Path $env:USERPROFILE ".claude\sessions") }
function Get-HordeClaudeProjectsDir { return (Join-Path $env:USERPROFILE ".claude\projects") }
function Get-HordeCodexSessionsDir { return (Join-Path (Get-HordeWezfleetRoot) "codex-sessions") }

function Test-HordeSessionId {
    # Is this a session id that may become a key or a file name? The pattern wezfleet uses for both
    # codex file names and mail directories (lib/CodexStatus.ps1:196, lib/Mail.ps1:151): refused
    # rather than sanitised, because a silently altered id keys a session that does not exist.
    #
    # WIDER THAN THE STORED RECORD. schema/session-record.v1 (PR #16) takes only a UUID as a
    # sessionId, while this accepts any 1-128 of [A-Za-z0-9._-], because codex ids and wezfleet's
    # own checks allow that. So a record identity keys here may be one the engine's store refuses;
    # which rule wins is for step 2.2, where identity feeds the store (review finding 9 of PR #19).
    param($Id)
    return ($Id -is [string] -and $Id -cmatch '^[A-Za-z0-9._-]{1,128}$')
}

function ConvertTo-HordeClaudeProjectKey {
    # The directory name Claude keeps a cwd's transcripts under: every character that is not an ASCII
    # letter or digit becomes a dash. wezfleet replaced only colons and slashes (lib/Registry.ps1:103),
    # which is wrong for any cwd with a space, underscore or dot; the 149 project directories on the
    # measuring machine held 0 of any of them (core-ownership L-049).
    param([Parameter(Mandatory = $true)][string]$Cwd)
    return ($Cwd -creplace '[^A-Za-z0-9]', '-')
}

function Get-HordeCodexTtlSeconds {
    # wezfleet's rule (lib/CodexStatus.ps1:75-84): an override that is not a positive integer is
    # IGNORED, not honoured. core/tristate's Limit-HordeAge throws on such a TTL instead, so the
    # fallback has to happen here, before it is called - for the environment's override and for a
    # TTL passed in alike. The parse is wezfleet's: [int]::TryParse with no style is
    # NumberStyles.Integer, which allows white space around the digits and a leading sign, so "+60"
    # and " 60" are 60 in both (review finding 4 of PR #19). One difference is kept: wezfleet parses
    # in the current culture, this in the invariant one, which differs only for a culture whose sign
    # symbols are not + and -.
    param($Value = $env:WEZFLEET_CODEX_STATUS_TTL)
    $n = 0
    if ("$Value" -ne "" -and [int]::TryParse("$Value", [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n) -and $n -gt 0) { return $n }
    return $script:HordeCodexTtlDefault
}

function Get-HordeProcessTable {
    # The running processes as an answer: known @{ [int]pid = { pid; name; created; commandLine } },
    # created in UTC, or unknown with the reason - read through the platform seam, so a node on
    # another system supplies its own (second review of PR #31, finding 5). Unknown is not empty:
    # wezfleet's Get-WfClaudeProcesses returned an empty list when the query failed
    # (lib/Common.ps1:657-659), which a caller cannot tell from no processes. What the Windows reader
    # measured about creation times is with it, in core/Platform.ps1.
    return (Read-HordePlatformProcessTable -Platform (Get-HordeLocalPlatform))
}

function ConvertTo-HordeMicroseconds {
    # A time at microsecond precision, by integer division. Never `/`: PowerShell divides two longs
    # as doubles, and a tick count has 18 digits where a double holds about 16 (CONTRIBUTING 12).
    param([datetime]$Time)
    $rem = [long]0
    return [Math]::DivRem([long]$Time.ToUniversalTime().Ticks, [long]10, [ref]$rem)
}

function ConvertFrom-HordeEpochMs {
    # An agent's time - epoch milliseconds, an integer in every census file - as a UTC [datetime],
    # or $null when it is not one.
    param($Value)
    if ($Value -isnot [int] -and $Value -isnot [long]) { return $null }
    try { return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$Value).UtcDateTime } catch { return $null }
}

function Get-HordeTimeField {
    # A field holding an agent time, as an answer carrying a [datetime].
    param($Record, [string]$Name)
    $f = Get-HordeField -Record $Record -Name $Name
    if ($f.state -ne "known") { return $f }
    $t = ConvertFrom-HordeEpochMs $f.value
    if ($null -eq $t) { return (New-HordeUnknown -Reason ("'" + $Name + "' is not a time in epoch milliseconds: '" + $f.value + "'")) }
    return (New-HordeKnown -Value $t -ObservedAt $null)
}

function Get-HordeProcessVerdict {
    # Is the process a control file describes still the one running under its pid? Returns
    # { same; kind; reason }: same is $true only when the pid is running and its creation time equals
    # procStart to the microsecond. kind says which case it is, for callers to act on; the reason is
    # for people. Callers choose by kind, never by words in the reason (review finding 3 of PR #19):
    #   verified     the pid is running and is the process the file describes
    #   gone         the pid is not running: the file is stale
    #   reused       the pid is running but started at another time: the file is stale
    #   uncheckable  procStart is missing or not a file time, or the table gives no start time
    #   no-table     the process table could not be read
    #   remote       the pid belongs to another device or another process space, so this table is
    #                never consulted for it (remote plan R11, core/Namespace.ps1)
    #
    # procStart is a DECIMAL STRING of file-time ticks on disk (10 of 10 files, 2026-09-30), so it is
    # parsed as an integer and compared as one: as text, "0" + the same ticks would be another time.
    #
    # -Namespace and -Local place the pid (R11). A caller that names no namespace checks a pid of this
    # machine's own table, as every caller of 2026-10-02 does: the control files it reads are local.
    # One that names one is refused before the table is touched unless the pid is this device's, in
    # this table's space: pid 1234 on another machine is not pid 1234 here.
    param([int]$ProcId, $ProcStart, $Processes, $Namespace = $null, $Local = $null)
    #
    # A namespace without this machine's is not checked against nothing: -Namespace given alone is
    # uncheckable, never looked up (review of this PR: "-or" mutated to "-and" looked it up).
    # LIMIT, written down: -Local is the caller's word. The table does not yet carry the namespace it
    # was read in, so a caller that names another device as local is believed. That moves into the
    # table when a remote pid can reach this code (R12, R13).
    if ($null -ne $Namespace -or $null -ne $Local) {
        $placed = Test-HordeNamespaceLocal -Namespace $Namespace -Local $Local
        if ($placed.state -ne "known") { return [pscustomobject]@{ same = $false; kind = "uncheckable"; reason = $placed.reason } }
        if ($placed.value -ne $true) { return [pscustomobject]@{ same = $false; kind = "remote"; reason = $placed.reason } }
    }
    if ($Processes.state -ne "known") { return [pscustomobject]@{ same = $false; kind = "no-table"; reason = ("the process table could not be read (" + $Processes.reason + ")") } }
    $ticks = [long]0
    if ($null -eq $ProcStart -or -not [long]::TryParse("$ProcStart", [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ticks)) {
        return [pscustomobject]@{ same = $false; kind = "uncheckable"; reason = ("procStart '" + $ProcStart + "' is not an integer tick count, so the process cannot be checked") }
    }
    $fileTime = $null
    try { $fileTime = [DateTime]::FromFileTimeUtc($ticks) } catch { return [pscustomobject]@{ same = $false; kind = "uncheckable"; reason = ("procStart " + $ticks + " is not a file time") } }
    $table = $Processes.value
    if (-not $table.ContainsKey($ProcId)) {
        return [pscustomobject]@{ same = $false; kind = "gone"; reason = ("process " + $ProcId + " is not running, so this control file is stale") }
    }
    $proc = $table[$ProcId]
    if ($null -eq $proc.created) { return [pscustomobject]@{ same = $false; kind = "uncheckable"; reason = ("the process table gives no start time for pid " + $ProcId) } }
    if ((ConvertTo-HordeMicroseconds $proc.created) -ne (ConvertTo-HordeMicroseconds $fileTime)) {
        return [pscustomobject]@{ same = $false; kind = "reused"; reason = ("pid " + $ProcId + " was reused: it now belongs to a process started " + $proc.created.ToString("o") + ", not the one this file describes (" + $fileTime.ToString("o") + ")") }
    }
    return [pscustomobject]@{ same = $true; kind = "verified"; reason = "" }
}

function New-HordeIdentityRecord {
    # A record: the session id plainly, the file it came from, the kind of process check its file
    # passed or failed (Get-HordeProcessVerdict; "unchecked" for an agent that writes no pid), and
    # every agent-owned field as an answer - unknown with $Missing's reason for each field this agent
    # does not write.
    param([string]$SessionId, [string]$Source, [hashtable]$Known, [string]$Missing, [hashtable]$Provisional, [string]$ProcessCheck)
    $fields = [ordered]@{}
    foreach ($n in $script:HordeIdentityFields) {
        if ($Known.ContainsKey($n)) { $fields[$n] = $Known[$n] }
        else { $fields[$n] = New-HordeUnknown -Reason ($Missing + " " + $n) }
    }
    return [pscustomobject]@{ PSTypeName = "Horde.IdentityRecord"; sessionId = $SessionId; source = $Source; processCheck = $ProcessCheck; fields = $fields; provisional = $Provisional }
}

function Get-HordeControlFiles {
    # The *.json files of a control directory, or the reason there are none to read. A missing or
    # unlistable directory is a gap, never an empty listing: wezfleet's readers returned an empty map
    # for both (lib/MailPump.ps1:58, lib/CodexStatus.ps1:218) while their callers said an empty map
    # means UNKNOWN (lib/MailPump.ps1:53-54).
    #
    # Only the extension .json: the key files Claude keeps beside each control file
    # (<pid>.<64 hex>.key, census 2026-09-30) are never opened.
    param([string]$Dir, [string]$Agent, $Gaps)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        [void]$Gaps.Add("there is no " + $Agent + " control directory at " + $Dir + "; that is unknown, not an empty fleet")
        return @()
    }
    try { return @(Get-ChildItem -LiteralPath $Dir -File -ErrorAction Stop | Where-Object { $_.Extension -eq ".json" }) }
    catch { [void]$Gaps.Add("the " + $Agent + " control directory could not be listed: " + $_.Exception.Message); return @() }
}

function Read-HordeControlJson {
    # One control file, parsed, or $null with the reason added to Gaps - or, for a file that was
    # listed and is gone by the time it is opened, its name added to Vanished instead.
    param($File, $Gaps, $Vanished)
    $obj = $null
    try { $obj = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $File.FullName) }
    catch {
        # GONE IS NOT UNREADABLE. Claude removes a session's file when the session exits, so on a
        # live machine a listed file can be gone a moment later: the session exited during the read,
        # and the listing is still whole for every session that is running (review finding 5 of
        # PR #19). A file that is still there and cannot be read is a gap.
        if (-not (Test-Path -LiteralPath $File.FullName)) { [void]$Vanished.Add($File.Name); return $null }
        [void]$Gaps.Add($File.Name + " could not be read: " + $_.Exception.Message); return $null }
    if ($null -eq $obj -or $obj -isnot [System.Management.Automation.PSCustomObject]) {
        [void]$Gaps.Add($File.Name + " is not a JSON object"); return $null
    }
    return $obj
}

function New-HordeAgentRead {
    # What one agent's reader returns: { agent; entries; complete; verified; orphans; findings }.
    param([string]$Agent, $Entries, $Gaps, $Verified, $Orphans, $Findings)
    $complete = New-HordeKnown -Value $true
    if ($Gaps.Count -gt 0) { $complete = New-HordeUnknown -Reason (@($Gaps) -join "; ") }
    return [pscustomobject]@{ PSTypeName = "Horde.AgentRead"; agent = $Agent; entries = @($Entries); complete = $complete
                              verified = @($Verified); orphans = $Orphans; findings = @($Findings) }
}

function Read-HordeClaudeControlFiles {
    # Claude Code's control files: ~/.claude/sessions/<pid>.json, one per running session, written by
    # the session itself. Returns what New-HordeAgentRead describes; verified lists the session ids
    # whose process was checked and is the one the file describes.
    param(
        [string]$Dir = (Get-HordeClaudeSessionsDir),
        $Processes = (Get-HordeProcessTable),
        [string]$ProjectsDir = (Get-HordeClaudeProjectsDir)
    )
    Assert-HordeProcessTable $Processes
    $gaps = New-Object System.Collections.ArrayList
    $findings = New-Object System.Collections.ArrayList
    $entries = New-Object System.Collections.ArrayList
    $verified = New-Object System.Collections.ArrayList
    $verifiedPids = @{}
    $vanished = New-Object System.Collections.ArrayList
    $uncheckablePids = @{}
    # WHICH PROCESSES MAY BE THIS AGENT, by image, read once: imagePids its own image, hostPids an image
    # it can run inside. The orphan answer below reads them, and so does a node deciding whether a stale
    # file's end is proven (core/Projection.ps1, Get-HordeSessionEndProof), so the image names stay
    # here, in the one reader that already holds them.
    $imagePids = @{}
    $hostPids = @{}
    if ($Processes.state -eq "known") {
        foreach ($p in $Processes.value.Values) {
            if ($script:HordeClaudeProcessNames -icontains "$($p.name)") { $imagePids[[int]$p.pid] = $true }
            elseif ($script:HordeClaudeHostNames -icontains "$($p.name)") { $hostPids[[int]$p.pid] = $true }
        }
    }
    foreach ($f in (Get-HordeControlFiles -Dir $Dir -Agent "claude" -Gaps $gaps)) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        # THE FILE IS NAMED BY ITS PID, and one that disagrees with its own pid is refused: 10 of 10
        # agreed on 2026-09-30, and wezfleet keyed by the pid field without ever looking at the name
        # (lib/Mail.ps1:144), so a copied or stale file would have been read as another process.
        if ($base -notmatch '^[0-9]{1,9}$') { [void]$gaps.Add($f.Name + " is not named by a pid, so it is not a control file this reader knows"); continue }
        $j = Read-HordeControlJson -File $f -Gaps $gaps -Vanished $vanished
        if ($null -eq $j) { continue }
        $pidField = Get-HordeField -Record $j -Name "pid"
        if ($pidField.state -ne "known" -or ($pidField.value -isnot [int] -and $pidField.value -isnot [long]) -or "$($pidField.value)" -ne $base) {
            [void]$gaps.Add($f.Name + " names pid '" + $(if ($pidField.state -eq "known") { $pidField.value } else { "" }) + "', not its own file name, so it was refused"); continue
        }
        $sidField = Get-HordeField -Record $j -Name "sessionId"
        if ($sidField.state -ne "known") { [void]$gaps.Add($f.Name + " has no session id, so it was refused"); continue }
        if (-not (Test-HordeSessionId $sidField.value)) { [void]$gaps.Add($f.Name + " has a malformed session id, so it was refused"); continue }
        $sid = $sidField.value
        $procId = [int]$base

        $procStartField = Get-HordeField -Record $j -Name "procStart"
        $procStartRaw = $null
        if ($procStartField.state -eq "known") { $procStartRaw = $procStartField.value }
        $verdict = Get-HordeProcessVerdict -ProcId $procId -ProcStart $procStartRaw -Processes $Processes
        if ($verdict.kind -ceq "uncheckable") { $uncheckablePids[$procId] = $true }
        if ($verdict.same) { [void]$verified.Add($sid); $verifiedPids[$procId] = $true }
        # A stale file and a file that cannot be checked are both findings. An unreadable process
        # table is not one per file: it is said once, in verifiedLive and the orphan answer.
        elseif (@("gone", "reused", "uncheckable") -ccontains $verdict.kind) { [void]$findings.Add($f.Name + ": " + $verdict.reason) }

        $k = @{}
        $k["agent"] = New-HordeKnown -Value "claude"
        # THE LIVE FIELDS are facts about a running process, so they are known only for the process
        # the file describes. The identity fields below stay known as written: a stale file still says
        # truthfully which session, directory and name that process had.
        if ($verdict.same -eq $true) {
            $k["pid"] = New-HordeKnown -Value $procId
            $k["procStart"] = New-HordeKnown -Value ([long]::Parse("$procStartRaw", [System.Globalization.CultureInfo]::InvariantCulture))
            # Carried as the agent's own messaging address: the pipe is the agent's undocumented
            # internal channel (YedPool/wezfleet 648095e), so Horde carries it and never writes to it.
            $k["messagingAddress"] = Get-HordeField -Record $j -Name "messagingSocketPath"
            # Live status is what the session says about itself, observed at the time it wrote it
            # (statusUpdatedAt, epoch ms). Only the values seen on disk are believed.
            $st = Get-HordeField -Record $j -Name "status"
            if ($st.state -ne "known") { $k["liveStatus"] = $st }
            elseif ($script:HordeClaudeStatuses -cnotcontains "$($st.value)") { $k["liveStatus"] = New-HordeUnknown -Reason ("the control file's status '" + $st.value + "' is not one Horde knows") }
            else { $k["liveStatus"] = New-HordeKnown -Value "$($st.value)" -ObservedAt (ConvertFrom-HordeEpochMs (Get-HordeField -Record $j -Name "statusUpdatedAt").value) }
            # WHAT A WAITING SESSION WAITS FOR. Claude Code writes waitingFor beside status only while
            # the session waits on the user and drops the key otherwise: on 2026-09-30 it was in 1 of
            # 10 control files, the one whose status was waiting, as "permission prompt", and in none
            # of the 9 idle ones (core-ownership L-055). So a missing key is the agent saying it waits
            # for nothing - but only when its status is one Horde knows and is not waiting. A status
            # that says waiting, says nothing, or is one Horde does not know leaves the wait unknown.
            $wf = $j.PSObject.Properties["waitingFor"]
            if ($null -ne $wf -and $wf.Value -is [string] -and $wf.Value -ne "") { $k["waitingFor"] = New-HordeKnown -Value $wf.Value -ObservedAt (ConvertFrom-HordeEpochMs (Get-HordeField -Record $j -Name "statusUpdatedAt").value) }
            elseif ($null -ne $wf) { $k["waitingFor"] = New-HordeUnknown -Reason "the control file's waitingFor is not text, or is empty" }
            elseif ($st.state -ne "known") { $k["waitingFor"] = New-HordeUnknown -Reason "the control file has no status, so whether the session waits is unknown" }
            elseif ($script:HordeClaudeStatuses -cnotcontains "$($st.value)") { $k["waitingFor"] = New-HordeUnknown -Reason ("the control file's status '" + $st.value + "' is not one Horde knows, so whether the session waits is unknown") }
            elseif ("$($st.value)" -ceq "waiting") { $k["waitingFor"] = New-HordeUnknown -Reason "the status is waiting but the control file does not say for what" }
            else { $k["waitingFor"] = New-HordeAbsent -Note "the control file names nothing the session waits for" }
        } else {
            foreach ($n in @("pid", "procStart", "messagingAddress", "liveStatus", "waitingFor")) { $k[$n] = New-HordeUnknown -Reason $verdict.reason }
        }
        $k["cwd"] = Get-HordeField -Record $j -Name "cwd"
        $k["name"] = Get-HordeField -Record $j -Name "name"
        $k["nameSource"] = Get-HordeField -Record $j -Name "nameSource"
        $k["nameSince"] = Get-HordeTimeField -Record $j -Name "nameSince"
        # startedAt is the session's start INSIDE this process - later than the process's creation
        # in 10 of 10 files, by 1.3 s to 160 s - so it is carried, and never used as the process check.
        $k["startedAt"] = Get-HordeTimeField -Record $j -Name "startedAt"
        $k["agentVersion"] = Get-HordeField -Record $j -Name "version"
        $k["peerProtocol"] = Get-HordeField -Record $j -Name "peerProtocol"
        $k["peerFeatures"] = Get-HordeField -Record $j -Name "peerFeatures"
        # kind and entrypoint are carried exactly as written. What wezfleet measured to tell a nested
        # `claude -p` (sdk-cli) from a pane session (cli) is the ENVIRONMENT VARIABLE
        # CLAUDE_CODE_ENTRYPOINT (YedPool/wezfleet hooks/wf-registry-refresh.ps1:64-81), not this key;
        # the key has been seen only as cli (10 of 10 files, 2026-09-30), so what a nested session's
        # control file says here is unmeasured (core-ownership L-048).
        $k["sessionKind"] = Get-HordeField -Record $j -Name "kind"
        $k["entrypoint"] = Get-HordeField -Record $j -Name "entrypoint"
        $k["pidDomain"] = Get-HordeField -Record $j -Name "pidDomain"
        # bridgeSessionId has three states on disk (census: a string 8, null 1, missing 1): null is
        # the agent saying there is none; missing says nothing.
        $bridgeProp = $j.PSObject.Properties["bridgeSessionId"]
        if ($null -eq $bridgeProp) { $k["bridgeSessionId"] = New-HordeUnknown -Reason "the control file has no 'bridgeSessionId' field" }
        elseif ($null -eq $bridgeProp.Value) { $k["bridgeSessionId"] = New-HordeAbsent -Note "the control file says there is no bridge session" }
        else { $k["bridgeSessionId"] = New-HordeKnown -Value $bridgeProp.Value }
        $k["formerNames"] = Get-HordeField -Record $j -Name "formerNames"
        if ($k["formerNames"].state -eq "known") {
            foreach ($fn in @($k["formerNames"].value)) {
                $fnSid = $null
                if ($null -ne $fn -and $null -ne $fn.PSObject.Properties["sessionId"]) { $fnSid = "$($fn.sessionId)" }
                if ($null -ne $fnSid -and $fnSid -cne $sid) {
                    [void]$findings.Add($f.Name + ": a former name carries session " + $fnSid + ", not this file's " + $sid + "; reported, not merged, because whether /clear changes the id is unmeasured")
                }
            }
        }
        # The transcript lives under the control file's own cwd (10 of 10, 2026-09-30), and is taken
        # only when it is there.
        if ($k["cwd"].state -eq "known" -and $k["cwd"].value -is [string] -and "$($k['cwd'].value)" -ne "") {
            $tp = Join-Path (Join-Path $ProjectsDir (ConvertTo-HordeClaudeProjectKey -Cwd $k["cwd"].value)) ($sid + ".jsonl")
            if (Test-Path -LiteralPath $tp -PathType Leaf) { $k["transcriptPath"] = New-HordeKnown -Value $tp }
            else { $k["transcriptPath"] = New-HordeUnknown -Reason ("the derived transcript " + $tp + " does not exist") }
        } else { $k["transcriptPath"] = New-HordeUnknown -Reason "the control file gives no cwd to derive the transcript from" }
        $k["resumeCommand"] = New-HordeUnknown -Reason "the resume command is computed by the AgentPort (step 5.1), not read"
        [void]$entries.Add((New-HordeIdentityRecord -SessionId $sid -Source $f.FullName -Known $k -Missing "the claude control file has no" -Provisional @{ formerNames = $script:HordeFormerNamesProvisional } -ProcessCheck $verdict.kind))
    }
    # A CLAUDE PROCESS NO CONTROL FILE VERIFIES yields no record: it says nothing about which session
    # it is. It is listed, because it is a real process holding resources (census 2026-09-30: one such
    # orphan, alive, whose file Claude had removed). Known only when both the table and the listing
    # are whole - a file that could not be read may be that process's.
    #
    # VERIFIES, not merely "has a file at its pid": a stale file whose pid was reused by a new claude
    # process hid that process when any file at the pid counted (review finding 2 of PR #19). A claude
    # process at the pid of a file that cannot be checked is neither verified nor an orphan, so the
    # answer is unknown. And the names are provisional (see $script:HordeOrphanProvisional): a node
    # process no file verifies may be a claude with no file, so while one runs the answer is unknown,
    # never a known list that may be short.
    # A file that vanished during the read belonged to a session that exited after the process table
    # was read, so its pid, still in the table, is not an orphan.
    $vanishedPids = @{}
    foreach ($v in $vanished) {
        [void]$findings.Add($v + ": exited during the read - listed, then removed before it could be opened, as Claude removes a session's file when it exits")
        $vb = [System.IO.Path]::GetFileNameWithoutExtension($v)
        if ($vb -match '^[0-9]{1,9}$') { $vanishedPids[[int]$vb] = $true }
    }
    $orphans = $null
    if ($Processes.state -ne "known") { $orphans = New-HordeUnknown -Reason ("the process table could not be read (" + $Processes.reason + ")") }
    elseif ($gaps.Count -gt 0) { $orphans = New-HordeUnknown -Reason "the control listing is incomplete, so a process without a readable file may still have one" }
    else {
        $list = New-Object System.Collections.ArrayList
        $unsure = New-Object System.Collections.ArrayList
        $hosts = New-Object System.Collections.ArrayList
        foreach ($p in $Processes.value.Values) {
            $pp = [int]$p.pid
            if ($verifiedPids.ContainsKey($pp) -or $vanishedPids.ContainsKey($pp)) { continue }
            if ($imagePids.ContainsKey($pp)) {
                if ($uncheckablePids.ContainsKey($pp)) { [void]$unsure.Add($pp) } else { [void]$list.Add($pp) }
            } elseif ($hostPids.ContainsKey($pp)) { [void]$hosts.Add($pp) }
        }
        if ($unsure.Count -gt 0) { $orphans = New-HordeUnknown -Reason ("claude process " + (@($unsure | Sort-Object) -join ", ") + " has a control file that cannot be checked, so whether it is that file's process is unknown") }
        elseif ($hosts.Count -gt 0) { $orphans = New-HordeUnknown -Reason ("" + $hosts.Count + " node process(es) that no control file verifies are running (" + (@($hosts | Sort-Object) -join ", ") + "), and Claude Code can run under node, so a claude process with no file may be among them") }
        else { $orphans = New-HordeKnown -Value @($list | Sort-Object) }
    }
    $read = New-HordeAgentRead -Agent "claude" -Entries $entries -Gaps $gaps -Verified $verified -Orphans $orphans -Findings $findings
    $read | Add-Member -NotePropertyName imagePids -NotePropertyValue $imagePids
    $read | Add-Member -NotePropertyName hostPids -NotePropertyValue $hostPids
    $read | Add-Member -NotePropertyName verifiedPids -NotePropertyValue $verifiedPids
    return $read
}

function Read-HordeCodexControlFiles {
    # wezfleet's codex control files: <wezfleet root>\codex-sessions\<sessionId>.json, written by the
    # codex status hook (YedPool/wezfleet lib/CodexStatus.ps1). A codex session has
    # no control file until its first turn: the hook fires then, not at thread creation
    # (lib/CodexStatus.ps1:19-20), so a new codex session is invisible here until it has spoken.
    #
    # Codex writes no pid, start time, name or messaging address (lib/CodexStatus.ps1:51-57), so
    # those fields are unknown and never invented, and no codex session is ever process-verified.
    # The file also carries the pane, run directory and fleet id wezfleet's hook took from the
    # environment; those belong to the host and the engine (core/ownership.json), and none is carried.
    param(
        [string]$Dir = (Get-HordeCodexSessionsDir),
        $TtlSeconds = (Get-HordeCodexTtlSeconds),
        [datetime]$Now = (Get-Date)
    )
    # A TTL passed in takes the override's fallback, so a bad one cannot fail the whole read.
    $ttl = Get-HordeCodexTtlSeconds -Value $TtlSeconds
    $gaps = New-Object System.Collections.ArrayList
    $entries = New-Object System.Collections.ArrayList
    $vanished = New-Object System.Collections.ArrayList
    foreach ($f in (Get-HordeControlFiles -Dir $Dir -Agent "codex" -Gaps $gaps)) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        # The file is written in place, with no temp file (lib/CodexStatus.ps1:200), so a read can
        # catch it half-written. That is an unreadable file - the listing is incomplete - never an
        # absent session.
        $j = Read-HordeControlJson -File $f -Gaps $gaps -Vanished $vanished
        if ($null -eq $j) { continue }
        $sidField = Get-HordeField -Record $j -Name "sessionId"
        if ($sidField.state -ne "known" -or -not (Test-HordeSessionId $sidField.value) -or "$($sidField.value)" -cne $base) {
            [void]$gaps.Add($f.Name + " does not hold the session it is named after, so it was refused"); continue
        }
        $agentField = Get-HordeField -Record $j -Name "agent"
        if ($agentField.state -ne "known" -or "$($agentField.value)" -cne "codex") { [void]$gaps.Add($f.Name + " is not a codex record (agent '" + $(if ($agentField.state -eq "known") { $agentField.value } else { "" }) + "'), so it was refused"); continue }
        $sid = $sidField.value
        $k = @{}
        $k["agent"] = New-HordeKnown -Value "codex"
        $k["cwd"] = Get-HordeField -Record $j -Name "cwd"
        $k["transcriptPath"] = Get-HordeField -Record $j -Name "transcriptPath"
        $k["resumeCommand"] = New-HordeUnknown -Reason "the resume command is computed by the AgentPort (step 5.1), not read"
        # A codex reading is believed for its TTL and no longer, idle included: "a session killed
        # while idle would then read idle forever" (lib/CodexStatus.ps1:230-236). ended is exempt - a
        # session reporting its own end - and does not decay.
        $at = ConvertFrom-HordeEpochMs (Get-HordeField -Record $j -Name "statusUpdatedAt").value
        $st = Get-HordeField -Record $j -Name "status"
        if ($st.state -ne "known") { $k["liveStatus"] = $st }
        elseif ("$($st.value)" -ceq "unknown") { $k["liveStatus"] = New-HordeUnknown -Reason "the codex hook itself reported unknown" }
        elseif ($script:HordeCodexStatuses -cnotcontains "$($st.value)") { $k["liveStatus"] = New-HordeUnknown -Reason ("the codex status '" + $st.value + "' is not one Horde knows") }
        elseif ("$($st.value)" -ceq "ended") { $k["liveStatus"] = New-HordeKnown -Value "ended" -ObservedAt $at }
        else { $k["liveStatus"] = Limit-HordeAge -Answer (New-HordeKnown -Value "$($st.value)" -ObservedAt $at) -TtlSeconds $ttl -Now $Now }
        [void]$entries.Add((New-HordeIdentityRecord -SessionId $sid -Source $f.FullName -Known $k -Missing "codex writes no" -Provisional @{ transcriptPath = "taken from the codex control file; no derivation of a codex transcript path has been measured" } -ProcessCheck "unchecked"))
    }
    $orphans = New-HordeUnknown -Reason "codex writes no pid, so a codex process cannot be matched to a file"
    $codexFindings = @($vanished | ForEach-Object { $_ + ": removed during the read - listed, then gone before it could be opened" })
    return (New-HordeAgentRead -Agent "codex" -Entries $entries -Gaps $gaps -Verified @() -Orphans $orphans -Findings $codexFindings)
}

function Assert-HordeProcessTable {
    # The process table is an answer: known holding a pid table, or unknown. A bare table is refused,
    # so a caller cannot hand over a table it failed to read as if it were empty.
    param($Processes)
    if (-not (Test-HordeAnswer $Processes)) { throw "-Processes must be a process table answer (Get-HordeProcessTable), not a bare value" }
    if ($Processes.state -eq "known" -and $Processes.value -isnot [hashtable]) { throw "-Processes must hold a process table keyed by pid" }
    if ($Processes.state -eq "absent") { throw "-Processes cannot be absent: a process table always has processes" }
}

function Get-HordeIdentity {
    # Every agent's sessions, read into one listing. Returns:
    #   records          session id -> record (New-HordeIdentityRecord), ids compared ignoring case
    #   complete         agent -> answer: known true when that agent's listing is whole, unknown with
    #                    every reason otherwise - an unreadable, refused or duplicated file among them
    #   duplicates       { sessionId; sources } for every id named by more than one file, unless
    #                    exactly one is process-verified and every other is proven stale (then the
    #                    verified one is the record and the rest are findings); none of them is in
    #                    records, and each agent it came from is incomplete
    #   verifiedLive     answer: the session ids whose process was checked and is the one described.
    #                    Unknown when the process table or the claude listing is not whole, because a
    #                    session missing from it may be alive.
    #   orphanProcesses  answer: claude processes running that no control file verifies; unknown
    #                    while one cannot be told apart (see $script:HordeOrphanProvisional)
    #   provisional      field -> why the rule behind it rests on something unmeasured
    #   findings         stale files, reused pids, files that cannot be checked, leftovers beside a
    #                    verified file, former names naming another session
    param(
        [string]$ClaudeDir = (Get-HordeClaudeSessionsDir),
        [string]$ProjectsDir = (Get-HordeClaudeProjectsDir),
        [string]$CodexDir = (Get-HordeCodexSessionsDir),
        $Processes = (Get-HordeProcessTable),
        $TtlSeconds = (Get-HordeCodexTtlSeconds),
        [datetime]$Now = (Get-Date)
    )
    Assert-HordeProcessTable $Processes
    $reads = @(
        (Read-HordeClaudeControlFiles -Dir $ClaudeDir -Processes $Processes -ProjectsDir $ProjectsDir),
        (Read-HordeCodexControlFiles -Dir $CodexDir -TtlSeconds $TtlSeconds -Now $Now))
    $bySid = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rd in $reads) {
        foreach ($e in $rd.entries) {
            if (-not $bySid.ContainsKey($e.sessionId)) { $bySid[$e.sessionId] = New-Object System.Collections.ArrayList }
            [void]$bySid[$e.sessionId].Add([pscustomobject]@{ agent = $rd.agent; record = $e })
        }
    }
    $records = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    $duplicates = New-Object System.Collections.ArrayList
    $leftoverFindings = New-Object System.Collections.ArrayList
    $dupGaps = @{}
    foreach ($sid in $bySid.Keys) {
        $all = $bySid[$sid]
        if ($all.Count -eq 1) { $records[$sid] = $all[0].record; continue }
        # A LEFTOVER IS NOT A TIE. A session resumed after its process died leaves the dead process's
        # file beside the live one. When exactly one file is process-verified and every other is
        # PROVEN stale - its process gone, or its pid now another process - nothing is being chosen:
        # the verified file is the session, and the others are reported. Calling that a duplicate made
        # the whole claude listing incomplete and dropped the one session certainly running (review
        # finding 1 of PR #19).
        $liveOnes = @($all | Where-Object { "$($_.record.processCheck)" -ceq "verified" })
        $deadOnes = @($all | Where-Object { @("gone", "reused") -ccontains "$($_.record.processCheck)" })
        if ($liveOnes.Count -eq 1 -and ($liveOnes.Count + $deadOnes.Count) -eq $all.Count) {
            $records[$sid] = $liveOnes[0].record
            foreach ($x in $deadOnes) {
                [void]$leftoverFindings.Add((Split-Path -Leaf $x.record.source) + " also names session " + $sid + ", but its process is " + $x.record.processCheck + "; the verified file " + (Split-Path -Leaf $liveOnes[0].record.source) + " is kept")
            }
            continue
        }
        # Otherwise never choose: two verified files, or any that cannot be checked, is a real tie.
        # Which of two files is the live one is exactly the question that went wrong silently:
        # "seven conversations ran in both with nothing noticing" (YedPool/wezfleet 0e1c75a).
        [void]$duplicates.Add([pscustomobject]@{ sessionId = $sid; sources = @($all | ForEach-Object { $_.record.source }) })
        foreach ($x in $all) {
            if (-not $dupGaps.ContainsKey($x.agent)) { $dupGaps[$x.agent] = New-Object System.Collections.ArrayList }
            if ($dupGaps[$x.agent] -notcontains $sid) { [void]$dupGaps[$x.agent].Add($sid) }
        }
    }
    $complete = [ordered]@{}
    $findings = New-Object System.Collections.ArrayList
    foreach ($rd in $reads) {
        $why = New-Object System.Collections.ArrayList
        if ($rd.complete.state -ne "known") { [void]$why.Add($rd.complete.reason) }
        if ($dupGaps.ContainsKey($rd.agent)) { [void]$why.Add("the listing omits " + (@($dupGaps[$rd.agent]) -join ", ") + ", each named by more than one control file") }
        if ($why.Count -gt 0) { $complete[$rd.agent] = New-HordeUnknown -Reason (@($why) -join "; ") }
        else { $complete[$rd.agent] = $rd.complete }
        foreach ($x in $rd.findings) { [void]$findings.Add($x) }
    }
    foreach ($x in $leftoverFindings) { [void]$findings.Add($x) }
    $claudeRead = $reads[0]
    $verifiedLive = $null
    if ($Processes.state -ne "known") { $verifiedLive = New-HordeUnknown -Reason ("the process table could not be read (" + $Processes.reason + ")") }
    elseif ($complete["claude"].state -ne "known") { $verifiedLive = New-HordeUnknown -Reason ("the claude listing is incomplete: " + $complete["claude"].reason) }
    else { $verifiedLive = New-HordeKnown -Value @($claudeRead.verified | Where-Object { $records.ContainsKey($_) }) }
    # agent -> { imagePids; hostPids; verifiedPids }, for each agent whose reader matches processes by
    # image (an agent that writes no pid has none).
    $processes = @{}
    foreach ($rd in $reads) { if ($null -ne $rd.PSObject.Properties["imagePids"]) { $processes[$rd.agent] = [pscustomobject]@{ imagePids = $rd.imagePids; hostPids = $rd.hostPids; verifiedPids = $rd.verifiedPids } } }
    return [pscustomobject]@{ PSTypeName = "Horde.Identity"; records = $records; complete = $complete; duplicates = @($duplicates)
                              verifiedLive = $verifiedLive; orphanProcesses = $claudeRead.orphans; findings = @($findings); agentProcesses = $processes
                              provisional = @{ orphanProcesses = $script:HordeOrphanProvisional } }
}

function Get-HordeSelfSessionId {
    # Which session is asking. Only the agent's own export: CLAUDE_CODE_SESSION_ID is each process's
    # own id, even in a nested `claude -p` (YedPool/wezfleet hooks/wf-registry-refresh.ps1:74-75).
    #   - wezfleet fell back to WEZFLEET_SESSION_ID (lib/Mail.ps1:88), a FLEET id returned through the
    #     same string as a session id. Never here.
    #   - wezfleet's last resort read the pane record for WEZTERM_PANE, which failed or not depending
    #     on how many terminals were open (88aab20). An identity that depends on that is not one;
    #     no pane record is read here.
    # This is for a process asking about ITSELF. The variable is inherited, so it never identifies
    # another session (YedPool/wezfleet lib/Protocol.ps1:361-364); the readers above never read it.
    param([System.Collections.IDictionary]$Environment = [System.Environment]::GetEnvironmentVariables())
    $v = $null
    if ($Environment.Contains("CLAUDE_CODE_SESSION_ID")) { $v = "$($Environment['CLAUDE_CODE_SESSION_ID'])" }
    if ($null -eq $v -or $v -eq "") { return (New-HordeUnknown -Reason "CLAUDE_CODE_SESSION_ID is not set, and nothing else names this session") }
    if (-not (Test-HordeSessionId $v)) { return (New-HordeUnknown -Reason "CLAUDE_CODE_SESSION_ID is not a well-formed session id") }
    return (New-HordeKnown -Value $v)
}
