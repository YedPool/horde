# cli/RelayMetrics - the runner's side of the relay's request metrics: what this PC counts of its own
# conversation with the relay, and the one request a day that fetches the relay's summary of yesterday.
#
# WHY (the design note "relay request metrics", Orc F, 2026-10-14, approved by C). The founder asked for a
# metrics system that shows how requests are made, whether they are efficient, and whether batching or
# other methods would be cheaper, faster or more stable - and for suggestions back to him. The relay
# counts every request it answers (relays/<name>/, its own words); the fleet analyst reads the counts
# from <HORDE_HOME>\metrics, and sees BOTH ENDS of each conversation there: the relay's summary of a day
# and this PC's own counts of the same day, in one file, relay-YYYY-MM-DD.json.
#
# THIS PC'S OWN COUNTS, per UTC hour (cli/RelayRun.ps1 counts them as the run goes):
#   polls          watches of the machine's mailbox made (one a turn)
#   emptyPolls     of those, the ones that brought nothing
#   retries        turns begun after a failed turn (what the relay sees as x-horde-attempt over 1)
#   backoffWaits   backoffs waited out, and backoffMs their milliseconds
# Held in memory and written to pc-YYYY-MM-DD.json in the same folder whenever the hour turns and when
# the run ends, so a run that is restarted keeps what it counted before. Nothing of a message, a mailbox
# or a key is ever in them: the names above and whole numbers.
#
# ONE REQUEST A DAY. On the first turn of each UTC day the run asks the relay once for yesterday's
# summary (relays/Port.ps1, Get-HordeRelayDaySummary) - unless relay-<yesterday>.json is already there,
# so a run restarted later that day asks nothing. Whatever the answer, the file is written then, with
# the relay's summary or why it could not be read, and this PC's counts of that day; the day is then
# done, and a summary that failed is not asked for again. A relay that keeps no summary is asked nothing
# more and no file is written; nor are this PC's counts kept for it.
#
# EVERY FILE IS PRINTABLE ASCII: whatever the relay sent is written as JSON with every other character
# escaped (\uXXXX). Each is written to a temporary name beside it and then moved over, so a reader never
# sees half a file.
#
# NOTHING HERE THROWS: a count or a file that could not be written costs the metrics, never the run.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeRelayMetricsFolder = "metrics"
$script:HordeRelayMetricsNames = @("polls", "emptyPolls", "retries", "backoffWaits", "backoffMs")
$script:HordeRelayMetricsAscii = New-Object System.Text.ASCIIEncoding

function Get-HordeRelayMetricsHour { param([datetime]$At) return $At.ToUniversalTime().ToString("yyyy-MM-dd'T'HH", [System.Globalization.CultureInfo]::InvariantCulture) }
function Get-HordeRelayMetricsDay { param([datetime]$At) return $At.ToUniversalTime().ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture) }

function New-HordeRelayRunMetrics {
    # The run's metrics: { home; on; hours (hour -> counts); lookedOn }. -Connection decides whether
    # there is anything to keep at all: only a relay that keeps a summary of its own (the header).
    param([Parameter(Mandatory = $true)][string]$HordeHome, $Connection)
    $on = $false
    try { $on = ($null -ne $Connection -and $null -ne $Connection.relay -and $null -ne $Connection.relay.daySummary) } catch { $on = $false }
    return [pscustomobject]@{ home = $HordeHome; on = $on; hours = @{}; lookedOn = "" }
}

function Add-HordeRelayRunMetric {
    # One more -Name (one of the header's), by -By, in the hour of -At (UTC now by default).
    param([Parameter(Mandatory = $true)]$Metrics, [Parameter(Mandatory = $true)][string]$Name, [long]$By = 1, $At = $null)
    if (-not $Metrics.on -or $script:HordeRelayMetricsNames -cnotcontains $Name -or $By -lt 0) { return }
    $when = $(if ($At -is [datetime]) { $At } else { [datetime]::UtcNow })
    $hour = Get-HordeRelayMetricsHour -At $when
    if (-not $Metrics.hours.ContainsKey($hour)) { $c = [ordered]@{}; foreach ($n in $script:HordeRelayMetricsNames) { $c[$n] = [long]0 }; $Metrics.hours[$hour] = $c }
    $Metrics.hours[$hour][$Name] = [long]$Metrics.hours[$hour][$Name] + $By
}

function ConvertTo-HordeRelayMetricsJson {
    # -Value as JSON of printable ASCII and line ends only: every other character escaped (the header).
    param($Value)
    $json = $Value | ConvertTo-Json -Depth 12
    return [regex]::Replace($json, '[^\x0A\x0D\x20-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") })
}

function Write-HordeRelayMetricsFile {
    # -Text to -Path, through a temporary file beside it (the header). $true when written.
    param([string]$Path, [string]$Text)
    $tmp = $Path + ".tmp"
    try {
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllText($tmp, $Text, $script:HordeRelayMetricsAscii)
        if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Delete($Path) }
        [System.IO.File]::Move($tmp, $Path)
        return $true
    } catch {
        try { if ([System.IO.File]::Exists($tmp)) { [System.IO.File]::Delete($tmp) } } catch { }
        return $false
    }
}

function Get-HordeRelayMetricsPath {
    param([string]$HordeHome, [string]$Kind, [string]$Day)
    return (Join-Path (Join-Path $HordeHome $script:HordeRelayMetricsFolder) ($Kind + "-" + $Day + ".json"))
}

function Read-HordeRelayRunCounts {
    # This PC's counts of -Day as kept in its pc file: an ordered hour -> counts. Empty when there is no
    # file, or one that does not read (it is then written over).
    param([string]$HordeHome, [string]$Day)
    $out = [ordered]@{}
    $path = Get-HordeRelayMetricsPath -HordeHome $HordeHome -Kind "pc" -Day $Day
    try {
        if (-not [System.IO.File]::Exists($path)) { return $out }
        $j = [System.IO.File]::ReadAllText($path, $script:HordeRelayMetricsAscii) | ConvertFrom-Json
        foreach ($h in @($j.hours)) {
            $hour = "" + $h.hour
            if ($hour -cnotmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}\z' -or -not $hour.StartsWith($Day)) { continue }
            $c = [ordered]@{}
            foreach ($n in $script:HordeRelayMetricsNames) { $p = $h.PSObject.Properties[$n]; $c[$n] = $(if ($null -ne $p -and $p.Value -is [ValueType] -and [long]$p.Value -ge 0) { [long]$p.Value } else { [long]0 }) }
            $out[$hour] = $c
        }
    } catch { return ([ordered]@{}) }
    return $out
}

function ConvertTo-HordeRelayRunCountsList {
    # An hour -> counts map as the files hold it: [{ hour; polls; ... }], in hour order.
    param($Hours)
    $list = New-Object System.Collections.ArrayList
    foreach ($hour in @($Hours.Keys | Sort-Object)) {
        $row = [ordered]@{ hour = $hour }
        foreach ($n in $script:HordeRelayMetricsNames) { $row[$n] = [long]$Hours[$hour][$n] }
        [void]$list.Add([pscustomobject]$row)
    }
    return , @($list.ToArray())
}

function Save-HordeRelayRunMetrics {
    # Add what the run holds to each day's pc file, and hold nothing more (the header). -IfHourTurned
    # saves only when the run holds an hour before the current one: once an hour, not once a turn.
    param([Parameter(Mandatory = $true)]$Metrics, [switch]$IfHourTurned, $Now = $null)
    if (-not $Metrics.on -or $Metrics.hours.Count -eq 0) { return }
    $when = $(if ($Now -is [datetime]) { $Now } else { [datetime]::UtcNow })
    $current = Get-HordeRelayMetricsHour -At $when
    if ($IfHourTurned -and @($Metrics.hours.Keys | Where-Object { $_ -cne $current }).Count -eq 0) { return }
    foreach ($day in @($Metrics.hours.Keys | ForEach-Object { $_.Substring(0, 10) } | Sort-Object -Unique)) {
        $held = Read-HordeRelayRunCounts -HordeHome $Metrics.home -Day $day
        foreach ($hour in @($Metrics.hours.Keys | Where-Object { $_.StartsWith($day) })) {
            if (-not $held.Contains($hour)) { $c = [ordered]@{}; foreach ($n in $script:HordeRelayMetricsNames) { $c[$n] = [long]0 }; $held[$hour] = $c }
            foreach ($n in $script:HordeRelayMetricsNames) { $held[$hour][$n] = [long]$held[$hour][$n] + [long]$Metrics.hours[$hour][$n] }
        }
        $text = ConvertTo-HordeRelayMetricsJson ([ordered]@{ schemaVersion = 1; day = $day; hours = (ConvertTo-HordeRelayRunCountsList $held) })
        $null = Write-HordeRelayMetricsFile -Path (Get-HordeRelayMetricsPath -HordeHome $Metrics.home -Kind "pc" -Day $day) -Text $text
    }
    $Metrics.hours = @{}
}

function Invoke-HordeRelayRunMetricsDay {
    # The day's one request (the header, ONE REQUEST A DAY), on the first call of each UTC day of -Now:
    # $null when there was nothing to do; otherwise { day; path; state; reason } - state the summary's,
    # known or unknown - for the run to say in one line. -Connection is the run's.
    param([Parameter(Mandatory = $true)]$Metrics, [Parameter(Mandatory = $true)]$Connection, $Now = $null)
    if (-not $Metrics.on) { return $null }
    $when = $(if ($Now -is [datetime]) { $Now } else { [datetime]::UtcNow })
    $today = Get-HordeRelayMetricsDay -At $when
    if ($Metrics.lookedOn -ceq $today) { return $null }
    $Metrics.lookedOn = $today
    $day = Get-HordeRelayMetricsDay -At $when.ToUniversalTime().AddDays(-1)
    $path = Get-HordeRelayMetricsPath -HordeHome $Metrics.home -Kind "relay" -Day $day
    try { if ([System.IO.File]::Exists($path)) { return $null } } catch { return $null }
    Save-HordeRelayRunMetrics -Metrics $Metrics -Now $when
    $a = Get-HordeRelayDaySummary -Connection $Connection -Day $day
    $pcPath = Get-HordeRelayMetricsPath -HordeHome $Metrics.home -Kind "pc" -Day $day
    if ($a.state -ceq "absent") {
        # The relay keeps none now: nothing is written, and this PC's counts have nothing to sit beside.
        $Metrics.on = $false
        try { if ([System.IO.File]::Exists($pcPath)) { [System.IO.File]::Delete($pcPath) } } catch { }
        return $null
    }
    $relay = $(if ($a.state -ceq "known") { [ordered]@{ state = "known"; summary = $a.value.summary } } else { [ordered]@{ state = "unknown"; reason = ("" + $a.reason) } })
    $pc = ConvertTo-HordeRelayRunCountsList (Read-HordeRelayRunCounts -HordeHome $Metrics.home -Day $day)
    $text = ConvertTo-HordeRelayMetricsJson ([ordered]@{ schemaVersion = 1; day = $day; relay = $relay; pc = [ordered]@{ hours = $pc } })
    if (-not (Write-HordeRelayMetricsFile -Path $path -Text $text)) { return [pscustomobject]@{ day = $day; path = $path; state = "unknown"; reason = "the file could not be written" } }
    try { if ([System.IO.File]::Exists($pcPath)) { [System.IO.File]::Delete($pcPath) } } catch { }
    return [pscustomobject]@{ day = $day; path = $path; state = $a.state; reason = ("" + $a.reason) }
}
