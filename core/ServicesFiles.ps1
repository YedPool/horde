# core/ServicesFiles - the files the supervisor of services keeps under <home>\services: one state
# file a service, one journal, the supervisor's own heartbeat, a lock, and each service's output.
#
# WHY APART FROM core/Services.ps1. That file decides and touches nothing; this one reads and writes
# and decides nothing. A decision can then be tested with a clock and a state made in memory, and a
# file's shape can change without the rules moving (core/WakeFiles.ps1 is apart from core/Wake.ps1 for
# the same reason).
#
#   <home>\services\state\<name>.json   what the supervisor knows of one service between passes:
#                                       its phase, the revision it runs and the one before, what is
#                                       pinned, its failures, what has been told. Replaced whole.
#   <home>\services\journal.jsonl       one line for each thing a pass did, and for each wait when it
#                                       begins - not on every pass while it lasts (the wake journal
#                                       measured what a line a pass costs: 28,800 a day at a 3 s tick).
#                                       Set aside at 4 MiB, so there are at most two files.
#   <home>\services\tend-heartbeat.json the supervisor's own heartbeat (core/Heartbeat.ps1): the
#                                       scheduled job IS the supervisor, and status must be able to
#                                       say that it has stopped coming round.
#   <home>\services\tend.lock           held open by a pass for as long as it runs.
#   <home>\services\logs\<name>.log     what a service started as a horde command printed.
#
# NOTHING SECRET IS WRITTEN. A state or a journal line holds reasons that came from other programs - a
# revision tool's error can quote a remote address with a credential in it - so every such text goes
# through core/Secrets.ps1 before it is kept (Protect-HordeServiceText), here and not at each caller.
#
# A STATE FILE THAT CANNOT BE READ IS UNKNOWN, NEVER "NEW". Read as a fresh state it would forget the
# pinned revision and the failures in a row, and the supervisor would retry a revision it had rolled
# back and restart at full pace a service that keeps failing. The pass leaves that service alone and
# says why, until a person mends or removes the file.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "Home.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "Secrets.ps1")
. (Join-Path $PSScriptRoot "Heartbeat.ps1")
. (Join-Path $PSScriptRoot "Services.ps1")

# How large the journal, or one service's output, grows before it is set aside: 4 MiB, as the wake
# journal's (about 20,000 lines of 200 bytes).
$script:HordeServiceJournalMaxBytes = 4194304
# The most a state file may be before it is refused unread: a full one is about 3 KiB.
$script:HordeServiceStateMaxBytes = 65536
# The longest a kept reason may be. A reason is one sentence; a program's whole error output is not.
$script:HordeServiceReasonChars = 600
# How often the supervisor's pass comes round, in seconds: the scheduled job's one minute. Its
# heartbeat promises this tick, so "stale" for it is three minutes.
$script:HordeServiceTendTickSeconds = 60

function Get-HordeServiceFolder {
    param([string]$HordeHome = "")
    if ($HordeHome -eq "") { $HordeHome = Get-HordeHome }
    return [System.IO.Path]::Combine($HordeHome, "services")
}

function Get-HordeServiceStatePath {
    param([Parameter(Mandatory = $true)][string]$Name, [string]$HordeHome = "")
    if ($Name -cnotmatch $script:HordeServiceNamePattern) { throw ("not a service name: '" + $Name + "'") }
    return [System.IO.Path]::Combine((Get-HordeServiceFolder -HordeHome $HordeHome), "state", ($Name + ".json"))
}

function Get-HordeServiceLogPath {
    param([Parameter(Mandatory = $true)][string]$Name, [string]$HordeHome = "")
    if ($Name -cnotmatch $script:HordeServiceNamePattern) { throw ("not a service name: '" + $Name + "'") }
    return [System.IO.Path]::Combine((Get-HordeServiceFolder -HordeHome $HordeHome), "logs", ($Name + ".log"))
}

function Get-HordeServiceJournalPath { param([string]$HordeHome = "") return [System.IO.Path]::Combine((Get-HordeServiceFolder -HordeHome $HordeHome), "journal.jsonl") }
function Get-HordeServiceTendHeartbeatPath { param([string]$HordeHome = "") return [System.IO.Path]::Combine((Get-HordeServiceFolder -HordeHome $HordeHome), "tend-heartbeat.json") }
function Get-HordeServiceTendLockPath { param([string]$HordeHome = "") return [System.IO.Path]::Combine((Get-HordeServiceFolder -HordeHome $HordeHome), "tend.lock") }
function Get-HordeServiceTendTickSeconds { return $script:HordeServiceTendTickSeconds }

function Protect-HordeServiceText {
    # A text as the supervisor may keep or tell it: one line, every secret-shaped stretch hidden
    # (core/Secrets.ps1), cut at the cap. Every reason that came from outside Horde passes through.
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text -or $Text.Length -eq 0) { return "" }
    $line = (($Text -replace '[\r\n\t]+', ' ') -replace '\p{Cc}', '').Trim()
    $line = (Protect-HordeSecretText -Text $line).text
    if ($line.Length -gt $script:HordeServiceReasonChars) { $line = $line.Substring(0, $script:HordeServiceReasonChars) + "..." }
    return $line
}

function ConvertTo-HordeServiceStateRecord {
    # The state as it is written: times as text, every kept reason protected.
    param([Parameter(Mandatory = $true)]$State)
    $time = { param($At) if ($At -is [datetime]) { return (ConvertTo-HordeHeartbeatTimeText -At $At) } return $null }
    $r = [ordered]@{ schemaVersion = 1; name = "" + $State.name; phase = "" + $State.phase; intent = "" + $State.intent; phaseSince = (& $time $State.phaseSince)
        target = "" + $State.target; from = "" + $State.from; runningRevision = "" + $State.runningRevision; previousRevision = "" + $State.previousRevision
        pinnedRevision = "" + $State.pinnedRevision; verifiedRevision = "" + $State.verifiedRevision; refused = $null; started = $null
        proving = [bool]$State.proving; failures = [int]$State.failures; nextStartAt = (& $time $State.nextStartAt); confirmBy = (& $time $State.confirmBy)
        stuck = (Protect-HordeServiceText ("" + $State.stuck)); told = @($State.told | ForEach-Object { "" + $_ }); notices = @(); lastAction = $null
        lastFetchAt = (& $time $State.lastFetchAt); fetchProblem = (Protect-HordeServiceText ("" + $State.fetchProblem)); lastSaid = "" + $State.lastSaid }
    if ($null -ne $State.refused) { $r["refused"] = [ordered]@{ revision = "" + $State.refused.revision; kind = "" + $State.refused.kind; reason = (Protect-HordeServiceText ("" + $State.refused.reason)); at = (& $time $State.refused.at) } }
    if ($null -ne $State.started) { $r["started"] = [ordered]@{ pid = [int]$State.started.pid; startedAt = (& $time $State.started.startedAt); at = (& $time $State.started.at) } }
    if ($null -ne $State.lastAction) { $r["lastAction"] = [ordered]@{ at = (& $time $State.lastAction.at); action = "" + $State.lastAction.action; step = "" + $State.lastAction.step; outcome = "" + $State.lastAction.outcome; reason = (Protect-HordeServiceText ("" + $State.lastAction.reason)) } }
    $r["notices"] = @($State.notices | ForEach-Object { [ordered]@{ id = "" + $_.id; kind = "" + $_.kind; text = (Protect-HordeServiceText ("" + $_.text)); at = (& $time $_.at) } })
    return $r
}

function ConvertFrom-HordeServiceStateRecord {
    # The state a parsed file holds, or a sentence saying why it is not one: { state; problem }.
    # Checked member by member, because the next pass ACTS on it: a phase nobody wrote, a revision
    # that is not one, or a stop with no time would each send a decision somewhere no test has been.
    param($Record, [Parameter(Mandatory = $true)][string]$Name)
    $bad = { param([string]$Why) return [pscustomobject]@{ state = $null; problem = $Why } }
    if ($null -eq $Record -or $Record -isnot [System.Management.Automation.PSCustomObject]) { return (& $bad "it is not a record") }
    $have = Get-HordeObjectByKey $Record
    if (-not $have.ContainsKey("schemaVersion") -or $have["schemaVersion"] -ne 1) { return (& $bad "its schemaVersion is not 1") }
    if (-not $have.ContainsKey("name") -or "" + $have["name"] -cne $Name) { return (& $bad ("it is not the state of " + $Name)) }
    $s = New-HordeServiceState -Name $Name
    $text = { param([string]$Key) if ($have.ContainsKey($Key) -and $have[$Key] -is [string]) { return [string]$have[$Key] } return "" }
    $when = { param($Value) if ($null -eq $Value) { return $null } return (ConvertFrom-HordeHeartbeatTimeText $Value) }
    $s.phase = & $text "phase"
    if ($script:HordeServicePhases -cnotcontains $s.phase) { return (& $bad "its phase is not one the supervisor knows") }
    $s.intent = & $text "intent"
    foreach ($k in @("target", "from", "runningRevision", "previousRevision", "pinnedRevision", "verifiedRevision")) {
        $v = & $text $k
        if ($v -ne "" -and $v -cnotmatch $script:HordeServiceRevisionPattern) { return (& $bad ("its " + $k + " is not a revision")) }
        $s.$k = $v
    }
    foreach ($k in @("phaseSince", "nextStartAt", "confirmBy", "lastFetchAt")) {
        if ($have.ContainsKey($k) -and $null -ne $have[$k]) {
            $t = & $when $have[$k]
            if ($null -eq $t) { return (& $bad ("its " + $k + " is not a time")) }
            $s.$k = $t
        }
    }
    if ($s.phase -cne "steady") {
        if (@("update", "rollback", "heal") -cnotcontains $s.intent) { return (& $bad "it is part way through something and does not say what") }
        if ($s.phaseSince -isnot [datetime]) { return (& $bad "it is part way through something and does not say since when") }
        if ($s.intent -cne "heal" -and ($s.target -eq "" -or $s.from -eq "")) { return (& $bad "it is part way through an update and does not say between which revisions") }
        if ($s.intent -ceq "heal" -and $s.phase -cne "stopping") { return (& $bad "its phase and what it is doing do not go together") }
    }
    if ($have.ContainsKey("proving")) { $s.proving = [bool]($have["proving"] -eq $true) }
    if ($have.ContainsKey("failures") -and ($have["failures"] -is [int] -or $have["failures"] -is [long]) -and $have["failures"] -ge 0 -and $have["failures"] -le 1000000) { $s.failures = [int]$have["failures"] }
    $s.stuck = & $text "stuck"
    $s.fetchProblem = & $text "fetchProblem"
    $s.lastSaid = & $text "lastSaid"
    if ($have.ContainsKey("told") -and $null -ne $have["told"]) { $s.told = [string[]]@(@($have["told"]) | Where-Object { $_ -is [string] -and $_ -ne "" } | Select-Object -Last $script:HordeServiceToldMost) }
    # Nested records are read through an exact-key table, never by property: under strict mode a
    # member that is not there throws, and a file a person edited may lack any of them.
    $part = { param($Value) if ($Value -is [System.Management.Automation.PSCustomObject]) { return ,(Get-HordeObjectByKey $Value) } return $null }
    if ($have.ContainsKey("refused") -and $null -ne $have["refused"]) {
        $f = & $part $have["refused"]
        $fat = $null
        if ($null -ne $f) { $fat = & $when $f["at"] }
        if ($null -eq $f -or ("" + $f["revision"]) -cnotmatch $script:HordeServiceRevisionPattern -or @("verify", "apply", "retreat") -cnotcontains ("" + $f["kind"]) -or $null -eq $fat) { return (& $bad "its refused update is not whole") }
        $s.refused = [pscustomobject]@{ revision = "" + $f["revision"]; kind = "" + $f["kind"]; reason = "" + $f["reason"]; at = $fat }
    }
    if ($have.ContainsKey("started") -and $null -ne $have["started"]) {
        $p = & $part $have["started"]
        $pStart = $null; $pAt = $null
        if ($null -ne $p) { $pStart = & $when $p["startedAt"]; $pAt = & $when $p["at"] }
        if ($null -eq $p -or ($p["pid"] -isnot [int] -and $p["pid"] -isnot [long]) -or $p["pid"] -le 0 -or $p["pid"] -gt [int]::MaxValue -or $null -eq $pStart -or $null -eq $pAt) { return (& $bad "the process it names is not whole: a pid, when it started and when it was started") }
        $s.started = [pscustomobject]@{ pid = [int]$p["pid"]; startedAt = $pStart; at = $pAt }
    }
    if ($have.ContainsKey("lastAction") -and $null -ne $have["lastAction"]) {
        $a = & $part $have["lastAction"]
        $aAt = $null
        if ($null -ne $a) { $aAt = & $when $a["at"] }
        if ($null -ne $aAt) { $s.lastAction = [pscustomobject]@{ at = $aAt; action = "" + $a["action"]; step = "" + $a["step"]; outcome = "" + $a["outcome"]; reason = "" + $a["reason"] } }
    }
    if ($have.ContainsKey("notices") -and $null -ne $have["notices"]) {
        $kept = New-Object System.Collections.ArrayList
        foreach ($item in @($have["notices"])) {
            $n = & $part $item
            if ($null -eq $n) { continue }
            $nAt = & $when $n["at"]
            if (("" + $n["id"]) -cnotmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z' -or @("escalate", "recovered") -cnotcontains ("" + $n["kind"]) -or ("" + $n["text"]) -eq "" -or $null -eq $nAt) { continue }
            [void]$kept.Add([pscustomobject]@{ id = "" + $n["id"]; kind = "" + $n["kind"]; text = "" + $n["text"]; at = $nAt })
        }
        $s.notices = @($kept.ToArray() | Select-Object -Last $script:HordeServiceNoticesMost)
    }
    return [pscustomobject]@{ state = $s; problem = "" }
}

function Read-HordeServiceState {
    # One service's state as an answer: known (the state), absent (the supervisor has never kept one:
    # the caller begins with New-HordeServiceState), or unknown with the reason (the header says why
    # that is not "new").
    param([Parameter(Mandatory = $true)][string]$Name, [string]$HordeHome = "")
    $path = Get-HordeServiceStatePath -Name $Name -HordeHome $HordeHome
    if (-not [System.IO.File]::Exists($path)) { return (New-HordeAbsent -Note "the supervisor has kept no state of it yet") }
    $record = $null
    try {
        $text = Read-HordeSharedText -Path $path
        if ($text.Length -gt $script:HordeServiceStateMaxBytes) { return (New-HordeUnknown -Reason ("its state file " + $path + " is larger than a state file is")) }
        $record = $text | ConvertFrom-Json
    } catch { return (New-HordeUnknown -Reason ("its state file " + $path + " could not be read") -ErrorRecord $_) }
    $made = ConvertFrom-HordeServiceStateRecord -Record $record -Name $Name
    if ($null -eq $made.state) { return (New-HordeUnknown -Reason ("its state file " + $path + " is not a state the supervisor wrote: " + $made.problem + "; mend it or remove it")) }
    return (New-HordeKnown -Value $made.state)
}

function Write-HordeServiceState {
    # Replace one service's state whole (core/FileAtomic.ps1): a pass killed mid-write leaves the
    # state of the pass before or this one, never half.
    param([Parameter(Mandatory = $true)]$State, [string]$HordeHome = "")
    $path = Get-HordeServiceStatePath -Name $State.name -HordeHome $HordeHome
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    $temp = $path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject (ConvertTo-HordeServiceStateRecord -State $State) -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $path }
    catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

function Get-HordeServiceSaidKey {
    # What a journal line is the same line by: the service's action, step and code. Two passes that
    # decide the same wait for the same reason say it once.
    param([Parameter(Mandatory = $true)]$Decision)
    return ("" + $Decision.action + "|" + $Decision.step + "|" + $Decision.code)
}

function Test-HordeServiceWorthSaying {
    # PURE. Does this pass's decision get a journal line? A step that was taken always does. A wait
    # or a "nothing" does when it is not what the last line already said.
    param([Parameter(Mandatory = $true)]$Decision, [string]$LastSaid = "")
    if ($Decision.step -ne "") { return $true }
    return ((Get-HordeServiceSaidKey -Decision $Decision) -cne $LastSaid)
}

function Write-HordeServiceJournal {
    # Append one line for each entry to the journal: { at; service; action; step; code; outcome; reason }.
    # Returns how many lines it wrote. BOUNDED: at -MaxBytes the journal is set aside as journal.1.jsonl,
    # replacing the one set aside before, and a new one begun.
    param($Entries, [string]$HordeHome = "", [long]$MaxBytes = $script:HordeServiceJournalMaxBytes)
    $lines = New-Object System.Collections.ArrayList
    foreach ($e in @($Entries)) {
        if ($null -eq $e) { continue }
        $row = [ordered]@{ at = (ConvertTo-HordeHeartbeatTimeText -At $e.at); service = "" + $e.service; action = "" + $e.action; step = "" + $e.step; code = "" + $e.code; outcome = "" + $e.outcome; reason = (Protect-HordeServiceText ("" + $e.reason)) }
        [void]$lines.Add((ConvertTo-Json -InputObject $row -Compress))
    }
    if ($lines.Count -eq 0) { return 0 }
    $path = Get-HordeServiceJournalPath -HordeHome $HordeHome
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    if ([System.IO.File]::Exists($path) -and (New-Object System.IO.FileInfo($path)).Length -ge $MaxBytes) { Move-HordeFileAtomic -From $path -To ([System.IO.Path]::ChangeExtension($path, ".1.jsonl")) }
    [System.IO.File]::AppendAllText($path, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    return $lines.Count
}

function New-HordeServiceJournalEntry {
    param([Parameter(Mandatory = $true)][datetime]$At, [Parameter(Mandatory = $true)][string]$Service, [string]$Action = "", [string]$Step = "", [string]$Code = "", [string]$Outcome = "", [string]$Reason = "")
    return [pscustomobject]@{ at = $At; service = $Service; action = $Action; step = $Step; code = $Code; outcome = $Outcome; reason = $Reason }
}

function Read-HordeServiceJournalTail {
    # The last -Count lines of the journal, as written; none when there is no journal. Just after it
    # was set aside the new one is short, so the tail is filled from the one before.
    param([int]$Count = 10, [string]$HordeHome = "")
    $path = Get-HordeServiceJournalPath -HordeHome $HordeHome
    $lines = @()
    foreach ($p in @([System.IO.Path]::ChangeExtension($path, ".1.jsonl"), $path)) {
        if (-not [System.IO.File]::Exists($p)) { continue }
        $lines = @($lines) + @((Read-HordeSharedText -Path $p) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }
    if ($lines.Count -le $Count) { return $lines }
    return @($lines[($lines.Count - $Count)..($lines.Count - 1)])
}

function Enter-HordeServiceTendLock {
    # ONE PASS AT A TIME, A HOME. Returns the open lock - the caller disposes it when the pass ends -
    # or $null when another pass holds it. An open file handle, not a pid in a file (the wake lock's
    # header says why): the operating system closes it when its process ends, however it ends, so a
    # killed pass never leaves the home locked. -WaitSeconds is for a person's `horde rollout`, which
    # would rather wait out the minute's pass than be told to come back.
    param([string]$HordeHome = "", [int]$WaitSeconds = 0, [scriptblock]$Sleep = $null)
    if ($null -eq $Sleep) { $Sleep = { param($Ms) Start-Sleep -Milliseconds $Ms } }
    $path = Get-HordeServiceTendLockPath -HordeHome $HordeHome
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    $tries = 1 + [int]([System.Math]::Max(0, $WaitSeconds) * 2)
    for ($i = 0; $i -lt $tries; $i++) {
        try { return (New-Object System.IO.FileStream -ArgumentList $path, ([System.IO.FileMode]::OpenOrCreate), ([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::None)) }
        catch [System.IO.IOException] { if ($i + 1 -lt $tries) { $null = & $Sleep 500 } }
    }
    return $null
}

function Step-HordeServiceLog {
    # Before a service is started: set its output file aside when it has reached the cap, so one
    # service's output is at most two files and what it grew to in one run. Only ever called when the
    # service is not running, so nothing holds the file. A failure here is the log's, not the start's.
    param([Parameter(Mandatory = $true)][string]$Name, [string]$HordeHome = "", [long]$MaxBytes = $script:HordeServiceJournalMaxBytes)
    $path = Get-HordeServiceLogPath -Name $Name -HordeHome $HordeHome
    try {
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
        if ([System.IO.File]::Exists($path) -and (New-Object System.IO.FileInfo($path)).Length -ge $MaxBytes) { Move-HordeFileAtomic -From $path -To ([System.IO.Path]::ChangeExtension($path, ".1.log")) }
    } catch { }
    return $path
}
