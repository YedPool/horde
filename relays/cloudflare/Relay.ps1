# relays/cloudflare - the hosted relay: a Worker with one Durable Object per mailbox (worker/), reached
# from this machine over HTTPS and a WebSocket. This file is the machine's side, the relay port's
# adapter (relays/Port.ps1, ADAPTER CONTRACT); Wrangler.ps1 runs the Worker locally and Deploy.ps1
# puts it on Cloudflare.
#
# WHY IT EXISTS (relay design 2026-10-09, PR plan item 8; the founder's plan for PR 8a, 2026-10-11). The
# local relay reaches no other machine; this one is where a phone and the machines of a horde meet. It
# declares reach.remote yes, so a channel between machines can pick it.
#
# CONNECT takes Options, plain data so a fresh runspace can be handed the same (the conformance suite
# does):
#   origin         https://<host>[:port], or http://127.0.0.1|localhost[:port] for a local dev only;
#                  when not given, the production origin wrangler.json names (Wrangler.ps1,
#                  Get-HordeCloudflareRelayDeployment), so `horde relay run -Relay cloudflare` needs no flag
#   authorization  optional: the whole Authorization header value every request carries. The Worker
#                  refuses every request no authenticator vouches for (worker/auth.js); in 8a only the
#                  test authenticator of a local dev exists, so only a suite has a value to put here.
#                  Sign-in (8b) replaces it with a signature per request from this machine's key.
#
# THE WIRE (worker/api.js has the whole list): put is POST .../items, read is GET .../items, ack is POST
# .../ack, and a watch is a WebSocket on .../watch that the relay answers with one message of items the
# moment there are any, or that this side closes when its timeout ends. A watch of 0 ms is a read: a
# socket closed before its first message would lose items that were already there.
#
# EVERY ANSWER IS THE FAR END'S, AND UNTRUSTED. A status other than 200, a body that is not the JSON
# expected, a socket that fails: unknown, with the relay's own words cut to 200 printable characters,
# and never thrown. The port then checks every item as it checks any relay's.
#
# THIS ADAPTER DOES NOT CHECK A TEXT'S LENGTH ITSELF. The port has, for its callers; the relay's own cap
# is the Worker's, and the conformance suite's "the relay refuses it when the port is bypassed" must
# reach the Worker to mean anything. A check here would answer for it, and hide a Worker that let an
# oversize text through.
#
# Runs on Windows PowerShell 5.1 and PowerShell 7 alike: System.Net.Http and System.Net.WebSockets.

$script:HordeCloudflareRelayAdapterFolder = $PSScriptRoot
. (Join-Path $PSScriptRoot "Wrangler.ps1")
Add-Type -AssemblyName System.Net.Http

# https with a host name, or plain http to this machine only. No path, no user, no wildcard.
$script:HordeCloudflareRelayOriginPattern = '\A(https://[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?|http://(localhost|127\.0\.0\.1))(:[0-9]{1,5})?\z'
# An Authorization value: printable ASCII on one line, as a header must be.
$script:HordeCloudflareRelayAuthorizationPattern = '\A[\x20-\x7E]{1,4096}\z'
$script:HordeCloudflareRelayRequestSeconds = 30
$script:HordeCloudflareRelayConnectMs = 15000
# The most one answer may be: the Worker's batch budget (worker/rules.js, BATCH_CHARS) and the JSON
# around it, with room. A longer answer is not this Worker's.
$script:HordeCloudflareRelayAnswerBytes = 2097152

function Get-HordeCloudflareRelayWords {
    # The far end's words, made safe to show: printable ASCII only, at most 200 characters.
    param($Text)
    $t = ("" + $Text) -replace '[^\x20-\x7E]', '?'
    if ($t.Length -gt 200) { $t = $t.Substring(0, 200) + "..." }
    return $t
}

function ConvertTo-HordeCloudflareRelayJsonString {
    # A JSON string of printable ASCII (a key or a text, already checked by the port): only the quote and
    # the backslash need escaping.
    param([string]$Text)
    return ('"' + $Text.Replace('\', '\\').Replace('"', '\"') + '"')
}

function Get-HordeCloudflareRelayMailboxPath {
    param([string]$Mailbox, [string]$Op)
    return ("/v1/mailboxes/" + $Mailbox + "/" + $Op)
}

function Invoke-HordeCloudflareRelayHttp {
    # One request to the relay: known, the parsed JSON body of a 200; unknown with the status and the
    # relay's words otherwise.
    param($State, [string]$Method, [string]$Path, [string]$Body = $null, [string]$What)
    $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method)), ($State.origin + $Path))
    if ($State.authorization -ne "") { [void]$req.Headers.TryAddWithoutValidation("Authorization", $State.authorization) }
    if ($null -ne $Body -and $Body -ne "") { $req.Content = New-Object System.Net.Http.StringContent($Body, [System.Text.Encoding]::ASCII, "application/json") }
    try {
        $res = $State.http.SendAsync($req).GetAwaiter().GetResult()
        try {
            $text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $code = [int]$res.StatusCode
        } finally { $res.Dispose() }
    } catch { return (New-HordeUnknown -Reason ("the relay at " + $State.origin + " could not be reached for the " + $What) -ErrorRecord $_) }
    finally { $req.Dispose() }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $null }
    if ($code -ne 200) {
        $words = $(if ($null -ne $parsed -and $parsed -is [System.Management.Automation.PSCustomObject] -and $null -ne $parsed.PSObject.Properties["error"]) { $parsed.error } else { $text })
        return (New-HordeUnknown -Reason ("the relay answered the " + $What + " with " + $code + ": " + (Get-HordeCloudflareRelayWords $words)))
    }
    if ($null -eq $parsed -or $parsed -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason ("the relay answered the " + $What + " with something that is not a JSON object")) }
    return (New-HordeKnown -Value $parsed -ObservedAt ([datetime]::UtcNow))
}

function ConvertTo-HordeCloudflareRelayItems {
    # An answer holding items, as the port takes it: known { items }. Whether each item holds together is
    # the port's to judge; here only that there is a list.
    param($Answer, [string]$What)
    if ($Answer.state -cne "known") { return $Answer }
    $p = $Answer.value.PSObject.Properties["items"]
    if ($null -eq $p) { return (New-HordeUnknown -Reason ("the relay answered the " + $What + " without items")) }
    $items = @()
    if ($null -ne $p.Value) { $items = @($p.Value) }
    return (New-HordeKnown -Value ([pscustomobject]@{ items = $items }) -ObservedAt $Answer.observedAt)
}

function Receive-HordeCloudflareRelaySocketText {
    # The first whole text message on -Socket within -TimeoutMs: the text, or $null when the time ran out
    # or the relay closed with nothing to say. Throws when the socket fails.
    param([System.Net.WebSockets.ClientWebSocket]$Socket, [int]$TimeoutMs)
    $cts = New-Object System.Threading.CancellationTokenSource($TimeoutMs)
    $buf = New-Object byte[] 65536
    $all = New-Object System.IO.MemoryStream
    try {
        while ($true) {
            $seg = New-Object System.ArraySegment[byte] -ArgumentList @(, $buf)
            try { $r = $Socket.ReceiveAsync($seg, $cts.Token).GetAwaiter().GetResult() }
            catch [System.OperationCanceledException] { return $null }
            if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }
            $all.Write($buf, 0, $r.Count)
            if ($all.Length -gt $script:HordeCloudflareRelayAnswerBytes) { throw ("the relay's watch message is over " + $script:HordeCloudflareRelayAnswerBytes + " bytes") }
            if ($r.EndOfMessage) { return [System.Text.Encoding]::ASCII.GetString($all.ToArray()) }
        }
    } finally { $cts.Dispose(); $all.Dispose() }
}

function Invoke-HordeCloudflareRelayWatch {
    # The watch over a WebSocket: known { items } - empty when the time ran out - or unknown.
    param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
    $ws = $State.origin -replace '\Ahttp', 'ws'
    $uri = New-Object System.Uri($ws + (Get-HordeCloudflareRelayMailboxPath -Mailbox $Mailbox -Op "watch") + "?since=" + $Since + "&max=" + $Max + "&timeoutMs=" + $TimeoutMs)
    $socket = New-Object System.Net.WebSockets.ClientWebSocket
    try {
        if ($State.authorization -ne "") { $socket.Options.SetRequestHeader("Authorization", $State.authorization) }
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $cts = New-Object System.Threading.CancellationTokenSource($script:HordeCloudflareRelayConnectMs)
        try { $null = $socket.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult() }
        catch { return (New-HordeUnknown -Reason ("the relay at " + $State.origin + " did not open the watch: " + (Get-HordeCloudflareRelayWords $_.Exception.Message))) }
        finally { $cts.Dispose() }
        # What is left of the timeout once the socket is open, and never less than a moment, so items
        # the relay sends at once on opening are still read.
        $left = [int][Math]::Max(250, $TimeoutMs - $clock.ElapsedMilliseconds)
        try { $text = Receive-HordeCloudflareRelaySocketText -Socket $socket -TimeoutMs $left }
        catch { return (New-HordeUnknown -Reason ("the relay's watch failed: " + (Get-HordeCloudflareRelayWords $_.Exception.Message))) }
        if ($null -eq $text) { return (New-HordeKnown -Value ([pscustomobject]@{ items = @() }) -ObservedAt ([datetime]::UtcNow)) }
        $parsed = $null
        try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $null }
        if ($null -eq $parsed -or $parsed -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason "the relay's watch message is not a JSON object") }
        return (ConvertTo-HordeCloudflareRelayItems -Answer (New-HordeKnown -Value $parsed -ObservedAt ([datetime]::UtcNow)) -What "watch")
    } finally { $socket.Dispose() }
}

$null = Register-HordeRelay -Folder $script:HordeCloudflareRelayAdapterFolder `
    -Connect {
        param($Options)
        $get = {
            param([string]$Name)
            if ($Options -is [System.Collections.IDictionary]) { if ($Options.Contains($Name)) { return $Options[$Name] }; return $null }
            if ($null -ne $Options -and $null -ne $Options.PSObject.Properties[$Name]) { return $Options.$Name }
            return $null
        }
        $origin = & $get "origin"
        if ($null -eq $origin -or "$origin" -eq "") { $origin = (Get-HordeCloudflareRelayDeployment).origin }
        if ($origin -isnot [string] -or $origin -cnotmatch $script:HordeCloudflareRelayOriginPattern) { return (New-HordeUnknown -Reason "the cloudflare relay needs Options.origin: https://<host>[:port], or http://127.0.0.1[:port] for a local dev") }
        $auth = & $get "authorization"
        if ($null -eq $auth) { $auth = "" }
        if ($auth -isnot [string] -or ($auth -ne "" -and $auth -cnotmatch $script:HordeCloudflareRelayAuthorizationPattern)) { return (New-HordeUnknown -Reason "Options.authorization is one line of printable ASCII") }
        # TLS 1.2 at least, for Windows PowerShell on a .NET that would otherwise offer older ones.
        if ($origin.StartsWith("https:")) { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 }
        $http = New-Object System.Net.Http.HttpClient
        $http.Timeout = [TimeSpan]::FromSeconds($script:HordeCloudflareRelayRequestSeconds)
        $http.MaxResponseContentBufferSize = $script:HordeCloudflareRelayAnswerBytes
        return (New-HordeKnown -Value ([pscustomobject]@{ origin = $origin; authorization = $auth; http = $http }))
    } `
    -Put {
        param($State, [string]$Mailbox, [string]$Key, [string]$Text)
        $body = '{"key":' + (ConvertTo-HordeCloudflareRelayJsonString $Key) + ',"text":' + (ConvertTo-HordeCloudflareRelayJsonString $Text) + '}'
        $a = Invoke-HordeCloudflareRelayHttp -State $State -Method "POST" -Path (Get-HordeCloudflareRelayMailboxPath -Mailbox $Mailbox -Op "items") -Body $body -What "put"
        if ($a.state -cne "known") { return $a }
        $seq = $a.value.PSObject.Properties["seq"]
        $dup = $a.value.PSObject.Properties["duplicate"]
        return (New-HordeKnown -Value ([pscustomobject]@{ seq = $(if ($seq) { $seq.Value } else { $null }); duplicate = $(if ($dup) { $dup.Value } else { $null }) }) -ObservedAt $a.observedAt)
    } `
    -Get {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max)
        $a = Invoke-HordeCloudflareRelayHttp -State $State -Method "GET" -Path ((Get-HordeCloudflareRelayMailboxPath -Mailbox $Mailbox -Op "items") + "?since=" + $Since + "&max=" + $Max) -What "read"
        return (ConvertTo-HordeCloudflareRelayItems -Answer $a -What "read")
    } `
    -Watch {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
        if ($TimeoutMs -le 0) {
            $a = Invoke-HordeCloudflareRelayHttp -State $State -Method "GET" -Path ((Get-HordeCloudflareRelayMailboxPath -Mailbox $Mailbox -Op "items") + "?since=" + $Since + "&max=" + $Max) -What "watch"
            return (ConvertTo-HordeCloudflareRelayItems -Answer $a -What "watch")
        }
        return (Invoke-HordeCloudflareRelayWatch -State $State -Mailbox $Mailbox -Since $Since -Max $Max -TimeoutMs $TimeoutMs)
    } `
    -Ack {
        param($State, [string]$Mailbox, [long]$Through)
        $a = Invoke-HordeCloudflareRelayHttp -State $State -Method "POST" -Path (Get-HordeCloudflareRelayMailboxPath -Mailbox $Mailbox -Op "ack") -Body ('{"through":' + $Through + '}') -What "ack"
        if ($a.state -cne "known") { return $a }
        $t = $a.value.PSObject.Properties["through"]
        return (New-HordeKnown -Value ([pscustomobject]@{ through = $(if ($t) { $t.Value } else { $null }) }) -ObservedAt $a.observedAt)
    }
