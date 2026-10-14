# cli/RelayJoin - `horde relay joins`, `horde relay approve` and `horde relay reject`: the founder, AT THIS
# MACHINE, answers a new phone's join request (relay/Join.ps1 has every rule; channels/join carries it).
#
#   horde relay joins                         every join request, newest first, with its state
#   horde relay approve <request> <number>    the 12-digit number the NEW phone shows, typed here; this
#                                             machine compares it with its own (three wrong reject it)
#   horde relay reject <request>              reject it: its passkey, if one registered, is revoked
#
# WHY THE NUMBER IS TYPED, NEVER SHOWN HERE (relay/Pairing.ps1, WHAT A STOLEN OFFER CAN AND CANNOT DO, and
# design-phone-started-pairing.md threat 5): what makes the new phone trusted is the founder reading the
# number on the phone in his hand. A machine that printed its own number could be copied from, and a
# stranger's phone in the same Google account would be approved. So `joins` lists who asks, never a number.
# The approval takes effect at the runner's next turn: it closes the request, tells the new phone it is
# confirmed, and tells every trusted device.
#
# No Set-StrictMode here: this file is dot-sourced.

function Get-HordeRelayJoinLines {
    # The join requests of -HordeHome as lines for `horde relay joins`.
    param([string]$HordeHome = "", $Now = $null)
    $all = Get-HordeRelayJoins -HordeHome $HordeHome -Now $Now
    if ($all.state -cne "known") { throw ("the join requests cannot be read: " + $all.reason) }
    $out = New-Object System.Collections.ArrayList
    foreach ($j in @($all.value | Sort-Object -Property @{ Expression = { $_.request.receivedAt } } -Descending)) {
        $q = $j.request
        $at = [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$q.requestedAt).LocalDateTime.ToString("yyyy-MM-dd HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
        $state = $(if ($null -ne $j.closed) { $j.closed.outcome + " (" + $j.closed.reason + ")" } elseif ($j.expired) { "expired" } elseif ($null -eq $j.device) { "waiting for the new phone's passkey" } else { "waiting for the number: horde relay approve " + $q.request + " <number>" })
        [void]$out.Add("join " + $q.request + "  '" + $q.label + "'  " + $q.agent + "  " + $(if ($q.country -cne "") { $q.country } else { "country unknown" }) + "  " + $at + "  " + $state)
    }
    if ($out.Count -eq 0) { [void]$out.Add("no new phone has asked to join this machine") }
    return @($out.ToArray())
}

function Invoke-HordeRelayJoinApprove {
    # `horde relay approve`: the lines to print, or a throw naming why nothing was approved.
    param([string]$HordeHome = "", [string]$Request, [string]$Number, $Now = $null)
    if ($Request -ceq "" -or $Number -ceq "") { throw "relay approve needs the join request's id and the 12-digit number the NEW phone shows: horde relay approve <request> <number> (horde relay joins lists the requests)" }
    $a = Approve-HordeRelayJoin -HordeHome $HordeHome -Request $Request -Number $Number -Now $Now
    if (-not $a.ok) { throw $a.reason }
    return @("approved: the new phone '" + $a.value.label + "' (device " + $a.value.id + ") is trusted. It is told so, and every trusted device too, at the relay run's next turn; on the new phone, tap Finish pairing.")
}

function Invoke-HordeRelayJoinReject {
    # `horde relay reject`: the lines to print, or a throw naming why nothing was rejected.
    param([string]$HordeHome = "", [string]$Request, [string]$Reason = "", $Now = $null)
    if ($Request -ceq "") { throw "relay reject needs the join request's id (horde relay joins lists them)" }
    $r = Reject-HordeRelayJoin -HordeHome $HordeHome -Request $Request -Reason $(if ($Reason -cne "") { $Reason } else { "rejected at the machine with horde relay reject" }) -Now $Now
    if (-not $r.ok) { throw $r.reason }
    return @($r.reason + ". The relay frees its slot and blocks the asking address for the hour at the relay run's next turn; if it was not your phone, change your Google password.")
}
