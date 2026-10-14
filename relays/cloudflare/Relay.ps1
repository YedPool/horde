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
#   authorization  optional, for a suite only: the whole Authorization header value every request
#                  carries - the test authenticator's bearer token of a local dev (worker/auth.js).
#   hordeHome      optional: the Horde home whose relay identity signs (empty: this user's own).
# WITHOUT authorization, EVERY REQUEST IS SIGNED by this machine's relay signing key
# (RequestSigner.ps1): the Worker answers a machine only by the key a signed-in phone registered to its
# account while it paired (relay/Pairing.ps1, THE ACCOUNT GRANT), and only for that key's horde. The key
# is opened at the first request, not at connect, and kept open for the connection's life; a machine
# with no identity yet is told so by every operation, as unknown - never a request sent unsigned.
#
# THE WIRE (worker/api.js has the whole list): put is POST .../items, read is GET .../items, ack is POST
# .../ack, and a watch is a WebSocket on .../watch that the relay answers with one message of items the
# moment there are any, or that this side closes when its timeout ends. Once the socket is open it is
# read for what is left of the timeout and never less than 250 ms, so a watch of 0 ms still gets the
# items that were already there: the relay sends those the moment the socket opens.
#
# THE WATCH IN SLICES (relays/Port.ps1, A WATCH IN SLICES). The socket is the watch: opening it is the
# one request the watch costs the relay (worker/limits.js counts the upgrade and nothing after it), and
# while it is open the mailbox's Durable Object is hibernating, woken only by a put into THAT mailbox
# (worker/mailbox.js, wake). So this side can keep the socket open and do other things between looks at
# it: a put into the phone's mailbox is an ordinary POST to another object, and one into the watched
# mailbox is answered on the socket as it always was. A slice is therefore a wait of some milliseconds
# on a receive that stays pending across slices - nothing is sent, nothing is cancelled, no request is
# made - and the blocking watch is one slice as long as the watch. NOT RUN AGAINST THE DEPLOYED RELAY
# from here: the conformance suite runs it against a local dev of the same Worker, which shares the
# Worker's code and not the network or the platform's own WebSocket front end.
#
# A SENDER TRIMS ITS OWN STREAM (relays/Port.ps1, the section of that name; worker/api.js, worker/mailbox.js).
# The put that trims is the same POST with ?keepFrom=<seq> on its path - in the query because this
# machine's signature covers the path and the query, so the instruction is signed with the put it rides
# on, and because the Worker holds a put's body to exactly its two members. A WORKER DEPLOYED BEFORE
# THIS takes the put and ignores the query: its answer has no "trimmed", this adapter then leaves it
# out, and the port reports "not said" - which is how a machine running this code against an older
# relay finds out, at no cost, that its mailbox is not being trimmed yet. NOT RUN AGAINST THE DEPLOYED
# RELAY from here: the suites run it against a local dev of the same Worker.
#
# A ROTATED IDENTITY IS CARRIED TO THE RELAY (relay PR 8c; worker/rotation.js). After
# relay/Identity.ps1 rotates this machine's keys, the relay still knows only the old signing key, so it
# answers the new one 401. The first 401 of a connection (a request, or a watch the relay would not
# open) is then answered once: when the identity's previous generation was retired with a vouch naming
# this very key as its successor, that record is posted, signed by the new key, and the relay moves the
# registration; the request is then made once more. Nothing is kept on disk for it: a relay that
# already moved it refuses the record again, which costs one request per connection and no more.
#
# A WATCH THE RELAY ENDED (worker/mailbox.js: replaced by a newer watch of this machine in the mailbox -
# one live watch per device there - or the account deleted) is a failed watch here, unknown - never
# "nothing came" - so a caller that watches again backs off first instead of evicting the newer watch
# in its turn. The relay says so in the watch's one message, { error, code }, and again in its close
# code (4000 and up); either is read as the end.
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
# WHICH FILES HERE HOLD THIS RELAY'S SECRETS (relays/Port.ps1, the section of that name) is
# SecretFiles.ps1's to say: the Google client file the settings name, and the deploy tool's login.
#
# WHICH ATTEMPT EACH REQUEST IS (the relay's request metrics: worker/metrics.js, THE RETRY HEADER). Every
# request and every watch carries x-horde-attempt: 1, plus the requests of this connection in a row before
# it that came back unknown - so the one after a failure (the runner's next turn after its backoff, or a
# request made again after a rotation) says it is a retry, and the first after an answer says 1 again.
# The relay only counts it. It is a header, not part of what is signed, so it changes no signature.
#
# THE DAY'S SUMMARY (relays/Port.ps1, A RELAY THAT COUNTS ITS OWN REQUESTS; worker/metrics-api.js): one
# signed GET of /v1/metrics/summary?day=<day>. The relay answers an owner account's machine with the
# relay-wide view, and any other machine with its own account's hours; this side asks once and takes
# whichever it is given.
#
# Runs on Windows PowerShell 5.1 and PowerShell 7 alike: System.Net.Http and System.Net.WebSockets.

$script:HordeCloudflareRelayAdapterFolder = $PSScriptRoot
. (Join-Path $PSScriptRoot "Deploy.ps1")
. (Join-Path $PSScriptRoot "Bundle.ps1")
. (Join-Path $PSScriptRoot "RequestSigner.ps1")
. (Join-Path $PSScriptRoot "SecretFiles.ps1")
Add-Type -AssemblyName System.Net.Http

# https with a host name, or plain http to this machine only. No path, no user, no wildcard.
$script:HordeCloudflareRelayOriginPattern = '\A(https://[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?|http://(localhost|127\.0\.0\.1))(:[0-9]{1,5})?\z'
# An Authorization value: printable ASCII on one line, as a header must be.
$script:HordeCloudflareRelayAuthorizationPattern = '\A[\x20-\x7E]{1,4096}\z'
$script:HordeCloudflareRelayRequestSeconds = 30
$script:HordeCloudflareRelayConnectMs = 15000
# The relay's own close codes (worker/mailbox.js), and what each means.
$script:HordeCloudflareRelayCloseWords = @{ 4001 = "the relay replaced this watch with a newer one of this machine"; 4002 = "the relay closed the watch: the account was deleted" }
$script:HordeCloudflareRelayRotationPath = "/v1/machines/rotation"
# HOW LONG A RUNNER'S WATCH WAITS HERE (relays/Port.ps1, -RunWatchMs): the longest a watch may, 60 s, so
# an always-on machine is 1,440 requests a day against its account's day (worker/limits.js), and a
# fleet of three is under a quarter of it. The one place this interval is written.
$script:HordeCloudflareRelayRunWatchMs = 60000
# The most one answer may be: the Worker's batch budget (worker/rules.js, BATCH_CHARS) and the JSON
# around it, with room. A longer answer is not this Worker's.
$script:HordeCloudflareRelayAnswerBytes = 2097152
# The attempt header (the header, WHICH ATTEMPT), and the most it says: the most the Worker reads.
$script:HordeCloudflareRelayAttemptHeader = "x-horde-attempt"
$script:HordeCloudflareRelayAttemptMax = 999
$script:HordeCloudflareRelaySummaryPath = "/v1/metrics/summary"

function Get-HordeCloudflareRelayWords {
    # The far end's words, made safe to show: printable ASCII only, at most 200 characters.
    param($Text)
    $t = ("" + $Text) -replace '[^\x20-\x7E]', '?'
    if ($t.Length -gt 200) { $t = $t.Substring(0, 200) + "..." }
    return $t
}

function ConvertFrom-HordeCloudflareRelayRetryAfter {
    # A Retry-After header's value in ms: whole seconds (what the Worker sends, worker/answers.js) or an
    # HTTP date; -1 when it is neither.
    param([string]$Text)
    $t = $Text.Trim()
    if ($t -cmatch '\A[0-9]{1,9}\z') { return ([long]$t * 1000) }
    $when = [datetime]::MinValue
    if ([datetime]::TryParseExact($t, "r", [System.Globalization.CultureInfo]::InvariantCulture, ([System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal), [ref]$when)) {
        return ([long][System.Math]::Max(0, ($when - [datetime]::UtcNow).TotalMilliseconds))
    }
    return [long]-1
}

function Add-HordeCloudflareRelayRefusal {
    # A REFUSAL MAY SAY MORE THAN ITS REASON (relays/Port.ps1): the relay's status, and its Retry-After
    # in ms when it gave one that reads, as members of -Answer, an unknown. -Answer, for the return.
    param($Answer, [int]$Status, [string]$RetryAfter = "")
    if ($Status -gt 0) { $Answer | Add-Member -NotePropertyName status -NotePropertyValue $Status }
    $ms = ConvertFrom-HordeCloudflareRelayRetryAfter -Text $RetryAfter
    if ($ms -ge 0) { $Answer | Add-Member -NotePropertyName retryAfterMs -NotePropertyValue $ms }
    return $Answer
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

function Get-HordeCloudflareRelayAttempt {
    # The attempt this connection's next request is (the header, WHICH ATTEMPT), as the header's text.
    param($State)
    return ([string][Math]::Min($script:HordeCloudflareRelayAttemptMax, [int]$State.failedInARow + 1))
}

function Set-HordeCloudflareRelayAttemptOutcome {
    # A request of -State's came back -Answer: known puts the count of failures in a row back to 0, and
    # anything else adds one. -Answer, for the return.
    param($State, $Answer)
    if ($null -ne $Answer -and $Answer.state -ceq "known") { $State.failedInARow = 0 } else { $State.failedInARow = [int]$State.failedInARow + 1 }
    return $Answer
}

function Get-HordeCloudflareRelayAuthorization {
    # The Authorization value for one request: the suite's given one, or this machine's signature over
    # it (the header). Known text, or unknown when there is no key to sign with.
    param($State, [string]$Method, [string]$Target, [AllowEmptyCollection()][byte[]]$Body = @())
    if ($State.authorization -ne "") { return (New-HordeKnown -Value $State.authorization) }
    if ($null -eq $State.signer) {
        $s = Open-HordeCloudflareRelaySigner -HordeHome $State.hordeHome
        if ($s.state -cne "known") { return (New-HordeUnknown -Reason ("this machine cannot sign its requests to the relay: " + $s.reason)) }
        $State.signer = $s.value
    }
    try { return (New-HordeKnown -Value (New-HordeCloudflareRelayMachineAuthorization -Key $State.signer.key -KeyId $State.signer.keyId -Origin $State.origin -Method $Method -Target $Target -Body $Body)) }
    catch { return (New-HordeUnknown -Reason "this machine's signing key did not sign the request" -ErrorRecord $_) }
}

function Send-HordeCloudflareRelayRotation {
    # A ROTATED IDENTITY (the header), presented at most once a connection: $true when the relay moved
    # this machine's registration to its current key, so the refused request is worth making again.
    param($State)
    if ($State.authorization -ne "" -or $State.rotationTried -or $null -eq $State.signer) { return $false }
    $State.rotationTried = $true
    if ($State.signer.generation -lt 2) { return $false }
    $t = Get-HordeRelayRetirementText -HordeHome $State.hordeHome -Generation ($State.signer.generation - 1)
    if ($t.state -cne "known") { return $false }
    if ($t.value -cnotmatch ('"successorSignKeyId":"' + $State.signer.keyId + '"') -or $t.value -cmatch '"vouch":""}\z') { return $false }
    $a = Invoke-HordeCloudflareRelayHttp -State $State -Method "POST" -Path $script:HordeCloudflareRelayRotationPath -Body ('{"record":' + (ConvertTo-HordeCloudflareRelayJsonString $t.value) + '}') -What "rotation" -Once
    return ($a.state -ceq "known")
}

function Invoke-HordeCloudflareRelayHttp {
    # One request to the relay: known, the parsed JSON body of a 200; unknown with the status and the
    # relay's words otherwise. The body is sent as the very bytes the signature hashed. A 401 may carry
    # a rotation to the relay and be made again, once (the header); -Once is that second try.
    param($State, [string]$Method, [string]$Path, [string]$Body = $null, [string]$What, [switch]$Once)
    # Assigned, not piped through $(...): an empty array through a subexpression comes out $null.
    $bytes = New-Object byte[] 0
    if ($null -ne $Body -and $Body -ne "") { $bytes = [System.Text.Encoding]::ASCII.GetBytes($Body) }
    $auth = Get-HordeCloudflareRelayAuthorization -State $State -Method $Method -Target $Path -Body $bytes
    if ($auth.state -cne "known") { return $auth }
    $req = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($Method)), ($State.origin + $Path))
    [void]$req.Headers.TryAddWithoutValidation("Authorization", $auth.value)
    [void]$req.Headers.TryAddWithoutValidation($script:HordeCloudflareRelayAttemptHeader, (Get-HordeCloudflareRelayAttempt -State $State))
    if ($bytes.Length -gt 0) {
        $req.Content = New-Object System.Net.Http.ByteArrayContent(, $bytes)
        $req.Content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue("application/json")
    }
    try {
        $res = $State.http.SendAsync($req).GetAwaiter().GetResult()
        try {
            $text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $code = [int]$res.StatusCode
            $retryAfter = $(if ($null -ne $res.Headers.RetryAfter) { "" + $res.Headers.RetryAfter } else { "" })
        } finally { $res.Dispose() }
    } catch { return (Set-HordeCloudflareRelayAttemptOutcome -State $State -Answer (New-HordeUnknown -Reason ("the relay at " + $State.origin + " could not be reached for the " + $What) -ErrorRecord $_)) }
    finally { $req.Dispose() }
    $parsed = $null
    try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $null }
    # The refused request is one failure, so the request made again after a rotation says it is a retry.
    if ($code -eq 401 -and -not $Once -and (Send-HordeCloudflareRelayRotation -State $State)) { $State.failedInARow = [int]$State.failedInARow + 1; return (Invoke-HordeCloudflareRelayHttp -State $State -Method $Method -Path $Path -Body $Body -What $What -Once) }
    if ($code -ne 200) {
        $words = $(if ($null -ne $parsed -and $parsed -is [System.Management.Automation.PSCustomObject] -and $null -ne $parsed.PSObject.Properties["error"]) { $parsed.error } else { $text })
        return (Set-HordeCloudflareRelayAttemptOutcome -State $State -Answer (Add-HordeCloudflareRelayRefusal -Answer (New-HordeUnknown -Reason ("the relay answered the " + $What + " with " + $code + ": " + (Get-HordeCloudflareRelayWords $words))) -Status $code -RetryAfter $retryAfter))
    }
    if ($null -eq $parsed -or $parsed -isnot [System.Management.Automation.PSCustomObject]) { return (Set-HordeCloudflareRelayAttemptOutcome -State $State -Answer (New-HordeUnknown -Reason ("the relay answered the " + $What + " with something that is not a JSON object"))) }
    return (Set-HordeCloudflareRelayAttemptOutcome -State $State -Answer (New-HordeKnown -Value $parsed -ObservedAt ([datetime]::UtcNow)))
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

function Wait-HordeCloudflareRelayWatch {
    # Wait-HordeCloudflareRelayWatchSlice, and the watch's end counted for the next request's attempt (the
    # header, WHICH ATTEMPT): a failed watch is a failure, a watch that ended is not; a slice that only
    # ran out says nothing yet.
    param($Handle, [int]$WaitMs)
    $w = Wait-HordeCloudflareRelayWatchSlice -Handle $Handle -WaitMs $WaitMs
    if ($null -ne $Handle.conn -and ($w.state -cne "known" -or $w.value.ended)) { $null = Set-HordeCloudflareRelayAttemptOutcome -State $Handle.conn -Answer $w }
    return $w
}

function Wait-HordeCloudflareRelayWatchSlice {
    # Wait up to -WaitMs more on a watch Open-HordeCloudflareRelayWatch opened (the header, THE WATCH IN
    # SLICES): known { ended; items } - ended with the items once the relay's one message came, ended
    # with none when the watch's time ran out or the relay closed with nothing to say, not ended when
    # only this slice is over - or unknown when the socket failed or the relay ended the watch itself.
    param($Handle, [int]$WaitMs)
    $slice = [System.Diagnostics.Stopwatch]::StartNew()
    # THE FIRST SLICE IS NEVER LESS THAN A MOMENT, so items the relay sends at once on opening are read
    # even by a slice that does not wait: a watch of 0 ms is still a read (the header, THE WIRE).
    if (-not $Handle.waited) { $Handle.waited = $true; $WaitMs = [int][Math]::Max($WaitMs, [Math]::Min(250, $Handle.leftMs)) }
    while ($true) {
        # ONE RECEIVE IS LEFT PENDING ACROSS SLICES, and each slice only waits on it. Cancelling a receive
        # to end a slice would abort the socket (the platform's rule for a cancelled receive), which
        # would end the watch and cost a new request to open the next one.
        if ($null -eq $Handle.pending) {
            $seg = New-Object System.ArraySegment[byte] -ArgumentList @(, $Handle.buffer)
            $Handle.pending = $Handle.socket.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
        }
        $leftOfWatch = $Handle.leftMs - $Handle.sinceOpen.ElapsedMilliseconds
        $leftOfSlice = $WaitMs - $slice.ElapsedMilliseconds
        $came = $false
        try { $came = $Handle.pending.Wait([int][Math]::Max(0, [Math]::Min($leftOfWatch, $leftOfSlice))) }
        catch {
            $inner = $_.Exception
            while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
            return (New-HordeUnknown -Reason ("the relay's watch failed: " + (Get-HordeCloudflareRelayWords $inner.Message)))
        }
        if (-not $came) {
            if ($Handle.leftMs - $Handle.sinceOpen.ElapsedMilliseconds -le 0) { return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = @() }) -ObservedAt ([datetime]::UtcNow)) }
            if ($WaitMs - $slice.ElapsedMilliseconds -le 0) { return (New-HordeKnown -Value ([pscustomobject]@{ ended = $false; items = @() }) -ObservedAt ([datetime]::UtcNow)) }
            continue
        }
        $r = $Handle.pending.Result
        $Handle.pending = $null
        if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            $code = [int]$r.CloseStatus
            if ($code -ge 4000 -and $code -le 4999) { return (New-HordeUnknown -Reason ("the relay's watch failed: " + $(if ($script:HordeCloudflareRelayCloseWords.ContainsKey($code)) { $script:HordeCloudflareRelayCloseWords[$code] } else { "the relay closed the watch (" + $code + ")" }))) }
            return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = @() }) -ObservedAt ([datetime]::UtcNow))
        }
        $Handle.message.Write($Handle.buffer, 0, $r.Count)
        if ($Handle.message.Length -gt $script:HordeCloudflareRelayAnswerBytes) { return (New-HordeUnknown -Reason ("the relay's watch failed: the relay's watch message is over " + $script:HordeCloudflareRelayAnswerBytes + " bytes")) }
        if (-not $r.EndOfMessage) { continue }
        $text = [System.Text.Encoding]::ASCII.GetString($Handle.message.ToArray())
        $parsed = $null
        try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $null }
        if ($null -eq $parsed -or $parsed -isnot [System.Management.Automation.PSCustomObject]) { return (New-HordeUnknown -Reason "the relay's watch message is not a JSON object") }
        if ($null -ne $parsed.PSObject.Properties["error"]) { return (New-HordeUnknown -Reason ("the relay ended the watch: " + (Get-HordeCloudflareRelayWords $parsed.error))) }
        $got = ConvertTo-HordeCloudflareRelayItems -Answer (New-HordeKnown -Value $parsed -ObservedAt ([datetime]::UtcNow)) -What "watch"
        if ($got.state -cne "known") { return $got }
        return (New-HordeKnown -Value ([pscustomobject]@{ ended = $true; items = @($got.value.items) }) -ObservedAt $got.observedAt)
    }
}

function Close-HordeCloudflareRelayWatch {
    # Let go of a watch's socket: this side closing it is how a watch ends when nothing came (the
    # header, THE WIRE). The receive left pending is then looked at once, so its end is not left
    # unobserved. Never throws.
    param($Handle)
    if ($null -eq $Handle) { return }
    try { $Handle.socket.Dispose() } catch { }
    try { if ($null -ne $Handle.pending) { $null = $Handle.pending.Wait(50) } } catch { }
    try { $Handle.message.Dispose() } catch { }
}

function Open-HordeCloudflareRelayWatch {
    # Open the watch's WebSocket - the one request a watch costs the relay: known, the handle
    # Wait-HordeCloudflareRelayWatch waits on and Close-HordeCloudflareRelayWatch lets go of, or unknown.
    # A watch the relay would not open may carry a rotation to it and be opened again, once (the header).
    param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs, [switch]$Once)
    $ws = $State.origin -replace '\Ahttp', 'ws'
    $target = (Get-HordeCloudflareRelayMailboxPath -Mailbox $Mailbox -Op "watch") + "?since=" + $Since + "&max=" + $Max + "&timeoutMs=" + $TimeoutMs
    $auth = Get-HordeCloudflareRelayAuthorization -State $State -Method "GET" -Target $target
    if ($auth.state -cne "known") { return $auth }
    $uri = New-Object System.Uri($ws + $target)
    $socket = New-Object System.Net.WebSockets.ClientWebSocket
    $opened = $false
    try {
        $socket.Options.SetRequestHeader("Authorization", $auth.value)
        $socket.Options.SetRequestHeader($script:HordeCloudflareRelayAttemptHeader, (Get-HordeCloudflareRelayAttempt -State $State))
        # PowerShell 7 keeps a refused upgrade's status and headers only when asked to (.NET 7 and up);
        # Windows PowerShell 5.1 has no such option, and keeps them on the inner WebException's response.
        $collect = $socket.Options.PSObject.Properties["CollectHttpResponseDetails"]
        if ($null -ne $collect) { $socket.Options.CollectHttpResponseDetails = $true }
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $cts = New-Object System.Threading.CancellationTokenSource($script:HordeCloudflareRelayConnectMs)
        try { $null = $socket.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult() }
        catch {
            # The status is in the message under pwsh 7, and in an inner exception's under Windows
            # PowerShell 5.1 ("Unable to connect", then "(401) Unauthorized"): all of them are read.
            $why = ""
            $code = 0
            $retryAfter = ""
            for ($e = $_.Exception; $null -ne $e; $e = $e.InnerException) {
                $why += $e.Message + " "
                $resp = $e.PSObject.Properties["Response"]
                if ($e -is [System.Net.WebException] -and $null -ne $resp -and $resp.Value -is [System.Net.HttpWebResponse]) {
                    try { $code = [int]$resp.Value.StatusCode; $retryAfter = "" + $resp.Value.Headers["Retry-After"] } catch { }
                }
            }
            if ($null -ne $collect -and [int]$socket.HttpStatusCode -gt 0) {
                $code = [int]$socket.HttpStatusCode
                if ($null -ne $socket.HttpResponseHeaders) { foreach ($h in $socket.HttpResponseHeaders) { if ($h.Key -ieq "Retry-After") { $retryAfter = (@($h.Value) -join ",") } } }
            }
            if ($why.Contains("401") -and -not $Once -and (Send-HordeCloudflareRelayRotation -State $State)) { $State.failedInARow = [int]$State.failedInARow + 1; return (Open-HordeCloudflareRelayWatch -State $State -Mailbox $Mailbox -Since $Since -Max $Max -TimeoutMs $TimeoutMs -Once) }
            return (Set-HordeCloudflareRelayAttemptOutcome -State $State -Answer (Add-HordeCloudflareRelayRefusal -Answer (New-HordeUnknown -Reason ("the relay at " + $State.origin + " did not open the watch: " + (Get-HordeCloudflareRelayWords $why.Trim()))) -Status $code -RetryAfter $retryAfter))
        }
        finally { $cts.Dispose() }
        # What is left of the timeout once the socket is open, and never less than a moment, so items
        # the relay sends at once on opening are still read.
        $left = [int][Math]::Max(250, $TimeoutMs - $clock.ElapsedMilliseconds)
        $opened = $true
        return (New-HordeKnown -Value ([pscustomobject]@{ socket = $socket; leftMs = $left; sinceOpen = [System.Diagnostics.Stopwatch]::StartNew(); waited = $false
            buffer = (New-Object byte[] 65536); message = (New-Object System.IO.MemoryStream); pending = $null; conn = $State }) -ObservedAt ([datetime]::UtcNow))
    } finally { if (-not $opened) { $socket.Dispose() } }
}

function Send-HordeCloudflareRelayPut {
    # The put, and with -KeepFrom over 0 the put that also trims its key's stream (the header, A SENDER
    # TRIMS ITS OWN STREAM): known { seq; duplicate } as the relay gave them, and trimmed when - and only
    # when - the relay said it. The port judges each member; nothing here is believed.
    param($State, [string]$Mailbox, [string]$Key, [string]$Text, [long]$KeepFrom = 0)
    $body = '{"key":' + (ConvertTo-HordeCloudflareRelayJsonString $Key) + ',"text":' + (ConvertTo-HordeCloudflareRelayJsonString $Text) + '}'
    $path = Get-HordeCloudflareRelayMailboxPath -Mailbox $Mailbox -Op "items"
    if ($KeepFrom -gt 0) { $path = $path + "?keepFrom=" + $KeepFrom }
    $a = Invoke-HordeCloudflareRelayHttp -State $State -Method "POST" -Path $path -Body $body -What "put"
    if ($a.state -cne "known") { return $a }
    $seq = $a.value.PSObject.Properties["seq"]
    $dup = $a.value.PSObject.Properties["duplicate"]
    $out = [pscustomobject]@{ seq = $(if ($seq) { $seq.Value } else { $null }); duplicate = $(if ($dup) { $dup.Value } else { $null }) }
    $trimmed = $a.value.PSObject.Properties["trimmed"]
    if ($KeepFrom -gt 0 -and $null -ne $trimmed) { $out | Add-Member -NotePropertyName trimmed -NotePropertyValue $trimmed.Value }
    return (New-HordeKnown -Value $out -ObservedAt $a.observedAt)
}

function Get-HordeCloudflareRelayDaySummary {
    # The relay's summary of the UTC day -Day (the header, THE DAY'S SUMMARY): known, the summary object
    # as the relay gave it, or unknown. One request.
    param($State, [string]$Day)
    return (Invoke-HordeCloudflareRelayHttp -State $State -Method "GET" -Path ($script:HordeCloudflareRelaySummaryPath + "?day=" + $Day) -What "day's summary")
}

function Invoke-HordeCloudflareRelayWatch {
    # The blocking watch: known { items } - empty when the time ran out - or unknown. It is the watch in
    # slices, opened, waited on in one slice as long as the watch, and let go of: one code path for both.
    param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
    $o = Open-HordeCloudflareRelayWatch -State $State -Mailbox $Mailbox -Since $Since -Max $Max -TimeoutMs $TimeoutMs
    if ($o.state -cne "known") { return $o }
    try {
        while ($true) {
            $w = Wait-HordeCloudflareRelayWatch -Handle $o.value -WaitMs $o.value.leftMs
            if ($w.state -cne "known" -or $w.value.ended) { return $w }
        }
    } finally { Close-HordeCloudflareRelayWatch -Handle $o.value }
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
        $hordeHome = & $get "hordeHome"
        if ($null -eq $hordeHome) { $hordeHome = "" }
        if ($hordeHome -isnot [string] -or ($hordeHome -ne "" -and -not [System.IO.Path]::IsPathRooted($hordeHome))) { return (New-HordeUnknown -Reason "Options.hordeHome is an absolute folder") }
        # TLS 1.2 at least, for Windows PowerShell on a .NET that would otherwise offer older ones.
        if ($origin.StartsWith("https:")) { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 }
        $http = New-Object System.Net.Http.HttpClient
        $http.Timeout = [TimeSpan]::FromSeconds($script:HordeCloudflareRelayRequestSeconds)
        $http.MaxResponseContentBufferSize = $script:HordeCloudflareRelayAnswerBytes
        return (New-HordeKnown -Value ([pscustomobject]@{ origin = $origin; authorization = $auth; hordeHome = $hordeHome; signer = $null; http = $http; rotationTried = $false; failedInARow = 0 }))
    } `
    -Put {
        param($State, [string]$Mailbox, [string]$Key, [string]$Text)
        return (Send-HordeCloudflareRelayPut -State $State -Mailbox $Mailbox -Key $Key -Text $Text)
    } `
    -PutKeeping {
        param($State, [string]$Mailbox, [string]$Key, [string]$Text, [long]$KeepFrom)
        return (Send-HordeCloudflareRelayPut -State $State -Mailbox $Mailbox -Key $Key -Text $Text -KeepFrom $KeepFrom)
    } `
    -Get {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max)
        $a = Invoke-HordeCloudflareRelayHttp -State $State -Method "GET" -Path ((Get-HordeCloudflareRelayMailboxPath -Mailbox $Mailbox -Op "items") + "?since=" + $Since + "&max=" + $Max) -What "read"
        return (ConvertTo-HordeCloudflareRelayItems -Answer $a -What "read")
    } `
    -Watch {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
        return (Invoke-HordeCloudflareRelayWatch -State $State -Mailbox $Mailbox -Since $Since -Max $Max -TimeoutMs $TimeoutMs)
    } `
    -WatchOpen {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
        return (Open-HordeCloudflareRelayWatch -State $State -Mailbox $Mailbox -Since $Since -Max $Max -TimeoutMs $TimeoutMs)
    } `
    -WatchWait {
        param($State, $Handle, [int]$WaitMs)
        return (Wait-HordeCloudflareRelayWatch -Handle $Handle -WaitMs $WaitMs)
    } `
    -WatchClose {
        param($State, $Handle)
        Close-HordeCloudflareRelayWatch -Handle $Handle
    } `
    -Ack {
        param($State, [string]$Mailbox, [long]$Through)
        $a = Invoke-HordeCloudflareRelayHttp -State $State -Method "POST" -Path (Get-HordeCloudflareRelayMailboxPath -Mailbox $Mailbox -Op "ack") -Body ('{"through":' + $Through + '}') -What "ack"
        if ($a.state -cne "known") { return $a }
        $t = $a.value.PSObject.Properties["through"]
        return (New-HordeKnown -Value ([pscustomobject]@{ through = $(if ($t) { $t.Value } else { $null }) }) -ObservedAt $a.observedAt)
    } `
    -Deploy {
        param([string]$Site, [scriptblock]$Say, [string]$HordeHome)
        return (Publish-HordeCloudflareRelay -Site $Site -Say $Say -HordeHome $HordeHome)
    } `
    -Bundle {
        param([string]$Tree, [string]$Work)
        return (Get-HordeCloudflareRelayBundleHash -Tree $Tree -Work $Work)
    } `
    -DaySummary {
        param($State, [string]$Day)
        return (Get-HordeCloudflareRelayDaySummary -State $State -Day $Day)
    } `
    -RunWatchMs $script:HordeCloudflareRelayRunWatchMs `
    -SecretFiles {
        param([string]$HordeHome)
        return (Get-HordeCloudflareRelaySecretFiles -HordeHome $HordeHome)
    }
