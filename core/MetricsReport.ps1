# core/MetricsReport - `horde metrics summarize`: read transcripts, measure them, show a table, and
# record the summaries when the gate allows.
#
# THE COMMAND FILE ONLY DECLARES (cli/Commands.ps1); the work is here, so a suite can call it without
# a process. It names no harness: transcripts are read through whichever adapter claims them.
#
# READING IS NOT GATED; RECORDING IS. Summarising a file the user names on the command line is the
# user reading their own file, as `Get-Content` would; nothing is kept. What the gate controls is
# whether a summary is written to Horde's home (core/MetricsStore.ps1).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). Needs core/Tristate.ps1,
# core/ReadShared.ps1, core/Home.ps1, core/Transcript.ps1, core/Price.ps1, core/Metrics.ps1,
# core/MetricsStore.ps1, and the adapters loaded.

function Get-HordeTranscriptFiles {
    # The .jsonl files a path names: the file itself, or every .jsonl under a folder, in name order.
    # Extension compared here, not with -Filter, which also matches 8.3 short names (cli/Commands.ps1,
    # measured 2026-09-29).
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return @((Get-Item -LiteralPath $Path).FullName) }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        return @(Get-ChildItem -LiteralPath $Path -File -Recurse | Where-Object { $_.Extension -ieq ".jsonl" } | Sort-Object FullName | ForEach-Object { $_.FullName })
    }
    throw ("no file or folder at " + $Path)
}

function Select-HordeRecordsInWindow {
    # The records whose time is inside [From, To]; either bound may be $null.
    param($Records, $From, $To)
    return @(@($Records) | Where-Object { ($null -eq $From -or $_.ts -ge $From) -and ($null -eq $To -or $_.ts -le $To) })
}

function Invoke-HordeMetricsSummarize {
    # Summarise every transcript under Path. Returns { rows; unread; priceTable; gate; recorded }:
    # rows hold each transcript's read, worker summary, orchestrator measures, the record and what
    # happened to it; unread lists files no adapter could read, with the reason.
    param([Parameter(Mandatory = $true)][string]$Path, $From = $null, $To = $null)
    $windowed = ($null -ne $From -or $null -ne $To)
    $table = Read-HordePriceBook
    $gate = Read-HordeMetricsGate
    $roots = @()
    foreach ($a in (Get-HordeTranscriptAdapters)) { $roots += @(& $a.storeRoots) }
    $rows = New-Object System.Collections.ArrayList
    $unread = New-Object System.Collections.ArrayList
    foreach ($file in (Get-HordeTranscriptFiles -Path $Path)) {
        $read = Read-HordeTranscript -Path $file
        if ($read.state -ne "known") { [void]$unread.Add([pscustomobject]@{ file = (Split-Path -Leaf $file); reason = $read.reason }); continue }
        $r = $read.value
        $records = @($r.records)
        if ($windowed) { $records = Select-HordeRecordsInWindow -Records $records -From $From -To $To }
        $worker = Get-HordeWorkerSummary -Records $records -PriceTable $table
        $orc = Get-HordeOrcMeasures -Records $records
        $record = New-HordeTranscriptSummaryRecord -Read $r -Worker $worker -Orc $orc
        if ($windowed) {
            $record["window"] = [ordered]@{ from = (ConvertTo-HordeJsonSafe $From); to = (ConvertTo-HordeJsonSafe $To) }
        }
        $decision = Get-HordeMetricsWriteDecision -Gate $gate -FirstEventAt $worker.firstEventAt -StoreRoots $roots -Windowed:$windowed
        $written = ""
        if ($decision.write) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($file)
            $written = Write-HordeMetricsRecord -Record $record -Adapter $r.adapter -Name $name
        }
        [void]$rows.Add([pscustomobject]@{ file = (Split-Path -Leaf $file); adapter = $r.adapter; read = $r; worker = $worker; orc = $orc; record = $record; decision = $decision; written = $written })
    }
    return [pscustomobject]@{ rows = $rows.ToArray(); unread = $unread.ToArray(); priceTable = $table; gate = $gate }
}

function Format-HordeCount {
    # An answer as table text: its value, "-" for absent, "?" for unknown. Numbers get thousands
    # separators in the invariant culture.
    param($Answer, [scriptblock]$Pick = { param($v) $v })
    if ($null -eq $Answer -or -not (Test-HordeAnswer $Answer)) { return "?" }
    if ($Answer.state -eq "absent") { return "-" }
    if ($Answer.state -eq "unknown") { return "?" }
    $v = & $Pick $Answer.value
    if ($v -is [int] -or $v -is [long]) { return $v.ToString("N0", [System.Globalization.CultureInfo]::InvariantCulture) }
    return "$v"
}

function Format-HordeMinutes {
    param($Seconds)
    return ([decimal]::Round([decimal]$Seconds / 60, 1)).ToString("0.0", [System.Globalization.CultureInfo]::InvariantCulture) + "m"
}

function Format-HordeTable {
    # Rows of cells as aligned text lines; the first row is the header.
    param($Rows)
    $rows = @($Rows)
    if ($rows.Count -eq 0) { return @() }
    $widths = @()
    foreach ($row in $rows) { for ($i = 0; $i -lt @($row).Count; $i++) { $len = "$(@($row)[$i])".Length; if ($widths.Count -le $i) { $widths += $len } elseif ($len -gt $widths[$i]) { $widths[$i] = $len } } }
    $out = @()
    foreach ($row in $rows) {
        $cells = @()
        for ($i = 0; $i -lt @($row).Count; $i++) { $cells += "$(@($row)[$i])".PadRight($widths[$i]) }
        $out += ($cells -join "  ").TrimEnd()
    }
    return $out
}

function Format-HordeMetricsSummary {
    # The text a user sees: the workers table, the orchestrator table when any transcript received
    # notifications, then what was not read, what prices were used, and what was recorded.
    param([Parameter(Mandatory = $true)]$Result)
    $lines = New-Object System.Collections.ArrayList
    $w = @(, @("transcript", "engine", "model", "wall", "calls", "tools", "input", "cache read", "cache write", "output", "longest gap (start UTC)", "longest tool call", "notional USD (ESTIMATE)"))
    foreach ($row in $Result.rows) {
        $s = $row.worker
        $gap = "-"
        if ($s.longestGap.state -eq "known") { $gap = (Format-HordeMinutes $s.longestGap.value.seconds) + " (" + $s.longestGap.value.startedAt.ToString("yyyy-MM-dd HH:mm", [System.Globalization.CultureInfo]::InvariantCulture) + ")" }
        $tool = "-"
        if ($s.longestToolCall.state -eq "known") {
            $tool = (Format-HordeMinutes $s.longestToolCall.value.seconds) + " " + $s.longestToolCall.value.name
            if (-not $s.longestToolCall.value.returned) { $tool += " (no result)" }
        }
        $cost = "?"
        if ($s.cost.cost.state -eq "known") { $cost = ([decimal]::Round($s.cost.cost.value, 2)).ToString("0.00", [System.Globalization.CultureInfo]::InvariantCulture) }
        $wall = "-"; if ($s.wallClockSeconds.state -eq "known") { $wall = Format-HordeMinutes $s.wallClockSeconds.value }
        $w += , @($row.file, $row.adapter, (Format-HordeCount $s.model), $wall, (Format-HordeCount $s.calls), (Format-HordeCount $s.toolCalls),
            (Format-HordeCount $s.tokens { param($v) $v.input }), (Format-HordeCount $s.tokens { param($v) $v.cacheRead }), (Format-HordeCount $s.tokens { param($v) $v.cacheWrite }),
            (Format-HordeCount $s.tokens { param($v) $v.output }), $gap, $tool, $cost)
    }
    foreach ($l in (Format-HordeTable -Rows $w)) { [void]$lines.Add($l) }

    $orcRows = @($Result.rows | Where-Object { $_.orc.notifications -gt 0 })
    if ($orcRows.Count -gt 0) {
        [void]$lines.Add("")
        [void]$lines.Add("orchestrator measures (attributed only where the transcript proves the worker)")
        $o = @(, @("transcript", "notifications (interim)", "still-waiting calls", "their context tokens", "worker results landed: chars (~tokens ESTIMATE)", "unattributed: chars", "job notifications"))
        foreach ($row in $orcRows) {
            $m = $row.orc
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            $o += , @($row.file, ("" + $m.notifications + " (" + $m.interimNotifications + ")"),
                ("" + $m.stillWaiting.calls + " (workers " + @($m.stillWaiting.byWorker.Values | Measure-Object -Sum).Sum + ", jobs " + $m.stillWaiting.jobs + ", unattributed " + $m.stillWaiting.unattributed + $(if ($m.stillWaiting.callsWithoutUsage -gt 0) { ", without usage " + $m.stillWaiting.callsWithoutUsage } else { "" }) + ")"),
                (Format-HordeCount $m.stillWaiting.contextTokens),
                ($m.landed.workerChars.ToString("N0", $inv) + " (~" + $m.landed.workerTokensEstimated.ToString("N0", $inv) + ") from " + @($m.landed.byWorker.Keys).Count + " workers"),
                ($m.landed.unattributedChars.ToString("N0", $inv) + " in " + $m.landed.unattributedCount),
                ("" + $m.landed.jobCount))
        }
        foreach ($l in (Format-HordeTable -Rows $o)) { [void]$lines.Add($l) }
    }

    [void]$lines.Add("")
    foreach ($u in $Result.unread) { [void]$lines.Add("not read: " + $u.file + ": " + $u.reason) }
    $skipped = @($Result.rows | Where-Object { $_.read.parseSkipped -gt 0 -or $_.read.tornTail -gt 0 })
    foreach ($row in $skipped) { [void]$lines.Add("lines not parsed: " + $row.file + ": " + $row.read.parseSkipped + " skipped, " + $row.read.tornTail + " still being written") }
    if ($Result.priceTable.state -eq "known") { [void]$lines.Add("cost: notional list price from " + ($Result.priceTable.value["sources"] -join ", ") + "; an ESTIMATE, never money spent on a subscription") }
    else { [void]$lines.Add("cost: unknown - " + $Result.priceTable.reason) }
    $written = @($Result.rows | Where-Object { $_.written -ne "" })
    if ($written.Count -gt 0) { [void]$lines.Add("recorded " + $written.Count + " summaries under " + (Join-Path (Get-HordeMetricsDir) "summaries")) }
    $notWritten = @($Result.rows | Where-Object { $_.written -eq "" })
    $reasons = @($notWritten | Group-Object { $_.decision.reason })
    foreach ($g in $reasons) { [void]$lines.Add("not recorded (" + $g.Count + "): " + $g.Name) }
    return $lines.ToArray()
}
