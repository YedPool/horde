# core/RelayWatch - is the hosted relay up, and can a new phone sign in through it? Decided by no model.
#
# WHY THIS EXISTS. On 2026-10-14 every new sign-in to the phone app failed for 2 h 38 min and nobody saw
# it: the Google client id the relay sends had a byte order mark (U+FEFF) in front of it, so Google
# answered invalid_client to each one. The pages themselves answered 200 the whole time. So a watcher
# that only asked "does the page load" would have stayed green. This one asks three things, without
# following any redirect:
#   1. GET /                  answers 200
#   2. GET /app/index.html    answers 200
#   3. GET /auth/google       answers 303 to https://accounts.google.com/..., and the client_id in that
#                             address, URL-decoded, is exactly the shape a Google web client id has:
#                             digits, a hyphen, lower-case letters and digits, ".apps.googleusercontent.com"
#                             - plain ASCII, no byte order mark, no blank anywhere.
# THE CLIENT ID IS NEVER PRINTED, journaled or told: a reason says only which rule it broke.
#
# WHO IS TOLD, AND HOW (the warchief and C, 2026-10-14). The first time it fails after it was healthy -
# and only after failuresBeforeAlert checks in a row (2), so one blip tells nobody - the warchief is told
# through the fleet's mail, which does not travel through the relay; then ONE notice to the founder's
# phone is tried as well, knowing it may not arrive, because that notice does travel through the relay.
# While it stays down, nothing more is said. When it is healthy again - TWO healthy checks in a row, so a
# relay that flaps does not send a notice each way - both are told once more, with how long it was down.
# A TELL THAT FAILED IS NOT A TELL (review of PR 307): the outage counts as told only once the warchief's
# mail was taken, so one failed fleet mail cannot silence a whole outage; the next check tries again. The
# notice is tried once an outage and once a recovery, whatever it answers.
# A STATE FILE THAT CANNOT BE READ is told to the warchief (at most once a day), never a silent stop.
#
# WHAT A CHECK COSTS THE RELAY: each GET /auth/google spends one of the relay's signInStartsPerMinute and
# sets a throwaway state cookie the watcher never sends back. At one check every five minutes that is one
# start in five minutes against a limit of several a minute.
#
# THE CHECK IS HANDED IN (Invoke-HordeRelayWatch -Tools): a suite points it at a server of its own and
# never at the real relay. This file starts nothing; the real fetch is Get-HordeRelayWatchResponse.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1). It runs under -Version Latest.

. (Join-Path $PSScriptRoot "Tristate.ps1")
. (Join-Path $PSScriptRoot "JsonText.ps1")
. (Join-Path $PSScriptRoot "ReadShared.ps1")
. (Join-Path $PSScriptRoot "FileAtomic.ps1")

# THE SAME RULE AS THE RELAY ADAPTER'S OWN GOOGLE CLIENT FILE (its GoogleClient.ps1, its length bounds), and
# a client_id named twice is refused as PR 275's deploy check refuses it ("no single client_id"; PR 275 was
# not on main when this was written, so its rule is copied here, by value, not by name).
$script:HordeRelayClientIdPattern = '\A[0-9]{1,32}-[a-z0-9]{1,64}\.apps\.googleusercontent\.com\z'
$script:HordeRelayGoogleHost = "accounts.google.com"
# A check that takes longer than this is a failure: a relay that does not answer in 15 s is down to a phone.
$script:HordeRelayFetchSeconds = 15

function Test-HordeRelayClientId {
    # PURE. Whether -Value (already URL-decoded) is a Google web client id: "" when it is, else why not -
    # in words that never repeat the value.
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ($null -eq $Value -or $Value -eq "") { return "the sign-in address carries no client_id" }
    if ($Value.Contains([string][char]0xFEFF)) { return "the client_id carries a byte order mark (U+FEFF)" }
    if ($Value -match '\s') { return "the client_id carries a blank or a line break" }
    foreach ($c in $Value.ToCharArray()) { if ([int]$c -gt 126 -or [int]$c -lt 32) { return "the client_id carries a character that is not plain ASCII" } }
    if ($Value -cnotmatch $script:HordeRelayClientIdPattern) { return "the client_id is not the shape of a Google web client id" }
    return ""
}

function Get-HordeRelayQueryValues {
    # PURE. Every URL-decoded value of -Name in the query of -Url, in order: none, one, or (a fault) more.
    param([Parameter(Mandatory = $true)][string]$Url, [Parameter(Mandatory = $true)][string]$Name)
    $q = $Url.IndexOf("?")
    if ($q -lt 0) { return [string[]]@() }
    $found = New-Object System.Collections.ArrayList
    foreach ($pair in $Url.Substring($q + 1).Split("&")) {
        $eq = $pair.IndexOf("=")
        $k = $(if ($eq -ge 0) { $pair.Substring(0, $eq) } else { $pair })
        if ([System.Uri]::UnescapeDataString($k.Replace("+", " ")) -ceq $Name) { [void]$found.Add($(if ($eq -ge 0) { [System.Uri]::UnescapeDataString($pair.Substring($eq + 1).Replace("+", " ")) } else { "" })) }
    }
    return [string[]]$found.ToArray()
}

function Get-HordeRelayHealth {
    # The three checks (header) against -Origin through -Fetch, a block param($Url) answering { status;
    # location } without following a redirect, or throwing when nothing answered: { ok; why }.
    param([Parameter(Mandatory = $true)][string]$Origin, [Parameter(Mandatory = $true)][scriptblock]$Fetch)
    $base = $Origin.TrimEnd("/")
    $ask = {
        param([string]$Path)
        try { return (@(& $Fetch ($base + $Path)) | Select-Object -Last 1) } catch { return [pscustomobject]@{ status = 0; location = ""; failed = ("" + $_.Exception.Message) } }
    }
    foreach ($path in @("/", "/app/index.html")) {
        $r = & $ask $path
        if ($null -eq $r -or [int]$r.status -ne 200) { return [pscustomobject]@{ ok = $false; why = ("GET " + $path + " " + $(if ($null -eq $r -or [int]$r.status -eq 0) { "got no answer" } else { "answered " + $r.status + ", not 200" })) } }
    }
    $r = & $ask "/auth/google"
    if ($null -eq $r -or [int]$r.status -eq 0) { return [pscustomobject]@{ ok = $false; why = "GET /auth/google got no answer" } }
    if ([int]$r.status -ne 303) { return [pscustomobject]@{ ok = $false; why = ("GET /auth/google answered " + $r.status + ", not 303") } }
    $to = "" + $r.location
    $uri = $null
    if (-not [System.Uri]::TryCreate($to, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -cne "https" -or $uri.Host -cne $script:HordeRelayGoogleHost) { return [pscustomobject]@{ ok = $false; why = "GET /auth/google redirects somewhere that is not https://accounts.google.com" } }
    $ids = @(Get-HordeRelayQueryValues -Url $to -Name "client_id")
    if ($ids.Count -gt 1) { return [pscustomobject]@{ ok = $false; why = "GET /auth/google: the sign-in address names client_id more than once; every new sign-in fails" } }
    $bad = Test-HordeRelayClientId -Value $(if ($ids.Count -eq 1) { $ids[0] } else { "" })
    if ($bad -ne "") { return [pscustomobject]@{ ok = $false; why = ("GET /auth/google: " + $bad + "; every new sign-in fails") } }
    return [pscustomobject]@{ ok = $true; why = "" }
}

function New-HordeRelayWatchState {
    return [pscustomobject]@{ v = 1; lastCheckAt = $null; failures = 0; healthy = 0; downSince = $null; alerted = $false; notified = $false; lastWhy = "" }
}

function Get-HordeRelayWatchDecision {
    # PURE. After one check: { state; alert; why } - alert "down" (tell now), "recovered" (tell now, why
    # says for how long it was down) or "" (say nothing). It never marks an outage told: that is done
    # only once the tell is taken (Invoke-HordeRelayWatch). -Policy holds relayFailuresBeforeAlert.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Health, [Parameter(Mandatory = $true)][datetime]$Now, [Parameter(Mandatory = $true)]$Policy)
    $utcNow = $Now.ToUniversalTime()
    $s = [pscustomobject]@{ v = 1; lastCheckAt = $utcNow; failures = [int]$State.failures; healthy = [int]$State.healthy; downSince = $State.downSince
                            alerted = [bool]$State.alerted; notified = [bool]$State.notified; lastWhy = "" + $State.lastWhy }
    if ($Health.ok) {
        $s.healthy = $s.healthy + 1
        if (-not $s.alerted -and -not $s.notified) {
            # Nobody told of an outage: a blip is forgotten at once. (Review of PR 307: a founder told "down"
            # whose warchief's tell was never taken is still owed "back", so notified keeps the outage open.)
            $s.failures = 0; $s.downSince = $null; $s.lastWhy = ""; $s.notified = $false
            return [pscustomobject]@{ state = $s; alert = ""; why = "" }
        }
        if ($s.healthy -lt 2) { return [pscustomobject]@{ state = $s; alert = ""; why = "healthy once; one more healthy check before it is called back" } }
        $mins = $(if ($s.downSince -is [datetime]) { [int][System.Math]::Round(($utcNow - ([datetime]$s.downSince).ToUniversalTime()).TotalMinutes) } else { -1 })
        return [pscustomobject]@{ state = $s; alert = "recovered"; why = $(if ($mins -ge 0) { "it was down about " + $mins + " minutes" } else { "how long it was down is not known" }) }
    }
    $s.healthy = 0
    $s.failures = $s.failures + 1
    if ($null -eq $s.downSince) { $s.downSince = $utcNow }
    $s.lastWhy = "" + $Health.why
    if (-not $s.alerted -and $s.failures -ge [int]$Policy.relayFailuresBeforeAlert) { return [pscustomobject]@{ state = $s; alert = "down"; why = $Health.why } }
    return [pscustomobject]@{ state = $s; alert = ""; why = $Health.why }
}

function Read-HordeRelayWatchState {
    # The watcher's state at -Path: known (a fresh one when there is no file), unknown when unreadable.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return (New-HordeKnown -Value (New-HordeRelayWatchState)) }
    try {
        $doc = ConvertFrom-HordeJson -Text (Read-HordeSharedText -Path $Path)
        if ($doc -isnot [System.Management.Automation.PSCustomObject] -or ("" + $doc.v) -cne "1") { throw "it is not a relay watch state, v 1" }
        $s = New-HordeRelayWatchState
        $s.failures = [int]$doc.failures; $s.healthy = [int]$doc.healthy; $s.alerted = ($doc.alerted -eq $true); $s.notified = ($doc.notified -eq $true); $s.lastWhy = "" + $doc.lastWhy
        foreach ($k in @("lastCheckAt", "downSince")) {
            $t = [datetime]::MinValue
            if ($doc.$k -is [string] -and [datetime]::TryParse($doc.$k, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$t)) { $s.$k = $t.ToUniversalTime() }
        }
        return (New-HordeKnown -Value $s)
    } catch { return (New-HordeUnknown -Reason "the relay watch's state file cannot be read" -ErrorRecord $_) }
}

function Write-HordeRelayWatchState {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$State)
    $o = [ordered]@{ v = 1; lastCheckAt = $null; failures = [int]$State.failures; healthy = [int]$State.healthy; downSince = $null; alerted = [bool]$State.alerted; notified = [bool]$State.notified; lastWhy = "" + $State.lastWhy }
    if ($State.lastCheckAt -is [datetime]) { $o.lastCheckAt = $State.lastCheckAt.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($State.downSince -is [datetime]) { $o.downSince = $State.downSince.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture) }
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
    $temp = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    [System.IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $o -Compress), (New-Object System.Text.UTF8Encoding($false)))
    try { Move-HordeFileAtomic -From $temp -To $Path } catch { try { [System.IO.File]::Delete($temp) } catch { }; throw }
}

function Send-HordeRelayWatchWord {
    # Hand one text to the tool -Name: { ok; line }. A tool that is $null tells nobody.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Who)
    if ($null -eq $Tools[$Name]) { return [pscustomobject]@{ ok = $false; line = ("relay watch: would tell " + $Who + ", but telling is off") } }
    $r = $null
    try { $r = @(& $Tools[$Name] $Text) | Select-Object -Last 1 } catch { $r = [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
    $ok = ($null -ne $r -and $r.ok -eq $true)
    return [pscustomobject]@{ ok = $ok; line = ("relay watch: " + $(if ($ok) { "told " + $Who } else { "could not tell " + $Who + ": " + $(if ($null -ne $r) { "" + $r.detail } else { "no answer" }) })) }
}

function Invoke-HordeRelayWatch {
    # One look, when one is due (relayEveryMinutes since the last): { lines }. -Tools: Now; Fetch
    # param($Url); Tell param($Body) and Notify param($Line), each answering { ok; detail } or $null to
    # tell nobody. -Origin "" turns the watch off, and says so once a pass.
    param([Parameter(Mandatory = $true)]$Tools, [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)][string]$StatePath, [AllowEmptyString()][string]$Origin)
    $lines = New-Object System.Collections.ArrayList
    if ($Origin -eq "") { return [pscustomobject]@{ lines = @("relay watch: off - no relay origin is set (relayOrigin, or pairOrigin in the relay settings)") } }
    $utcNow = ([datetime](@(& $Tools["Now"]) | Select-Object -Last 1)).ToUniversalTime()
    $read = Read-HordeRelayWatchState -Path $StatePath
    if ($read.state -cne "known") {
        # A STATE THAT CANNOT BE READ IS TOLD (review of PR 307), at most once a day: the time it was last
        # told is the time of a small file beside it, which needs no reading of the broken one.
        [void]$lines.Add("relay watch: " + $read.reason + "; nothing is checked until it is mended or removed")
        $mark = $StatePath + ".told"
        $last = $(if ([System.IO.File]::Exists($mark)) { [System.IO.File]::GetLastWriteTimeUtc($mark) } else { [datetime]::MinValue })
        if ($utcNow -ge $last.AddHours(24)) {
            $w = Send-HordeRelayWatchWord -Tools $Tools -Name "Tell" -Text ("RELAY WATCH STOPPED`nThe relay watch's state file cannot be read, so the hosted relay is not being checked. It is " + $StatePath + "; removing it starts the watch afresh.") -Who "the warchief"
            [void]$lines.Add($w.line)
            if ($w.ok) { try { [System.IO.File]::WriteAllText($mark, "told") ; [System.IO.File]::SetLastWriteTimeUtc($mark, $utcNow) } catch { } }
        }
        return [pscustomobject]@{ lines = @($lines.ToArray()) }
    }
    $st = $read.value
    if ($st.lastCheckAt -is [datetime] -and $utcNow -lt $st.lastCheckAt.AddMinutes([int]$Policy.relayEveryMinutes)) { return [pscustomobject]@{ lines = @() } }
    $health = Get-HordeRelayHealth -Origin $Origin -Fetch $Tools["Fetch"]
    $d = Get-HordeRelayWatchDecision -State $st -Health $health -Now $utcNow -Policy $Policy
    $s = $d.state
    if ($d.alert -ceq "down") {
        [void]$lines.Add("relay watch: DOWN - " + $d.why)
        $w = Send-HordeRelayWatchWord -Tools $Tools -Name "Tell" -Text ("RELAY DOWN`nThe hosted relay at " + $Origin + " fails its check " + $s.failures + " times in a row: " + $d.why + ".`nThe founder's phone may get nothing from this machine, the notice sent beside this one included. You are told again when it is back.") -Who "the warchief"
        [void]$lines.Add($w.line)
        # TOLD ONLY WHEN TAKEN: a failed tell leaves it untold, and the next check tries again.
        if ($w.ok) { $s.alerted = $true }
        if (-not $s.notified) {
            $s.notified = $true
            [void]$lines.Add((Send-HordeRelayWatchWord -Tools $Tools -Name "Notify" -Text ("The relay check fails: " + $d.why + ". The warchief is told by fleet mail.") -Who "the founder's phone").line)
        }
    } elseif ($d.alert -ceq "recovered") {
        [void]$lines.Add("relay watch: recovered - " + $d.why)
        # Each is told "back" only if it was told "down": a warchief whose down-tell was never taken is
        # not sent a "back" for an outage he never heard of.
        $w = $(if ($s.alerted) { Send-HordeRelayWatchWord -Tools $Tools -Name "Tell" -Text ("RELAY BACK`nThe hosted relay at " + $Origin + " passes its check again; " + $d.why + ".") -Who "the warchief" }
               else { [pscustomobject]@{ ok = $true; line = "relay watch: the warchief was never told it was down, so he is not told it is back" } })
        [void]$lines.Add($w.line)
        # A recovery the warchief did not take stays owed: the next healthy check tells it again, and the
        # notice goes with the tell that was taken, so it is sent once.
        if ($w.ok) {
            if ($s.notified) { [void]$lines.Add((Send-HordeRelayWatchWord -Tools $Tools -Name "Notify" -Text ("The relay is back; " + $d.why + ".") -Who "the founder's phone").line) }
            $s.alerted = $false; $s.notified = $false; $s.failures = 0; $s.healthy = 0; $s.downSince = $null; $s.lastWhy = ""
        }
    } elseif (-not $health.ok) {
        [void]$lines.Add("relay watch: failing (" + $s.failures + " in a row), " + $d.why)
    }
    Write-HordeRelayWatchState -Path $StatePath -State $s
    return [pscustomobject]@{ lines = @($lines.ToArray()) }
}

function Get-HordeRelayWatchResponse {
    # THE REAL FETCH: one GET of -Url that never follows a redirect, { status; location }. Throws when
    # nothing answered in $script:HordeRelayFetchSeconds.
    param([Parameter(Mandatory = $true)][string]$Url)
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = "GET"
    $req.AllowAutoRedirect = $false
    $req.Timeout = $script:HordeRelayFetchSeconds * 1000
    $req.ReadWriteTimeout = $script:HordeRelayFetchSeconds * 1000
    $resp = $null
    try {
        # A 4xx or 5xx answer arrives as a web exception that carries the response; no answer carries none.
        try { $resp = $req.GetResponse() }
        catch {
            $web = $_.Exception
            while ($null -ne $web -and $web -isnot [System.Net.WebException]) { $web = $web.InnerException }
            if ($null -ne $web -and $null -ne $web.Response) { $resp = $web.Response } else { throw }
        }
        return [pscustomobject]@{ status = [int]$resp.StatusCode; location = ("" + $resp.Headers["Location"]) }
    } finally { if ($null -ne $resp) { $resp.Close() } }
}
