# DOES THE HOSTED RELAY'S ADAPTER CARRY A REFUSAL'S STATUS AND RETRY-AFTER, ON A WATCH AND A REQUEST?
#
# The founder's first live use (2026-10-11): `horde relay pair -Relay cloudflare` waited for the phone
# while the Worker answered 401 (the machine not yet registered), and its tries tripped the
# refused-signature limit, 429, whose Retry-After nothing read. relays/Port.ps1 now carries an
# unknown's status and retryAfterMs to the caller (A REFUSAL MAY SAY MORE THAN ITS REASON); this suite
# holds relays/cloudflare/Relay.ps1 to filling them in, from the two places a refusal arrives:
#   1. a watch: the WebSocket upgrade the relay refuses, where Windows PowerShell 5.1 and PowerShell 7
#      each hide the status and headers in their own place;
#   2. a request: a read and a put answered with a refusal, and the same with a Retry-After that is a
#      date, or that is not a number at all;
#   3. what is not a refusal carries nothing: a relay that is not there.
#
# THE RELAY HERE IS A STUB of the suite's own: a TCP listener on 127.0.0.1, in a runspace of this
# process, that answers each connection with the next canned HTTP response the suite queues. Nothing
# here runs node, wrangler or the Worker, and nothing leaves this machine. The adapter is connected with
# the suite-only authorization option, so no key store or identity is needed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "relays\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$shared = [hashtable]::Synchronized(@{ queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue)); seen = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList)) })
$rs = [runspacefactory]::CreateRunspace()
$rs.Open()
$ps = [powershell]::Create()
$ps.Runspace = $rs
[void]$ps.AddScript({
        param($Listener, $Shared)
        while ($true) {
            try { $c = $Listener.AcceptTcpClient() } catch { return }
            try {
                $s = $c.GetStream()
                $s.ReadTimeout = 5000
                $buf = New-Object byte[] 65536
                $got = ""
                while (-not $got.Contains("`r`n`r`n")) { $n = $s.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $got += [System.Text.Encoding]::ASCII.GetString($buf, 0, $n) }
                [void]$Shared.seen.Add(($got -split "`r`n")[0])
                $answer = $(if ($Shared.queue.Count -gt 0) { $Shared.queue.Dequeue() } else { "HTTP/1.1 500 Internal Server Error`r`nContent-Length: 0`r`nConnection: close`r`n`r`n" })
                $bytes = [System.Text.Encoding]::ASCII.GetBytes($answer)
                $s.Write($bytes, 0, $bytes.Length)
                $s.Flush()
            } catch { } finally { $c.Close() }
        }
    }).AddArgument($listener).AddArgument($shared)
$job = $ps.BeginInvoke()

function Add-Answer {
    # Queue one canned answer: -Status, its words, and -RetryAfter as given (none when empty).
    param([int]$Status, [string]$Words, [string]$RetryAfter = "")
    $body = '{"error":"refused (a stand-in)","code":"rate-limited"}'
    $head = "HTTP/1.1 " + $Status + " " + $Words + "`r`nContent-Type: application/json`r`nContent-Length: " + $body.Length + "`r`nConnection: close`r`n"
    if ($RetryAfter -ne "") { $head += "Retry-After: " + $RetryAfter + "`r`n" }
    $shared.queue.Enqueue($head + "`r`n" + $body)
}
function Get-Carried { param($Answer, [string]$Name) $p = $Answer.PSObject.Properties[$Name]; if ($null -eq $p) { return "-" }; return ("" + $p.Value) }

try {
    $c = Connect-HordeRelay -Name "cloudflare" -Options @{ origin = ("http://127.0.0.1:" + $port); authorization = "Bearer a-stand-in" }
    Check ($c.state -ceq "known") ("CONTROL: the adapter connects to the stub relay (" + $c.reason + ")")
    $mb = "work/pair-" + ("c" * 32)

    Write-Host ""
    Write-Host "--- 1. a watch the relay refuses ---" -ForegroundColor Cyan
    Add-Answer -Status 429 -Words "Too Many Requests" -RetryAfter "7"
    $w = Wait-HordeRelayItems -Connection $c.value -Mailbox $mb -Since 0 -TimeoutMs 1000
    Check ($w.state -ceq "unknown" -and (Get-Carried $w "status") -ceq "429" -and (Get-Carried $w "retryAfterMs") -ceq "7000") ("a watch refused 429 with Retry-After 7 carries status 429 and 7000 ms (" + (Get-Carried $w "status") + ", " + (Get-Carried $w "retryAfterMs") + "; " + $w.reason + ")")
    Check ($shared.seen.Count -ge 1 -and ("" + $shared.seen[$shared.seen.Count - 1]).StartsWith("GET /v1/mailboxes/work/pair-")) ("CONTROL: it was the watch's upgrade the stub refused (" + $(if ($shared.seen.Count) { $shared.seen[$shared.seen.Count - 1] } else { "nothing seen" }) + ")")
    Add-Answer -Status 401 -Words "Unauthorized"
    $w = Wait-HordeRelayItems -Connection $c.value -Mailbox $mb -Since 0 -TimeoutMs 1000
    Check ($w.state -ceq "unknown" -and (Get-Carried $w "status") -ceq "401" -and (Get-Carried $w "retryAfterMs") -ceq "-") ("a watch refused 401 with no Retry-After carries status 401 and no wait (" + (Get-Carried $w "status") + ", " + (Get-Carried $w "retryAfterMs") + ")")

    Write-Host ""
    Write-Host "--- 2. a request the relay refuses ---" -ForegroundColor Cyan
    Add-Answer -Status 429 -Words "Too Many Requests" -RetryAfter "3"
    $g = Receive-HordeRelayItems -Connection $c.value -Mailbox $mb -Since 0
    Check ($g.state -ceq "unknown" -and (Get-Carried $g "status") -ceq "429" -and (Get-Carried $g "retryAfterMs") -ceq "3000") ("a read refused 429 with Retry-After 3 carries status 429 and 3000 ms (" + (Get-Carried $g "status") + ", " + (Get-Carried $g "retryAfterMs") + ")")
    Add-Answer -Status 401 -Words "Unauthorized"
    $p = Send-HordeRelayItem -Connection $c.value -Mailbox $mb -Text "a text"
    Check ($p.state -ceq "unknown" -and (Get-Carried $p "status") -ceq "401" -and (Get-Carried $p "retryAfterMs") -ceq "-") ("a put refused 401 carries status 401 (" + (Get-Carried $p "status") + ", " + (Get-Carried $p "retryAfterMs") + ")")
    $when = [datetime]::UtcNow.AddSeconds(30).ToString("r", [System.Globalization.CultureInfo]::InvariantCulture)
    Add-Answer -Status 429 -Words "Too Many Requests" -RetryAfter $when
    $d = Receive-HordeRelayItems -Connection $c.value -Mailbox $mb -Since 0
    $dm = Get-Carried $d "retryAfterMs"
    Check ($dm -cne "-" -and [long]$dm -ge 20000 -and [long]$dm -le 31000) ("a Retry-After that is a date 30 s on is about 30000 ms (" + $dm + ")")
    Add-Answer -Status 429 -Words "Too Many Requests" -RetryAfter "soon"
    $x = Receive-HordeRelayItems -Connection $c.value -Mailbox $mb -Since 0
    Check ((Get-Carried $x "status") -ceq "429" -and (Get-Carried $x "retryAfterMs") -ceq "-") ("a Retry-After that is neither seconds nor a date is left out, the status kept (" + (Get-Carried $x "retryAfterMs") + ")")

    Write-Host ""
    Write-Host "--- 3. what is not a refusal carries nothing ---" -ForegroundColor Cyan
    $gone = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $gone.Start()
    $deadPort = ([System.Net.IPEndPoint]$gone.LocalEndpoint).Port
    $gone.Stop()
    $dc = Connect-HordeRelay -Name "cloudflare" -Options @{ origin = ("http://127.0.0.1:" + $deadPort); authorization = "Bearer a-stand-in" }
    $dw = Wait-HordeRelayItems -Connection $dc.value -Mailbox $mb -Since 0 -TimeoutMs 1000
    $dr = Receive-HordeRelayItems -Connection $dc.value -Mailbox $mb -Since 0
    Check ($dw.state -ceq "unknown" -and $dr.state -ceq "unknown" -and (Get-Carried $dw "status") -ceq "-" -and (Get-Carried $dr "status") -ceq "-") ("a relay that is not there is unknown with no status, on a watch and a read (" + $dw.reason + ")")
} finally {
    $listener.Stop()
    try { [void]$job.AsyncWaitHandle.WaitOne(5000) } catch { }
    $ps.Dispose()
    $rs.Dispose()
}

Complete-HordeSuite -Success "the hosted relay's adapter carries a refusal's status and Retry-After, on a watch and a request, and nothing for what is not a refusal"
