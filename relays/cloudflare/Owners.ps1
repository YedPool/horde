# relays/cloudflare/Owners.ps1 - the hosted relay's OWNERS, from the relay's setting relayOwnerAccounts
# (Settings.ps1) to the Worker's binding HORDE_RELAY_OWNER_ACCOUNTS (worker/budget.js), and what the LIVE
# relay says of its own owners (worker/status.js), so no deploy clears them by accident.
#
# WHY OWNERS. The relay is open to any Google account, and the free plan's day of Worker requests is the
# whole relay's. So the relay keeps a day of its own across every account (worker/limits.js,
# relayRequestsPerDay) and holds a reserve of it (relayOwnerReserve) back for its owners: once every
# other account's share is spent, they are refused until midnight UTC and the owners go on.
#
# AN OWNER IS NAMED AS signInAllowlist NAMES AN ACCOUNT (SignInAllowlist.ps1, its rules reused): an
# email, compared in lower case with the VERIFIED email of the account's last sign-in (worker/jwt.js
# refuses a token whose email Google does not vouch for), or a Google account id - the id token's sub,
# digits. The email is what the phone's Account screen shows; the sub is nowhere a person can read it.
# Written as the Worker reads it, one exact shape: {"emails":[...],"subs":[...]}, each entry once.
#
# A SECRET, as the allowlist is: the emails are a person's, and a secret keeps them out of every command
# line and the dashboard's plain variables. Written on EVERY deploy (Deploy.ps1), so a deploy decides
# the owners every time.
#
# WHICH IS WHY A HOME THAT NEVER SET IT MUST NOT DEPLOY OVER OWNERS (the review of PR 281). The
# supervisor publishes the phone page by itself from the runner's home (cli/RelayPublish.ps1); a home
# whose settings name no owner would write an empty list and silently take the reserve from its
# owners. So, with relayOwnerAccounts EMPTY, the deploy first asks the live relay (GET /status/owners:
# how many owners, never who - worker/status.js):
#   it has owners                 REFUSED, nothing deployed, the reason naming the setting and its file
#   it has none, or predates them DEPLOYED, with the warning that the whole day is shared (a Worker from
#                                 before owners answers that path 404: it has none)
#   it cannot be asked            REFUSED: not knowing is not "none"
# THE OPT-OUT is the setting itself: relayOwnerAccounts = "none" deploys with no owners on purpose,
# clearing any the live relay has, without asking it. A setting and not a command-line switch: it is the
# home's recorded decision, so it holds for the supervisor's deploys from that home too, and it needs no
# new word in the relay port's deploy contract (relays/Port.ps1), which knows nothing of owners.
# WHY ASK THE LIVE RELAY, NOT THE DEPLOY RECORD: <HORDE_HOME>\relay\deployed.json is each home's own; the
# runner's home records only its own deploys, so it cannot know what another home deployed since.
# The live relay is the one place every deploy's result is.
#
# No Set-StrictMode here: dot-sourced.

. (Join-Path $PSScriptRoot "SignInAllowlist.ps1")

$script:HordeCloudflareRelayOwnersBinding = "HORDE_RELAY_OWNER_ACCOUNTS"
$script:HordeCloudflareRelayOwnersMax = 16
$script:HordeCloudflareRelayOwnersNone = "none"
$script:HordeCloudflareRelayOwnersPath = "/status/owners"
# A suite's stand-in for the live relay: honoured only as http to this machine itself.
$script:HordeCloudflareRelayOwnersTestOrigin = "HORDE_RELAY_TEST_STATUS_ORIGIN"
$script:HordeCloudflareRelayOwnersAskSeconds = 15

function ConvertTo-HordeCloudflareRelayOwners {
    # The setting read: known { text (the binding's JSON); count; mode } or unknown saying what to mend.
    # mode: "set" (owners named), "none" (the opt-out: no owners, on purpose), "missing" (empty).
    param([Parameter(Mandatory = $true)]$Values)
    $raw = ("" + $Values.relayOwnerAccounts).Trim()
    $empty = '{"emails":[],"subs":[]}'
    if ($raw -ceq "") { return (New-HordeKnown -Value ([pscustomobject]@{ text = $empty; count = 0; mode = "missing" })) }
    if ($raw.ToLowerInvariant() -ceq $script:HordeCloudflareRelayOwnersNone) { return (New-HordeKnown -Value ([pscustomobject]@{ text = $empty; count = 0; mode = "none" })) }
    $emails = New-Object System.Collections.ArrayList
    $subs = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($part in @($raw -split ",")) {
        $e = $part.Trim()
        if ($e -eq "") { continue }
        $n++
        $lower = $e.ToLowerInvariant()
        if ($e -cmatch $script:HordeCloudflareRelayAllowlistSub) { if (-not $subs.Contains($e)) { [void]$subs.Add($e) } }
        elseif ($lower -cmatch $script:HordeCloudflareRelayAllowlistEmail) { if (-not $emails.Contains($lower)) { [void]$emails.Add($lower) } }
        else { return (New-HordeUnknown -Reason ("the setting relayOwnerAccounts holds an entry (number " + $n + ") that is neither an email nor a Google account id; nothing was deployed")) }
    }
    $count = $emails.Count + $subs.Count
    if ($count -gt $script:HordeCloudflareRelayOwnersMax) { return (New-HordeUnknown -Reason ("the setting relayOwnerAccounts names more than " + $script:HordeCloudflareRelayOwnersMax + " accounts; nothing was deployed")) }
    $quote = { param($list) (@($list | ForEach-Object { '"' + $_ + '"' }) -join ",") }
    return (New-HordeKnown -Value ([pscustomobject]@{ text = ('{"emails":[' + (& $quote $emails) + '],"subs":[' + (& $quote $subs) + ']}'); count = $count; mode = "set" }))
}

function Get-HordeCloudflareRelayStatusOrigin {
    # Where the live relay is asked: -Origin, or - for a suite only - the stand-in its variable names,
    # when that is http to this machine itself.
    param([Parameter(Mandatory = $true)][string]$Origin)
    $t = "" + [System.Environment]::GetEnvironmentVariable($script:HordeCloudflareRelayOwnersTestOrigin)
    if ($t -cmatch '\Ahttp://127\.0\.0\.1:[0-9]{1,5}\z') { return $t }
    return $Origin
}

function Get-HordeCloudflareRelayLiveOwners {
    # What the live relay at -Origin says of its owners: known { owners; reserve }, absent when it
    # predates them (the path is 404 there), or unknown when it cannot be asked or answers nonsense.
    param([Parameter(Mandatory = $true)][string]$Origin)
    $at = Get-HordeCloudflareRelayStatusOrigin -Origin $Origin
    Add-Type -AssemblyName System.Net.Http
    $http = New-Object System.Net.Http.HttpClient
    $http.Timeout = [TimeSpan]::FromSeconds($script:HordeCloudflareRelayOwnersAskSeconds)
    try {
        try { $res = $http.GetAsync($at + $script:HordeCloudflareRelayOwnersPath).GetAwaiter().GetResult() }
        catch { return (New-HordeUnknown -Reason ("the live relay at " + $at + " could not be asked whether it has owners")) }
        try {
            $code = [int]$res.StatusCode
            if ($code -eq 404) { return (New-HordeAbsent -Note "the live relay predates owners: it has none") }
            if ($code -ne 200) { return (New-HordeUnknown -Reason ("the live relay at " + $at + " answered " + $code + " when asked whether it has owners")) }
            $text = $res.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        } finally { $res.Dispose() }
    } finally { $http.Dispose() }
    if ($text.Length -gt 200 -or $text -cnotmatch '\A\{"owners":([0-9]{1,3}),"reserve":(true|false)\}\z') { return (New-HordeUnknown -Reason ("the live relay at " + $at + " answered whether it has owners with something that is not the answer")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ owners = [int]$Matches[1]; reserve = ($Matches[2] -ceq "true") }))
}

function Test-HordeCloudflareRelayOwnersDeploy {
    # May a deploy with these owners (-Owners, ConvertTo-HordeCloudflareRelayOwners's value) go ahead,
    # to the relay at -Origin, from settings in -SettingsFile? known { say } - the line to say, a warning
    # or the owners' count - or unknown with the plain reason it may not (the header).
    param([Parameter(Mandatory = $true)]$Owners, [Parameter(Mandatory = $true)][string]$Origin, [string]$SettingsFile = "")
    $shared = "the relay keeps no reserve: its whole day of requests is shared by every account, yours included"
    if ($Owners.mode -ceq "set") { return (New-HordeKnown -Value ("the relay's owners: " + $Owners.count + " account(s), who may use the reserve once every other account's share of the day is spent")) }
    if ($Owners.mode -ceq "none") { return (New-HordeKnown -Value ("warning: the setting relayOwnerAccounts is none, so this deploy names no owner and clears any the live relay has: " + $shared)) }
    $where = $(if ($SettingsFile -ne "") { " in " + $SettingsFile } else { "" })
    $live = Get-HordeCloudflareRelayLiveOwners -Origin $Origin
    if ($live.state -ceq "unknown") { return (New-HordeUnknown -Reason ($live.reason + ", and the setting relayOwnerAccounts" + $where + " names no owner: set it to the owners' emails or Google account ids, or to none to deploy with no owners; nothing was deployed")) }
    if ($live.state -ceq "known" -and $live.value.owners -gt 0) { return (New-HordeUnknown -Reason ("the live relay has " + $live.value.owners + " owner(s), and the setting relayOwnerAccounts" + $where + " names none, so this deploy would take the reserve from them: set it to the owners' emails or Google account ids (the phone's Account screen shows the email), or to none to clear them on purpose; nothing was deployed")) }
    return (New-HordeKnown -Value ("warning: the setting relayOwnerAccounts names no owner, and the live relay has none: " + $shared))
}

function Get-HordeCloudflareRelayStatusLines {
    # `horde relay status` for the hosted relay at -Origin: plain lines of what it says of itself.
    param([Parameter(Mandatory = $true)][string]$Origin)
    $live = Get-HordeCloudflareRelayLiveOwners -Origin $Origin
    $head = "relay at " + $Origin + ": "
    if ($live.state -ceq "unknown") { return @($head + "cannot say whether it has owners: " + $live.reason) }
    if ($live.state -ceq "absent" -or (-not $live.value.reserve)) { return @($head + "no owner set: the whole day is shared, no reserve") }
    if ($live.value.owners -eq 0) { return @($head + "its owners cannot be read (a broken owners setting): the reserve is held back from every account") }
    return @($head + $live.value.owners + " owner(s): the reserve of the day is kept for them")
}
