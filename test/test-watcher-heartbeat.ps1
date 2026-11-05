# IS A DEAD OR HUNG OVERSEER WATCHER SEEN FROM OUTSIDE IT, AND TOLD ONCE PER EPISODE? (T-0388)
#
# core/WatcherHeartbeat.ps1 and the watcher check of `horde analyst tend`. The watcher's run.json is a file
# this suite writes in temp; the clock is moved by hand. Nobody is told: the tellers are the suite's own
# recorders, and the command's real tellers refuse a home under temp.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\WatcherHeartbeat.ps1")

$work = Join-Path $env:TEMP ("horde-watcher-beat-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$t0 = [datetime]::new(2026, 11, 4, 20, 0, 0, [System.DateTimeKind]::Utc)
$policy = [pscustomobject]@{ watcherStaleMinutes = 30; watcherHungMinutes = 15 }
$runPath = Join-Path $work "run.json"
$statePath = Join-Path $work "state\watcher-beat.json"
function Iso { param([int]$MinutesAgo) return $t0.AddMinutes(-$MinutesAgo).ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture) }
function Put-Run { param([AllowEmptyString()][string]$Json) [System.IO.File]::WriteAllText($runPath, $Json, $utf8) }
function Put-Pass { param($StartedAgo, $FinishedAgo) Put-Run ("{""started"":" + $(if ($null -eq $StartedAgo) { "null" } else { """" + (Iso $StartedAgo) + """" }) + ",""finished"":" + $(if ($null -eq $FinishedAgo) { "null" } else { """" + (Iso $FinishedAgo) + """" }) + "}") }
function Verdict { return (Get-HordeWatcherVerdict -Run (Read-HordeWatcherRun -Path $runPath) -Now $t0 -Policy $policy) }

try {
    Write-Host ""
    Write-Host "--- what is stale ---" -ForegroundColor Cyan
    if (Test-Path $runPath) { Remove-Item $runPath }
    $v = Verdict
    Check ($v.stale -and $v.kind -ceq "missing" -and $v.why -like "*missing*") "no file is stale, and says missing"
    Put-Pass 12 10
    Check (-not (Verdict).stale) "a pass that finished 10 minutes ago is fresh"
    Put-Pass 31 31
    $v = Verdict
    Check ($v.stale -and $v.kind -ceq "stopped" -and $v.why -like "*31 minutes*") "finished 31 minutes ago is stopped"
    Put-Pass 30 30
    Check (-not (Verdict).stale) "finished exactly 30 minutes ago is not yet stale (older than 30 is)"
    Put-Pass 5 15
    Check (-not (Verdict).stale) "a pass begun 5 minutes ago, the last one finished 15 minutes ago: running, fresh"
    Put-Pass 16 25
    $v = Verdict
    Check ($v.stale -and $v.kind -ceq "hung" -and $v.why -like "*16 minutes*") "begun 16 minutes ago and not finished is hung, though the last finish is only 25 minutes old"
    Put-Pass 15 25
    Check (-not (Verdict).stale) "begun exactly 15 minutes ago is not yet hung"
    Put-Pass 20 22
    Check ((Verdict).kind -ceq "hung") "begun 20 minutes ago after a finish 22 minutes ago: hung"
    Put-Pass 3 4
    Check (-not (Verdict).stale) "started older than finished is an ordinary finished pass: fresh"
    Put-Pass 40 $null
    Check ((Verdict).kind -ceq "hung") "a first pass never finished (no finished time) and begun 40 minutes ago is hung"
    Put-Pass 2 $null
    Check (-not (Verdict).stale) "a first pass begun 2 minutes ago is fresh"
    Put-Pass $null 45
    Check ((Verdict).kind -ceq "stopped") "only a finished time, 45 minutes old: stopped"
    Put-Run "{""started"":""2026-11-04T19:55:00"",""finished"":""2026-11-04T19:56:00""}"
    Check (-not (Verdict).stale) "a time with no zone is read as UTC (4 minutes old: fresh)"
    Put-Run "{""started"":""2026-11-04T15:55:00-05:00"",""finished"":""2026-11-04T15:56:00-05:00""}"
    Check (-not (Verdict).stale) "a time with an offset is converted to UTC (4 minutes old: fresh)"
    foreach ($bad in @("", "not json", "[1,2]", "{}", "{""started"":""yesterday"",""finished"":""today""}", "{""started"":5,""finished"":6}")) {
        Put-Run $bad
        $v = Verdict
        Check ($v.stale -and $v.kind -ceq "unreadable") ("unreadable run file is stale: " + $(if ($bad -eq "") { "(empty)" } else { $bad }))
    }

    Write-Host ""
    Write-Host "--- one alarm per episode; told only when taken; back closes it ---" -ForegroundColor Cyan
    $rig = [pscustomobject]@{ now = $t0; tells = (New-Object System.Collections.ArrayList); notices = (New-Object System.Collections.ArrayList); tellOk = $true; noticeOk = $true }
    $tools = @{
        Now = { return $rig.now }.GetNewClosure()
        Tell = { param($Body) [void]$rig.tells.Add($Body); return [pscustomobject]@{ ok = $rig.tellOk; detail = "the fleet mail failed" } }.GetNewClosure()
        Notify = { param($Line) [void]$rig.notices.Add($Line); return [pscustomobject]@{ ok = $rig.noticeOk; detail = "the notice failed" } }.GetNewClosure()
    }
    function Look { param([int]$Minutes) $rig.now = $t0.AddMinutes($Minutes); return (Invoke-HordeWatcherHeartbeat -Tools $tools -Policy $policy -RunPath $runPath -StatePath $statePath) }
    # The run file is written in minutes from t0 (Put-At); a look is taken at t0 + Minutes.
    function Put-At { param($StartedMin, $FinishedMin) Put-Run ("{""started"":""" + $t0.AddMinutes($StartedMin).ToString("o") + """,""finished"":""" + $t0.AddMinutes($FinishedMin).ToString("o") + """}") }
    Put-At -2 0
    $null = Look 5
    Check ($rig.tells.Count -eq 0 -and $rig.notices.Count -eq 0) "fresh: nobody told"
    $w = Look 35
    Check ($rig.notices.Count -eq 1 -and $rig.tells.Count -eq 1 -and $rig.notices[0] -like "Overseer watcher is stale (stopped)*35 minutes*" -and $rig.tells[0] -like "OVERSEER WATCHER STALE*") "stale: the founder gets one notice and the warchief one mail, with the reason"
    Check ((@($w.lines) -join " ") -like "*STALE (stopped)*told the founder's phone*told the warchief*") "and the pass says so"
    $null = Look 40; $null = Look 90
    Check ($rig.notices.Count -eq 1 -and $rig.tells.Count -eq 1) "while it stays stale nothing more is said"
    Put-At 99 100
    $w = Look 105
    Check ($rig.notices.Count -eq 2 -and $rig.notices[1] -like "*running again*" -and $rig.tells.Count -eq 1) "fresh again: one back notice to the founder, the episode closes"
    $null = Look 106
    Check ($rig.notices.Count -eq 2) "and then quiet while fresh"
    $null = Look 140
    Check ($rig.notices.Count -eq 3 -and $rig.tells.Count -eq 2 -and $rig.notices[2] -like "*stopped*") "stale again later: a new episode alarms again"
    Put-At 199 200; $null = Look 205
    Check ($rig.notices.Count -eq 4) "(recovered again)"

    Write-Host ""
    Write-Host "--- a tell that failed is not a tell ---" -ForegroundColor Cyan
    $rig.tells.Clear(); $rig.notices.Clear(); Remove-Item -LiteralPath $statePath
    $rig.tellOk = $false; $rig.noticeOk = $false
    $null = Look 300
    $null = Look 301
    Check ($rig.notices.Count -eq 2 -and $rig.tells.Count -eq 2) "neither taken: the next pass tries both again"
    $rig.noticeOk = $true
    $null = Look 302
    $null = Look 303
    Check ($rig.notices.Count -eq 3 -and $rig.tells.Count -eq 3) "the notice taken (the mail still failing): the episode counts as told, no more tries"
    $rig.tellOk = $true; $rig.noticeOk = $false; Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.notices.Clear()
    $null = Look 310; $null = Look 311
    Check ($rig.tells.Count -eq 1 -and $rig.notices.Count -eq 1) "the mail taken (the notice failing): told, no more tries"

    Write-Host ""
    Write-Host "--- no teller, a broken state file, a throwing teller ---" -ForegroundColor Cyan
    Remove-Item -LiteralPath $statePath
    $none = @{ Now = { return $t0.AddMinutes(400) }; Tell = $null; Notify = $null }
    $w = Invoke-HordeWatcherHeartbeat -Tools $none -Policy $policy -RunPath $runPath -StatePath $statePath
    Check ((@($w.lines) -join " ") -like "*telling is off*" -and -not (Test-Path $statePath)) "no tellers: it says so, and the episode is not marked told"
    [System.IO.File]::WriteAllText($statePath, "garbage{", $utf8)
    $rig.tells.Clear(); $rig.notices.Clear()
    $null = Look 400
    Check ($rig.notices.Count -eq 1) "a state file that cannot be read is a fresh one: at worst one more alarm"
    Remove-Item -LiteralPath $statePath
    $boom = @{ Now = { return $t0.AddMinutes(400) }; Tell = { throw "boom" }; Notify = { throw "boom" } }
    $w = Invoke-HordeWatcherHeartbeat -Tools $boom -Policy $policy -RunPath $runPath -StatePath $statePath
    Check ((@($w.lines) -join " ") -like "*could not tell the warchief: boom*" -and -not (Test-Path $statePath)) "a teller that throws is a failed tell, not a stopped pass"

    Write-Host ""
    Write-Host "--- is anyone reading the alarms? ---" -ForegroundColor Cyan
    $rp = [pscustomobject]@{ watcherReaderMinutes = 120 }
    $rdir = Join-Path $work "reader"
    $selfPath = Join-Path $rdir "self.txt"
    $mailRoot = Join-Path $rdir "mail"
    $rstate = Join-Path $rdir "state\reader.json"
    $sid = "abcd1234-reader"
    $inbox = Join-Path $mailRoot ($sid + "\inbox")
    [void][System.IO.Directory]::CreateDirectory($rdir)
    function Put-Mail { param([string]$Name, [AllowEmptyString()][string]$Json) [void][System.IO.Directory]::CreateDirectory($inbox); [System.IO.File]::WriteAllText((Join-Path $inbox ($Name + ".json")), $Json, $utf8) }
    function Mail-Ago { param([int]$Minutes) return ("{""createdAt"":""" + (Iso $Minutes) + """}") }
    function Reader { return (Get-HordeWatcherReaderVerdict -SelfPath $selfPath -MailRoot $mailRoot -Now $t0 -Policy $rp) }
    Check ((Reader).kind -ceq "unknown") "no file naming the reader is an alarm, not quiet"
    [System.IO.File]::WriteAllText($selfPath, "..\..\evil", $utf8)
    Check ((Reader).kind -ceq "unknown") "a first word that is no session id is unknown, and no path is built from it"
    [System.IO.File]::WriteAllText($selfPath, ($sid + " S`n"), $utf8)
    Check ((Reader).kind -ceq "nomail") "no fleet mail folder is an alarm, not quiet"
    [void][System.IO.Directory]::CreateDirectory($mailRoot)
    Check (-not (Reader).stale) "a reader with no inbox yet has nothing unread"
    Put-Mail "a" (Mail-Ago 120)
    Check (-not (Reader).stale) "mail exactly 120 minutes old is not yet stale"
    Put-Mail "b" (Mail-Ago 121)
    Put-Mail "c" (Mail-Ago 5)
    $v = Reader
    Check ($v.stale -and $v.kind -ceq "unread" -and $v.why -like "3 unread, the oldest 121 minutes*") "older than 120 is stale, and it counts all of them and ages the oldest"
    Remove-Item -LiteralPath (Join-Path $inbox "a.json"), (Join-Path $inbox "b.json"), (Join-Path $inbox "c.json")
    Put-Mail "bad" "not json"
    [System.IO.File]::SetLastWriteTimeUtc((Join-Path $inbox "bad.json"), $t0.AddMinutes(-300))
    Check ((Reader).kind -ceq "unread") "a message that cannot be read counts by its file's time"
    Remove-Item -LiteralPath (Join-Path $inbox "bad.json")
    Put-Mail "old" (Mail-Ago 300)
    $rig.tells.Clear(); $rig.notices.Clear(); $rig.tellOk = $true; $rig.noticeOk = $true
    $rt = @{ Now = { return $t0 }; Tell = $tools["Tell"]; Notify = $tools["Notify"] }
    function ReaderLook { return (Invoke-HordeWatcherReaderCheck -Tools $rt -Policy $rp -SelfPath $selfPath -MailRoot $mailRoot -StatePath $rstate) }
    $w = ReaderLook
    Check ($rig.notices.Count -eq 1 -and $rig.tells.Count -eq 1 -and (@($w.lines) -join " ") -like "*STALE (unread)*") "unread mail: one notice and one tell"
    $w = ReaderLook
    Check ($rig.notices.Count -eq 1 -and $rig.tells.Count -eq 1 -and @($w.lines).Count -eq 0) "and nothing more while it stays unread"
    Remove-Item -LiteralPath (Join-Path $inbox "old.json")
    $w = ReaderLook
    Check ($rig.notices.Count -eq 1 -and @($w.lines).Count -eq 0) "taken: the episode closes with no notice"
    Put-Mail "again" (Mail-Ago 300)
    $null = ReaderLook
    Check ($rig.notices.Count -eq 2) "the next backlog is a new episode"
    Remove-Item -LiteralPath $rstate
    $rig.notices.Clear(); $rig.tellOk = $false; $rig.noticeOk = $false
    $null = ReaderLook
    Check (-not (Test-Path $rstate)) "neither tell taken: not marked told, so the next pass tries again"
    $rig.tellOk = $true; $rig.noticeOk = $true

    Write-Host ""
    Write-Host "--- the settings and the command ---" -ForegroundColor Cyan
    foreach ($f in @("Tristate", "Home", "ModuleSettings", "AnalystRounds")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
    $d = Get-HordeAnalystSettings -HordeHome $work
    Check ($d.values.watcherCheck -eq $true -and $d.values.watcherStaleMinutes -eq 30 -and $d.values.watcherHungMinutes -eq 15 -and $d.values.watcherReaderMinutes -eq 120 -and $d.values.watcherRunFile -ceq "") "the settings default to 30, 15 and 120 minutes, on, the default file"
}
finally {
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

Complete-HordeSuite -Success "a stopped, hung or missing overseer watcher is seen from outside, told once per episode, and only when the tell was taken"
