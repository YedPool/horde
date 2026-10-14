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
$rig = [pscustomobject]@{ now = $t0; tells = (New-Object System.Collections.ArrayList); notices = (New-Object System.Collections.ArrayList) }
$tools = @{
    Now = { return $rig.now }.GetNewClosure()
    Fetch = $fetch
    Tell = { param($Body) [void]$rig.tells.Add($Body); return [pscustomobject]@{ ok = $true; detail = "" } }.GetNewClosure()
    Notify = { param($Line) [void]$rig.notices.Add($Line); return [pscustomobject]@{ ok = $true; detail = "" } }.GetNewClosure()
}
$statePath = Join-Path $work "relay-watch.json"
function Watch { param([int]$Minutes) $rig.now = $t0.AddMinutes($Minutes); return (Invoke-HordeRelayWatch -Tools $tools -Policy $policy -StatePath $statePath -Origin $origin) }
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
    Check ((Get-HordeRelayQueryValue -Url "https://a/b?x=1&client_id=%EF%BB%BFab%2Ec" -Name "client_id") -ceq ([string][char]0xFEFF + "ab.c")) "the client_id is URL-decoded before it is checked"

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
    $sync.mode = "elsewhere"; $h = Health
    Check (-not $h.ok -and $h.why -like "*not https://accounts.google.com*") "a sign-in that redirects elsewhere fails"
    $sync.mode = "up"

    Write-Host ""
    Write-Host "--- told once when down, quiet while down, told once when back; one blip tells nobody ---" -ForegroundColor Cyan
    $null = Watch 0
    Check ($rig.tells.Count -eq 0 -and $rig.notices.Count -eq 0) "healthy: nobody told"
    $null = Watch 2
    $hitsBefore = $sync.hits
    $null = Watch 4
    Check ($sync.hits -eq $hitsBefore) "a look is taken only every relayEveryMinutes (5)"
    $sync.mode = "500"
    $w = Watch 5
    Check ($rig.tells.Count -eq 0 -and (@($w.lines) -join " ") -like "*failing (1 in a row)*") "one failure: nobody told yet"
    $sync.mode = "up"
    $null = Watch 10
    Check ($rig.tells.Count -eq 0 -and $rig.notices.Count -eq 0) "a single blip, then healthy: nobody told, ever"
    $sync.mode = "bom"
    $null = Watch 15
    $null = Watch 20
    Check ($rig.tells.Count -eq 1 -and $rig.tells[0] -like "RELAY DOWN*byte order mark*" -and $rig.notices.Count -eq 1) "two in a row: the warchief is told by fleet mail, and one notice is tried"
    Check ($rig.tells[0] -cnotlike ("*" + $goodId + "*") -and $rig.notices[0] -cnotlike ("*" + $goodId + "*")) "neither carries the client id"
    $sync.mode = "closed"
    $null = Watch 25; $null = Watch 30
    Check ($rig.tells.Count -eq 1 -and $rig.notices.Count -eq 1) "while it stays down, nothing more is said, whatever the failure"
    $sync.mode = "up"
    $null = Watch 40
    Check ($rig.tells.Count -eq 2 -and $rig.tells[1] -like "RELAY BACK*down about 25 minutes*" -and $rig.notices.Count -eq 2 -and $rig.notices[1] -like "*down about 25 minutes*") "back: told once more, with how long it was down (from the first failure)"
    $null = Watch 45
    Check ($rig.tells.Count -eq 2) "and then nothing while it is healthy"
    $three = [pscustomobject]@{ relayEveryMinutes = 5; relayFailuresBeforeAlert = 3 }
    $sp3 = Join-Path $work "three.json"
    $sync.mode = "500"
    foreach ($m in @(0, 5)) { $rig.now = $t0.AddMinutes(100 + $m); $null = Invoke-HordeRelayWatch -Tools $tools -Policy $three -StatePath $sp3 -Origin $origin }
    Check ($rig.tells.Count -eq 2) "with the setting at 3, two failures tell nobody"
    $rig.now = $t0.AddMinutes(110); $null = Invoke-HordeRelayWatch -Tools $tools -Policy $three -StatePath $sp3 -Origin $origin
    Check ($rig.tells.Count -eq 3) "and the third does"
    $sync.mode = "up"
    Check ((Invoke-HordeRelayWatch -Tools $tools -Policy $policy -StatePath (Join-Path $work "off.json") -Origin "").lines[0] -like "*off*") "no origin: the watch is off, and says so"

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
