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
    # The warchief's mailbox as the suite plays it (T-0391 slice 8): Tell marks and posts under (key, generation) like the real marked teller and
    # answers ok only when it posted (tellOk); with tellOk off and tellListed on it answers an UNKNOWN result that left its mark. Taken says "taken"
    # only when the suite has the warchief's session take that notice (taken[]), "pending" while marked, "lost" when the suite gives it up.
    $rig = [pscustomobject]@{ now = $t0; tells = (New-Object System.Collections.ArrayList); posts = (New-Object System.Collections.ArrayList); notices = (New-Object System.Collections.ArrayList)
                              tellOk = $true; tellListed = $false; noticeOk = $true; marked = @{}; taken = @{}; lost = @{}; held = @{}; dup = $false }
    $tools = @{
        Now = { return $rig.now }.GetNewClosure()
        Tell = {
            param($Body, $Key, $Gen)
            $id = "" + $Key + "|" + $Gen
            [void]$rig.tells.Add($Body); [void]$rig.posts.Add($id)
            if ($rig.dup) { return [pscustomobject]@{ ok = $true; detail = ""; listed = $false } }
            if ($rig.tellOk -or $rig.tellListed) { $rig.marked[$id] = $true }
            return [pscustomobject]@{ ok = $rig.tellOk; detail = "the fleet mail failed"; listed = ($rig.tellOk -or $rig.tellListed) }
        }.GetNewClosure()
        Taken = {
            param($Key, $Gen)
            $id = "" + $Key + "|" + $Gen
            if ($rig.lost.ContainsKey($id)) { return "lost" }
            if ($rig.held.ContainsKey($id)) { return "held" }
            if ($rig.marked.ContainsKey($id)) { if ($rig.taken.ContainsKey($id)) { return "taken" }; return "pending" }
            return "unknown"
        }.GetNewClosure()
        Notify = { param($Line) [void]$rig.notices.Add($Line); return [pscustomobject]@{ ok = $rig.noticeOk; detail = "the notice failed" } }.GetNewClosure()
    }
    # Look starts the state at episode 0 when there is no file, so a test can name the ids; a direct Invoke does not (the clock-made number, below).
    function Seed0 { param([string]$Path) if (-not [System.IO.File]::Exists($Path)) { Write-HordeWatcherBeatState -Path $Path -State (New-HordeWatcherBeatState -Gen 0) } }
    function Look { param([int]$Minutes) Seed0 $statePath; $rig.now = $t0.AddMinutes($Minutes); return (Invoke-HordeWatcherHeartbeat -Tools $tools -Policy $policy -RunPath $runPath -StatePath $statePath) }
    function Beat-State { return (Read-HordeWatcherBeatState -Path $statePath) }
    # The run file is written in minutes from t0 (Put-At); a look is taken at t0 + Minutes.
    function Put-At { param($StartedMin, $FinishedMin) Put-Run ("{""started"":""" + $t0.AddMinutes($StartedMin).ToString("o") + """,""finished"":""" + $t0.AddMinutes($FinishedMin).ToString("o") + """}") }
    Put-At -2 0
    $null = Look 5
    Check ($rig.tells.Count -eq 0 -and $rig.notices.Count -eq 0) "fresh: nobody told"
    $w = Look 35
    Check ($rig.notices.Count -eq 1 -and $rig.tells.Count -eq 1 -and $rig.notices[0] -like "Overseer watcher is stale (stopped)*35 minutes*" -and $rig.tells[0] -like "OVERSEER WATCHER STALE*") "stale: the founder gets one notice and the warchief one mail, with the reason"
    Check ((@($w.lines) -join " ") -like "*STALE (stopped)*told the founder's phone*posted to the warchief (counted as told only when his session takes it)*") "and the pass says so: the mail is posted, not yet told"
    Check ($rig.notices[0] -clike "*A notice to the warchief was posted and is being watched for its taking." -and $rig.notices[0] -cnotlike "*warchief is told*") "the phone is told what is known of the warchief's mail: posted and watched"
    Check ($rig.posts[0] -ceq "watcher-stale|0") "the mail is posted under the key watcher-stale and episode 0"
    $null = Look 40; $null = Look 90
    Check ($rig.notices.Count -eq 1 -and $rig.tells.Count -eq 1) "while it stays stale and the mail is awaited nothing more is said or posted"
    Check (-not (Beat-State).alerted -and (Beat-State).tell -ceq "posted" -and (Beat-State).phoneAbout -ceq "posted") "ROUND 3 (changed from 'nothing more is said' pinning the bug): the phone taking its notice does NOT count the episode told while the warchief's mail is only posted - the look at that mail goes on"
    Put-At 99 100
    $w = Look 105
    Check ($rig.notices.Count -eq 2 -and $rig.notices[1] -like "*running again*" -and $rig.tells.Count -eq 1) "fresh again: one back notice to the founder, the episode closes"
    $null = Look 106
    Check ($rig.notices.Count -eq 2) "and then quiet while fresh"
    $null = Look 140
    Check ($rig.notices.Count -eq 3 -and $rig.tells.Count -eq 2 -and $rig.notices[2] -like "*stopped*" -and $rig.posts[1] -ceq "watcher-stale|1") "stale again later: a new episode alarms again, with a new notice id"
    Put-At 199 200; $null = Look 205
    Check ($rig.notices.Count -eq 4) "(recovered again)"

    Write-Host ""
    Write-Host "--- a tell that failed is not a tell, and a tell not taken is not one either ---" -ForegroundColor Cyan
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); Remove-Item -LiteralPath $statePath
    $rig.tellOk = $false; $rig.noticeOk = $false
    $null = Look 300
    $null = Look 301
    Check ($rig.notices.Count -eq 2 -and $rig.tells.Count -eq 2 -and $rig.posts[0] -ceq $rig.posts[1]) "neither accepted: the next pass tries both again, the mail under the same id"
    Check ($rig.notices[0] -clike "*A notice to the warchief was not posted.") "and the phone's words say it was not posted"
    $rig.noticeOk = $true
    $null = Look 302
    $null = Look 303
    Check ($rig.notices.Count -eq 3 -and $rig.tells.Count -eq 4 -and $rig.posts[3] -ceq $rig.posts[0] -and -not (Beat-State).alerted) "ROUND 4 (changed from 'the episode counts as told, no more tries', which pinned the bug): the phone accepted but the mail was REFUSED - it is posted again, same id, on every later pass, and the episode is not told"
    $rig.tellOk = $true
    $null = Look 304
    Check ($rig.tells.Count -eq 5 -and (Beat-State).tell -ceq "posted" -and -not (Beat-State).alerted) "the refusal ends: the mail is posted, and awaited"
    $rig.taken[$rig.posts[4]] = $true
    $null = Look 305
    Check ((Beat-State).alerted -and (Beat-State).tell -ceq "taken") "and its TAKEN tells the episode"
    $rig.tellOk = $false
    # TELLING OFF (no Tell tool at all): only then does the phone's accept end it.
    Remove-Item -LiteralPath $statePath
    $noTell = @{ Now = $tools["Now"]; Tell = $null; Taken = $null; Notify = $tools["Notify"] }
    $rig.notices.Clear()
    $rig.now = $t0.AddMinutes(306); $null = Invoke-HordeWatcherHeartbeat -Tools $noTell -Policy $policy -RunPath $runPath -StatePath $statePath
    $rig.now = $t0.AddMinutes(307); $null = Invoke-HordeWatcherHeartbeat -Tools $noTell -Policy $policy -RunPath $runPath -StatePath $statePath
    Check ($rig.notices.Count -eq 1 -and (Beat-State).alerted -and $rig.notices[0] -clike "*telling is off.") "telling off: no mail can ever be posted, so the phone's accept counts the episode told, and it is not told twice"
    $rig.taken.Clear(); $rig.marked.Clear()
    # THE MAIL ACCEPTED IS NOT TOLD: only the warchief's own TAKEN counts it.
    $rig.tellOk = $true; $rig.noticeOk = $false; Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear()
    $null = Look 310; $null = Look 311
    Check ($rig.tells.Count -eq 1 -and $rig.notices.Count -eq 2 -and -not (Beat-State).alerted -and (Beat-State).tell -ceq "posted") "the mail accepted (the notice failing): POSTED, not told - not posted again - and the phone, which refused, is tried again on the next pass"
    $null = Look 312
    Check (-not (Beat-State).alerted -and $rig.tells.Count -eq 1 -and $rig.notices.Count -eq 3) "still not told on a later pass (and the phone tried again)"
    $rig.taken[$rig.posts[0]] = $true
    $w = Look 313
    Check ((Beat-State).alerted -and (Beat-State).tell -ceq "taken" -and (@($w.lines) -join " ") -like "*took the notice*" -and $rig.tells.Count -eq 1) "the warchief's session takes it: now it is told, and the line says so"
    $nTaken = $rig.notices.Count
    $null = Look 314
    Check ($rig.notices.Count -eq ($nTaken + 1) -and (Beat-State).phoneAbout -ceq "") "NIT 1: the phone still has not taken anything, so it is tried again even after TAKEN"
    $rig.noticeOk = $true
    $null = Look 315
    Check ((Beat-State).phoneAbout -ceq "taken" -and $rig.notices[-1] -clike "*A notice to the warchief was taken by his session.") "and when it takes it, it is told what is known: the warchief's session took the notice"
    $nDone = $rig.notices.Count
    $null = Look 316
    Check ($rig.tells.Count -eq 1 -and $rig.notices.Count -eq $nDone) "and then quiet"
    $rig.noticeOk = $false
    # ROUND 3, RED FIRST: the phone ACCEPTS, the warchief never takes the mail, and the messenger then HOLDS it: the watch must still be looking.
    Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.taken.Clear()
    $rig.noticeOk = $true
    $null = Look 317; $null = Look 318
    Check ((Beat-State).tell -ceq "posted" -and -not (Beat-State).alerted -and $rig.notices.Count -eq 1 -and $rig.tells.Count -eq 1) "the phone accepted 'posted and watched'; the mail is not taken: still being looked at, not counted"
    $rig.held[$rig.posts[0]] = $true
    $w = Look 319
    Check ((Beat-State).tell -ceq "held" -and $rig.notices.Count -eq 2 -and $rig.notices[-1] -clike "*The warchief's notice could not be delivered: the messenger holds it, and it was not taken." -and (Beat-State).alerted) "the mail is then HELD: the phone is told so, in the held words, once - and the episode is now over (phone told, mail not in play)"
    $null = Look 320
    Check ($rig.notices.Count -eq 2 -and $rig.tells.Count -eq 1) "and nothing more is said"
    $rig.held.Clear(); $rig.noticeOk = $false
    # An UNKNOWN result may have landed: its mark is kept, the phone says may, and it is posted again, same id (it may not have).
    Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.taken.Clear()
    $rig.tellOk = $false; $rig.tellListed = $true
    $null = Look 320; $null = Look 321
    Check ($rig.tells.Count -eq 2 -and $rig.posts[1] -ceq $rig.posts[0] -and $rig.notices[0] -clike "*A notice to the warchief may have been posted; the watch cannot tell." -and (Beat-State).tell -ceq "maybe" -and -not (Beat-State).alerted) "an UNKNOWN result: the phone is told it MAY have been posted (not 'not posted'), it is watched, and posted AGAIN at the next pass under the same id"
    $rig.tellOk = $true; $rig.tellListed = $false
    $null = Look 322
    Check ($rig.tells.Count -eq 3 -and $rig.posts[2] -ceq $rig.posts[0] -and (Beat-State).tell -ceq "posted") "a repost the messenger then accepts makes it posted"
    # A notice the messenger HOLDS is not told, not posted again - and the phone, which refused, is tried again with what is known (SHOULD-FIX 2).
    $rig.held[$rig.posts[0]] = $true
    $w = Look 323
    Check ((Beat-State).tell -ceq "held" -and -not (Beat-State).alerted -and (@($w.lines) -join " ") -clike "*the notice to the warchief could not be delivered (the messenger holds it for good) and is not taken; he is not told*") "a notice the messenger holds is NOT told: the line says it could not be delivered"
    $nBefore = $rig.notices.Count
    $null = Look 324
    Check ($rig.tells.Count -eq 3 -and $rig.notices.Count -eq ($nBefore + 1) -and $rig.notices[-1] -clike "*The warchief's notice could not be delivered: the messenger holds it, and it was not taken.") "the phone refused earlier: it is tried again, with what is known, and nothing is posted again"
    $rig.noticeOk = $true
    $null = Look 325
    Check ((Beat-State).alerted -and $rig.tells.Count -eq 3) "the phone takes it this time: the episode is told, to the phone"
    $nAfter = $rig.notices.Count
    $null = Look 326
    Check ($rig.notices.Count -eq $nAfter) "and then quiet"
    Put-At 329 330
    $null = Look 331
    Check ((Beat-State).tell -ceq "" -and (Beat-State).gen -eq 1 -and -not (Beat-State).alerted) "fresh again closes the episode and raises the number"
    # ok with no mark kept (already posted): neither posted nor watched, and said so; an earlier copy's fate is not this notice's.
    Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.held.Clear()
    $rig.noticeOk = $false; $rig.dup = $true
    Put-At 199 200
    $null = Look 345; $null = Look 346
    $rig.taken[$rig.posts[0]] = $true
    $null = Look 347
    Check ($rig.tells.Count -eq 3 -and $rig.notices[0] -clike "*Nothing new was posted to the warchief: the messenger already held a copy of this notice." -and (Beat-State).tell -ceq "" -and -not (Beat-State).alerted) "a repost of a copy the messenger held: the phone is told nothing new was posted (not 'posted and watched'), it is tried again, and the copy's TAKEN is not counted"
    $rig.dup = $false
    # A REMOVED STATE FILE never starts again at an episode whose ids the messenger holds (MUST-FIX 1b).
    Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.taken.Clear()
    $rig.marked["watcher-stale|0"] = $true; $rig.taken["watcher-stale|0"] = $true
    $rig.tellOk = $true; $rig.noticeOk = $false
    $rig.now = $t0.AddMinutes(360)
    $null = Invoke-HordeWatcherHeartbeat -Tools $tools -Policy $policy -RunPath $runPath -StatePath $statePath
    $secsW = [long][System.Math]::Floor(($t0.AddMinutes(360).ToUniversalTime() - ([datetime]"1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds)
    Check ((Beat-State).gen -eq $secsW -and $rig.posts[0] -ceq ("watcher-stale|" + $secsW)) "a state with no file takes its episode number from the clock, writes it at once, and the notice id carries it - not the id of 'episode 0'"
    $rig.now = $t0.AddMinutes(361)
    $w = Invoke-HordeWatcherHeartbeat -Tools $tools -Policy $policy -RunPath $runPath -StatePath $statePath
    Check (-not (Beat-State).alerted -and (Beat-State).tell -ceq "posted" -and $rig.tells.Count -eq 1 -and (@($w.lines) -join " ") -cnotlike "*took the notice*") "and an earlier episode's taken notice is not counted as this one's TAKEN"
    $rig.taken.Clear(); $rig.marked.Clear()
    # Nothing accepted: the retry has the SAME id (the fresh state was written at once with its clock-made number).
    Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.taken.Clear()
    $rig.tellOk = $false; $rig.tellListed = $false; $rig.noticeOk = $false
    $rig.now = $t0.AddMinutes(370); $null = Invoke-HordeWatcherHeartbeat -Tools $tools -Policy $policy -RunPath $runPath -StatePath $statePath
    $rig.now = $t0.AddMinutes(371); $null = Invoke-HordeWatcherHeartbeat -Tools $tools -Policy $policy -RunPath $runPath -StatePath $statePath
    Check ($rig.posts.Count -eq 2 -and $rig.posts[0] -ceq $rig.posts[1] -and $rig.posts[0] -cnotlike "*|0") "a post nothing accepted is tried again at the next pass under the same id, though the state had no file (its clock-made number was written at once)"
    # A post whose result was unknown, that turns out TAKEN, is counted told (the look comes before the repost).
    Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.taken.Clear()
    $rig.tellOk = $false; $rig.tellListed = $true
    $null = Look 380
    $rig.taken[$rig.posts[0]] = $true
    $null = Look 381
    Check ((Beat-State).alerted -and $rig.tells.Count -eq 1) "a post whose result was unknown, that turns out TAKEN, is counted told - and not posted again"
    $rig.tellOk = $true; $rig.tellListed = $false; $rig.taken.Clear(); $rig.marked.Clear()
    # ROUND 3 (SHOULD 2): a mail whose result stays unknown is posted again at each pass, and the 7-day give-up counts from the FIRST post.
    Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.taken.Clear()
    $rig.tellOk = $false; $rig.tellListed = $true; $rig.noticeOk = $true
    $dayMin = 1440
    $null = Look 3000
    foreach ($d in @(3, 6)) { $null = Look (3000 + $d * $dayMin) }
    Check ((Beat-State).tell -ceq "maybe" -and (Beat-State).tellAt -eq $t0.AddMinutes(3000) -and $rig.tells.Count -eq 3) "an unknown mail posted again for days keeps the time of its FIRST post"
    $w = Look (3000 + 8 * $dayMin)
    Check ((Beat-State).tell -ceq "lost" -and (@($w.lines) -join " ") -like "*not taken in time*") "so it is given up 7 days after the first post, however often it was posted again"
    $rig.tellOk = $true; $rig.tellListed = $false
    # With no Taken tool nothing is counted; a notice awaited a notice-ttl is given up.
    Remove-Item -LiteralPath $statePath
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.lost.Clear()
    $rig.tellOk = $true; $rig.tellListed = $false
    $noTaken = @{ Now = $tools["Now"]; Tell = $tools["Tell"]; Notify = $tools["Notify"] }
    $rig.noticeOk = $false
    $rig.now = $t0.AddMinutes(500); $null = Invoke-HordeWatcherHeartbeat -Tools $noTaken -Policy $policy -RunPath $runPath -StatePath $statePath
    $rig.now = $t0.AddMinutes(501); $null = Invoke-HordeWatcherHeartbeat -Tools $noTaken -Policy $policy -RunPath $runPath -StatePath $statePath
    Check (-not (Beat-State).alerted -and (Beat-State).tell -ceq "posted" -and $rig.tells.Count -eq 1) "no Taken tool: nothing is ever counted as taken, and nothing is posted twice"
    $rig.now = $t0.AddMinutes(500 + 8 * 24 * 60)
    $w = Invoke-HordeWatcherHeartbeat -Tools $noTaken -Policy $policy -RunPath $runPath -StatePath $statePath
    Check ((Beat-State).tell -ceq "lost" -and (@($w.lines) -join " ") -like "*the notice to the warchief was not taken in time and is no longer watched (it may still be in his mailbox)*") "and one awaited a notice-ttl (7 days) is given up, in what is known of it"
    $rig.noticeOk = $true
    [System.IO.File]::WriteAllText($statePath, '{"v":1,"alerted":true,"since":"2026-11-04T20:00:00.0000000Z"}', $utf8)
    Check ((Beat-State).alerted -and (Beat-State).gen -eq 0 -and (Beat-State).tell -ceq "" -and (Beat-State).phoneAbout -ceq "legacy" -and -not (Beat-State).unreadable) "a state file an earlier version wrote still reads: episode 0, nothing posted, and the phone counted as told (it is not told again)"
    [System.IO.File]::WriteAllText($statePath, '{"v":1,"alerted":false,"gen":3,"tell":"posted","phoneAbout":"bogus"}', $utf8)
    Check ((Beat-State).unreadable) "a phone value that is not known makes the state unreadable: no guess"

    Write-Host ""
    Write-Host "--- no teller, a broken state file, a throwing teller ---" -ForegroundColor Cyan
    Remove-Item -LiteralPath $statePath
    $none = @{ Now = { return $t0.AddMinutes(400) }; Tell = $null; Notify = $null }
    $w = Invoke-HordeWatcherHeartbeat -Tools $none -Policy $policy -RunPath $runPath -StatePath $statePath
    Check ((@($w.lines) -join " ") -like "*telling is off*" -and -not (Beat-State).alerted -and (Beat-State).tell -ceq "") "no tellers: it says so, and the episode is not marked told"
    [System.IO.File]::WriteAllText($statePath, "garbage{", $utf8)
    foreach ($m in @(".told", ".phone", ".logged")) { if (Test-Path ($statePath + $m)) { Remove-Item -LiteralPath ($statePath + $m) } }
    $rig.tells.Clear(); $rig.notices.Clear(); $rig.posts.Clear(); $rig.marked.Clear(); $rig.taken.Clear()
    $w = Look 400
    Check ((@($w.lines) -join " ") -like "*its state file cannot be read*" -and [System.IO.File]::ReadAllText($statePath) -ceq "garbage{") "ROUND 3 (SHOULD 1): a state file that cannot be read is said, and the file is KEPT, not written over"
    Check ($rig.tells.Count -eq 1 -and $rig.posts[0] -clike "watcher-unreadable|*" -and $rig.tells[0] -like "WATCHER CHECK BLIND*" -and $rig.notices.Count -eq 1 -and $rig.notices[0] -clike "*cannot read its state file*A notice to the warchief was posted and is being watched for its taking.") "ROUND 4: and nobody is left in the dark: the warchief's mail is posted (marked first) and the phone is told what is known of it"
    $w = Look 401
    Check ($rig.tells.Count -eq 1 -and $rig.notices.Count -eq 1 -and @($w.lines).Count -eq 0) "once a day: nothing more is posted, told or logged on the next pass"
    $rig.taken[$rig.posts[0]] = $true
    $w = Look 402
    Check ((@($w.lines) -join " ") -like "*took the UNREADABLE-STATE notice*" -and ([System.IO.File]::ReadAllText($statePath + ".told")) -ceq "told") "the warchief's session takes it: counted told"
    Check ($rig.notices.Count -eq 2 -and $rig.notices[-1] -clike "*A notice to the warchief was taken by his session.") "ROUND 5: and the phone, told 'posted and watched', is told ONCE that it was taken"
    $null = Look 403; $null = Look 404
    Check ($rig.notices.Count -eq 2) "and not again on later passes"
    $null = Look (400 + 1440 + 5)
    Check ($rig.tells.Count -eq 2 -and $rig.posts[1] -cne $rig.posts[0] -and $rig.notices.Count -eq 3) "a day later it is said again, under a new id"
    foreach ($m in @(".told", ".phone", ".logged")) { if (Test-Path ($statePath + $m)) { Remove-Item -LiteralPath ($statePath + $m) } }
    # ROUND 5, SHOULD 1: a refused mail is tried again on every pass, but the LOG says it once a day (its own mark, so it holds across a restart).
    $rig.tellOk = $false; $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear()
    $ll = @()
    foreach ($m in @(3000, 3001, 3002)) { $ll += @((Look $m).lines) }
    Check ($rig.tells.Count -eq 3 -and $rig.posts[1] -ceq $rig.posts[0] -and $rig.posts[2] -ceq $rig.posts[0] -and -not (Test-Path ($statePath + ".told"))) "a refused mail leaves no mark and is tried again at EVERY pass, same id"
    Check (@($ll | Where-Object { $_ -like "*its state file cannot be read*" }).Count -eq 1 -and @($ll | Where-Object { $_ -like "*could not tell the warchief*" }).Count -le 1) "REFUSED: three passes give exactly one 'cannot be read' line and the refusal is logged once"
    Check (Test-Path ($statePath + ".logged")) "the day's log is kept in a mark of its own"
    foreach ($m in @(".told", ".phone", ".logged")) { if (Test-Path ($statePath + $m)) { Remove-Item -LiteralPath ($statePath + $m) } }
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear()
    $noTell2 = @{ Now = $tools["Now"]; Tell = $null; Taken = $null; Notify = $tools["Notify"] }
    $ll = @()
    foreach ($m in @(3010, 3011, 3012)) { $rig.now = $t0.AddMinutes($m); $ll += @((Invoke-HordeWatcherHeartbeat -Tools $noTell2 -Policy $policy -RunPath $runPath -StatePath $statePath).lines) }
    Check (@($ll | Where-Object { $_ -like "*its state file cannot be read*" }).Count -eq 1 -and @($ll | Where-Object { $_ -like "*telling is off*" -and $_ -like "*the warchief*" }).Count -eq 1) "TELLING OFF: three passes give exactly one 'cannot be read' line and one 'telling is off' line"
    # ROUND 5, SHOULD 2: the phone was told 'not posted'; when the mail is later posted and TAKEN it is told once - not on every pass, and not for 'posted'.
    foreach ($m in @(".told", ".phone", ".logged")) { if (Test-Path ($statePath + $m)) { Remove-Item -LiteralPath ($statePath + $m) } }
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.taken.Clear()
    $rig.tellOk = $false; $null = Look 3020
    Check ($rig.notices.Count -eq 1 -and $rig.notices[0] -clike "*A notice to the warchief was not posted." -and ([System.IO.File]::ReadAllText($statePath + ".phone")) -ceq "none") "the mail was refused: the phone is told 'not posted', and keeps what it was told"
    $rig.tellOk = $true; $null = Look 3021
    Check ($rig.tells.Count -eq 2 -and $rig.notices.Count -eq 1) "the mail is then posted: that is not a change the phone is told of"
    $rig.taken[$rig.posts[-1]] = $true
    $null = Look 3022
    Check ($rig.notices.Count -eq 2 -and $rig.notices[-1] -clike "*A notice to the warchief was taken by his session." -and ([System.IO.File]::ReadAllText($statePath + ".phone")) -ceq "taken") "and TAKEN: the phone gets exactly one update"
    $null = Look 3023; $null = Look 3024
    Check ($rig.notices.Count -eq 2) "and none when nothing changed"
    foreach ($m in @(".told", ".phone", ".logged")) { if (Test-Path ($statePath + $m)) { Remove-Item -LiteralPath ($statePath + $m) } }
    $rig.tellOk = $true
    [System.IO.File]::WriteAllText($statePath, '{"v":1,"alerted":true,"since":"2026-11-04T20:00:00.0000000Z","gen":5,"tell":"bogus"}', $utf8)
    $w = Look 3002
    Check ((@($w.lines) -join " ") -like "*cannot be read*" -and [System.IO.File]::ReadAllText($statePath) -clike '*"tell":"bogus"*') "and so is a live episode with a value that is not known: it is not forgotten"
    foreach ($m in @(".told", ".phone", ".logged")) { if (Test-Path ($statePath + $m)) { Remove-Item -LiteralPath ($statePath + $m) } }
    Remove-Item -LiteralPath $statePath
    $boom = @{ Now = { return $t0.AddMinutes(400) }; Tell = { throw "boom" }; Notify = { throw "boom" } }
    $w = Invoke-HordeWatcherHeartbeat -Tools $boom -Policy $policy -RunPath $runPath -StatePath $statePath
    Check ((@($w.lines) -join " ") -like "*could not tell the warchief: boom*" -and -not (Beat-State).alerted -and (Beat-State).tell -ceq "") "a teller that throws is a failed tell, not a stopped pass"

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
    Check ((Get-HordeWatcherReaderMessageTime -Path (Join-Path $inbox "bad.json")) -eq $t0.AddMinutes(-300)) "CONTROL: the file time of a message that is there"
    Remove-Item -LiteralPath (Join-Path $inbox "bad.json")
    # Review of T-0388: the reader takes a message between the listing and the read; a missing file's time reads 1601.
    Check ($null -eq (Get-HordeWatcherReaderMessageTime -Path (Join-Path $inbox "bad.json"))) "a message taken while it is being looked at has no age: a reader draining its mail is no alarm"
    Put-Mail "denied" (Mail-Ago 5)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $null = & icacls $inbox /deny ("*" + $me + ":(RD)")
    try { $v = Reader; $listed = $true } catch { $listed = $false } finally { $null = & icacls $inbox /remove:d ("*" + $me) }
    Check ($listed -and $v.stale -and $v.kind -ceq "unreadable") "an inbox that cannot be listed is an alarm, not a thrown pass and not quiet"
    Check (-not (Reader).stale) "CONTROL: the same inbox, readable again, is quiet"
    Remove-Item -LiteralPath (Join-Path $inbox "denied.json")
    Put-Mail "old" (Mail-Ago 300)
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear(); $rig.taken.Clear(); $rig.lost.Clear(); $rig.tellOk = $true; $rig.tellListed = $false; $rig.noticeOk = $true
    $rt = @{ Now = { return $t0 }; Tell = $tools["Tell"]; Taken = $tools["Taken"]; Notify = $tools["Notify"] }
    function ReaderLook { Seed0 $rstate; return (Invoke-HordeWatcherReaderCheck -Tools $rt -Policy $rp -SelfPath $selfPath -MailRoot $mailRoot -StatePath $rstate) }
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
    Check (-not (Read-HordeWatcherBeatState -Path $rstate).alerted -and (Read-HordeWatcherBeatState -Path $rstate).tell -ceq "") "neither accepted: not marked told, so the next pass tries again"
    # T-0391 slice 8: the same check counts the warchief's mail as told only when his session takes it.
    $rig.tells.Clear(); $rig.posts.Clear(); $rig.notices.Clear(); $rig.marked.Clear()
    $rig.tellOk = $true; $rig.noticeOk = $false
    $w = ReaderLook
    Check ($rig.tells.Count -eq 1 -and $rig.posts[0] -clike "watcher-unread|*" -and -not (Read-HordeWatcherBeatState -Path $rstate).alerted -and (Read-HordeWatcherBeatState -Path $rstate).tell -ceq "posted" -and $rig.notices[0] -clike "*A notice to the warchief was posted and is being watched for its taking.") "the mail accepted (the notice failing): posted, not told; the phone is told only that it is posted and watched"
    $w = ReaderLook
    Check ($rig.tells.Count -eq 1) "and nothing is posted again while it awaits (the phone, which refused, is tried again)"
    $rig.taken[$rig.posts[0]] = $true
    $w = ReaderLook
    Check ((Read-HordeWatcherBeatState -Path $rstate).alerted -and (@($w.lines) -join " ") -like "watcher reader check: the warchief's session took the notice*") "the warchief's session takes it: told, and the line says so"
    $rig.tellOk = $true; $rig.noticeOk = $true

    # ROUND 3 (SHOULD 1): the reader check's state fails closed too.
    [System.IO.File]::WriteAllText($rstate, "garbage{", $utf8)
    $rig.tells.Clear(); $rig.notices.Clear(); $rig.posts.Clear()
    $w = ReaderLook
    Check ((@($w.lines) -join " ") -like "*its state file cannot be read*" -and [System.IO.File]::ReadAllText($rstate) -ceq "garbage{" -and $rig.tells.Count -eq 1 -and $rig.posts[0] -clike "watcher-reader-unreadable|*" -and $rig.notices.Count -eq 1) "the reader check's unreadable state is said, the file is kept, and a person is told (mail and phone), once a day"
    $w = ReaderLook
    Check ($rig.tells.Count -eq 1 -and $rig.notices.Count -eq 1 -and @($w.lines).Count -eq 0) "and not again on the next pass"

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
