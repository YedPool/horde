# relays/cloudflare/Owners.ps1 - the hosted relay's OWNERS, from the relay's setting relayOwnerAccounts
# (Settings.ps1) to the Worker's binding HORDE_RELAY_OWNER_ACCOUNTS (worker/budget.js).
#
# WHY OWNERS. The relay is open to any Google account, and the free plan's day of Worker requests is the
# whole relay's. So the relay keeps a day of its own across every account (worker/limits.js,
# relayRequestsPerDay) and holds a reserve of it (relayOwnerReserve) back for its owners: once every
# other account's share is spent, they are refused until midnight UTC and the owners go on.
#
# AN OWNER IS A GOOGLE ACCOUNT ID - the id token's sub, digits, which the relay's account id carries as
# "google:<sub>" - never an email: an email can change hands and is not what the relay keys accounts by.
# Written as the Worker reads it: the ids separated by commas, no spaces, each once, in the order given.
#
# A PLAIN VAR, NOT A SECRET (worker/budget.js says why: an id names an account and opens nothing). The
# deploy passes it to `wrangler deploy` as --var, so it lives in the Worker's deployed vars - and only
# there: wrangler.json, the committed config, never holds it. With NONE set there is no reserve - the
# whole day is shared by every account, the owner's included - and the deploy says so as a warning.
#
# REFUSED, before anything is deployed: an entry that is not a Google account id (an email, most
# likely - said so), and more than the Worker takes. No refusal repeats an entry.
#
# No Set-StrictMode here: dot-sourced.

$script:HordeCloudflareRelayOwnersBinding = "HORDE_RELAY_OWNER_ACCOUNTS"
# What worker/budget.js takes, its twin.
$script:HordeCloudflareRelayOwnerSub = '\A[0-9]{1,255}\z'
$script:HordeCloudflareRelayOwnersMax = 16

function ConvertTo-HordeCloudflareRelayOwners {
    # The binding's text from the settings' values: known text ("" for none), or unknown saying what to mend.
    param([Parameter(Mandatory = $true)]$Values)
    $subs = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($raw in @(("" + $Values.relayOwnerAccounts) -split ",")) {
        $e = $raw.Trim()
        if ($e -eq "") { continue }
        $n++
        if ($e -cnotmatch $script:HordeCloudflareRelayOwnerSub) {
            $hint = $(if ($e.Contains("@")) { " (an email: the owners are named by their Google account id, the sign-in's sub)" } else { "" })
            return (New-HordeUnknown -Reason ("the setting relayOwnerAccounts holds an entry (number " + $n + ") that is not a Google account id" + $hint + "; nothing was deployed"))
        }
        if (-not $subs.Contains($e)) { [void]$subs.Add($e) }
    }
    if ($subs.Count -gt $script:HordeCloudflareRelayOwnersMax) { return (New-HordeUnknown -Reason ("the setting relayOwnerAccounts names more than " + $script:HordeCloudflareRelayOwnersMax + " accounts; nothing was deployed")) }
    return (New-HordeKnown -Value (@($subs) -join ","))
}

function Get-HordeCloudflareRelayOwnersArgs {
    # wrangler deploy's arguments for the owners' text -Owners: --var with the binding, or none for none.
    param([AllowEmptyString()][string]$Owners)
    if ($Owners -eq "") { return @() }
    return @("--var", ($script:HordeCloudflareRelayOwnersBinding + ":" + $Owners))
}
