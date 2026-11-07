# IS THE FLEET ANALYST KEPT ALIVE AND LEAN, AND IS EVERY ROUND, START AND TELL MADE WHEN IT SHOULD BE?
#
# core/AnalystSession.ps1, cli/AnalystTend.ps1 and `horde analyst`. NOTHING HERE SPAWNS, WAKES, TYPES
# INTO OR KILLS A SESSION OR A PANE: every pass runs on a table of tools this suite wrote - a clock it
# moves by hand, a process listing it made, and a poster, teller, notifier and spawner that only record
# what they were asked. The transcript is a file of the suite's own, read through an adapter the suite
# registers. The end-to-end part runs the real horde command against a Horde home in temp, where the
# real tools refuse to post, tell, notify or spawn before they look for anything (cli/AnalystTend.ps1).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "AnalystRounds", "AnalystSession")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "cli\AnalystTend.ps1")

$work = Join-Path $env:TEMP ("horde-analyst-tend-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$t0 = [datetime]::new(2026, 10, 14, 12, 0, 0, [System.DateTimeKind]::Utc)
$sidA = "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"
$sidB = "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"
$warchief = "cccccccc-3333-4333-8333-cccccccccccc"

# THE SUITE'S TRANSCRIPT ADAPTER: a line "<UTC time>,<input>,<cache read>,<cache write>" is one call.
Register-HordeTranscriptAdapter -Name "suite-calls" -Claim { param($p) $p -like "*.calls" } -Read {
    param($p, $sink)
    $n = 0
    foreach ($l in [System.IO.File]::ReadAllLines($p)) {
        $n++
        $x = $l.Split(",")
        $ts = [datetime]::Parse($x[0], [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        $sink.Add((New-HordeTranscriptRecord -Kind "call" -Role "assistant" -Ts $ts -Line $n -Fields @{ id = ("c" + $n); model = (New-HordeKnown -Value "m"); usage = (New-HordeUsage -Uncached ([long]$x[1]) -CacheRead ([long]$x[2]) -CacheWrite ([long]$x[3]) -Output 10 -Split (New-HordeAbsent -Note "none")) }))
    }
    return [pscustomobject]@{ sessionId = "s"; parseSkipped = 0; tornTail = 0 }
}

function New-Listing {
    # A reading of who is running, in core/Identity.ps1's shape: -Live ids verified, -Gone ids whose
    # process ended; -Whole $false makes the listing incomplete.
    param([string[]]$Live = @(), [string[]]$Gone = @(), [bool]$Whole = $true, [string]$Transcript = "")
    $records = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $Live) { $records[$id] = [pscustomobject]@{ sessionId = $id; processCheck = "verified"; fields = @{ transcriptPath = $(if ($Transcript -ne "") { New-HordeKnown -Value $Transcript } else { New-HordeUnknown -Reason "none" }) } } }
    foreach ($id in $Gone) { $records[$id] = [pscustomobject]@{ sessionId = $id; processCheck = "gone"; fields = @{ transcriptPath = (New-HordeUnknown -Reason "none") } } }
    return [pscustomobject]@{ records = $records; duplicates = @(); verifiedLive = $(if ($Whole) { New-HordeKnown -Value @($Live) } else { New-HordeUnknown -Reason "the process table could not be read" }) }
}

function Write-Handover {
    param([string]$Folder, [string]$Sid, [datetime]$At)
    [void][System.IO.Directory]::CreateDirectory($Folder)
    [System.IO.File]::WriteAllText((Join-Path $Folder "handover.json"), ('{"v":1,"sessionId":"' + $Sid + '","writtenAt":"' + $At.ToString("o") + '","round":"","holds":"two alarms open","told":"","followUps":""}'), $utf8)
}

function New-Rig {
    # A Horde home in temp with its own analyst settings, and a table of recording tools.
    param([string]$Name, [string]$Settings = "")
    $h = Join-Path $work $Name
    [void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings"))
    if ($Settings -ne "") { [System.IO.File]::WriteAllText((Join-Path $h "settings\analyst.json"), ('{ "schemaVersion": 1, "settings": { ' + $Settings + ' } }'), $utf8) }
    $policy = Get-HordeAnalystPolicy -HordeHome $h
    if (-not $policy.ok) { throw $policy.reason }
    $rig = [pscustomobject]@{
        home = $h; folder = (Get-HordeAnalystFolder -Values $policy.values -HordeHome $h); policy = $policy
        now = $t0; listing = (New-Listing); context = $null
        posts = (New-Object System.Collections.ArrayList); tells = (New-Object System.Collections.ArrayList)
        notices = (New-Object System.Collections.ArrayList); spawns = (New-Object System.Collections.ArrayList)
        postOk = $true; spawnOk = $true; tools = $null
    }
    $rig.tools = @{
        Now      = { return $rig.now }.GetNewClosure()
        Identity = { return $rig.listing }.GetNewClosure()
        Length   = { param($Path) try { return [long](New-Object System.IO.FileInfo($Path)).Length } catch { return [long]-1 } }
        Context  = { param($Path) return (Get-HordeAnalystContextTokens -Path $Path) }
        Post     = { param($SessionId, $MessageId, $Body, $Values) [void]$rig.posts.Add([pscustomobject]@{ to = $SessionId; id = $MessageId; body = $Body }); return [pscustomobject]@{ ok = $rig.postOk; woken = $true; detail = $(if ($rig.postOk) { "" } else { "the mailbox is full" }) } }.GetNewClosure()
        Tell     = { param($Key, $Body, $Values) [void]$rig.tells.Add([pscustomobject]@{ key = $Key; body = $Body }); return [pscustomobject]@{ ok = $true; detail = "" } }.GetNewClosure()
        Notify   = { param($Line) [void]$rig.notices.Add($Line); return [pscustomobject]@{ ok = $true; detail = "" } }.GetNewClosure()
        # The stand-in Tell above always posts, so its notice is always on the awaiting list (the real tool reads the list).
        Watching = { param($Key, $Gen) return "listed" }
        Spawn    = { param($Script, $Handover, $Reason, $Values) [void]$rig.spawns.Add([pscustomobject]@{ script = $Script; handover = $Handover; reason = $Reason }); return [pscustomobject]@{ ok = $rig.spawnOk; detail = $(if ($rig.spawnOk) { "" } else { "exited 1" }) } }.GetNewClosure()
    }
    return $rig
}
function Pass { param($Rig) return (Invoke-HordeAnalystPass -Tools $Rig.tools -Policy $Rig.policy -Folder $Rig.folder) }
function State { param($Rig) return (Read-HordeAnalystState -Path (Join-Path $Rig.folder "supervisor.json")).value }
function Finding { param($Rig, [string]$Id, [string]$Wake = "round") [void][System.IO.Directory]::CreateDirectory($Rig.folder); [System.IO.File]::AppendAllText((Join-Path $Rig.folder "findings.jsonl"), ('{"v":1,"id":"' + $Id + '","at":"2026-10-14T12:00:00Z","source":"monitor","wake":"' + $Wake + '","text":"SECRET-FINDING-WORDS"}' + "`n"), $utf8) }
function Mail { param($Rig, [string]$Text) return (Write-HordeAnalystMail -Folder $Rig.folder -Text $Text -Markers $Rig.policy.markers -Now $Rig.now) }
function Ack { param($Rig, [string]$Id) [System.IO.File]::AppendAllText((Join-Path $Rig.folder "acks.txt"), ("round " + $Id + " done`n"), $utf8) }
function Calls { param($Rig, [string]$Lines) $p = Join-Path $Rig.folder "t.calls"; [System.IO.File]::WriteAllText($p, $Lines, $utf8); return $p }
$spawnSetting = '"spawnScript": "' + ((Join-Path $work "spawn-analyst.ps1").Replace("\", "\\")) + '"'

try {
    Write-Host ""
    Write-Host "--- the handover file's contract ---" -ForegroundColor Cyan
    $ok = ConvertFrom-HordeAnalystHandoverText -Text ('{"v":1,"sessionId":"' + $sidA + '","writtenAt":"2026-10-14T12:00:00Z","round":"r1","holds":"x","told":"","followUps":""}')
    Check ($ok.state -ceq "known" -and $ok.value.sessionId -ceq $sidA -and $ok.value.writtenAt -eq $t0) "a good handover gives its session and time"
    $bad = ConvertFrom-HordeAnalystHandoverText -Text ('{"v":1,"sessionId":"4d469554","writtenAt":"2026-10-14T12:00:00","round":"","holds":"x","told":"","extra":1}')
    Check ($bad.state -ceq "unknown" -and $bad.reason -like "*'extra'*" -and $bad.reason -like "*no member 'followUps'*") "members it does not have and members missing are each named"
    $bad2 = ConvertFrom-HordeAnalystHandoverText -Text ('{"v":1,"sessionId":"4d469554","writtenAt":"2026-10-14T12:00:00","round":"","holds":"' + ("x" * 4001) + '","told":"","followUps":""}')
    Check ($bad2.reason -like "*sessionId is not a session id written out in full*" -and $bad2.reason -like "*writtenAt is not a time with a zone*" -and $bad2.reason -like "*holds is not text of at most 4000*") "a short id, a time with no zone and an over-long text are each refused"
    $hp = Join-Path $work "big-handover.json"
    [System.IO.File]::WriteAllText($hp, ("x" * 9000), $utf8)
    Check ((Read-HordeAnalystHandover -Path $hp).reason -like "*more than the 8192*") "a handover over 8 KB is refused unread"
    Check ((Read-HordeAnalystHandover -Path (Join-Path $work "none.json")).state -ceq "absent") "no handover is absent"

    Write-Host ""
    Write-Host "--- the supervisor's state is written whole and read back ---" -ForegroundColor Cyan
    $sp = Join-Path $work "state\supervisor.json"
    $s = New-HordeAnalystState
    $s.sessionId = $sidA; $s.phase = "running"; $s.lastRoundAt = $t0; $s.findingsOffset = 42; $s.told = [string[]]@("no-answer")
    $s.rounds = @([pscustomobject]@{ id = "20261014T120000Z-r"; kind = "round"; at = $t0; sessionId = $sidA; alerted = $true; woken = "yes" })
    Write-HordeAnalystState -Path $sp -State $s
    $back = Read-HordeAnalystState -Path $sp
    Check ($back.state -ceq "known" -and $back.value.sessionId -ceq $sidA -and $back.value.lastRoundAt -eq $t0 -and $back.value.findingsOffset -eq 42) "the session, the last round and the place in the findings come back"
    Check (@($back.value.rounds).Count -eq 1 -and $back.value.rounds[0].alerted -and @($back.value.told) -ccontains "no-answer") "and the rounds and what was told"
    [System.IO.File]::WriteAllText($sp, '{"v":1,"phase":"sleeping"}', $utf8)
    Check ((Read-HordeAnalystState -Path $sp).state -ceq "unknown") "a state that cannot be read is unknown, never a fresh start: that would start a second analyst"

    Write-Host ""
    Write-Host "--- liveness is the agent's own account, proven ---" -ForegroundColor Cyan
    Check ((Get-HordeAnalystLiveness -SessionId $sidA -Identity (New-Listing -Live @($sidA))).alive.value -eq $true) "a verified control file is alive"
    Check ((Get-HordeAnalystLiveness -SessionId $sidA -Identity (New-Listing -Gone @($sidA))).alive.value -eq $false) "a control file whose process ended is gone"
    Check ((Get-HordeAnalystLiveness -SessionId $sidA -Identity (New-Listing)).alive.value -eq $false) "no file in a whole listing is gone"
    Check ((Get-HordeAnalystLiveness -SessionId $sidA -Identity (New-Listing -Whole $false)).alive.state -ceq "unknown") "no file in a listing that is not whole is unknown: never a start"

    Write-Host ""
    Write-Host "--- context is the last call's usage, never its text ---" -ForegroundColor Cyan
    $cp = Join-Path $work "x.calls"
    [System.IO.File]::WriteAllText($cp, "2026-10-14T11:00:00Z,10,50000,2000`n2026-10-14T11:30:00Z,5,60000,1000`n", $utf8)
    $ct = Get-HordeAnalystContextTokens -Path $cp
    Check ($ct.state -ceq "known" -and $ct.value.tokens -eq 61005 -and $ct.value.at -eq $t0.AddMinutes(-30)) "input + cache read + cache write of the newest call"
    [System.IO.File]::WriteAllText($cp, "", $utf8)
    Check ((Get-HordeAnalystContextTokens -Path $cp).state -ceq "absent") "a transcript with no call yet is absent"

    Write-Host ""
    Write-Host "--- no analyst known: the warchief is told once, nothing is started ---" -ForegroundColor Cyan
    $r = New-Rig "first" $spawnSetting
    $p1 = Pass $r
    Check ($p1.problem -ceq "" -and $r.tells.Count -eq 1 -and $r.tells[0].key -ceq "no-analyst" -and $r.spawns.Count -eq 0) "told no-analyst, and nothing started: a first run never starts a second analyst"
    $null = Pass $r
    Check ($r.tells.Count -eq 1) "told once, not every pass"

    Write-Host ""
    Write-Host "--- the analyst writes its handover: adopted, then rounds ---" -ForegroundColor Cyan
    Write-Handover -Folder $r.folder -Sid $sidA -At $t0
    $r.listing = New-Listing -Live @($sidA) -Transcript (Calls $r "2026-10-14T11:55:00Z,10,60000,1000`n")
    $r.now = $t0.AddMinutes(1)
    $p2 = Pass $r
    Check ((State $r).sessionId -ceq $sidA -and (State $r).phase -ceq "running" -and (@($p2.lines) -join " ") -like "*adopted session*") "the session named in the handover is adopted"
    Check ($r.posts.Count -eq 0) "nothing waits and it was woken 6 minutes ago: no round"
    Finding $r "alarm:one"
    $r.now = $t0.AddMinutes(2)
    $null = Pass $r
    Check ($r.posts.Count -eq 1 -and $r.posts[0].to -ceq $sidA -and $r.posts[0].body -like "*1 new finding(s)*") "the first finding goes in a round at once: no round had been sent"
    Check ($r.posts[0].body -cnotlike "*SECRET-FINDING-WORDS*") "the round carries no finding's words"
    Check ($r.posts[0].id -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-3[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z' -and $r.posts[0].id -ceq (ConvertTo-HordeAnalystMessageId -Seed "20261014T120200Z-r")) "the message id is a uuid made from the round id: a repost is one message"
    Ack $r "20261014T120200Z-r"
    Finding $r "alarm:two"
    $r.now = $t0.AddMinutes(20)
    $null = Pass $r
    Check ($r.posts.Count -eq 1) "the next finding, 18 minutes later, waits"
    $r.now = $t0.AddMinutes(32)
    $null = Pass $r
    Check ($r.posts.Count -eq 2 -and $r.posts[1].body -like "*1 new finding(s)*") "30 minutes after the last round it goes, alone: the first was not carried twice"
    Ack $r "20261014T123200Z-r"

    Write-Host ""
    Write-Host "--- the warchief's mail: plain waits, URGENT and QUESTION wake at once ---" -ForegroundColor Cyan
    $r.now = $t0.AddMinutes(35)
    $said = Mail $r "when you can, look at lane C"
    Check ($said -like "*it goes in the next round") "the mail command says plain mail waits"
    $null = Pass $r
    Check ($r.posts.Count -eq 2) "plain mail 3 minutes after a round waits"
    $said = Mail $r "URGENT: the relay is down"
    Check ($said -like "*marked URGENT*") "and says an URGENT one wakes it"
    $null = Pass $r
    Check ($r.posts.Count -eq 2) "but not within 5 minutes of the last round: a burst is one wake (review of PR 305)"
    $r.now = $t0.AddMinutes(37)
    $null = Pass $r
    Check ($r.posts.Count -eq 3 -and $r.posts[2].body -like "*AT ONCE*" -and $r.posts[2].body -like "*2 mail(s) from the warchief*" -and $r.posts[2].body -like "*Marked: URGENT.*") "URGENT wakes it at once, and the plain mail rides along"
    Check (@([System.IO.Directory]::GetFiles((Join-Path $r.folder "mail\delivered"))).Count -eq 2 -and @([System.IO.Directory]::GetFiles((Join-Path $r.folder "mail"))).Count -eq 0) "both mails were moved to delivered"
    Check ($r.posts[2].body -cnotlike "*relay is down*") "the round names the mail, never its words"
    Ack $r ((State $r).rounds[-1].id)
    $r.now = $t0.AddMinutes(42)
    $null = Mail $r "QUESTION: is lane F waiting on you?"
    $null = Pass $r
    Check ($r.posts.Count -eq 4 -and $r.posts[3].body -like "*Marked: QUESTION.*") "QUESTION wakes it at once too"
    Ack $r ((State $r).rounds[-1].id)
    $r.now = $t0.AddMinutes(43)
    $null = Mail $r "urgent: lower case waits"
    $null = Pass $r
    Check ($r.posts.Count -eq 4) "urgent in lower case is plain mail: it waits"

    Write-Host ""
    Write-Host "--- a round with no ack: the warchief and the founder, once ---" -ForegroundColor Cyan
    $r.now = $t0.AddMinutes(75)
    $null = Pass $r
    Check ($r.posts.Count -eq 5) "the waiting mail goes in the next round"
    $late = (State $r).rounds[-1].id
    $r.now = $t0.AddMinutes(89)
    $null = Pass $r
    Check (@($r.tells | Where-Object { $_.key -ceq "no-answer" }).Count -eq 0) "14 minutes with no ack: nobody told yet"
    $r.now = $t0.AddMinutes(90)
    $null = Pass $r
    Check (@($r.tells | Where-Object { $_.key -ceq "no-answer" -and $_.body -like ("*Round: " + $late + "*") }).Count -eq 1 -and $r.notices.Count -eq 1 -and $r.notices[0] -like ("*round " + $late + " for 15 minutes*")) "15 minutes with no ack: the warchief and the founder are told"
    $r.now = $t0.AddMinutes(95)
    $null = Pass $r
    Check (@($r.tells | Where-Object { $_.key -ceq "no-answer" }).Count -eq 1 -and $r.notices.Count -eq 1) "and told once"
    Ack $r $late

    Write-Host ""
    Write-Host "--- the heartbeat follows its setting ---" -ForegroundColor Cyan
    $r.now = $t0.AddMinutes(75).AddHours(5).AddMinutes(59)
    $null = Pass $r
    Check ($r.posts.Count -eq 5) "5 h 59 min of quiet: no heartbeat"
    $r.now = $t0.AddMinutes(75).AddHours(6)
    $null = Pass $r
    Check ($r.posts.Count -eq 6 -and $r.posts[5].body -like "*HEARTBEAT*") "6 hours of quiet: a heartbeat round"
    $h2 = New-Rig "hb2" '"heartbeatHours": 2'
    Write-Handover -Folder $h2.folder -Sid $sidA -At $t0
    $h2.listing = New-Listing -Live @($sidA) -Transcript (Calls $h2 "2026-10-14T12:00:00Z,10,60000,1000`n")
    $h2.now = $t0.AddMinutes(1)
    $null = Pass $h2
    $h2.now = $t0.AddHours(2)
    $null = Pass $h2
    Check ($h2.posts.Count -eq 1 -and $h2.posts[0].body -like "*HEARTBEAT*") "with heartbeatHours 2, two hours after its last call: a heartbeat"
    $h2.listing = New-Listing -Live @($sidA) -Transcript (Calls $h2 "2026-10-14T12:00:00Z,10,60000,1000`n2026-10-14T15:30:00Z,10,61000,1000`n")
    $h2.now = $t0.AddHours(4)
    $null = Pass $h2
    Check ($h2.posts.Count -eq 1) "a turn its transcript shows is a wake too: half an hour after it, no heartbeat"
    $mk = New-Rig "markers" '"wakeNowMarkers": "STOP"'
    Write-Handover -Folder $mk.folder -Sid $sidA -At $t0
    $mk.listing = New-Listing -Live @($sidA) -Transcript (Calls $mk "2026-10-14T12:00:00Z,10,60000,1000`n")
    $mk.now = $t0.AddMinutes(1)
    $null = Pass $mk
    $null = Mail $mk "URGENT: not a marker here"
    $null = Pass $mk
    Check ($mk.posts.Count -eq 1 -and $mk.posts[0].body -cnotlike "*AT ONCE*") "with the markers set to STOP, URGENT is plain mail (a first round goes at once, as a round)"
    $null = Mail $mk "STOP the throttle"
    $mk.now = $t0.AddMinutes(6)
    $null = Pass $mk
    Check ($mk.posts.Count -eq 2 -and $mk.posts[1].body -like "*AT ONCE*") "and STOP wakes it at once"

    Write-Host ""
    Write-Host "--- gone: a fresh session through the spawn script, told, and adopted when it writes ---" -ForegroundColor Cyan
    $g = New-Rig "gone" $spawnSetting
    Write-Handover -Folder $g.folder -Sid $sidA -At $t0
    $g.listing = New-Listing -Live @($sidA) -Transcript (Calls $g "2026-10-14T12:00:00Z,10,60000,1000`n")
    $g.now = $t0.AddMinutes(1)
    $null = Pass $g
    $g.listing = New-Listing -Whole $false
    $g.now = $t0.AddMinutes(2)
    $null = Pass $g
    Check ($g.spawns.Count -eq 0 -and (State $g).phase -ceq "running") "a listing that is not whole is never read as gone: nothing started"
    $g.listing = New-Listing -Gone @($sidA)
    $g.now = $t0.AddMinutes(3)
    $null = Pass $g
    Check ($g.spawns.Count -eq 1 -and $g.spawns[0].reason -ceq "gone" -and $g.spawns[0].handover -ceq (Join-Path $g.folder "handover.json") -and $g.spawns[0].script -like "*spawn-analyst.ps1") "a gone session is replaced through the spawn script, from the handover file"
    Check (@($g.tells | Where-Object { $_.key -ceq "started-gone" }).Count -eq 1 -and (State $g).phase -ceq "starting") "the warchief is told it was started (decision 4)"
    Finding $g "alarm:while-starting"
    $g.now = $t0.AddMinutes(4)
    $null = Pass $g
    Check ($g.spawns.Count -eq 1 -and $g.posts.Count -eq 0) "while it starts: no second start, and no round to anyone"
    Write-Handover -Folder $g.folder -Sid $sidB -At $t0.AddMinutes(5)
    $g.listing = New-Listing -Live @($sidB) -Transcript (Calls $g "2026-10-14T12:05:00Z,10,50000,1000`n")
    $g.now = $t0.AddMinutes(6)
    $null = Pass $g
    Check ((State $g).sessionId -ceq $sidB -and (State $g).phase -ceq "running" -and $g.posts.Count -eq 1 -and $g.posts[0].to -ceq $sidB) "the fresh session is adopted when it writes its handover, and the waiting finding goes to it"
    $s2 = New-Rig "silent" $spawnSetting
    Write-Handover -Folder $s2.folder -Sid $sidA -At $t0
    $s2.listing = New-Listing -Live @($sidA) -Transcript (Calls $s2 "2026-10-14T12:00:00Z,10,60000,1000`n")
    $s2.now = $t0.AddMinutes(1); $null = Pass $s2
    $s2.listing = New-Listing -Gone @($sidA)
    $s2.now = $t0.AddMinutes(2); $null = Pass $s2
    $s2.now = $t0.AddMinutes(21); $null = Pass $s2
    Check (@($s2.tells | Where-Object { $_.key -ceq "start-silent" }).Count -eq 0) "19 minutes without a handover: not yet told"
    $s2.now = $t0.AddMinutes(22); $null = Pass $s2
    $s2.now = $t0.AddMinutes(60); $null = Pass $s2
    Check (@($s2.tells | Where-Object { $_.key -ceq "start-silent" }).Count -eq 1 -and $s2.spawns.Count -eq 1) "20 minutes without one: the warchief is told once, and no second start is made"

    Write-Host ""
    Write-Host "--- over the cap: the next round goes to a fresh session ---" -ForegroundColor Cyan
    $o = New-Rig "cap" $spawnSetting
    Write-Handover -Folder $o.folder -Sid $sidA -At $t0
    $o.listing = New-Listing -Live @($sidA) -Transcript (Calls $o "2026-10-14T12:00:00Z,10,118000,1000`n")
    $o.now = $t0.AddMinutes(1); $null = Pass $o; $null = Pass $o
    Check ((State $o).contextTokens -eq 119010 -and $o.spawns.Count -eq 0) "119k is under the 120k cap: kept"
    $o.listing = New-Listing -Live @($sidA) -Transcript (Calls $o "2026-10-14T12:00:00Z,10,118000,1000`n2026-10-14T12:01:00Z,10,120000,1000`n")
    $o.now = $t0.AddMinutes(2); $null = Pass $o
    Check ($o.spawns.Count -eq 0 -and (State $o).contextTokens -eq 121010) "over the cap with nothing to deliver: nothing started yet"
    Finding $o "alarm:x"
    $o.now = $t0.AddMinutes(3); $null = Pass $o
    Check ($o.spawns.Count -eq 1 -and $o.spawns[0].reason -ceq "over-cap" -and $o.posts.Count -eq 0) "a round due while over the cap starts a fresh session, and the old one gets no round"
    Check (@($o.tells | Where-Object { $_.key -ceq "started-over-cap" -and $_.body -like "*close it when you choose*" }).Count -eq 1) "the warchief is told, and that the old one is his to close"
    $cs = New-Rig "cap-setting" ($spawnSetting + ', "contextCapTokens": 200000')
    Write-Handover -Folder $cs.folder -Sid $sidA -At $t0
    $cs.listing = New-Listing -Live @($sidA) -Transcript (Calls $cs "2026-10-14T12:00:00Z,10,150000,1000`n")
    $cs.now = $t0.AddMinutes(1); $null = Pass $cs
    Finding $cs "alarm:y"
    $cs.now = $t0.AddMinutes(2); $null = Pass $cs
    Check ((State $cs).contextTokens -eq 151010 -and $cs.spawns.Count -eq 0 -and $cs.posts.Count -eq 1) "the cap is a setting: at 200k, 151k is kept and gets its round"

    Write-Host ""
    Write-Host "--- no spawn script: nothing is ever started ---" -ForegroundColor Cyan
    $n = New-Rig "nospawn"
    Write-Handover -Folder $n.folder -Sid $sidA -At $t0
    $n.listing = New-Listing -Live @($sidA)
    $n.now = $t0.AddMinutes(1); $null = Pass $n
    $n.listing = New-Listing -Gone @($sidA)
    $n.now = $t0.AddMinutes(2); $null = Pass $n
    $n.now = $t0.AddMinutes(3); $null = Pass $n
    Check ($n.spawns.Count -eq 0 -and @($n.tells | Where-Object { $_.key -ceq "no-spawn-gone" }).Count -eq 1) "gone with no spawn script: the warchief is told once, nothing started"
    $fs = New-Rig "spawnfail" $spawnSetting
    Write-Handover -Folder $fs.folder -Sid $sidA -At $t0
    $fs.listing = New-Listing -Live @($sidA)
    $fs.now = $t0.AddMinutes(1); $null = Pass $fs
    $fs.listing = New-Listing -Gone @($sidA); $fs.spawnOk = $false
    $fs.now = $t0.AddMinutes(2); $null = Pass $fs
    $fs.now = $t0.AddMinutes(3); $null = Pass $fs
    Check ($fs.spawns.Count -eq 1 -and @($fs.tells | Where-Object { $_.key -ceq "spawn-failed" }).Count -eq 1 -and (State $fs).phase -ceq "starting") "a spawn that failed (or timed out) is told once and stays starting: it may have opened a session all the same"
    $fs.now = $t0.AddMinutes(22); $null = Pass $fs
    $fs.now = $t0.AddMinutes(33); $null = Pass $fs
    $fs.now = $t0.AddHours(3); $null = Pass $fs
    Check ($fs.spawns.Count -eq 1 -and @($fs.tells | Where-Object { $_.key -ceq "start-silent" }).Count -eq 1) "it is never started again by itself: after the wait the warchief is told, once (review of PR 306)"
    Write-Handover -Folder $fs.folder -Sid $sidB -At $t0.AddHours(3)
    $fs.listing = New-Listing -Live @($sidB)
    $fs.now = $t0.AddHours(3).AddMinutes(1); $null = Pass $fs
    Check ((State $fs).sessionId -ceq $sidB -and (State $fs).phase -ceq "running") "and a session that writes its handover later - the timed-out spawn's, or one the warchief started - is adopted"

    Write-Host ""
    Write-Host "--- review of PR 306: never a second session ---" -ForegroundColor Cyan
    # A pass killed while its spawn runs: the spawn tool looks at the state file on disk at the moment it
    # is called, then the pass dies (the tool throws, as a killed process would never return).
    $k = New-Rig "killed" $spawnSetting
    Write-Handover -Folder $k.folder -Sid $sidA -At $t0
    $k.listing = New-Listing -Live @($sidA)
    $k.now = $t0.AddMinutes(1); $null = Pass $k
    $k.listing = New-Listing -Gone @($sidA)
    $seenPhase = New-Object System.Collections.ArrayList
    $k.tools["Spawn"] = { param($Script, $Handover, $Reason, $Values) [void]$k.spawns.Add($Reason); $onDisk = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($k.folder, "supervisor.json")); [void]$seenPhase.Add($(if ($onDisk -match '"phase":\s*"(\w+)"') { $Matches[1] } else { "none found" })); throw "the pass was killed here" }.GetNewClosure()
    $k.now = $t0.AddMinutes(2); $null = Pass $k
    Check ($seenPhase.Count -eq 1 -and $seenPhase[0] -ceq "starting") "starting is on disk BEFORE the spawn script runs"
    $k.now = $t0.AddMinutes(3); $null = Pass $k
    $k.now = $t0.AddMinutes(40); $null = Pass $k
    Check ($k.spawns.Count -eq 1) "so a pass after one killed mid-spawn starts nothing more"
    # The over-cap swap whose spawn times out: the old session is still alive; no third session, ever.
    $oc = New-Rig "cap-timeout" $spawnSetting
    Write-Handover -Folder $oc.folder -Sid $sidA -At $t0
    $oc.listing = New-Listing -Live @($sidA) -Transcript (Calls $oc "2026-10-14T12:00:00Z,10,130000,1000`n")
    $oc.now = $t0.AddMinutes(1); $null = Pass $oc; $null = Pass $oc
    $oc.spawnOk = $false
    Finding $oc "alarm:cap"
    $oc.now = $t0.AddMinutes(2); $null = Pass $oc
    foreach ($m in @(10, 31, 45, 90, 200)) { $oc.now = $t0.AddMinutes($m); $null = Pass $oc }
    Check ($oc.spawns.Count -eq 1 -and $oc.spawns[0].reason -ceq "over-cap" -and $oc.posts.Count -eq 0) "an over-cap swap whose spawn timed out, with the old session alive: one spawn, never a second or a third"
    # Two passes at once (a hand tend while run is passing): the machine-wide lock lets exactly one spawn.
    $two = New-Rig "two" $spawnSetting
    Write-Handover -Folder $two.folder -Sid $sidA -At $t0
    $two.listing = New-Listing -Live @($sidA)
    $two.now = $t0.AddMinutes(1); $null = Pass $two
    $lockName = "Local\HordeAnalystTendSuite" + [guid]::NewGuid().ToString("N")
    $spawnLog = Join-Path $work "two-spawns.txt"
    $racer = {
        param($Root, $Folder, $HomeDir, $LockName, $SpawnLog, $Gone, $At)
        Set-StrictMode -Off
        foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "AnalystRounds", "AnalystSession")) { . (Join-Path $Root ("core\" + $f + ".ps1")) }
        . (Join-Path $Root "cli\AnalystTend.ps1")
        $policy = Get-HordeAnalystPolicy -HordeHome $HomeDir
        $records = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
        $records[$Gone] = [pscustomobject]@{ sessionId = $Gone; processCheck = "gone"; fields = @{ transcriptPath = (New-HordeUnknown -Reason "none") } }
        $listing = [pscustomobject]@{ records = $records; duplicates = @(); verifiedLive = (New-HordeKnown -Value @()) }
        $tools = @{
            Now = { return $At }.GetNewClosure(); Identity = { return $listing }.GetNewClosure()
            Length = { param($Path) return [long]-1 }; Context = { param($Path) return $null }
            Post = $null; Tell = { param($Key, $Body, $Values) return [pscustomobject]@{ ok = $true; detail = "" } }; Notify = $null
            Spawn = { param($Script, $Handover, $Reason, $Values) [System.IO.File]::AppendAllText($SpawnLog, ($Reason + "`n")); Start-Sleep -Seconds 3; return [pscustomobject]@{ ok = $true; detail = "" } }.GetNewClosure()
        }
        $done = Invoke-HordeAnalystLockedPass -Tools $tools -Policy $policy -Folder $Folder -LockName $LockName -WaitSeconds 20
        return ($done.lines -join " | ")
    }
    $jobs = @()
    foreach ($n in 1..2) {
        $ps = [powershell]::Create()
        [void]$ps.AddScript($racer).AddArgument($root).AddArgument($two.folder).AddArgument($two.home).AddArgument($lockName).AddArgument($spawnLog).AddArgument($sidA).AddArgument($t0.AddMinutes(2))
        $jobs += [pscustomobject]@{ ps = $ps; h = $ps.BeginInvoke() }
    }
    $said = @(); foreach ($j in $jobs) { $said += @($j.ps.EndInvoke($j.h)); $j.ps.Dispose() }
    $spawned = @([System.IO.File]::ReadAllLines($spawnLog) | Where-Object { $_ -ne "" })
    Check ($spawned.Count -eq 1) ("two passes at once: exactly one spawn (" + $spawned.Count + "; " + ($said -join " || ") + ")")
    Check ((State $two).phase -ceq "starting") "and the second pass found it starting"

    # A pass that cannot have the lock in time does NOTHING: another runspace holds it past -WaitSeconds,
    # and this pass, which would otherwise adopt the analyst its handover names, must not.
    $lk = New-Rig "locked"
    Write-Handover -Folder $lk.folder -Sid $sidA -At $t0
    $lk.listing = New-Listing -Live @($sidA)
    $lk.now = $t0.AddMinutes(1)
    $heldName = "Local\HordeAnalystTendSuite" + [guid]::NewGuid().ToString("N")
    $heldMark = Join-Path $work "lock-held.txt"
    $holder = [powershell]::Create()
    [void]$holder.AddScript({
        param($Name, $Mark)
        $m = New-Object System.Threading.Mutex($false, $Name)
        [void]$m.WaitOne()
        [System.IO.File]::WriteAllText($Mark, "held")
        Start-Sleep -Seconds 6
        $m.ReleaseMutex(); $m.Dispose()
    }).AddArgument($heldName).AddArgument($heldMark)
    $hh = $holder.BeginInvoke()
    $waited = 0; while (-not [System.IO.File]::Exists($heldMark) -and $waited -lt 200) { Start-Sleep -Milliseconds 50; $waited++ }
    Check ([System.IO.File]::Exists($heldMark)) "CONTROL: another runspace holds the lock"
    $skip = $null
    try { $skip = Invoke-HordeAnalystLockedPass -Tools $lk.tools -Policy $lk.policy -Folder $lk.folder -LockName $heldName -WaitSeconds 1 } catch { $skip = $null }
    [void]$holder.EndInvoke($hh); $holder.Dispose()
    Check ($null -ne $skip -and (Get-HordeTestMember $skip "skipped") -eq $true -and ((@(Get-HordeTestMember $skip "lines") -join " ") -like "*another pass*did nothing*")) "a pass that cannot have the lock in time does nothing, and says so"
    Check ((State $lk).sessionId -cne $sidA) "and it adopted nothing"

    Write-Host ""
    Write-Host "--- review of PR 306: no-answer is told once for a run of unacked rounds ---" -ForegroundColor Cyan
    $w = New-Rig "wedged"
    Write-Handover -Folder $w.folder -Sid $sidA -At $t0
    $w.listing = New-Listing -Live @($sidA)
    $w.now = $t0.AddMinutes(1); $null = Pass $w
    foreach ($m in @(2, 33, 64, 95, 126)) { Finding $w ("alarm:w" + $m); $w.now = $t0.AddMinutes($m); $null = Pass $w }
    $w.now = $t0.AddMinutes(150); $null = Pass $w
    Check ($w.posts.Count -eq 5 -and @($w.tells | Where-Object { $_.key -ceq "no-answer" }).Count -eq 1 -and $w.notices.Count -eq 1) "a wedged session with five unacked rounds: the warchief and the founder are told once, not five times"
    Ack $w ((State $w).rounds[-1].id)
    Finding $w "alarm:after-ack"
    $w.now = $t0.AddMinutes(160); $null = Pass $w
    $w.now = $t0.AddMinutes(176); $null = Pass $w
    Check (@($w.tells | Where-Object { $_.key -ceq "no-answer" }).Count -eq 2 -and $w.notices.Count -eq 2) "after an ack, the next unacked round is told again"

    # Only a NEWER ack ends a run: the first round is acked, then the session wedges. The old ack is
    # still in the file at every pass, and must not reopen no-answer for each late round after it.
    $oa = New-Rig "old-ack"
    Write-Handover -Folder $oa.folder -Sid $sidA -At $t0
    $oa.listing = New-Listing -Live @($sidA)
    $oa.now = $t0.AddMinutes(1); $null = Pass $oa
    Finding $oa "alarm:o2"; $oa.now = $t0.AddMinutes(2); $null = Pass $oa
    Ack $oa ((State $oa).rounds[-1].id)
    foreach ($m in @(33, 64, 95, 126)) { Finding $oa ("alarm:o" + $m); $oa.now = $t0.AddMinutes($m); $null = Pass $oa }
    $oa.now = $t0.AddMinutes(150); $null = Pass $oa
    Check ($oa.posts.Count -eq 5 -and @($oa.tells | Where-Object { $_.key -ceq "no-answer" }).Count -eq 1 -and $oa.notices.Count -eq 1) ("an old ack does not reopen the run: four late rounds after it are told once (" + @($oa.tells | Where-Object { $_.key -ceq "no-answer" }).Count + " tells, " + $oa.notices.Count + " notices)")

    Write-Host ""
    Write-Host "--- review of PR 306: the founder's notice does not wait on the warchief's tell ---" -ForegroundColor Cyan
    # Telling off, and fleet mail failing every time: either way the founder hears once per run of
    # unacked rounds, and the notice says the warchief was NOT told.
    foreach ($case in @("off", "failing")) {
        $q = $(if ($case -ceq "off") { New-Rig ("quiet-" + $case) -Settings '"tellWarchief": false' } else { New-Rig ("quiet-" + $case) })
        if ($case -ceq "failing") { $q.tools["Tell"] = { param($Key, $Body, $Values) return [pscustomobject]@{ ok = $false; detail = "the mail store is locked" } }; $q.tools["Watching"] = { param($Key, $Gen) return "gone" } }
        Write-Handover -Folder $q.folder -Sid $sidA -At $t0
        $q.listing = New-Listing -Live @($sidA)
        $q.now = $t0.AddMinutes(1); $null = Pass $q
        foreach ($m in @(2, 33, 64, 95, 126)) { Finding $q ("alarm:q" + $m); $q.now = $t0.AddMinutes($m); $null = Pass $q }
        $q.now = $t0.AddMinutes(150); $null = Pass $q
        Check ($q.posts.Count -eq 5 -and $q.notices.Count -eq 1) ("warchief telling " + $case + ": five unacked rounds tell the founder once (" + $q.notices.Count + ")")
        Check ($q.notices.Count -ge 1 -and $q.notices[0] -like "*a notice to the warchief was not posted*" -and $q.notices[0] -notlike "*the warchief was told*" -and $q.notices[0] -notlike "*is being watched*") ("warchief telling " + $case + ": and the notice says no notice was posted to the warchief, never that he was told")
        Ack $q ((State $q).rounds[-1].id)
        Finding $q "alarm:q-after-ack"
        $q.now = $t0.AddMinutes(160); $null = Pass $q
        $q.now = $t0.AddMinutes(176); $null = Pass $q
        Check ($q.notices.Count -eq 2) ("warchief telling " + $case + ": after an ack, the next run tells the founder again")
    }
    Check ($w.notices[0] -like "*a notice to the warchief was posted and is being watched for its taking*" -and $w.notices[0] -notlike "*the warchief was told*") "when the warchief's tell is posted, the notice says what is known: posted and watched, not told"

    Write-Host ""
    Write-Host "--- review of PR 306: a fresh session that never acks is still told ---" -ForegroundColor Cyan
    # The old session's run was told and never acked; a new session is adopted and never acks either.
    # Its unacked rounds must be told, not silenced by the old session's run.
    $sw = New-Rig "swap"
    Write-Handover -Folder $sw.folder -Sid $sidA -At $t0
    $sw.listing = New-Listing -Live @($sidA)
    $sw.now = $t0.AddMinutes(1); $null = Pass $sw
    foreach ($m in @(2, 33)) { Finding $sw ("alarm:s" + $m); $sw.now = $t0.AddMinutes($m); $null = Pass $sw }
    $sw.now = $t0.AddMinutes(50); $null = Pass $sw
    Check ($sw.notices.Count -eq 1) "the first session's unacked rounds are told once"
    $sw.listing = New-Listing -Live @($sidB) -Gone @($sidA)
    Write-Handover -Folder $sw.folder -Sid $sidB -At $t0.AddMinutes(55)
    $sw.now = $t0.AddMinutes(56); $null = Pass $sw
    Check ((State $sw).sessionId -ceq $sidB) "the fresh session is adopted"
    foreach ($m in @(60, 91)) { Finding $sw ("alarm:s" + $m); $sw.now = $t0.AddMinutes($m); $null = Pass $sw }
    $sw.now = $t0.AddMinutes(110); $null = Pass $sw
    Check ($sw.notices.Count -eq 2 -and @($sw.tells | Where-Object { $_.key -ceq "no-answer" }).Count -eq 2) ("the fresh session's unacked rounds are told too (" + $sw.notices.Count + ")")

    Write-Host ""
    Write-Host "--- review of PR 306: an unreadable findings file holds back no URGENT mail ---" -ForegroundColor Cyan
    $u = New-Rig "unreadable"
    Write-Handover -Folder $u.folder -Sid $sidA -At $t0
    $u.listing = New-Listing -Live @($sidA)
    $u.now = $t0.AddMinutes(1); $null = Pass $u
    [void][System.IO.Directory]::CreateDirectory((Join-Path $u.folder "findings.jsonl"))
    $null = Mail $u "URGENT: read this"
    $u.now = $t0.AddMinutes(2); $p2 = Pass $u
    Check ($u.posts.Count -eq 1 -and $u.posts[0].body -like "*Marked: URGENT.*" -and (@($p2.lines) -join " ") -like "*the findings:*") "the findings cannot be read, and the URGENT mail goes all the same"
    Check ((State $u).findingsOffset -eq 0) "and the findings' place is kept"

    Write-Host ""
    Write-Host "--- a post that fails loses nothing ---" -ForegroundColor Cyan
    $pf = New-Rig "postfail"
    Write-Handover -Folder $pf.folder -Sid $sidA -At $t0
    $pf.listing = New-Listing -Live @($sidA)
    $pf.now = $t0.AddMinutes(1); $null = Pass $pf
    $pf.postOk = $false
    $null = Mail $pf "URGENT: x"
    Finding $pf "alarm:z"
    $pf.now = $t0.AddMinutes(2); $null = Pass $pf
    Check ((State $pf).findingsOffset -eq 0 -and @([System.IO.Directory]::GetFiles((Join-Path $pf.folder "mail"))).Count -eq 1 -and @((State $pf).rounds).Count -eq 0) "the mail is put back and the findings' place is kept"
    $pf.postOk = $true
    $pf.now = $t0.AddMinutes(3); $null = Pass $pf
    Check ($pf.posts[-1].body -like "*AT ONCE*" -and $pf.posts[-1].body -like "*1 new finding(s)*" -and (State $pf).findingsOffset -gt 0) "and the next pass carries both"

    Write-Host ""
    Write-Host "--- the spawn script's command line ---" -ForegroundColor Cyan
    $seat = [pscustomobject]@{ sessionId = $warchief; pane = "23"; instance = "sock-15852" }
    $line = Get-HordeAnalystSpawnArguments -Script "C:\f\spawn.ps1" -Seat $seat -Handover "C:\f\handover.json" -Reason "gone"
    Check ($line -ceq ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\f\spawn.ps1" -ParentSessionId ' + $warchief + ' -ParentPane 23 -ParentInstance sock-15852 -Handover "C:\f\handover.json" -Reason gone')) "fixed names and checked values"
    Check (Throws { Get-HordeAnalystSpawnArguments -Script "C:\f\spawn.ps1" -Seat ([pscustomobject]@{ sessionId = $warchief; pane = "23 -X"; instance = "s" }) -Handover "C:\f\h.json" -Reason "gone" } "plain word") "a pane that is not one plain word is refused: nothing can become a second parameter"
    Check (Throws { Get-HordeAnalystSpawnArguments -Script "spawn.ps1" -Seat $seat -Handover "C:\f\h.json" -Reason "gone" } "absolute") "a script that is not an absolute path is refused"
    Check (Throws { Get-HordeAnalystSpawnArguments -Script "C:\f\spawn.ps1" -Seat $seat -Handover "C:\f\h.json" -Reason "restore" }) "a reason that is not gone or over-cap is refused"

    Write-Host ""
    Write-Host "--- the real command, in a home in temp: it tells nobody and starts nothing ---" -ForegroundColor Cyan
    $e = Join-Path $work "e2e home"
    [void][System.IO.Directory]::CreateDirectory((Join-Path $e "settings"))
    $env2 = @{ HORDE_HOME = $e; WEZFLEET_ROOT = (Join-Path $work "no-fleet-here") }
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst") -Env $env2
    Check ($x.code -eq 2 -and $x.out -like "*analyst needs a verb*") "analyst with no verb is a usage error"
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "status", "-Text", "x") -Env $env2
    Check ($x.code -eq 1 -and $x.out -like "*-Text does not belong to analyst status*") "a flag of another verb is refused"
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "mail", "-Text", "QUESTION: are you there?") -Env $env2
    Check ($x.code -eq 0 -and $x.out -like "*marked QUESTION*" -and @([System.IO.Directory]::GetFiles((Join-Path $e "analyst\mail"))).Count -eq 1) "mail leaves one file in the analyst folder, marked"
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "tend") -Env $env2
    Check ($x.code -eq 0 -and $x.out -like "*would tell the warchief (no-analyst), but telling is off*") "tend in a test's home finds no analyst and tells nobody"
    Check ($x.out -like "*watcher check: STALE (missing)*" -and $x.out -like "*would tell the founder's phone, but telling is off*") "tend checks the overseer watcher's run.json: no file under the fleet root is stale (missing), and a test's home tells nobody (T-0388)"
    $runDir = Join-Path $work "no-fleet-here\_home\orcs\overseer"
    [void][System.IO.Directory]::CreateDirectory($runDir)
    $nowIso = [datetime]::UtcNow.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    [System.IO.File]::WriteAllText((Join-Path $runDir "run.json"), ('{"started":"' + $nowIso + '","finished":"' + $nowIso + '"}'), $utf8)
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "tend") -Env $env2
    Check ($x.out -like "*watcher reader check: STALE (unknown)*") "tend checks the alarm reader too: no file naming it is an alarm, not quiet (T-0388)"
    [System.IO.File]::WriteAllText((Join-Path $runDir "self.txt"), "abcd1234-reader", $utf8)
    [void][System.IO.Directory]::CreateDirectory((Join-Path $work "no-fleet-here\mail"))
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "tend") -Env $env2
    Check ($x.code -eq 0 -and $x.out -cnotlike "*watcher check*" -and $x.out -cnotlike "*watcher reader check*") "and a fresh run.json at <fleet root>\_home\orcs\overseer, a named reader and an empty inbox say nothing"
    Write-Handover -Folder (Join-Path $e "analyst") -Sid $sidA -At ([datetime]::UtcNow)
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "tend") -Env $env2
    Check ($x.code -eq 0 -and $x.out -like ("*adopted session " + $sidA + "*")) "the next pass adopts the analyst its handover names"
    Check ($x.out -like "*posting is off*" -or $x.out -like "*no running analyst*" -or $x.out -like "*round*") "and posts nothing from a test's home"
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "status") -Env $env2
    Check ($x.code -eq 0 -and $x.out -like ("*session: " + $sidA + ", running*") -and $x.out -like "*heartbeat after 6 h, wake at once on URGENT, QUESTION*") "status shows the session and the settings"
    [System.IO.File]::WriteAllText((Join-Path $e "settings\analyst.json"), '{ "schemaVersion": 1, "settings": { "wakeNowMarkers": "URGENT,," } }', $utf8)
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "tend") -Env $env2
    Check ($x.code -eq 1 -and $x.out -like "*wakeNowMarkers*") "a marker list it cannot use refuses the command, naming the setting"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the analyst is adopted from its handover, rounds and wake-at-once marks and the heartbeat follow their settings, no-ack is told once, and a fresh session is started only through the spawn script, never on an unknown"
