# core/Heartbeat - one file by which a long-running piece of Horde says "I am still going", and one
# way for anything else to read it and decide how long a silence is too long.
#
# WHY ITS OWN FILE. The wake watcher already keeps a heartbeat (core/WakeFiles.ps1), written for its two
# modes and read by its own status. The supervisor of long-lived services (core/Services.ps1) needs the
# same thing of every piece it keeps alive - the relay runner first (cli/RelayRun.ps1), and of its own
# pass - and none of them is a wake watcher. So the heartbeat is said once here, with no mode, no folder
# and no caller's name in it: the caller gives the path. The wake files are left exactly as they are;
# they can move onto this file in a change of their own.
#
# WHAT A HEARTBEAT HOLDS, and why each member is there:
#   at           when it was written (UTC, text that reads back as the same instant).
#   pid          the process that wrote it.
#   startedAt    when THAT PROCESS started. A pid alone is not an identity: the operating system gives
#                a finished process's pid to the next one (core/Identity.ps1's second rule, and the
#                wake lock's header), so a reader that trusted the pid would take a stranger for the
#                service, and a supervisor would stop the stranger. The pair is the identity.
#   tickSeconds  how often this writer promises to beat. STALE IS COMPUTED FROM IT, NEVER A CONSTANT:
#                the wake watcher's first version called anything silent for 120 s stale while taking a
#                tick of up to an hour, so a healthy watcher read as dead for all but two minutes of
#                every hour (review of PR #207). The writer knows its own rhythm; the reader does not.
#   pass         how many times it has beaten since it started; a reader can see it move.
#   condition    LEFT OUT WHEN IT IS WELL. Otherwise one fixed word for why it is running and still
#                cannot do its work, and why the reason in a sentence. A process that beats is not
#                proof of a process that works: the relay runner started before anyone had signed in
#                beat on every turn while it could not open its keys, and a phone's answers waited on a
#                runner every reader called alive (review of PR 249, MUST 1). A reader that sees a
#                condition never calls the writer alive (core/Services.ps1).
#
# A WRITE THAT FAILS IS THE CALLER'S TO SWALLOW. Write-HordeHeartbeat throws like any write. A loop
# whose work matters more than its heartbeat calls Write-HordeHeartbeatQuietly, which answers known or
# unknown and never throws: a full disk or a held file must cost the heartbeat, never the loop.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")

# How many of its own ticks a writer may miss before it is called stale. Three, as the wake watcher's
# heartbeat settled on: one missed tick is a busy machine, two is a slow one, three is not running.
$script:HordeHeartbeatStaleTicks = 3
# The least a silence must last before anything is called stale, whatever tick the writer promised. A
# writer that promises 1 s would otherwise be stale after 3 s, and this machine's background processes
# are slowed by the operating system (core/Platform.ps1, POWER THROTTLING) by more than that.
$script:HordeHeartbeatStaleFloorSeconds = 30
# The most a heartbeat file may be before it is refused unread: the record is about 150 bytes.
$script:HordeHeartbeatMaxBytes = 4096
# How far apart two readings of one process's start may be and still be the same process. The writer
# and the reader each ask the operating system for the start time, and each reading is exact to the
# tick; one second is slack for a platform that rounds, and no pid is reused within a second of the
# start of the process that last had it, because that process would have to start, end and be replaced.
$script:HordeHeartbeatStartSlackSeconds = 1
# A condition is one word a reader can match exactly; its sentence is at most this long, on one line.
$script:HordeHeartbeatConditionPattern = '\A[a-z][a-z0-9-]{0,39}\z'
$script:HordeHeartbeatWhyMost = 300

function ConvertTo-HordeHeartbeatWhy {
    # A condition's sentence as a heartbeat holds it: on one line, no control character, capped.
    param([AllowNull()]$Text)
    $t = ("" + $Text) -replace '\p{Cc}+', ' '
    if ($t.Length -gt $script:HordeHeartbeatWhyMost) { $t = $t.Substring(0, $script:HordeHeartbeatWhyMost) }
    return $t.Trim()
}

function ConvertTo-HordeHeartbeatTimeText {
    # A UTC time as text that reads back as the same instant, to the tick.
    param([Parameter(Mandatory = $true)][datetime]$At)
    return $At.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-HordeHeartbeatTimeText {
    # The time ConvertTo-HordeHeartbeatTimeText wrote, as UTC, or $null when it is not one. Text with
    # no zone is not a time here: it cannot be placed (core/Tristate.ps1).
    param($Text)
    if ($Text -is [datetime]) {
        if ($Text.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
        return $Text.ToUniversalTime()
    }
    $parsed = [datetime]::MinValue
    if ($Text -isnot [string] -or -not [datetime]::TryParse($Text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { return $null }
    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) { return $null }
    return $parsed.ToUniversalTime()
}

function Get-HordeHeartbeatStaleSeconds {
    # After how long with no heartbeat a writer that beats every -TickSeconds is stale: three ticks,
    # and never less than -FloorSeconds. A tick of 0 or less is a writer that did not say; the floor
    # alone then decides, which is the strictest reading and so the one that is noticed.
    param([int]$TickSeconds = 0, [int]$FloorSeconds = $script:HordeHeartbeatStaleFloorSeconds)
    $ticks = [long]$script:HordeHeartbeatStaleTicks * [long][System.Math]::Max(0, $TickSeconds)
    return [int][System.Math]::Min([long][int]::MaxValue, [System.Math]::Max([long]$FloorSeconds, $ticks))
}

function Test-HordeHeartbeatSameStart {
    # Are two readings of a process's start the same process's? Both must be times; a missing one is
    # never "the same", because then the pid alone would be deciding.
    param($One, $Other)
    if ($One -isnot [datetime] -or $Other -isnot [datetime]) { return $false }
    return ([System.Math]::Abs(($One.ToUniversalTime() - $Other.ToUniversalTime()).TotalSeconds) -le $script:HordeHeartbeatStartSlackSeconds)
}

function Get-HordeHeartbeatSelf {
    # This process as a heartbeat names it: { pid; startedAt (UTC) }. startedAt is $null when the
    # operating system will not say, and a heartbeat written without it is one no reader can tie to a
    # process (Read-HordeHeartbeat keeps the $null; the supervisor then says it cannot tell).
    $self = [System.Diagnostics.Process]::GetCurrentProcess()
    try {
        $started = $null
        try { $started = $self.StartTime.ToUniversalTime() } catch { $started = $null }
        return [pscustomobject]@{ pid = [int]$self.Id; startedAt = $started }
    } finally { $self.Dispose() }
}

function Write-HordeHeartbeat {
    # Replace the heartbeat at -Path whole: written beside itself and renamed over it in one step
    # (core/FileAtomic.ps1), so a reader finds the last beat or this one and never half of either.
    # The folder is made when it is not there: the writer is the piece that owns it.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][datetime]$At,
        [Parameter(Mandatory = $true)][int]$ProcessId,
        $ProcessStartedAt = $null,
        [Parameter(Mandatory = $true)][int]$TickSeconds,
        [long]$Pass = 0,
        [string]$Condition = "",
        [string]$Why = ""
    )
    if (-not [System.IO.Path]::IsPathRooted($Path)) { throw ("a heartbeat is written to an absolute path, not '" + $Path + "'") }
    if ($Condition -ne "" -and $Condition -cnotmatch $script:HordeHeartbeatConditionPattern) { throw ("a heartbeat's condition is one lower-case word, not '" + $Condition + "'") }
    $beat = [ordered]@{ at = (ConvertTo-HordeHeartbeatTimeText -At $At); pid = $ProcessId; startedAt = $null; tickSeconds = $TickSeconds; pass = $Pass }
    if ($ProcessStartedAt -is [datetime]) { $beat["startedAt"] = ConvertTo-HordeHeartbeatTimeText -At $ProcessStartedAt }
    if ($Condition -ne "") { $beat["condition"] = $Condition; $beat["why"] = ConvertTo-HordeHeartbeatWhy -Text $Why }
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    [void][System.IO.Directory]::CreateDirectory($dir)
    $temp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $beat -Compress), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $Path }
    catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

function Write-HordeHeartbeatQuietly {
    # The same write for a loop that must outlive it: known "written", or unknown with the reason.
    # NEVER A THROW: the relay runner beats once a turn, and a turn must not end because a disk was
    # full or a reader held the file for longer than the rename waits.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][datetime]$At,
        [Parameter(Mandatory = $true)][int]$ProcessId,
        $ProcessStartedAt = $null,
        [Parameter(Mandatory = $true)][int]$TickSeconds,
        [long]$Pass = 0,
        [string]$Condition = "",
        [string]$Why = ""
    )
    try {
        Write-HordeHeartbeat -Path $Path -At $At -ProcessId $ProcessId -ProcessStartedAt $ProcessStartedAt -TickSeconds $TickSeconds -Pass $Pass -Condition $Condition -Why $Why
        return (New-HordeKnown -Value "written")
    } catch { return (New-HordeUnknown -Reason "the heartbeat could not be written" -ErrorRecord $_) }
}

function Read-HordeHeartbeat {
    # The heartbeat at -Path as an answer: known { at; pid; startedAt; tickSeconds; pass; condition;
    # why }, absent when
    # there is no file (the writer never ran here), or unknown when the file cannot be read as one. A
    # heartbeat that holds no time, or no pid, is unknown: it says nothing a reader can decide by.
    # startedAt is $null and tickSeconds 0 when the writer did not say; the reader decides what that
    # costs (Get-HordeHeartbeatVerdict).
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return (New-HordeAbsent -Note "there is no heartbeat: it has never run here") }
    $j = $null
    try {
        $text = Read-HordeSharedText -Path $Path
        if ($text.Length -gt $script:HordeHeartbeatMaxBytes) { return (New-HordeUnknown -Reason ("the heartbeat is " + $text.Length + " characters, more than a heartbeat is")) }
        $j = $text | ConvertFrom-Json
    } catch { return (New-HordeUnknown -Reason "the heartbeat could not be read" -ErrorRecord $_) }
    if ($null -eq $j -or $j -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason "the heartbeat is not a record") }
    $at = $null
    if ($null -ne $j.PSObject.Properties["at"]) { $at = ConvertFrom-HordeHeartbeatTimeText $j.at }
    if ($null -eq $at) { return (New-HordeUnknown -Reason "the heartbeat holds no time") }
    $processId = 0
    $given = $j.PSObject.Properties["pid"]
    if ($null -ne $given -and ($given.Value -is [int] -or $given.Value -is [long]) -and $given.Value -gt 0 -and $given.Value -le [int]::MaxValue) { $processId = [int]$given.Value }
    if ($processId -eq 0) { return (New-HordeUnknown -Reason "the heartbeat names no process") }
    $started = $null
    if ($null -ne $j.PSObject.Properties["startedAt"]) { $started = ConvertFrom-HordeHeartbeatTimeText $j.startedAt }
    $tick = 0
    $said = $j.PSObject.Properties["tickSeconds"]
    if ($null -ne $said -and ($said.Value -is [int] -or $said.Value -is [long]) -and $said.Value -gt 0 -and $said.Value -le 86400) { $tick = [int]$said.Value }
    $pass = [long]0
    $count = $j.PSObject.Properties["pass"]
    if ($null -ne $count -and ($count.Value -is [int] -or $count.Value -is [long]) -and $count.Value -ge 0) { $pass = [long]$count.Value }
    # A condition that is not one word is still a condition: it is read as "unwell", never as well -
    # an empty list or an empty object included (review of PR 249, round 2). Only a condition left
    # out, null or the empty text is none.
    $condition = ""; $why = ""
    $c = $j.PSObject.Properties["condition"]
    if ($null -ne $c -and $null -ne $c.Value -and -not ($c.Value -is [string] -and $c.Value -eq "")) {
        $condition = $(if (("" + $c.Value) -cmatch $script:HordeHeartbeatConditionPattern) { "" + $c.Value } else { "unwell" })
        $w = $j.PSObject.Properties["why"]
        if ($null -ne $w) { $why = ConvertTo-HordeHeartbeatWhy -Text $w.Value }
    }
    return (New-HordeKnown -Value ([pscustomobject]@{ at = $at; pid = $processId; startedAt = $started; tickSeconds = $tick; pass = $pass; condition = $condition; why = $why }) -ObservedAt $at)
}

function Get-HordeHeartbeatVerdict {
    # PURE. What a heartbeat answer says at -Now: known { fresh; ageSeconds; staleAfterSeconds;
    # tickSeconds }, or the answer's own absent or unknown passed on. The tick is the writer's own
    # when it gave one, else -DefaultTickSeconds (what the reader was told to expect of it).
    # A HEARTBEAT FROM THE FUTURE IS NOT FRESH BY ANY AMOUNT. A clock set back, or a file copied from
    # another machine, gives a negative age; read as "very fresh" it would keep a dead writer alive
    # until the clock caught up. More than the stale time ahead is unknown, with the reason; less is a
    # small disagreement between two clocks, and reads as an age of zero.
    param([Parameter(Mandatory = $true)]$Heartbeat, [Parameter(Mandatory = $true)][datetime]$Now, [int]$DefaultTickSeconds = 0, [int]$FloorSeconds = $script:HordeHeartbeatStaleFloorSeconds)
    Assert-HordeAnswer $Heartbeat
    if ($Heartbeat.state -cne "known") { return $Heartbeat }
    $tick = [int]$Heartbeat.value.tickSeconds
    if ($tick -le 0) { $tick = $DefaultTickSeconds }
    $stale = Get-HordeHeartbeatStaleSeconds -TickSeconds $tick -FloorSeconds $FloorSeconds
    $age = ($Now.ToUniversalTime() - $Heartbeat.value.at).TotalSeconds
    if ($age -lt (0 - $stale)) { return (New-HordeUnknown -Reason ("the heartbeat is dated " + [long](0 - $age) + " s in the future, so its age cannot be told")) }
    if ($age -lt 0) { $age = 0 }
    return (New-HordeKnown -Value ([pscustomobject]@{ fresh = [bool]($age -le $stale); ageSeconds = [long][System.Math]::Floor($age); staleAfterSeconds = $stale; tickSeconds = $tick }) -ObservedAt $Heartbeat.value.at)
}
