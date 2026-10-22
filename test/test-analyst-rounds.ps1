# WHEN IS THE FLEET ANALYST WOKEN, AND WHAT DOES A ROUND SAY?
#
# core/AnalystRounds.ps1. Every file is written under a folder this suite makes in temp and removes; the
# clock is a value the suite passes, never the machine's. Nothing here posts, wakes or starts anything:
# the module under test does none of those.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\AnalystRounds.ps1")

$work = Join-Path $env:TEMP ("horde-analyst-rounds-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$t0 = [datetime]::new(2026, 10, 14, 12, 0, 0, [System.DateTimeKind]::Utc)
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Line { param([string]$Id, [string]$Wake = "round", [string]$Text = "a finding") return ('{"v":1,"id":"' + $Id + '","at":"2026-10-14T12:00:00Z","source":"monitor","wake":"' + $Wake + '","text":"' + $Text + '"}') }
function Home-With { param([string]$Name, [string]$Json) $h = Join-Path $work $Name; [void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings")); if ($Json -ne "") { [System.IO.File]::WriteAllText((Join-Path $h "settings\analyst.json"), $Json, $utf8) }; return $h }

try {
    Write-Host ""
    Write-Host "--- the settings: the warchief's decisions are the defaults, and a file can change them ---" -ForegroundColor Cyan
    $d = Get-HordeAnalystSettings -HordeHome (Home-With "plain" "")
    Check ($d.state -ceq "defaults" -and $d.values.roundMinutes -eq 30 -and $d.values.ackMinutes -eq 15) "rounds every 30 minutes, an ack within 15"
    Check ($d.values.heartbeatHours -eq 6) "the heartbeat is after 6 hours with no wake, not 2 (the warchief, 2026-10-14)"
    Check ($d.values.wakeNowMarkers -ceq "URGENT,QUESTION") "URGENT and QUESTION wake it at once by default"
    Check ($d.values.nowGapMinutes -eq 5) "at-once rounds are at least 5 minutes apart by default"
    Check ($d.values.startBoundMinutes -eq 15 -and $d.values.startMaxAttempts -eq 3) "a start that brings no session is failed after 15 minutes, and 3 starts are made in all (T-0341)"
    $rb = Get-HordeAnalystSettings -HordeHome (Home-With "bound-low" '{ "schemaVersion": 1, "settings": { "startBoundMinutes": 1 } }')
    $rm = Get-HordeAnalystSettings -HordeHome (Home-With "attempts-zero" '{ "schemaVersion": 1, "settings": { "startMaxAttempts": 0 } }')
    Check ($rb.state -ceq "refused" -and $rm.state -ceq "refused") "a bound under 2 minutes and 0 starts are refused: a bound of nothing would respawn every pass"
    $c = Get-HordeAnalystSettings -HordeHome (Home-With "changed" '{ "schemaVersion": 1, "settings": { "heartbeatHours": 2, "wakeNowMarkers": "URGENT,STOP-NOW" } }')
    Check ($c.state -ceq "read" -and $c.values.heartbeatHours -eq 2 -and $c.values.wakeNowMarkers -ceq "URGENT,STOP-NOW") "a person's file sets the heartbeat and the markers"
    $r = Get-HordeAnalystSettings -HordeHome (Home-With "refused" '{ "schemaVersion": 1, "settings": { "heartbeatHours": 0 } }')
    Check ($r.state -ceq "refused" -and $null -eq $r.values -and (@($r.findings) -join " ") -like "*heartbeatHours*") "a heartbeat of 0 hours is refused, naming the key"
    Check ((Get-HordeAnalystFolder -Values $d.values -HordeHome "C:\h") -ceq "C:\h\analyst") "an empty folder setting is analyst under the home"
    Check ((Get-HordeAnalystFolder -Values ([pscustomobject]@{ folder = "D:\x" }) -HordeHome "C:\h") -ceq "D:\x") "a set folder is used as written"

    Write-Host ""
    Write-Host "--- markers: the first word, in capitals, standing alone ---" -ForegroundColor Cyan
    $mk = Get-HordeAnalystMarkers -Text "URGENT, QUESTION"
    Check ($mk.state -ceq "known" -and @($mk.value).Count -eq 2 -and $mk.value[1] -ceq "QUESTION") "the list is split on commas and trimmed"
    Check ((Get-HordeAnalystMarkers -Text "URGENT,urgent").state -ceq "unknown") "a marker in lower case is refused, not read as another"
    Check ((Get-HordeAnalystMarkers -Text "URGENT,").state -ceq "unknown") "an empty marker is refused: a list that lost a word would let an urgent mail wait"
    $m = [string[]]@("URGENT", "QUESTION")
    Check ((Get-HordeAnalystMailMarker -Text "URGENT: the relay is down" -Markers $m) -ceq "URGENT") "URGENT: wakes it"
    Check ((Get-HordeAnalystMailMarker -Text "  QUESTION 3: which lane?" -Markers $m) -ceq "QUESTION") "QUESTION followed by a number wakes it, after leading blanks"
    Check ((Get-HordeAnalystMailMarker -Text "QUESTION" -Markers $m) -ceq "QUESTION") "the marker alone is a marker"
    Check ((Get-HordeAnalystMailMarker -Text "URGENTLY needed" -Markers $m) -ceq "") "URGENTLY is not URGENT"
    Check ((Get-HordeAnalystMailMarker -Text "QUESTIONS for later" -Markers $m) -ceq "") "QUESTIONS is not QUESTION"
    Check ((Get-HordeAnalystMailMarker -Text "urgent: lower case" -Markers $m) -ceq "") "urgent in lower case waits: case is exact"
    Check ((Get-HordeAnalystMailMarker -Text "This is NOT THE IDENTITY QUESTION" -Markers $m) -ceq "") "a marker inside a sentence is not a marker (the watcher's false alarm of 2026-10-13)"
    Check ((Get-HordeAnalystMailMarker -Text "Please read: URGENT" -Markers $m) -ceq "") "nor is one after the first word"
    Check ((Get-HordeAnalystMailMarker -Text "STOP-NOW please" -Markers ([string[]]@("STOP-NOW"))) -ceq "STOP-NOW") "a marker the person set is a marker"
    Check ((Get-HordeAnalystMailMarker -Text "URGENT: x" -Markers ([string[]]@("QUESTION"))) -ceq "") "CONTROL: a word that is not in the setting is not a marker"

    Write-Host ""
    Write-Host "--- the round decision ---" -ForegroundColor Cyan
    $p = [pscustomobject]@{ roundMinutes = 30; heartbeatHours = 6 }
    $f1 = [pscustomobject]@{ id = "a"; wake = "round" }
    $fNow = [pscustomobject]@{ id = "still"; wake = "now" }
    $fNever = [pscustomobject]@{ id = "low"; wake = "never" }
    $mPlain = [pscustomobject]@{ id = "m1"; marker = "" }
    $mUrgent = [pscustomobject]@{ id = "m2"; marker = "URGENT" }
    $mQuestion = [pscustomobject]@{ id = "m3"; marker = "QUESTION" }
    $recent = $t0.AddMinutes(-10)
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $recent -LastWakeAt $recent -Findings @($f1) -Policy $p
    Check ($x.action -ceq "none" -and $x.nextAt -eq $t0.AddMinutes(20)) "a finding 10 minutes after a round waits 20 more"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $t0.AddMinutes(-30) -LastWakeAt $recent -Findings @($f1) -Mail @($mPlain) -Policy $p
    Check ($x.action -ceq "round" -and @($x.findings) -ceq "a" -and @($x.mail) -ceq "m1") "at 30 minutes the round carries the finding and the plain mail"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $recent -LastWakeAt $recent -Mail @($mPlain) -Policy $p
    Check ($x.action -ceq "none") "plain mail from the warchief waits for the round (decision 3)"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $recent -LastWakeAt $recent -Findings @($f1) -Mail @($mPlain, $mUrgent) -Policy $p
    Check ($x.action -ceq "now" -and @($x.mail).Count -eq 2 -and @($x.findings).Count -eq 1) "URGENT mail wakes it at once, and carries everything else waiting"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $t0.AddMinutes(-1) -LastWakeAt $recent -Mail @($mQuestion) -Policy $p
    Check ($x.action -ceq "now") "QUESTION mail wakes it at once too, a minute after a round (the warchief, 2026-10-14)"
    $pg = [pscustomobject]@{ roundMinutes = 30; heartbeatHours = 6; nowGapMinutes = 5 }
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $t0.AddMinutes(-1) -LastWakeAt $recent -Mail @($mUrgent) -Policy $pg
    Check ($x.action -ceq "none" -and $x.nextAt -eq $t0.AddMinutes(4)) "URGENT a minute after a round waits out the 5-minute gap: a burst is one wake (review of PR 305)"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $t0.AddMinutes(-5) -LastWakeAt $recent -Mail @($mUrgent) -Policy $pg
    Check ($x.action -ceq "now") "and goes once the gap is over"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $recent -LastWakeAt $recent -Findings @($fNow) -Policy $p
    Check ($x.action -ceq "now" -and @($x.findings) -ceq "still") "a finding marked now (a fleet gone still) wakes it at once"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $t0.AddHours(-3) -LastWakeAt $t0.AddHours(-3) -Findings @($fNever) -Policy $p
    Check ($x.action -ceq "none" -and $x.why -ceq "nothing waits") "a finding marked never is not carried and wakes nothing"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $null -LastWakeAt $recent -Findings @($f1) -Policy $p
    Check ($x.action -ceq "round") "the first finding ever goes in a round at once: no round has been sent"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $t0.AddHours(-7) -LastWakeAt $t0.AddHours(-5) -Policy $p
    Check ($x.action -ceq "none" -and $x.nextAt -eq $t0.AddHours(1)) "with nothing waiting, 5 hours of quiet is no heartbeat yet"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $t0.AddHours(-7) -LastWakeAt $t0.AddHours(-6) -Policy $p
    Check ($x.action -ceq "heartbeat" -and @($x.findings).Count -eq 0) "6 hours of quiet is a heartbeat"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $t0.AddHours(-7) -LastWakeAt $t0.AddHours(-3) -Policy ([pscustomobject]@{ roundMinutes = 30; heartbeatHours = 2 })
    Check ($x.action -ceq "heartbeat") "the heartbeat follows the setting: 2 hours set, 3 quiet, a heartbeat"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $null -LastWakeAt $null -Policy $p
    Check ($x.action -ceq "heartbeat") "no wake known at all is a heartbeat, so a new supervisor learns whether the session answers"
    $x = Get-HordeAnalystRoundDecision -Now $t0 -LastRoundAt $t0.AddMinutes(-31) -LastWakeAt $t0.AddHours(-7) -Findings @($f1) -Policy $p
    Check ($x.action -ceq "round") "CONTROL: a round, not a heartbeat, when something waits"

    Write-Host ""
    Write-Host "--- the findings file ---" -ForegroundColor Cyan
    $fp = Join-Path $work "findings.jsonl"
    $none = Read-HordeAnalystFindings -Path $fp -Offset 0
    Check ($none.state -ceq "known" -and @($none.value.items).Count -eq 0 -and $none.value.offset -eq 0) "no file is no findings"
    [System.IO.File]::WriteAllText($fp, ((Line "one") + "`n" + (Line "two" "now") + "`n" + "not json`n" + '{"v":1,"id":"x"}' + "`n" + (Line "three")), $utf8)
    $a = Read-HordeAnalystFindings -Path $fp -Offset 0
    Check ($a.state -ceq "known" -and @($a.value.items).Count -eq 4) "four whole lines are read; the fifth has no newline yet and waits"
    Check ($a.value.items[0].id -ceq "one" -and $a.value.items[1].wake -ceq "now" -and $a.value.items[0].bad -ceq "") "good lines give their id and wake"
    Check ($a.value.items[2].bad -ceq "it is not JSON" -and $a.value.items[2].wake -ceq "round" -and $a.value.items[2].id -like "unreadable@*") "a line that is not JSON is kept, waits for a round, and says why"
    Check ($a.value.items[3].bad -like "it has no member*") "a line missing members is kept the same way"
    [System.IO.File]::AppendAllText($fp, "`n" + (Line "four") + "`n", $utf8)
    $b = Read-HordeAnalystFindings -Path $fp -Offset $a.value.offset
    Check ($b.state -ceq "known" -and @($b.value.items).Count -eq 2 -and $b.value.items[0].id -ceq "three" -and $b.value.items[1].id -ceq "four") "the next read starts where the last stopped: the finished line, then the new one"
    $c2 = Read-HordeAnalystFindings -Path $fp -Offset $b.value.offset
    Check ($c2.state -ceq "known" -and @($c2.value.items).Count -eq 0 -and $c2.value.offset -eq $b.value.offset) "nothing new is nothing, and the place does not move"
    [System.IO.File]::WriteAllText($fp, (Line "fresh") + "`n", $utf8)
    $d2 = Read-HordeAnalystFindings -Path $fp -Offset $b.value.offset
    Check ($d2.value.restarted -and @($d2.value.items).Count -eq 1 -and $d2.value.items[0].id -ceq "fresh") "a file shorter than the place was replaced: read from its start, and said"
    $lp = Join-Path $work "long.jsonl"
    [System.IO.File]::WriteAllText($lp, (("x" * 300) + "`n" + (Line "after-long") + "`n"), $utf8)
    $l1 = Read-HordeAnalystFindings -Path $lp -Offset 0 -ReadMost 200
    Check ($l1.state -ceq "known" -and @($l1.value.items).Count -eq 1 -and $l1.value.items[0].bad -like "*longer than 200 bytes*" -and $l1.value.offset -eq 301) "a line longer than one read is skipped as one unreadable item, not a reader stopped for ever (review of PR 305)"
    $l2 = Read-HordeAnalystFindings -Path $lp -Offset $l1.value.offset -ReadMost 200
    Check (@($l2.value.items).Count -eq 1 -and $l2.value.items[0].id -ceq "after-long") "and the line after it is read"
    [System.IO.File]::WriteAllText($lp, ("y" * 300), $utf8)
    $l3 = Read-HordeAnalystFindings -Path $lp -Offset 0 -ReadMost 200
    Check (@($l3.value.items).Count -eq 0 -and $l3.value.offset -eq 0) "a long line with no newline yet is still being written: it waits"
    $bads = @(
        @('{"v":2,"id":"a","at":"2026-10-14T12:00:00Z","source":"m","wake":"round","text":"t"}', "its v is not 1"),
        @('{"v":1,"id":"a b","at":"2026-10-14T12:00:00Z","source":"m","wake":"round","text":"t"}', "its id is*"),
        @('{"v":1,"id":"a","at":"2026-10-14T12:00:00","source":"m","wake":"round","text":"t"}', "its at is not a time with a zone"),
        @('{"v":1,"id":"a","at":"2026-10-14T12:00:00Z","source":"m","wake":"soon","text":"t"}', "its wake is*"),
        @('{"v":1,"id":"a","at":"2026-10-14T12:00:00Z","source":"m","wake":"round","text":"two\nlines"}', "its text is*"),
        @('{"v":1,"id":"a","at":"2026-10-14T12:00:00Z","source":"m","wake":"round","text":"t","extra":1}', "it has the member 'extra'*"),
        @('[1]', "it is not a JSON object"))
    foreach ($pair in $bads) { $one = ConvertFrom-HordeAnalystFindingLine -Line $pair[0] -Place "9"; Check ($one.bad -like $pair[1] -and $one.wake -ceq "round") ("refused, and kept for a round: " + $pair[1]) }
    $ok = ConvertFrom-HordeAnalystFindingLine -Line (Line "fine" "never") -Place "0"
    Check ($ok.bad -ceq "" -and $ok.wake -ceq "never" -and $ok.at -eq $t0) "CONTROL: a good line passes, with its time in UTC"

    Write-Host ""
    Write-Host "--- the warchief's mail ---" -ForegroundColor Cyan
    $mf = Join-Path $work "mail"
    Check ((Read-HordeAnalystMail -Folder $mf -Markers $m).state -ceq "known") "no mail folder is no mail"
    [void][System.IO.Directory]::CreateDirectory($mf)
    [System.IO.File]::WriteAllText((Join-Path $mf "20261014T120000000Z-0000000b.txt"), "URGENT: look now", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $mf "20261014T110000000Z-0000000a.txt"), "when you can", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $mf "notes.txt"), "URGENT: not mail", $utf8)
    [void][System.IO.Directory]::CreateDirectory((Join-Path $mf "delivered"))
    $ml = Read-HordeAnalystMail -Folder $mf -Markers $m
    Check ($ml.state -ceq "known" -and @($ml.value).Count -eq 2) "two mails; a file not named as mail, and the delivered folder, are not mail"
    Check ($ml.value[0].id -ceq "20261014T110000000Z-0000000a" -and $ml.value[0].marker -ceq "" -and $ml.value[1].marker -ceq "URGENT") "oldest first, each with its marker"

    Write-Host ""
    Write-Host "--- acks and the no-answer alert ---" -ForegroundColor Cyan
    $ap = Join-Path $work "acks.txt"
    $na = Read-HordeAnalystAcks -Path $ap
    Check ($na.state -ceq "known" -and @($na.value).Count -eq 0) "no ack file is no acks"
    [System.IO.File]::WriteAllText($ap, "round 20261014T113000Z-r done`r`nround   bogus line`nround 20261014T120000Z-n done  `n", $utf8)
    $ak = Read-HordeAnalystAcks -Path $ap
    Check ($ak.state -ceq "known" -and @($ak.value).Count -eq 2 -and $ak.value -ccontains "20261014T120000Z-n") "the ack lines are read, with CRLF and trailing blanks, and the rest ignored"
    $rounds = @(
        [pscustomobject]@{ id = "20261014T113000Z-r"; at = $t0.AddMinutes(-30); alerted = $false },
        [pscustomobject]@{ id = "late"; at = $t0.AddMinutes(-15); alerted = $false },
        [pscustomobject]@{ id = "young"; at = $t0.AddMinutes(-14); alerted = $false },
        [pscustomobject]@{ id = "told"; at = $t0.AddMinutes(-60); alerted = $true })
    $al = @(Get-HordeAnalystAckAlerts -Now $t0 -Rounds $rounds -Acked $ak.value -Policy ([pscustomobject]@{ ackMinutes = 15 }))
    Check ($al.Count -eq 1 -and $al[0] -ceq "late") "only the round 15 minutes old with no ack is told: not the acked, the young, or the one told before"
    $al2 = @(Get-HordeAnalystAckAlerts -Now $t0 -Rounds $rounds -Acked $ak.value -Policy ([pscustomobject]@{ ackMinutes = 10 }))
    Check ($al2.Count -eq 2) "CONTROL: with 10 minutes set, the 14-minute one is told too"

    Write-Host ""
    Write-Host "--- a round says where to look, in fixed words ---" -ForegroundColor Cyan
    $paths = Get-HordeAnalystPaths -Folder "C:\h\analyst"
    $id = New-HordeAnalystRoundId -Now $t0 -Kind "now"
    Check ($id -ceq "20261014T120000Z-n") "a round's id is its time and its kind"
    $body = Format-HordeAnalystRoundBody -Id $id -Kind "now" -Findings 3 -Unreadable 1 -MailIds @("20261014T120000000Z-0000000b") -Markers @("URGENT") -Paths $paths -Handover "C:\h\analyst\handover.json" -FromOffset 120
    Check ($body -like "ANALYST ROUND 20261014T120000Z-n - AT ONCE*" -and $body -like "*3 new finding(s) in C:\h\analyst\findings.jsonl from byte 120*" -and $body -like "*1 of those line(s) could not be read*") "it names the findings by count and place"
    Check ($body -like "*1 mail(s) from the warchief, in C:\h\analyst\mail\delivered: 20261014T120000000Z-0000000b.txt. Marked: URGENT.*") "it names the mail by file and marker"
    Check ($body -like "*rewrite your handover file: C:\h\analyst\handover.json*" -and $body -like "*to C:\h\analyst\acks.txt: round 20261014T120000Z-n done") "and ends with the handover and the exact ack line"
    Check ($body -cnotlike "*look now*" -and $body -cnotlike "*a finding*") "no mail's or finding's words are in it"
    $hb = Format-HordeAnalystRoundBody -Id "x-h" -Kind "heartbeat" -Paths $paths
    Check ($hb -like "*HEARTBEAT*" -and $hb -like "*gone stale*" -and $hb -cnotlike "*finding(s)*" -and $hb -cnotlike "*handover*") "a heartbeat carries nothing, and no handover line when none is kept"
    Check (-not ($body + $hb).ToCharArray().Where({ [int]$_ -gt 126 })) "the words are plain ASCII"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "rounds batch what waits, the marked mail and the now findings wake at once, the heartbeat follows its setting, and a round says where to look in fixed words"
