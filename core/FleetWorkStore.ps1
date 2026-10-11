# core/FleetWorkStore - append one fleet-work event to <HORDE_HOME>\metrics\fleet-work\events.jsonl.
#
# LOCAL ONLY. This file appends to one file on the local disk and does nothing else: no network, no
# transport, no remote call, no message to any session.
#
# BEHIND THE METRICS CONSENT GATE (core/MetricsStore.ps1), the same one every metrics record passes:
# no gate file, a gate at level off, or a gate that cannot be read, and nothing is written - no folder,
# no file - and the answer is "off" with the gate's reason. An event whose time is before the gate's
# enabledAt is not written either: nothing from before consent is recorded (metrics design, decision 8).
# The rest of the decision - a metrics folder inside an engine's own folders is never written to - is
# core/MetricsStore.ps1's Get-HordeMetricsWriteDecision, called, not copied.
#
# THE RULES, and what makes each one hold:
#   - ONLY AN EVENT core/FleetWork.ps1 READS IS WRITTEN. The line is made, then read as any reader
#     reads it; a refused line is answered "refused" with its reasons, before the gate is asked.
#   - ONE WHOLE LINE PER EVENT. The line and its LF go to the disk in ONE write call on a handle opened
#     write-through, then flushed. A writer killed mid-call can leave part of a line and no LF: the
#     reader sets that last line apart as torn (core/FleetWork.ps1), and the next writer, seeing the
#     file does not end with an LF, puts one before its own line in the same write call. So an event
#     always starts at the start of a line, and the torn bytes are never touched.
#   - ONE WRITER AT A TIME, BY THE FILE ITSELF: the file is opened for writing sharing only reading.
#     The operating system lets no second handle open it for writing while the first is open, in any
#     process; readers share it. A writer that finds it held waits, up to -WaitMs, and then answers
#     "busy" having written nothing. No named lock to leak, no lock file to go stale: the handle is
#     the lock, and a killed writer's handle is closed by the system.
#   - AN ID IS KEPT ONCE. Under that same handle, the lines already in the file are looked through for
#     the event's id; a line that has it and READS (so a torn or broken line never counts) answers
#     "exists", and nothing is written. The writer of an event sets its id once and sends the same id
#     on every retry, so a retry after "busy", after a crash, or after a lost answer adds no second
#     line. A different line under a kept id is still "exists", with a finding that it differs: the
#     first line stands, as a line is never changed.
#   - NEVER CHANGED, NEVER REMOVED. Nothing here seeks anywhere but the end to write, truncates or
#     deletes. What ends or reverses a line is a new line naming its id (schema/fleet-work-event.v1).
# THE COST: each write reads the whole file to look for its id. At about 300 bytes a line that is
# 3 MB at 10,000 events; when it matters, the file is split by month - a change of its own.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path $PSScriptRoot "FleetWork.ps1")
. (Join-Path $PSScriptRoot "MetricsStore.ps1")

$script:HordeFleetWorkFolder = "fleet-work"
$script:HordeFleetWorkFileName = "events.jsonl"

function Get-HordeFleetWorkLogPath {
    # Where the record is: <metrics folder>\fleet-work\events.jsonl. Not created here.
    return [System.IO.Path]::Combine((Get-HordeMetricsDir), $script:HordeFleetWorkFolder, $script:HordeFleetWorkFileName)
}

function New-HordeFleetWorkEventId {
    # 32 lower-case hex digits. Lower case only: the credential check reads a long run of both cases
    # and digits as a key (decisions/Rules.ps1).
    return [guid]::NewGuid().ToString("N")
}

function New-HordeFleetWorkEvent {
    # An event as an ordered map, its id and time set now unless given. -Values is the kind's map; its
    # keys are put in ordinal order, so the same event always makes the same line.
    param([Parameter(Mandatory = $true)][string]$Kind, [Parameter(Mandatory = $true)][string]$Lane, [Parameter(Mandatory = $true)]$Values, [string]$Id = "", [string]$Time = "")
    if ($Id -eq "") { $Id = New-HordeFleetWorkEventId }
    if ($Time -eq "") { $Time = [datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture) }
    return [ordered]@{ schemaVersion = 1; kind = $Kind; lane = $Lane; id = $Id; time = $Time; values = $Values }
}

function ConvertTo-HordeFleetWorkLine {
    # The event as one line of compact JSON, without its LF: the line's fields in the schema's order,
    # the values' keys in ordinal order, and every character that is not ASCII written as a \u escape.
    param([Parameter(Mandatory = $true)]$FleetEvent)
    $e = Get-HordeObjectByKey $FleetEvent
    $v = Get-HordeObjectByKey $e["values"]
    $values = [ordered]@{}
    $keys = [string[]]@($v.Keys)
    [Array]::Sort($keys, [System.StringComparer]::Ordinal)
    foreach ($k in $keys) { $values[$k] = $v[$k] }
    $ordered = [ordered]@{ schemaVersion = $e["schemaVersion"]; kind = $e["kind"]; lane = $e["lane"]; id = $e["id"]; time = $e["time"]; values = $values }
    $json = ConvertTo-Json -InputObject $ordered -Depth 5 -Compress
    return [regex]::Replace($json, '[^\x00-\x7F]', { param($m) "\u" + ([int][char]$m.Value).ToString("x4") })
}

function Get-HordeFleetWorkConsent {
    # May an event written at -Time be recorded? { write; reason }. Asks the metrics gate.
    param([Parameter(Mandatory = $true)][datetime]$Time)
    $gate = Read-HordeMetricsGate
    if ($gate.state -ceq "known" -and $gate.value.level -ceq "usage" -and $Time -lt $gate.value.enabledAt) {
        return [pscustomobject]@{ write = $false; reason = ("the event's time is before metrics were enabled; nothing from before consent is recorded") }
    }
    return (Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt (New-HordeKnown -Value $Time))
}

function Open-HordeFleetWorkLog {
    # The record opened for appending, shared for reading only, or $null when another writer still holds
    # it after -WaitMs. Any failure but "held by another" is thrown.
    param([Parameter(Mandatory = $true)][string]$Path, [int]$WaitMs)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try { return [System.IO.FileStream]::new($Path, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::Read, 4096, [System.IO.FileOptions]::WriteThrough) }
        catch {
            $ex = $_.Exception
            if ($null -ne $ex.InnerException) { $ex = $ex.InnerException }
            # 32 is a sharing violation, 33 a lock violation: another handle has the file.
            $code = $ex.HResult -band 0xFFFF
            if ($ex -isnot [System.IO.IOException] -or ($code -ne 32 -and $code -ne 33)) { throw }
            if ($clock.ElapsedMilliseconds -ge $WaitMs) { return $null }
            Start-Sleep -Milliseconds 25
        }
    }
}

function Find-HordeFleetWorkKept {
    # The line already in -Text that is a kept event with -Id, or $null. Only ENDED lines are looked at,
    # and only one that reads counts: a torn or broken line holding the id is no event.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text, [Parameter(Mandatory = $true)][string]$Id)
    $parts = $Text.Split([char]10)
    # A key "id" follows "{" or ","; inside a JSON text a quote is escaped, so a quoted id is not this.
    $pattern = '[{,]\s*"id"\s*:\s*"' + [regex]::Escape($Id) + '"'
    for ($n = 0; $n -lt $parts.Length - 1; $n++) {
        $lineText = $parts[$n].TrimEnd([char]13)
        if (-not [regex]::IsMatch($lineText, $pattern)) { continue }
        $a = Read-HordeFleetWorkEventText -Text $lineText
        if ($a.state -ceq "read" -and $a.event.id -ceq $Id) { return $lineText }
    }
    return $null
}

function Save-HordeFleetWorkEvent {
    # Append one event to the record. Returns { state; path; findings }:
    #   "written"   the line and its LF are in the file, written through and flushed;
    #   "exists"    a line with the event's id is kept already; nothing was written;
    #   "off"       consent says no (findings: why); nothing was written and nothing created;
    #   "busy"      another writer held the record for -WaitMs; nothing was written. Send it again;
    #   "refused"   core/FleetWork.ps1 refused the line (findings: why); nothing was created.
    # -FleetEvent is a map or object of the schema's fields (New-HordeFleetWorkEvent makes one).
    param([Parameter(Mandatory = $true)][Alias("Event")]$FleetEvent, [int]$WaitMs = 5000)
    $line = ConvertTo-HordeFleetWorkLine -FleetEvent $FleetEvent
    $read = Read-HordeFleetWorkEventText -Text $line
    if ($read.state -cne "read") { return [pscustomobject]@{ state = "refused"; path = ""; findings = [string[]]@($read.findings) } }
    $consent = Get-HordeFleetWorkConsent -Time (ConvertFrom-HordeFleetWorkTime -Stamp $read.event.time)
    if (-not $consent.write) { return [pscustomobject]@{ state = "off"; path = ""; findings = [string[]]@($consent.reason) } }
    $path = Get-HordeFleetWorkLogPath
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
    $fs = Open-HordeFleetWorkLog -Path $path -WaitMs $WaitMs
    if ($null -eq $fs) { return [pscustomobject]@{ state = "busy"; path = $path; findings = [string[]]@("another writer held the record for " + $WaitMs + " ms; nothing was written. Send the same event, with the same id, again") } }
    try {
        $have = New-Object byte[] ([int]$fs.Length)
        $got = 0
        while ($got -lt $have.Length) { $r = $fs.Read($have, $got, $have.Length - $got); if ($r -le 0) { break }; $got += $r }
        $kept = Find-HordeFleetWorkKept -Text ([System.Text.Encoding]::ASCII.GetString($have, 0, $got)) -Id $read.event.id
        if ($null -ne $kept) {
            $same = @()
            if ($kept -cne $line) { $same = @("the line kept under this id differs from the one given; the kept line stands, and the new one was not written") }
            return [pscustomobject]@{ state = "exists"; path = $path; findings = [string[]]$same }
        }
        $lead = ""
        if ($got -gt 0 -and $have[$got - 1] -ne 10) { $lead = "`n" }
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($lead + $line + "`n")
        [void]$fs.Seek(0, [System.IO.SeekOrigin]::End)
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
    } finally { $fs.Dispose() }
    return [pscustomobject]@{ state = "written"; path = $path; findings = [string[]]@() }
}

function Read-HordeFleetWorkFile {
    # The record on disk folded (core/FleetWork.ps1's Read-HordeFleetWorkLog); no file folds to nothing.
    # Read shared, so a writer's handle does not stop it.
    $path = Get-HordeFleetWorkLogPath
    if (-not [System.IO.File]::Exists($path)) { return (Read-HordeFleetWorkLog -Text "") }
    return (Read-HordeFleetWorkLog -Text (Read-HordeSharedText -Path $path))
}
