# tools/nightly/NightlyWatch.ps1 - the missed-run watcher of the nightly net. T-0397.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\nightly\NightlyWatch.ps1 [-Plan] [-WorkRoot <dir>]
#       [-NoticeService <name> -NoticeSecretFile <path>] [-AtTime <datetime>] [-TaskXmlFile <file>]
#
# WHY IT EXISTS. On 2026-11-01 to 11-03 the nightly task fired an hour early, the net refused and nobody heard. PR 420
# made a refused start tell M, but that lives INSIDE the net: it cannot catch a task that never fired, a disabled or
# deleted task, a PC that was off, a run killed midway, or a tell that failed. This is a separate, independent checker,
# run by its own scheduled task once each morning (07:15, after the report deadline). It runs no tests, sends nothing
# about the tests, and does not depend on the net having run. It judges the night that began yesterday at 22:00 by the
# evidence on disk under the work folder (default %LOCALAPPDATA%\horde\nightly): nightly.log, reports\, */state.json.
#
#   RAN            the log shows the window open, the report exists, and the log shows it was sent.
#   NOT STARTED    nightly.log has no line for that date with the window open (also: no work folder, an empty one).
#   REFUSED        a -REFUSED report or a window CLOSED line, and no run.
#   FAILED, BUSY   those report files, and no report.
#   NOT REPORTED   it started but there is no reports\<date>.txt.
#   NOT TOLD       the report exists but the log has no report sent line.
# Every one but RAN is a MISSED night. A night that RAN but headed INCOMPLETE is a lower-level note to M only. The
# scheduled task itself is read too (missing, disabled, a trigger whose StartBoundary carries an offset): a finding even
# on a night that ran. THE WATCHER NEVER SAYS A RUN WAS RIGHT, only whether it happened and was reported.
#
# WHO HEARS, two channels, each tried whatever the other did:
#   1. the founder's phone: horde notify -Service <name> -SecretFile <path> -Text <one plain line>. Used only when BOTH
#      -NoticeService and -NoticeSecretFile are given; otherwise that channel is off and M's message says so. The secret is
#      never read here, only its path is handed to horde notify. A service is registered by M's side (notify-service).
#   2. M: <TellProgram> tell M -Kind report -MessageFile <file> (core Invoke-HordeNightlyTell).
# And always an alarm file, reports\<date>-WATCH.txt, written BEFORE either channel: the last resort.
# DEDUP (watch-state.json in the work folder): the same morning alarms once; a night still missed alarms again each
# morning with how many nights in a row (counted from the evidence, back at most -Lookback nights, so lost memory never
# hides it); recovery says so once. A corrupt memory only means one more alarm.
# Exit: 0 nothing to say, or it was said on at least one channel; 3 every channel failed (the alarm file is the last
# resort); 1 an error (the error is still written and told). -Plan prints the judgement and writes and sends nothing.
# Windows PowerShell 5.1 and 7. ASCII only.
param(
    [string]$WorkRoot = "",
    [string]$AtTime = "",
    [string]$TellProgram = "wezfleet",
    [string]$Target = "M",
    [string]$HordeScript = "",
    [string]$HordeHome = "",
    [string]$NoticeService = "",
    [string]$NoticeSecretFile = "",
    [string]$TaskName = "\Horde\HordeNightlyNet",
    [string]$TaskXmlFile = "",
    [ValidateRange(0, 900)][int]$TellRetrySeconds = 60,
    [ValidateRange(1, 5)][int]$TellTries = 2,
    [ValidateRange(2, 60)][int]$Lookback = 14,
    [switch]$Plan
)
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\NightlyNet.ps1")
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ($WorkRoot -eq "") { $WorkRoot = Join-Path (Join-Path $env:LOCALAPPDATA "horde") "nightly" }
if ($HordeScript -eq "") { $HordeScript = Join-Path $root "horde.ps1" }
$now = $(if ($AtTime -ne "") { [datetime]::Parse($AtTime, [System.Globalization.CultureInfo]::InvariantCulture) } else { Get-Date })
$ReportDir = Join-Path $WorkRoot "reports"
$WatchLog = Join-Path $WorkRoot "nightly-watch.log"
$StateFile = Join-Path $WorkRoot "watch-state.json"
$Fallback = Join-Path ([System.IO.Path]::GetTempPath()) "horde-nightly-fallback"

function Say {
    param([string]$Line)
    $l = (Get-Date).ToString("s") + " " + ($Line -replace "[^\x20-\x7E]", "?")
    # Its own log: nightly.log is the net's evidence and must hold only the net's lines.
    try { Add-Content -LiteralPath $WatchLog -Value $l -Encoding Ascii -ErrorAction Stop } catch { }
    Write-Host $l
}

function Read-WatchText {
    # A text file by its byte order mark (a log a 5.1 redirect wrote may be UTF-16); "" when it is not there.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    $b = [System.IO.File]::ReadAllBytes($Path)
    if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode.GetString($b) }
    return ([System.Text.Encoding]::UTF8.GetString($b).TrimStart([char]0xFEFF) -replace "`0", "")
}

function Write-WatchFile {
    # The alarm file: the report folder, and the temp path when that cannot be written. The path it landed in, or "".
    param([string]$Name, [string]$Text)
    foreach ($dir in @($ReportDir, $Fallback)) {
        try {
            [void][System.IO.Directory]::CreateDirectory($dir)
            $f = Join-Path $dir $Name
            [System.IO.File]::WriteAllText($f, $Text + "`n")
            return $f
        } catch { Say ("could not write " + $Name + " in " + $dir + ": " + $_.Exception.Message) }
    }
    return ""
}

function Get-WatchTaskXml {
    # The task's XML, or "" when it is missing or unreadable. -TaskXmlFile stands in for the scheduler (the suite): a
    # file that is not there is a missing task. The real scheduler is only ever read, with schtasks /Query.
    if ($TaskXmlFile -ne "") { return (Read-WatchText $TaskXmlFile) }
    try {
        $r = Invoke-HordeNightlyProcess -FilePath (Join-Path $env:SystemRoot "System32\schtasks.exe") -ArgumentList @("/Query", "/TN", $TaskName, "/XML") -TimeoutSeconds 60
        if ($r.timedOut -or $r.code -ne 0) { Say ("schtasks could not read " + $TaskName + " (exit " + $r.code + ")"); return "" }
        return (@($r.lines) -join "`n")
    } catch { Say ("schtasks failed: " + $_.Exception.Message); return "" }
}

function Get-WatchPending {
    # Findings M was not told, summed over every repo's state.json under the work folder.
    $n = 0
    foreach ($d in @(Get-ChildItem -LiteralPath $WorkRoot -Directory -ErrorAction SilentlyContinue)) {
        $f = Join-Path $d.FullName "state.json"
        $t = Read-WatchText $f
        if ($t -eq "") { continue }
        try { $o = ConvertFrom-HordeJson $t; if ($o.PSObject.Properties["pending"]) { $n += @(@($o.pending) | Where-Object { "" + $_ -ne "" }).Count } } catch { Say ("state unreadable, ignored: " + $f) }
    }
    return $n
}

function Send-WatchFounder {
    # horde notify -Service <name> -SecretFile <path> -Text <line>: the service proves itself with its secret file, which is
    # handed over by PATH and never read here. True when it exited 0.
    param([string]$Line)
    $old = $env:HORDE_HOME
    if ($HordeHome -ne "") { $env:HORDE_HOME = $HordeHome }
    try {
        $r = Invoke-HordeNightlyProcess -FilePath $HordeScript -ArgumentList @("notify", "-Service", $NoticeService, "-SecretFile", $NoticeSecretFile, "-Text", $Line) -TimeoutSeconds 120
    } finally { if ($HordeHome -ne "") { if ($null -eq $old) { Remove-Item Env:HORDE_HOME -ErrorAction SilentlyContinue } else { $env:HORDE_HOME = $old } } }
    $first = ConvertTo-HordeNightlyText ((@($r.lines) -join " "))
    if ($first.Length -gt 300) { $first = $first.Substring(0, 300) }
    Say ("founder notify exit " + $(if ($r.timedOut) { "TIMEOUT" } else { $r.code }) + ": " + $first)
    return (-not $r.timedOut -and $r.code -eq 0)
}

$date = ""
try {
    $night = Get-HordeNightlyWatchNight -Now $now
    $date = $night.date
    $folderMissing = -not (Test-Path -LiteralPath $WorkRoot -PathType Container)
    if (-not $folderMissing) { try { [void][System.IO.Directory]::CreateDirectory($ReportDir) } catch { } }
    $logText = Read-WatchText (Join-Path $WorkRoot "nightly.log")
    $reportNames = @(); if (Test-Path -LiteralPath $ReportDir -PathType Container) { $reportNames = @(Get-ChildItem -LiteralPath $ReportDir -File | ForEach-Object { $_.Name }) }
    $pending = $(if ($folderMissing) { 0 } else { Get-WatchPending })
    # Nights back from the one judged, until one that ran: the streak comes from the evidence, never from memory.
    $verdicts = @()
    foreach ($d in @(Get-HordeNightlyWatchDates -Date $date -Count $Lookback)) {
        $rt = $(if ($d -ceq $date) { Read-WatchText (Join-Path $ReportDir ($d + ".txt")) } else { "" })
        $v = Get-HordeNightlyWatchVerdict -Date $d -LogText $logText -ReportNames $reportNames -ReportText $rt -PendingCount $pending -FolderMissing $folderMissing
        $verdicts += $v
        if (-not $v.missed) { break }
    }
    $verdict = $verdicts[0]
    $streak = Get-HordeNightlyWatchStreak -Verdicts $verdicts
    $taskFindings = @(Get-HordeNightlyWatchTaskFindings -TaskXml (Get-WatchTaskXml))
    $state = Read-HordeNightlyWatchState -Text (Read-WatchText $StateFile)
    $decision = Get-HordeNightlyWatchDecision -Verdict $verdict -Streak $streak -TaskFindings $taskFindings -State $state
    Say ("watch " + $now.ToString("yyyy-MM-dd HH:mm") + ": night " + $date + " is " + $verdict.status + " (" + $verdict.detail + "), streak " + $streak + ", task findings " + $taskFindings.Count + ", decision " + $decision.kind)
    if ($Plan) {
        Write-Host ("PLAN night " + $date + ": " + $verdict.status + "; " + $verdict.detail)
        Write-Host ("PLAN missed in a row: " + $streak + "; incomplete note: " + $verdict.incomplete + "; decision: " + $decision.kind)
        foreach ($f in $taskFindings) { Write-Host ("PLAN task: " + $f) }
        Write-Host ("PLAN founder channel: " + $(if ($NoticeService -ne "" -and $NoticeSecretFile -ne "") { "on (service " + $NoticeService + ")" } else { "OFF (no -NoticeService and -NoticeSecretFile)" }))
        Write-Host "dry run: nothing written, nothing sent"
        exit 0
    }
    if ($decision.kind -ceq "quiet" -or $decision.kind -ceq "duplicate") { exit 0 }

    $msg = Format-HordeNightlyWatchMessage -Decision $decision -Verdict $verdict -Prior ([int]$state.streak) -Lookback $Lookback -Evidence ($WorkRoot)
    $alarmName = $date + "-WATCH.txt"
    $alarm = Write-WatchFile -Name $alarmName -Text $msg.m
    $founderOn = ($NoticeService -ne "" -and $NoticeSecretFile -ne "" -and $msg.founder -ne "")
    $channels = @()
    if ($founderOn) { $channels += [pscustomobject]@{ name = "founder"; send = { param($r) Send-WatchFounder $msg.founder } } }
    $channels += [pscustomobject]@{ name = "M"; send = {
            param($r)
            # M is told what the phone got, so a failure there is never silent either.
            $phoneNote = $(if ($founderOn) { $(if ($r["founder"]) { "the founder phone notice was sent" } else { "the founder phone notice FAILED, please tell the founder" }) } elseif ($msg.founder -ne "") { "the founder phone channel is not configured, please tell the founder" } else { "" })
            $text = $msg.m + $(if ($phoneNote -ne "") { "`n" + (ConvertTo-HordeNightlyText $phoneNote) } else { "" })
            $f = Write-WatchFile -Name $alarmName -Text $text
            if ($f -eq "") { return $false }
            return ((Invoke-HordeNightlyTell -Program $TellProgram -Target $Target -File $f -Tries $TellTries -RetrySeconds $TellRetrySeconds -Say { param($l) Say $l }) -eq 0)
        } }
    $sent = Invoke-HordeNightlyWatchSend -Channels $channels -Say { param($l) Say $l }
    $delivered = ($sent.ok -gt 0)
    # The state is saved whatever happened: a failed save only costs one more alarm.
    try {
        $next = Update-HordeNightlyWatchState -Decision $decision -Verdict $verdict -State $state -Delivered $delivered
        [System.IO.File]::WriteAllText($StateFile, ($next | ConvertTo-Json -Depth 3))
    } catch { Say ("the watch state was not saved: " + $_.Exception.Message) }
    if ($sent.allFailed) {
        Say ("EVERY channel failed: the alarm is in " + $alarm)
        exit 3
    }
    exit 0
} catch {
    $why = ConvertTo-HordeNightlyText ("" + $_.Exception.Message)
    Say ("the nightly watch FAILED: " + $why)
    if (-not $Plan) {
        $d = $(if ($date -ne "") { $date } else { $now.ToString("yyyy-MM-dd") })
        $f = Write-WatchFile -Name ($d + "-WATCH-ERROR.txt") -Text (ConvertTo-HordeNightlyText ("NIGHTLY WATCH " + $d + ": the watcher itself FAILED, so nobody checked last night. Error: " + $why + ". Log: " + $WatchLog))
        if ($f -ne "") { try { [void](Invoke-HordeNightlyTell -Program $TellProgram -Target $Target -File $f -Tries 1 -RetrySeconds 0 -Say { param($l) Say $l }) } catch { } }
    }
    exit 1
}
