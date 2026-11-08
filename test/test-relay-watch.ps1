# IS A RELAY THAT CANNOT SIGN A PHONE IN SEEN, AND TOLD ONCE, WITHOUT ONE BLIP TELLING ANYONE?
#
# core/RelayWatch.ps1 and the relay watch of `horde analyst tend`. The relay is a small HTTP server this
# suite runs on 127.0.0.1, on a port the system picks; the real relay is never asked (a test's home
# refuses any origin not on this machine, and that is checked here too). Nobody is told: the tellers
# are the suite's own recorders, and the command's real tellers refuse a home under temp.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
. (Join-Path $root "test\lib\Cli.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\RelayWatch.ps1")

$work = Join-Path $env:TEMP ("horde-relay-watch-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$t0 = [datetime]::new(2026, 10, 14, 12, 0, 0, [System.DateTimeKind]::Utc)
$goodId = "123456789012-abcdefghijklmnop0123456789abcdef.apps.googleusercontent.com"

# THE FAKE RELAY: a listener in a runspace of its own, answering by $sync.mode.
#   up      / and /app/index.html 200; /auth/google 303 to accounts.google.com with a good client_id
#   500     every path 500
#   closed  the connection is closed with no answer
#   bom     as up, with U+FEFF (percent-encoded) in front of the client_id
#   shape   as up, with a client_id of the wrong shape
#   elsewhere  as up, but /auth/google redirects to another host
#   two     as up, with client_id named twice
#   longid  as up, with a client id past the client file's length bounds
$sync = [hashtable]::Synchronized(@{ mode = "up"; id = $goodId; stop = $false; hits = 0 })
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$origin = "http://127.0.0.1:" + $port
$rs = [runspacefactory]::CreateRunspace()
$rs.Open()
$ps = [powershell]::Create()
$ps.Runspace = $rs
[void]$ps.AddScript({
    param($listener, $sync)
    while (-not $sync.stop) {
        if (-not $listener.Pending()) { Start-Sleep -Milliseconds 20; continue }
        $c = $listener.AcceptTcpClient()
        try {
            $s = $c.GetStream()
            $r = New-Object System.IO.StreamReader($s)
            $first = $r.ReadLine()
            while ($true) { $l = $r.ReadLine(); if ($null -eq $l -or $l -eq "") { break } }
            $sync.hits++
            $path = ($first -split " ")[1]
            $mode = $sync.mode
            if ($mode -eq "closed") { continue }
            $status = "200 OK"; $extra = ""
            if ($mode -eq "500") { $status = "500 Internal Server Error" }
            elseif ($path -eq "/auth/google") {
                $id = [System.Uri]::EscapeDataString($sync.id)
                if ($mode -eq "bom") { $id = "%EF%BB%BF" + $id }
                if ($mode -eq "shape") { $id = "not-a-client-id" }
                if ($mode -eq "two") { $id = $id + "&client_id=" + $id }
                if ($mode -eq "longid") { $id = ("1" * 33) + "-abc.apps.googleusercontent.com" }
                $where = $(if ($mode -eq "elsewhere") { "https://evil.example/o/oauth2/v2/auth" } else { "https://accounts.google.com/o/oauth2/v2/auth" })
                $status = "303 See Other"; $extra = "Location: " + $where + "?response_type=code&client_id=" + $id + "&redirect_uri=x`r`n"
            }
            $b = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.1 " + $status + "`r`n" + $extra + "Content-Length: 2`r`nConnection: close`r`n`r`nok")
            $s.Write($b, 0, $b.Length); $s.Flush()
        } catch { } finally { $c.Close() }
    }
}).AddArgument($listener).AddArgument($sync)
$handle = $ps.BeginInvoke()

$fetch = { param($Url) return (Get-HordeRelayWatchResponse -Url $Url) }
$policy = [pscustomobject]@{ relayEveryMinutes = 5; relayFailuresBeforeAlert = 2 }
# A WORLD (T-0391 slice 8): the warchief's mailbox as the suite plays it. Tell marks and posts a notice under (key, generation) like the real
# marked teller (cli/AnalystTend.ps1); Taken says "taken" only when the suite has the warchief's session take it (taken[], or autoTake), "pending"
# while it is marked and not taken, "lost" when the suite gives it up, "unknown" for a notice never marked. refuse[key] refuses that many posts
# (a known refusal: no mark); unknown[key] answers every post with an UNKNOWN result that left its mark; dup[key] answers that many posts
# "accepted" for an id the messenger already held (already-posted, and the mark this call wrote is taken off again: ok, not listed); held[id] is
# a notice the messenger holds for good (Taken says held), lost[id] one it gave up (lost).
function New-World {
    param([datetime]$Start)
    return [pscustomobject]@{ now = $Start; tells = (New-Object System.Collections.ArrayList); posts = (New-Object System.Collections.ArrayList); notices = (New-Object System.Collections.ArrayList)
                              marked = @{}; taken = @{}; lost = @{}; held = @{}; refuse = @{}; unknown = @{}; dup = @{}; autoTake = $false }
}
function New-WorldTools {
    param($W, [switch]$NoTaken)
    $f = $fetch
    $t = @{
        Now = { return $W.now }.GetNewClosure()
        Fetch = $f
        Tell = {
            param($Body, $Key, $Gen)
            $id = "" + $Key + "|" + $Gen
            [void]$W.tells.Add($Body); [void]$W.posts.Add($id)
            if ($W.refuse.ContainsKey($Key) -and $W.refuse[$Key] -gt 0) { $W.refuse[$Key] = $W.refuse[$Key] - 1; return [pscustomobject]@{ ok = $false; detail = "the fleet mail failed"; listed = $false } }
            if ($W.dup.ContainsKey($Key) -and $W.dup[$Key] -gt 0) { $W.dup[$Key] = $W.dup[$Key] - 1; return [pscustomobject]@{ ok = $true; detail = ""; listed = $false } }
            $W.marked[$id] = $true
            if ($W.unknown.ContainsKey($Key)) { return [pscustomobject]@{ ok = $false; detail = "no answer"; listed = $true } }
            return [pscustomobject]@{ ok = $true; detail = ""; listed = $true }
        }.GetNewClosure()
        Taken = {
            param($Key, $Gen)
            $id = "" + $Key + "|" + $Gen
            if ($W.lost.ContainsKey($id)) { return "lost" }
            if ($W.held.ContainsKey($id)) { return "held" }
            if ($W.marked.ContainsKey($id)) { if ($W.autoTake -or $W.taken.ContainsKey($id)) { return "taken" }; return "pending" }
            return "unknown"
        }.GetNewClosure()
        Notify = { param($Line) [void]$W.notices.Add($Line); return [pscustomobject]@{ ok = $true; detail = "" } }.GetNewClosure()
    }
    if ($NoTaken) { $t["Taken"] = $null }
    return $t
}
# Pass starts a world's state at episode 0 when there is no file, so a test can name the ids; PassRaw does not (the clock-made number, below).
function PassRaw { param($W, $Tools, [string]$Path, [double]$Minutes) $W.now = $t0.AddMinutes($Minutes); return (Invoke-HordeRelayWatch -Tools $Tools -Policy $policy -StatePath $Path -Origin $origin) }
function Pass { param($W, $Tools, [string]$Path, [double]$Minutes) if (-not [System.IO.File]::Exists($Path)) { Write-HordeRelayWatchState -Path $Path -State (New-HordeRelayWatchState) }; return (PassRaw $W $Tools $Path $Minutes) }
function State-Of { param([string]$Path) return (Read-HordeRelayWatchState -Path $Path).value }
function Bodies { param($W, [string]$Like) return @($W.tells | Where-Object { $_ -like $Like }).Count }
function Health { return (Get-HordeRelayHealth -Origin $origin -Fetch $fetch) }

try {
    Write-Host ""
    Write-Host "--- the client id's shape ---" -ForegroundColor Cyan
    Check ((Test-HordeRelayClientId -Value $goodId) -ceq "") "a Google web client id passes"
    Check ((Test-HordeRelayClientId -Value ([string][char]0xFEFF + $goodId)) -like "*byte order mark*") "one with a byte order mark in front fails, and says so (the fault of 2026-10-14)"
    Check ((Test-HordeRelayClientId -Value ($goodId + " ")) -like "*blank*" -and (Test-HordeRelayClientId -Value ($goodId + "`n")) -like "*blank*") "a trailing blank or line break fails"
    Check ((Test-HordeRelayClientId -Value ($goodId.Replace("abc", "ab" + [char]0x00E9)))-like "*not plain ASCII*") "a character that is not ASCII fails"
    Check ((Test-HordeRelayClientId -Value "abc.apps.googleusercontent.com") -like "*shape*" -and (Test-HordeRelayClientId -Value "") -like "*no client_id*") "a wrong shape and no id fail"
    foreach ($bad in @(([string][char]0xFEFF + $goodId), "not-a-client-id")) { Check ((Test-HordeRelayClientId -Value $bad) -cnotlike ("*" + $bad.Trim([char]0xFEFF) + "*")) "a reason never repeats the id" }
    Check (@(Get-HordeRelayQueryValues -Url "https://a/b?x=1&client_id=%EF%BB%BFab%2Ec" -Name "client_id")[0] -ceq ([string][char]0xFEFF + "ab.c")) "the client_id is URL-decoded before it is checked"

    Write-Host ""
    Write-Host "--- the three checks, against the suite's own relay ---" -ForegroundColor Cyan
    $h = Health
    Check ($h.ok) "a healthy relay passes all three"
    $sync.mode = "500"; $h = Health
    Check (-not $h.ok -and $h.why -ceq "GET / answered 500, not 200") "a 500 fails, naming the path and the status"
    $sync.mode = "closed"; $h = Health
    Check (-not $h.ok -and $h.why -ceq "GET / got no answer") "a connection closed with no answer fails"
    $sync.mode = "bom"; $h = Health
    Check (-not $h.ok -and $h.why -like "GET /auth/google: the client_id carries a byte order mark*every new sign-in fails" -and $h.why -cnotlike ("*" + $goodId + "*")) "a byte order mark in the client id fails, though every page is 200 - and the id is not in the reason"
    $sync.mode = "shape"; $h = Health
    Check (-not $h.ok -and $h.why -like "*not the shape*") "a client id of the wrong shape fails"
    $sync.mode = "two"; $h = Health
    Check (-not $h.ok -and $h.why -like "*names client_id more than once*") "a client_id named twice fails, as PR 275's deploy check refuses it"
    $sync.mode = "longid"; $h = Health
    Check (-not $h.ok -and $h.why -like "*not the shape*") "a client id past the client file's length bounds fails (the relay adapter's GoogleClient.ps1)"
    $sync.mode = "elsewhere"; $h = Health
    Check (-not $h.ok -and $h.why -like "*not https://accounts.google.com*") "a sign-in that redirects elsewhere fails"
    $sync.mode = "up"

    Write-Host ""
    Write-Host "--- told once when down, quiet while down, told once when back; one blip tells nobody - and told only when TAKEN (T-0391 slice 8) ---" -ForegroundColor Cyan
    $w1 = New-World $t0; $tl1 = New-WorldTools $w1; $sp1 = Join-Path $work "relay-watch.json"
    $null = Pass $w1 $tl1 $sp1 0
    Check ($w1.tells.Count -eq 0 -and $w1.notices.Count -eq 0) "healthy: nobody told"
    $null = Pass $w1 $tl1 $sp1 2
    $hitsBefore = $sync.hits
    $null = Pass $w1 $tl1 $sp1 4
    Check ($sync.hits -eq $hitsBefore) "a look is taken only every relayEveryMinutes (5)"
    $sync.mode = "500"
    $w = Pass $w1 $tl1 $sp1 5
    Check ($w1.tells.Count -eq 0 -and (@($w.lines) -join " ") -like "*failing (1 in a row)*") "one failure: nobody told yet"
    $sync.mode = "up"
    $null = Pass $w1 $tl1 $sp1 10
    Check ($w1.tells.Count -eq 0 -and $w1.notices.Count -eq 0) "a single blip, then healthy: nobody told, ever"
    $sync.mode = "bom"
    $null = Pass $w1 $tl1 $sp1 15
    $w = Pass $w1 $tl1 $sp1 20
    Check ($w1.tells.Count -eq 1 -and $w1.tells[0] -like "RELAY DOWN*byte order mark*" -and $w1.notices.Count -eq 1) "two in a row: the warchief's notice is posted by fleet mail, and one notice is tried"
    Check ($w1.posts[0] -ceq "relay-down|0" -and (@($w.lines) -join " ") -like "*relay watch: posted to the warchief (counted as told only when his session takes it)*") "it is posted under the key relay-down and episode 0, and the line says it is not yet told"
    $s1 = State-Of $sp1
    Check (-not $s1.alerted -and $s1.downTell -ceq "posted") "POSTED IS NOT TOLD: the outage is not marked told when the messenger accepted the mail"
    Check ($w1.notices[0] -clike "*A notice to the warchief was posted and is being watched for its taking.*" -and $w1.notices[0] -cnotlike "*fleet mail*") "the phone is told what is known: posted and watched - not that the warchief is told by fleet mail"
    Check ($w1.tells[0] -cnotlike ("*" + $goodId + "*") -and $w1.notices[0] -cnotlike ("*" + $goodId + "*")) "neither carries the client id"
    $sync.mode = "closed"
    $null = Pass $w1 $tl1 $sp1 25; $null = Pass $w1 $tl1 $sp1 30
    Check ($w1.tells.Count -eq 1 -and $w1.notices.Count -eq 1) "while it stays down and the mail is awaited, nothing more is said or posted, whatever the failure"
    $w1.taken["relay-down|0"] = $true
    $sync.mode = "up"
    $w = Pass $w1 $tl1 $sp1 35
    Check ((State-Of $sp1).alerted -and (State-Of $sp1).downTell -ceq "" -and (@($w.lines) -join " ") -like "*took the DOWN notice*") "the warchief's session takes it: the outage is counted as told, and the line says so"
    $sync.mode = "500"
    $null = Pass $w1 $tl1 $sp1 40
    Check ($w1.tells.Count -eq 1) "one healthy check in the middle of an outage is not a recovery: nothing is said (review of PR 307)"
    $sync.mode = "up"
    $null = Pass $w1 $tl1 $sp1 45
    Check ($w1.tells.Count -eq 1) "the first healthy check after it: still nothing"
    $null = Pass $w1 $tl1 $sp1 50
    Check ($w1.tells.Count -eq 2 -and $w1.tells[1] -like "RELAY BACK*down about 35 minutes*" -and $w1.posts[1] -ceq "relay-back|0" -and $w1.notices.Count -eq 2 -and $w1.notices[1] -like "*down about 35 minutes*") "two healthy checks in a row: the back notice is posted, with how long it was down (from the first failure), and the phone hears it once"
    Check ($w1.notices[1] -clike "*posted and is being watched for its taking.*") "and the phone is told of the back notice only that it is posted and watched"
    $s1 = State-Of $sp1
    Check ($s1.alerted -and $s1.backTell -ceq "posted" -and $s1.episode -eq 0) "A RECOVERY IS NOT TOLD UNTIL TAKEN: the episode stays open while the back notice awaits the warchief"
    $null = Pass $w1 $tl1 $sp1 55; $null = Pass $w1 $tl1 $sp1 60
    Check ($w1.tells.Count -eq 2 -and $w1.notices.Count -eq 2) "and it is not posted again while it awaits"
    $w1.taken["relay-back|0"] = $true
    $w = Pass $w1 $tl1 $sp1 65
    $s1 = State-Of $sp1
    Check (-not $s1.alerted -and -not $s1.notified -and $s1.backTell -ceq "" -and $s1.downTell -ceq "" -and $s1.episode -eq 1 -and (@($w.lines) -join " ") -like "*took the BACK notice*") "the back notice taken: the outage is closed, and the next one is episode 1"
    $null = Pass $w1 $tl1 $sp1 70
    Check ($w1.tells.Count -eq 2) "and then nothing while it is healthy"
    # A second outage is episode 1: every notice has a new id, and a taking seen on a pass that is not due is kept.
    $sync.mode = "500"
    $null = Pass $w1 $tl1 $sp1 75; $null = Pass $w1 $tl1 $sp1 80
    Check ($w1.posts[-1] -ceq "relay-down|1" -and $w1.notices.Count -eq 3) "the next outage is episode 1: its down notice has a new id, and the phone hears of it once"
    $w1.taken["relay-down|1"] = $true
    $null = Pass $w1 $tl1 $sp1 81
    Check ((State-Of $sp1).alerted -and (State-Of $sp1).downTell -ceq "") "a taking seen on a pass that is not due for a look is counted and kept at once"
    $sync.mode = "up"
    foreach ($m in @(85, 90, 95)) { $null = Pass $w1 $tl1 $sp1 $m }
    Check ($w1.posts[-1] -ceq "relay-back|1" -and (Bodies $w1 "RELAY BACK*") -eq 2 -and (State-Of $sp1).backTell -ceq "posted") "and its back notice has the new id too, and awaits its own taking (episode 0's taken back notice does not close it)"

    Write-Host ""
    Write-Host "--- review of PR 307: a tell that failed is not a tell; it is tried again under the same id ---" -ForegroundColor Cyan
    $w2 = New-World $t0; $w2.autoTake = $true; $w2.refuse["relay-down"] = 1; $tl2 = New-WorldTools $w2; $sp2 = Join-Path $work "failed-tell.json"
    $sync.mode = "500"
    foreach ($m in @(200, 205)) { $null = Pass $w2 $tl2 $sp2 $m }
    Check ($w2.tells.Count -eq 1 -and -not (State-Of $sp2).alerted -and (State-Of $sp2).downTell -ceq "" -and $w2.notices.Count -eq 1 -and $w2.notices[0] -clike "*A notice to the warchief was not posted.*") "the warchief's mail was refused: nothing is marked posted or told, and the phone is told it was not posted"
    $null = Pass $w2 $tl2 $sp2 210
    Check ($w2.tells.Count -eq 2 -and $w2.posts[1] -ceq $w2.posts[0] -and (State-Of $sp2).downTell -ceq "posted" -and -not (State-Of $sp2).alerted) "the next check tries again under the SAME id, and it is posted - still not told"
    $null = Pass $w2 $tl2 $sp2 215
    Check ($w2.tells.Count -eq 2 -and (State-Of $sp2).alerted -and $w2.notices.Count -eq 1) "the next pass sees it taken: told; then quiet; and the phone's notice was tried once for the outage"

    Write-Host ""
    Write-Host "--- review of PR 307: a founder told 'down' is told 'back', even if the warchief never was ---" -ForegroundColor Cyan
    $w3 = New-World $t0; $w3.autoTake = $true; $w3.refuse["relay-down"] = 99; $tl3 = New-WorldTools $w3; $sp3b = Join-Path $work "never-told.json"
    $sync.mode = "500"
    foreach ($m in @(300, 305, 310)) { $null = Pass $w3 $tl3 $sp3b $m }
    Check ($w3.notices.Count -eq 1 -and $w3.notices[0] -like "The relay check fails*" -and -not (State-Of $sp3b).alerted -and $w3.posts[0] -ceq $w3.posts[1]) "the warchief's mail is refused throughout: the phone was told it is down once, the outage is not told, and each try has the same id"
    $sync.mode = "up"
    foreach ($m in @(315, 320, 325)) { $null = Pass $w3 $tl3 $sp3b $m }
    Check ($w3.notices.Count -eq 2 -and $w3.notices[1] -like "The relay is back*" -and $w3.notices[1] -clike "*No notice about the outage was posted to the warchief, so none about its end is posted.*") ("two healthy checks: the phone is told it is back, and that nothing reached the warchief (" + $w3.notices.Count + " notices)")
    Check ((Bodies $w3 "RELAY BACK*") -eq 0) "and the warchief, never told it was down, is not told it is back"
    Check (-not (State-Of $sp3b).notified -and (State-Of $sp3b).episode -eq 1) "and the outage is closed"

    Write-Host ""
    Write-Host "--- review of PR 307: a 'back' the warchief did not take stays owed ---" -ForegroundColor Cyan
    $w4 = New-World $t0; $w4.autoTake = $true; $w4.refuse["relay-back"] = 1; $tl4 = New-WorldTools $w4; $sp4 = Join-Path $work "back-owed.json"
    $sync.mode = "500"
    foreach ($m in @(400, 405)) { $null = Pass $w4 $tl4 $sp4 $m }
    $sync.mode = "up"
    foreach ($m in @(410, 415)) { $null = Pass $w4 $tl4 $sp4 $m }
    Check ((State-Of $sp4).alerted -and (Bodies $w4 "RELAY BACK*") -eq 1 -and (State-Of $sp4).backTell -ceq "" -and $w4.notices.Count -eq 1) "told 'down'; the 'back' mail is refused: the outage stays open, and the phone is not yet told 'back'"
    $null = Pass $w4 $tl4 $sp4 420
    Check ((Bodies $w4 "RELAY BACK*") -eq 2 -and $w4.posts[-1] -ceq $w4.posts[-2] -and (State-Of $sp4).backTell -ceq "posted" -and $w4.notices.Count -eq 2 -and $w4.notices[1] -like "The relay is back*") "the next healthy check posts it again under the same id, and the phone hears 'back' once, with it"
    $null = Pass $w4 $tl4 $sp4 425
    Check (-not (State-Of $sp4).alerted -and (State-Of $sp4).episode -eq 1 -and $w4.notices.Count -eq 2) "and it is closed only when the warchief takes it"

    Write-Host ""
    Write-Host "--- review of PR 307: a founder never told 'down' is not told 'back' ---" -ForegroundColor Cyan
    $w5 = New-World $t0; $w5.autoTake = $true; $tl5 = New-WorldTools $w5; $sp5 = Join-Path $work "founder-never-told.json"
    $seed = New-HordeRelayWatchState
    $seed.failures = 2; $seed.alerted = $true; $seed.notified = $false; $seed.downSince = $t0.AddMinutes(490); $seed.lastCheckAt = $t0.AddMinutes(495); $seed.lastWhy = "planted"
    Write-HordeRelayWatchState -Path $sp5 -State $seed
    Check ((State-Of $sp5).alerted -and -not (State-Of $sp5).notified) "CONTROL: the planted state reads back as told to the warchief only"
    $sync.mode = "up"
    foreach ($m in @(500, 505)) { $null = Pass $w5 $tl5 $sp5 $m }
    Check ((Bodies $w5 "RELAY BACK*") -eq 1 -and $w5.notices.Count -eq 0) ("two healthy checks: the warchief's back notice is posted, the phone is not told (" + $w5.notices.Count + " notices)")
    $null = Pass $w5 $tl5 $sp5 510
    Check (-not (State-Of $sp5).alerted) "and the outage is closed once it is taken"

    Write-Host ""
    Write-Host "--- T-0391 slice 8: a result that is unknown may have landed; a notice given up is not posted again; no Taken tool counts nothing ---" -ForegroundColor Cyan
    $w8 = New-World $t0; $w8.unknown["relay-down"] = $true; $tl8 = New-WorldTools $w8; $sp8 = Join-Path $work "unknown.json"
    $sync.mode = "500"
    foreach ($m in @(600, 605)) { $null = Pass $w8 $tl8 $sp8 $m }
    Check ($w8.notices[0] -clike "*A notice to the warchief may have been posted; the watch cannot tell.*" -and $w8.notices[0] -cnotlike "*was not posted*" -and (State-Of $sp8).downTell -ceq "maybe" -and -not (State-Of $sp8).alerted) "an UNKNOWN result keeps its mark: the phone is told it MAY have been posted - never 'not posted' - and it is watched, not counted"
    $null = Pass $w8 $tl8 $sp8 610
    Check ($w8.tells.Count -eq 2 -and $w8.posts[1] -ceq $w8.posts[0] -and $w8.notices.Count -eq 1 -and (State-Of $sp8).downTell -ceq "maybe") "and it is posted AGAIN at the next check under the same id (it may not have landed), the phone is not told twice"
    $w8.unknown.Remove("relay-down")
    $null = Pass $w8 $tl8 $sp8 615
    Check ($w8.tells.Count -eq 3 -and $w8.posts[2] -ceq $w8.posts[0] -and (State-Of $sp8).downTell -ceq "posted") "a repost the messenger then accepts makes it posted"
    $w8.taken[$w8.posts[0]] = $true
    $null = Pass $w8 $tl8 $sp8 620
    Check ((State-Of $sp8).alerted) "and its TAKEN counts it"
    $w8b = New-World $t0; $w8b.unknown["relay-down"] = $true; $tl8b = New-WorldTools $w8b; $sp8b = Join-Path $work "unknown-taken.json"
    foreach ($m in @(630, 635)) { $null = Pass $w8b $tl8b $sp8b $m }
    $w8b.taken["relay-down|0"] = $true
    $null = Pass $w8b $tl8b $sp8b 640
    Check ((State-Of $sp8b).alerted -and $w8b.tells.Count -eq 1) "a post whose result was unknown, that turns out TAKEN, is counted told (the look comes before the repost)"
    $w9 = New-World $t0; $tl9 = New-WorldTools $w9; $sp9 = Join-Path $work "lost.json"
    foreach ($m in @(700, 705)) { $null = Pass $w9 $tl9 $sp9 $m }
    $w9.lost["relay-down|0"] = $true
    $w = Pass $w9 $tl9 $sp9 710
    Check ((State-Of $sp9).downTell -ceq "lost" -and -not (State-Of $sp9).alerted -and (@($w.lines) -join " ") -like "*DOWN notice to the warchief was not taken in time and is no longer watched (it may still be in his mailbox)*" -and (@($w.lines) -join " ") -cnotlike "*unread*") "a down notice the engine gave up is NOT told: the line says only that it was not taken in time, and that it may still be in his mailbox"
    $null = Pass $w9 $tl9 $sp9 715
    Check ($w9.tells.Count -eq 1) "and none is posted again for that outage"
    $sync.mode = "up"
    foreach ($m in @(720, 725)) { $null = Pass $w9 $tl9 $sp9 $m }
    Check ((Bodies $w9 "RELAY BACK*") -eq 0 -and (State-Of $sp9).episode -eq 1 -and -not (State-Of $sp9).notified) "a recovery of an outage the warchief never heard of is not posted, and the episode is closed"
    $w10 = New-World $t0; $tl10 = New-WorldTools $w10; $sp10 = Join-Path $work "down-pending.json"
    $sync.mode = "500"
    foreach ($m in @(800, 805)) { $null = Pass $w10 $tl10 $sp10 $m }
    $sync.mode = "up"
    foreach ($m in @(810, 815)) { $null = Pass $w10 $tl10 $sp10 $m }
    Check ((Bodies $w10 "RELAY BACK*") -eq 1 -and (State-Of $sp10).backTell -ceq "posted" -and -not (State-Of $sp10).alerted) "a down notice posted and not yet taken is owed its back notice: he has the down mail in his inbox"
    $w11 = New-World $t0; $tl11 = New-WorldTools $w11; $sp11 = Join-Path $work "refail.json"
    $sync.mode = "500"
    foreach ($m in @(900, 905)) { $null = Pass $w11 $tl11 $sp11 $m }
    $w11.taken["relay-down|0"] = $true
    $sync.mode = "up"
    foreach ($m in @(910, 915)) { $null = Pass $w11 $tl11 $sp11 $m }
    $sync.mode = "500"
    $null = Pass $w11 $tl11 $sp11 920
    $w11.taken["relay-back|0"] = $true
    $null = Pass $w11 $tl11 $sp11 925
    Check ((State-Of $sp11).episode -eq 1 -and $w11.posts[-1] -ceq "relay-down|1" -and (Bodies $w11 "RELAY DOWN*") -eq 2) "a back notice taken while the relay fails again closes that outage; the new one is episode 1, with a new id"
    $w12 = New-World $t0; $w12.autoTake = $true; $tl12 = New-WorldTools $w12 -NoTaken; $sp12 = Join-Path $work "no-taken.json"
    foreach ($m in @(1000, 1005, 1010, 1015, 1020)) { $null = Pass $w12 $tl12 $sp12 $m }
    Check (-not (State-Of $sp12).alerted -and (State-Of $sp12).downTell -ceq "posted" -and $w12.tells.Count -eq 1) "with no Taken tool nothing is ever counted as taken - the messenger's ok is not enough - and nothing is posted twice"
    $w = Pass $w12 $tl12 $sp12 (1005 + 8 * 24 * 60)
    Check ((State-Of $sp12).downTell -ceq "lost" -and (@($w.lines) -join " ") -like "*not taken in time*") "and a notice awaited a notice-ttl (7 days) is given up"
    $sync.mode = "up"
    Write-HordeRelayWatchState -Path (Join-Path $work "old.json") -State (New-HordeRelayWatchState)
    $oldDoc = '{"v":1,"lastCheckAt":null,"failures":2,"healthy":0,"downSince":null,"alerted":true,"notified":true,"lastWhy":"x"}'
    [System.IO.File]::WriteAllText((Join-Path $work "old.json"), $oldDoc, $utf8)
    $w13 = New-World $t0; $w13.autoTake = $true; $w13.unknown["relay-back"] = $true; $tl13 = New-WorldTools $w13; $sp13 = Join-Path $work "back-unknown.json"
    $sync.mode = "500"
    foreach ($m in @(1100, 1105)) { $null = Pass $w13 $tl13 $sp13 $m }
    $sync.mode = "up"
    foreach ($m in @(1110, 1115, 1120)) { $null = Pass $w13 $tl13 $sp13 $m }
    Check ($w13.notices.Count -eq 2 -and $w13.notices[1] -clike "*A notice to the warchief may have been posted; the watch cannot tell.*" -and (Bodies $w13 "RELAY BACK*") -eq 1) "a back notice whose result is unknown: the phone is told it MAY have been posted, once, and it is not posted twice"
    $w15 = New-World $t0; $tl15 = New-WorldTools $w15; $sp15 = Join-Path $work "back-given-up.json"
    $sync.mode = "500"
    foreach ($m in @(1300, 1305)) { $null = Pass $w15 $tl15 $sp15 $m }
    $w15.taken["relay-down|0"] = $true
    $sync.mode = "up"
    foreach ($m in @(1310, 1315)) { $null = Pass $w15 $tl15 $sp15 $m }
    $w15.lost["relay-back|0"] = $true
    $w = Pass $w15 $tl15 $sp15 1320
    Check ((State-Of $sp15).episode -eq 1 -and -not (State-Of $sp15).alerted -and (State-Of $sp15).backTell -ceq "" -and (@($w.lines) -join " ") -like "*BACK notice to the warchief was not taken in time and is no longer watched*the outage is closed*") "a back notice the engine gave up is not told, but the outage is closed (no notice can come of it), and the line says so"
    # ROUND 2, MUST-FIX 2: a notice that is not taken and is no longer watched is said in what is known of it - held is not delivered; lost may still be in his mailbox.
    $w16 = New-World $t0; $tl16 = New-WorldTools $w16; $sp16 = Join-Path $work "held.json"
    $sync.mode = "500"
    foreach ($m in @(1400, 1405)) { $null = Pass $w16 $tl16 $sp16 $m }
    $w16.held["relay-down|0"] = $true
    $w = Pass $w16 $tl16 $sp16 1410
    Check ((State-Of $sp16).downTell -ceq "held" -and -not (State-Of $sp16).alerted -and (@($w.lines) -join " ") -clike "*DOWN notice to the warchief could not be delivered (the messenger holds it for good) and is not taken; he is not told*") "a down notice the messenger HOLDS is not told, and the line says it could not be delivered"
    $sync.mode = "up"
    foreach ($m in @(1415, 1420)) { $null = Pass $w16 $tl16 $sp16 $m }
    Check ($w16.notices[-1] -clike "*The warchief's notice about the outage could not be delivered (the messenger holds it), so none about its end is posted.*" -and $w16.notices[-1] -cnotlike "*reached*") "and the phone is told only that: not 'no notice reached the warchief'"
    Check ((Get-HordeWatchLostWords -Why "held") -ceq "The warchief's notice could not be delivered: the messenger holds it, and it was not taken." -and (Get-HordeWatchLostWords -Why "lost") -ceq "The warchief's notice was not taken in time and is no longer watched; it may still be in his mailbox.") "the words for a phone about a notice that is not taken and not watched: held was not delivered; lost may still be in his mailbox"
    Check ($w9.notices[-1] -clike "*The warchief's notice about the outage was not taken in time, so none about its end is posted.*" -and $w9.notices[-1] -cnotlike "*reached*") "a notice given up by the engine: the phone is told it was not taken in time - not that nothing reached the warchief"
    # ROUND 2, MUST-FIX 1: a removed state file never starts again at an episode whose ids the messenger holds.
    $w17 = New-World $t0; $tl17 = New-WorldTools $w17; $sp17 = Join-Path $work "removed.json"
    $sync.mode = "500"
    foreach ($m in @(1500, 1505)) { $null = PassRaw $w17 $tl17 $sp17 $m }
    $secs17 = [long][System.Math]::Floor(($t0.AddMinutes(1500).ToUniversalTime() - ([datetime]"1970-01-01T00:00:00Z").ToUniversalTime()).TotalSeconds)
    $e17 = (State-Of $sp17).episode
    Check ($e17 -eq $secs17 -and $w17.posts[0] -ceq ("relay-down|" + $e17)) "a state with no file takes its episode number from the clock (seconds since 1970), and the notice ids carry it"
    $w17.taken["relay-down|" + $e17] = $true
    $sync.mode = "up"
    foreach ($m in @(1510, 1515)) { $null = PassRaw $w17 $tl17 $sp17 $m }
    $w17.taken["relay-back|" + $e17] = $true
    $null = PassRaw $w17 $tl17 $sp17 1520
    Check ((State-Of $sp17).episode -eq ($e17 + 1) -and -not (State-Of $sp17).alerted) "CONTROL: the first outage is told and closed"
    [System.IO.File]::Delete($sp17)
    $sync.mode = "500"
    foreach ($m in @(1600, 1605)) { $null = PassRaw $w17 $tl17 $sp17 $m }
    $nowIds = @($w17.posts | Select-Object -Last 1)
    Check ($nowIds[0] -cne ("relay-down|" + $e17) -and $nowIds[0] -cne ("relay-down|" + ($e17 + 1)) -and (State-Of $sp17).episode -gt ($e17 + 1)) "STATE FILE REMOVED (the STOPPED notice's own advice): the new outage has a NEW id, not the first outage's"
    $w = PassRaw $w17 $tl17 $sp17 1610
    Check (-not (State-Of $sp17).alerted -and (@($w.lines) -join " ") -cnotlike "*took the DOWN notice*") "and the first outage's taken notice is not counted as the new outage's TAKEN"
    # ROUND 2, MUST-FIX 1(a): a post that is only a repost of a copy the messenger already held is neither posted nor watched, and is said so.
    $w18 = New-World $t0; $w18.dup["relay-down"] = 99; $tl18 = New-WorldTools $w18; $sp18 = Join-Path $work "copy.json"
    $sync.mode = "500"
    foreach ($m in @(1700, 1705)) { $null = Pass $w18 $tl18 $sp18 $m }
    $w18.taken["relay-down|0"] = $true
    Check ($w18.notices[0] -clike "*Nothing new was posted to the warchief: the messenger already held a copy of this notice.*" -and $w18.notices[0] -cnotlike "*being watched*" -and (State-Of $sp18).downTell -ceq "") "ok with no mark kept (already posted): the phone is told nothing new was posted - not 'posted and being watched' - and nothing is stored as posted"
    $w = Pass $w18 $tl18 $sp18 1710
    Check ($w18.tells.Count -eq 2 -and -not (State-Of $sp18).alerted -and (@($w.lines) -join " ") -like "*nothing new was posted to the warchief: the messenger already held a copy*") "it is tried again at the next check, and an earlier copy's fate is never counted as this notice's TAKEN"
    # SHOULD-FIX 1 for the STOPPED notice: an unknown result is posted again, same id.
    $w19 = New-World $t0; $w19.unknown["relay-stopped"] = $true; $tl19 = New-WorldTools $w19
    $bad19 = Join-Path $work "bad-state19.json"
    [System.IO.File]::WriteAllText($bad19, "not json", $utf8)
    $null = PassRaw $w19 $tl19 $bad19 0
    Check ($w19.tells.Count -eq 1 -and ([System.IO.File]::ReadAllText($bad19 + ".told")) -clike "maybe *") "a STOPPED notice with an unknown result is kept as maybe"
    $null = PassRaw $w19 $tl19 $bad19 5
    Check ($w19.tells.Count -eq 2 -and $w19.posts[1] -ceq $w19.posts[0]) "and is posted again at the next pass under the same id"
    $w19.unknown.Remove("relay-stopped")
    $null = PassRaw $w19 $tl19 $bad19 10
    Check ($w19.tells.Count -eq 3 -and ([System.IO.File]::ReadAllText($bad19 + ".told")) -clike "posted *") "then, accepted, it is posted and awaited"
    # A back notice whose result is unknown is posted again, and the phone is told of it once; its age is that of the first post (7 days).
    $w20 = New-World $t0; $w20.unknown["relay-back"] = $true; $tl20 = New-WorldTools $w20; $sp20 = Join-Path $work "back-unknown-repost.json"
    $sync.mode = "500"
    foreach ($m in @(1800, 1805)) { $null = Pass $w20 $tl20 $sp20 $m }
    $w20.taken["relay-down|0"] = $true
    $sync.mode = "up"
    foreach ($m in @(1810, 1815, 1820, 1825)) { $null = Pass $w20 $tl20 $sp20 $m }
    Check ((Bodies $w20 "RELAY BACK*") -eq 3 -and $w20.posts[-1] -ceq "relay-back|0" -and (State-Of $sp20).backTell -ceq "maybe" -and $w20.notices.Count -eq 2) "a back notice with an unknown result is posted again at each healthy check, same id, and the phone hears of it once"
    Check ((State-Of $sp20).backAt -eq $t0.AddMinutes(1815)) "and its age is that of the first post"
    $w21 = New-World $t0; $w21.unknown["relay-down"] = $true; $tl21 = New-WorldTools $w21; $sp21 = Join-Path $work "unknown-ages.json"
    $sync.mode = "500"
    foreach ($m in @(2000, 2005, (2005 + 3 * 1440), (2005 + 6 * 1440))) { $null = Pass $w21 $tl21 $sp21 $m }
    Check ((State-Of $sp21).downTell -ceq "maybe" -and (State-Of $sp21).downAt -eq $t0.AddMinutes(2005)) "an unknown result posted again for days keeps the time of its FIRST post"
    $w = Pass $w21 $tl21 $sp21 (2005 + 8 * 1440)
    Check ((State-Of $sp21).downTell -ceq "lost" -and (@($w.lines) -join " ") -like "*not taken in time*") "so it is given up a notice-ttl (7 days) after the first post, however often it was posted again"
    $w14 = New-World $t0; $tl14 = New-WorldTools $w14; $tl14["Tell"] = $null; $sp14 = Join-Path $work "telling-off.json"
    $sync.mode = "500"
    foreach ($m in @(1200, 1205)) { $null = Pass $w14 $tl14 $sp14 $m }
    Check ($w14.notices.Count -eq 1 -and $w14.notices[0] -clike "*A notice to the warchief was not posted.*" -and (State-Of $sp14).downTell -ceq "") "telling off: nothing is posted, nothing is marked, and the phone is told it was not posted"
    $so = State-Of (Join-Path $work "old.json")
    Check ($so.alerted -and $so.episode -eq 0 -and $so.downTell -ceq "" -and $so.backTell -ceq "") "a state file an earlier version wrote still reads: episode 0, nothing posted"
    [System.IO.File]::WriteAllText((Join-Path $work "oddtell.json"), '{"v":1,"lastCheckAt":null,"failures":2,"healthy":0,"downSince":null,"alerted":false,"notified":true,"lastWhy":"x","downTell":"bogus"}', $utf8)
    Check ((Read-HordeRelayWatchState -Path (Join-Path $work "oddtell.json")).state -cne "known") "a downTell that is not a known value makes the state unreadable: no guess"

    Write-Host ""
    Write-Host "--- review of PR 307: a state file that cannot be read is told (and counted only when taken), not a silent stop ---" -ForegroundColor Cyan
    $w6 = New-World $t0; $tl6 = New-WorldTools $w6
    $bad = Join-Path $work "bad-state.json"
    [System.IO.File]::WriteAllText($bad, "not json", $utf8)
    $wb = Pass $w6 $tl6 $bad 300
    Check ($w6.tells.Count -eq 1 -and $w6.tells[0] -like "RELAY WATCH STOPPED*" -and (@($wb.lines) -join " ") -like "*cannot be read*" -and $w6.posts[0] -clike "relay-stopped|*") "the warchief's notice that the watch has stopped is posted under the key relay-stopped"
    Check (([System.IO.File]::ReadAllText($bad + ".told")) -clike "posted *") "and is kept as posted, not told"
    $null = Pass $w6 $tl6 $bad 310
    Check ($w6.tells.Count -eq 1) "and not again while it awaits"
    $null = Pass $w6 $tl6 $bad (300 + 24 * 60)
    Check ($w6.tells.Count -eq 1) "nor a day later while it is still not taken"
    $w6.taken[$w6.posts[0]] = $true
    $w = Pass $w6 $tl6 $bad (300 + 24 * 60 + 5)
    Check ([System.IO.File]::ReadAllText($bad + ".told") -ceq "told" -and (@($w.lines) -join " ") -like "*took the STOPPED notice*" -and $w6.tells.Count -eq 1) "the warchief's session takes it: the file says told, from then"
    $null = Pass $w6 $tl6 $bad (300 + 24 * 60 + 60)
    Check ($w6.tells.Count -eq 1) "and not again within the day of its being taken"
    $null = Pass $w6 $tl6 $bad (300 + 2 * 24 * 60 + 10)
    Check ($w6.tells.Count -eq 2 -and $w6.posts[1] -cne $w6.posts[0]) "but again a day after, while it is still broken - under a new id"
    $w6b = New-World $t0; $w6b.refuse["relay-stopped"] = 1; $tl6b = New-WorldTools $w6b
    $bad2 = Join-Path $work "bad-state2.json"
    [System.IO.File]::WriteAllText($bad2, "not json", $utf8)
    $null = Pass $w6b $tl6b $bad2 0
    Check ($w6b.tells.Count -eq 1 -and -not [System.IO.File]::Exists($bad2 + ".told")) "a stopped notice the messenger refused leaves no mark"
    $null = Pass $w6b $tl6b $bad2 5
    Check ($w6b.tells.Count -eq 2 -and $w6b.posts[1] -ceq $w6b.posts[0] -and [System.IO.File]::Exists($bad2 + ".told")) "and is tried again at the next pass, under the same id"
    $three = [pscustomobject]@{ relayEveryMinutes = 5; relayFailuresBeforeAlert = 3 }
    $sp3 = Join-Path $work "three.json"
    $sync.mode = "500"
    $w7 = New-World $t0; $tl7 = New-WorldTools $w7
    foreach ($m in @(100, 105)) { $w7.now = $t0.AddMinutes($m); $null = Invoke-HordeRelayWatch -Tools $tl7 -Policy $three -StatePath $sp3 -Origin $origin }
    Check ($w7.tells.Count -eq 0) "with the setting at 3, two failures tell nobody"
    $w7.now = $t0.AddMinutes(110); $null = Invoke-HordeRelayWatch -Tools $tl7 -Policy $three -StatePath $sp3 -Origin $origin
    Check ($w7.tells.Count -eq 1) "and the third does"
    $sync.mode = "up"
    Check ((Invoke-HordeRelayWatch -Tools $tl7 -Policy $policy -StatePath (Join-Path $work "off.json") -Origin "").lines[0] -like "*off*") "no origin: the watch is off, and says so"

    Write-Host ""
    Write-Host "--- the real command, in a home in temp ---" -ForegroundColor Cyan
    $e = Join-Path $work "e2e"
    [void][System.IO.Directory]::CreateDirectory((Join-Path $e "settings"))
    [System.IO.File]::WriteAllText((Join-Path $e "settings\analyst.json"), ('{ "schemaVersion": 1, "settings": { "relayOrigin": "' + $origin + '", "relayFailuresBeforeAlert": 1 } }'), $utf8)
    $envE = @{ HORDE_HOME = $e; WEZFLEET_ROOT = (Join-Path $work "no-fleet-here") }
    $sync.mode = "bom"
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "tend") -Env $envE
    Check ($x.code -eq 0 -and $x.out -like "*relay watch: DOWN - GET /auth/google: the client_id carries a byte order mark*" -and $x.out -like "*would tell the warchief, but telling is off*") "tend checks the relay, sees the fault, and tells nobody from a test's home"
    Check ($x.out -cnotlike ("*" + $goodId + "*")) "the command never prints the client id"
    [System.IO.File]::WriteAllText((Join-Path $e "settings\analyst.json"), '{ "schemaVersion": 1, "settings": { "relayOrigin": "https://relay.example.invalid", "relayFailuresBeforeAlert": 1 } }', $utf8)
    Remove-Item -LiteralPath (Join-Path $e "analyst\relay-watch.json") -Force
    $x = Invoke-HordeCliProcess -Root $root -HordeArgs @("analyst", "tend") -Env $envE
    Check ($x.code -eq 0 -and $x.out -like "*relay watch: DOWN - GET / got no answer*") "a test's home never reaches a relay off this machine: the fetch refuses it"
} finally {
    $sync.stop = $true
    try { [void]$ps.EndInvoke($handle) } catch { }
    $ps.Dispose(); $rs.Dispose(); $listener.Stop()
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "a relay whose sign-in carries a bad client id is seen though its pages answer, told once by fleet mail and one notice, quiet while down, told again when back, and one blip tells nobody"
