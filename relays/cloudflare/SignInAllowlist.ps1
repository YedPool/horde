# relays/cloudflare/SignInAllowlist.ps1 - who may sign in to the hosted relay, from the relay's settings
# (Settings.ps1) to the Worker's binding HORDE_RELAY_SIGNIN_ALLOWLIST (worker/allowlist.js).
#
# SIGNUP IS PUBLIC BY DEFAULT: any Google account may sign in, and gets an account of its own - its own
# mailboxes and machines, which no other account reaches. signInAllowlistOn is the one switch that
# turns the list on; signInAllowlist holds it: emails and Google account ids (the id token's sub),
# separated by commas. The list is kept while the switch is off, so it can be filled first.
#
# WRITTEN AS THE WORKER READS IT, one exact shape: {"on":<bool>,"emails":[...],"subs":[...]}, emails in
# lower case, each entry once, in the order given. The deploy stores it as a Worker SECRET, through a
# pipe like the client's values (Deploy.ps1): the addresses are not secrets, but they are a person's,
# and a secret keeps them out of every command line and the dashboard's plain variables.
#
# REFUSED, before anything is deployed: an entry that is neither an email nor an account id, and a list
# switched on with nobody on it - a relay nobody can sign in to is a mistake to be told about, not to
# deploy (the Worker itself fails closed on a broken list). No refusal repeats an entry.
#
# No Set-StrictMode here: dot-sourced.

# What worker/allowlist.js takes, its twin: an address of lower-case letters, digits and . _ % + ' -,
# and a domain; a Google account id is digits.
$script:HordeCloudflareRelayAllowlistEmail = '\A[a-z0-9._%+''-]{1,64}@[a-z0-9.-]{1,253}\z'
$script:HordeCloudflareRelayAllowlistSub = '\A[0-9]{1,255}\z'
$script:HordeCloudflareRelayAllowlistMax = 256

function ConvertTo-HordeCloudflareRelayAllowlist {
    # The binding's text from the settings' values: known text, or unknown saying what to mend.
    param([Parameter(Mandatory = $true)]$Values)
    $emails = New-Object System.Collections.ArrayList
    $subs = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($raw in @(("" + $Values.signInAllowlist) -split ",")) {
        $e = $raw.Trim()
        if ($e -eq "") { continue }
        $n++
        $lower = $e.ToLowerInvariant()
        if ($e -cmatch $script:HordeCloudflareRelayAllowlistSub) { if (-not $subs.Contains($e)) { [void]$subs.Add($e) } }
        elseif ($lower -cmatch $script:HordeCloudflareRelayAllowlistEmail) { if (-not $emails.Contains($lower)) { [void]$emails.Add($lower) } }
        else { return (New-HordeUnknown -Reason ("the setting signInAllowlist holds an entry (number " + $n + ") that is neither an email nor a Google account id; nothing was deployed")) }
    }
    if ($emails.Count + $subs.Count -gt $script:HordeCloudflareRelayAllowlistMax) { return (New-HordeUnknown -Reason ("the setting signInAllowlist names more than " + $script:HordeCloudflareRelayAllowlistMax + " accounts")) }
    $on = ($Values.signInAllowlistOn -eq $true)
    if ($on -and $emails.Count + $subs.Count -eq 0) { return (New-HordeUnknown -Reason "the setting signInAllowlistOn is true and signInAllowlist names nobody: nobody could sign in; nothing was deployed") }
    $quote = { param($list) (@($list | ForEach-Object { '"' + $_ + '"' }) -join ",") }
    return (New-HordeKnown -Value ('{"on":' + $(if ($on) { "true" } else { "false" }) + ',"emails":[' + (& $quote $emails) + '],"subs":[' + (& $quote $subs) + ']}'))
}
