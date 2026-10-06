# remote/Messaging.ps1 - the rules of messaging over the link, decided once, for the node and the hub.
#
# WHY (plan step R21; review of PR #97, 2026-10-06). The contract text states how a deliver is
# addressed and gated, how a receipt moves a message, and which messages mail.next still owes. Left as
# prose, slice 4 (the node) and slice 5 (the hub) would each choose, and the review found where a choice
# was a bypass: a label followed to a session the hub never spawned. So each rule is a pure function
# here, tested by test/test-messaging-rules.ps1 with a mutant per rule, and the node and hub call it.
#
# PURE. Given what the caller already knows - the live sessions, the hub's records, the outbox - each
# function answers. It reads no file, starts nothing and touches no session, so it lives in remote/
# under tools/ExecScan.ps1's proof. The stage order is remote/Contract.ps1's, the same lists the verb
# table is checked against, so the rules and the schema cannot drift apart.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Contract.ps1")

function Get-HordeMailStageRank {
    # Where a stage stands: its index along the forward order, or one past the end for a final stage
    # that is not on it. -1 for a stage nobody knows.
    param([string]$Stage)
    $i = [array]::IndexOf(@($script:HordeMailStageOrder), $Stage)
    if ($i -ge 0) { return $i }
    if ($script:HordeMailFinalStages -ccontains $Stage) { return @($script:HordeMailStageOrder).Count }
    return -1
}

function Resolve-HordeMailReceipt {
    # What one receipt does to one outbox record (F2, F6). -Recorded is the record's stage, "" when the
    # node never returned this message from mail.next. Returns { refused; stage; changed }: refused is the
    # reason when the receipt is refused (and nothing is recorded); otherwise stage is the record's stage
    # AFTER the receipt - the one asked for when it moved the record forward, the one already recorded when
    # it did not - and that is the stage the ack carries.
    param([AllowEmptyString()][string]$Recorded, [Parameter(Mandatory = $true)][string]$Asked)
    if ($Recorded -eq "") { return [pscustomobject]@{ refused = "no outbound message with this id was ever returned from mail.next by this node"; stage = ""; changed = $false } }
    $receiptStages = @(@($script:HordeMailStageOrder) + @($script:HordeMailFinalStages) | Where-Object { $_ -cne "queued" })
    if ($receiptStages -cnotcontains $Asked) { return [pscustomobject]@{ refused = ("'" + $Asked + "' is not a receipt stage"); stage = $Recorded; changed = $false } }
    $have = Get-HordeMailStageRank -Stage $Recorded
    if ($have -lt 0) { return [pscustomobject]@{ refused = ("the record holds '" + $Recorded + "', which is not a stage"); stage = $Recorded; changed = $false } }
    # A FINAL STAGE IS NEVER OVERWRITTEN, and a replay of it records nothing.
    if ($script:HordeMailFinalStages -ccontains $Recorded) { return [pscustomobject]@{ refused = ""; stage = $Recorded; changed = $false } }
    # FORWARD ONLY: a final stage, or a later one along the order. A stale or backward receipt answers
    # with what is recorded.
    if ($script:HordeMailFinalStages -ccontains $Asked -or (Get-HordeMailStageRank -Stage $Asked) -gt $have) {
        return [pscustomobject]@{ refused = ""; stage = $Asked; changed = $true }
    }
    return [pscustomobject]@{ refused = ""; stage = $Recorded; changed = $false }
}

function Test-HordeMailSettled {
    # Does a message at this stage no longer count for mail.next (F3)? Every known stage but queued: held
    # settles too, so a held message at the head never blocks the queue behind it. A stage nobody knows
    # is never read as settled.
    param([string]$Stage)
    if ((Get-HordeMailStageRank -Stage $Stage) -lt 0) { return $false }
    return ($Stage -cne "queued")
}

function Select-HordeMailNext {
    # mail.next over an outbox: how many messages are unsettled, and the oldest of them by createdAt
    # (messageId breaks a tie, so the answer never depends on the order the records were read in).
    # Returns { pending; next }, next $null when none waits.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Outbox)
    $waiting = @($Outbox | Where-Object { $null -ne $_ -and -not (Test-HordeMailSettled -Stage "$($_.stage)") })
    $next = $null
    if ($waiting.Count -gt 0) {
        # ORDINAL, as remote/Journal.ps1 sorts: createdAt is one fixed ISO spelling, so its ordinal order is
        # its time order, and a culture-aware sort can ignore the hyphens in it.
        $keys = [string[]]@($waiting | ForEach-Object { "$($_.createdAt)" + "|" + "$($_.messageId)" })
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        $first = $keys[0]
        $next = @($waiting | Where-Object { [string]::Equals(("$($_.createdAt)" + "|" + "$($_.messageId)"), $first, [System.StringComparison]::Ordinal) })[0]
    }
    return [pscustomobject]@{ pending = $waiting.Count; next = $next }
}

function Test-HordeMailSender {
    # Is outbound mail from the device its link authenticated (F5)? The node's payload says who sent it;
    # the hub believes only the link. Findings; empty means the sender's device is the peer's.
    param([Parameter(Mandatory = $true)]$Mail, [AllowEmptyString()][string]$PeerDeviceId)
    $claimed = "$(Get-HordeLinkProp (Get-HordeLinkProp $Mail 'from') 'deviceId')"
    if ($PeerDeviceId -eq "") { return @("the link peer's device is not known, so no mail from it can be attributed") }
    if (-not [string]::Equals($claimed, $PeerDeviceId, [System.StringComparison]::Ordinal)) {
        return @("the mail claims device " + $claimed + ", but the link's peer is device " + $PeerDeviceId)
    }
    return @()
}

function Test-HordeDeliverSameProcess {
    # Are two session entries the same process: pid AND procStart, both present and equal? A pid alone is
    # reused, and an empty start time proves nothing.
    param($A, $B)
    $ap = "$(Get-HordeLinkProp $A 'pid')"; $bp = "$(Get-HordeLinkProp $B 'pid')"
    $as = "$(Get-HordeLinkProp $A 'procStart')"; $bs = "$(Get-HordeLinkProp $B 'procStart')"
    if ($ap -eq "" -or $as -eq "" -or $bs -eq "") { return $false }
    return ([string]::Equals($ap, $bp, [System.StringComparison]::Ordinal) -and [string]::Equals($as, $bs, [System.StringComparison]::Ordinal))
}

function New-HordeDeliverTarget {
    param([string]$Refused = "", [string]$SessionId = "", [string]$Label = "", [string]$Via = "", [string]$Gate = "")
    return [pscustomobject]@{ refused = $Refused; sessionId = $SessionId; label = $Label; via = $Via; gate = $Gate }
}

function Resolve-HordeDeliverTarget {
    # Which live session a session.deliver reaches, and whether it may (F1). -Live is the node's live
    # sessions and -HubSpawned the sessions this hub spawned on the node, each { sessionId; label; pid;
    # procStart }; -DeliverTo is the node's own remote.deliverTo, from its own configuration and never
    # from the link. Returns { refused; sessionId; label; via; gate }: refused is the reason, or "" with
    # the session it reaches, how (id or label) and which gate let it through.
    #
    # THE ORDER IS THE RULE. First the session is resolved: the id when it is live (and a label given
    # must be the one it wears - never a retarget), else the label to the ONE live session wearing it.
    # Then the gate is applied to THAT session: hub-spawned by its id, or by its process (pid and
    # procStart) for an id a compact or /clear changed, never by its label; or opted in by its own label.
    param(
        [Parameter(Mandatory = $true)][string]$SessionId,
        [AllowEmptyString()][string]$Label,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Live,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$HubSpawned,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$DeliverTo
    )
    $live = @($Live | Where-Object { $null -ne $_ })
    $byId = @($live | Where-Object { [string]::Equals("$($_.sessionId)", $SessionId, [System.StringComparison]::Ordinal) })
    $target = $null
    $via = ""
    if ($byId.Count -gt 0) {
        $target = $byId[0]
        $via = "id"
        if ($Label -ne "" -and -not [string]::Equals("$($target.label)", $Label, [System.StringComparison]::Ordinal)) {
            return (New-HordeDeliverTarget -Refused ("session " + $SessionId + " is live but wears the label " + $target.label + ", not " + $Label + "; a deliver is never retargeted"))
        }
    }
    elseif ($Label -eq "") {
        return (New-HordeDeliverTarget -Refused ("session " + $SessionId + " is not live on this node and the deliver names no label to follow"))
    }
    else {
        $byLabel = @($live | Where-Object { [string]::Equals("$($_.label)", $Label, [System.StringComparison]::Ordinal) })
        if ($byLabel.Count -eq 0) { return (New-HordeDeliverTarget -Refused ("session " + $SessionId + " is not live and no live session wears the label " + $Label)) }
        if ($byLabel.Count -gt 1) { return (New-HordeDeliverTarget -Refused ("session " + $SessionId + " is not live and " + $byLabel.Count + " live sessions wear the label " + $Label + ", so it names none of them")) }
        $target = $byLabel[0]
        $via = "label"
    }
    # THE GATE, ON THE RESOLVED SESSION.
    $tid = "$($target.sessionId)"
    $gate = ""
    if (@($HubSpawned | Where-Object { $null -ne $_ -and [string]::Equals("$($_.sessionId)", $tid, [System.StringComparison]::Ordinal) }).Count -gt 0) { $gate = "hub-spawned" }
    elseif (@($HubSpawned | Where-Object { $null -ne $_ -and (Test-HordeDeliverSameProcess $_ $target) }).Count -gt 0) { $gate = "hub-spawned by process" }
    elseif ("$($target.label)" -ne "" -and $DeliverTo -ccontains "$($target.label)") { $gate = "opted-in" }
    if ($gate -eq "") {
        return (New-HordeDeliverTarget -Refused ("session " + $tid + " is neither spawned by this hub nor opted in by its label in this node's remote.deliverTo"))
    }
    return (New-HordeDeliverTarget -SessionId $tid -Label "$($target.label)" -Via $via -Gate $gate)
}
