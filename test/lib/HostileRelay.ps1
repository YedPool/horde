# test/lib/HostileRelay.ps1 - a relay that lies, for proving the CLIENT side survives one.
#
# WHY IT EXISTS (relay design 2026-10-09, threat model: "the relay ... can drop, delay or reorder
# messages"). The relay is untrusted, so relays/Port.ps1 must hold up against any answer a relay can
# give, not only the honest ones a real adapter gives in its conformance run. This relay stores
# honestly and answers dishonestly: every read can be reordered, repeated, thinned, padded with stale
# items, salted with malformed ones, overfilled past the batch asked for, or made to throw.
#
# WHY IT LIVES UNDER test/ AND NOT relays/. Every folder under relays/ is an adapter the conformance
# suite holds to the honest contract and a caller may pick. This one fails that contract on purpose,
# and it declines every capability (test/fixtures/relays/hostile/capabilities.json), so even if it
# were loaded no caller that requires anything could pick it. It is registered through the port like
# any relay, because the port refuses anything that was not.
#
# Faults, set with Set-HordeHostileRelayFaults (any combination; none means honest):
#   reorder    the batch reversed
#   duplicate  every item twice
#   drop       every item with an even seq left out
#   stale      the items at or before the cursor served again in front
#   conflict   a second item under the first item's seq, with other text
#   garbage    malformed items mixed in (see New-HordeHostileRelayGarbage)
#   overbatch  every item after the cursor, ignoring the batch size asked for
#   throw      the read throws
#   bad-answer the read answers with something that is not a tristate answer
#
# Requires relays/Port.ps1 to be loaded first.

$script:HordeHostileRelayFolder = Join-Path (Split-Path -Parent $PSScriptRoot) "fixtures\relays\hostile"
$script:HordeHostileRelayStore = @{}
$script:HordeHostileRelayFaults = @()

function Reset-HordeHostileRelay {
    $script:HordeHostileRelayStore = @{}
    $script:HordeHostileRelayFaults = @()
}

function Set-HordeHostileRelayFaults {
    param([AllowEmptyCollection()][string[]]$Faults = @())
    $script:HordeHostileRelayFaults = @($Faults)
}

function New-HordeHostileRelayGarbage {
    # One of each kind of malformed item a relay could send, each aimed at one check of the port.
    param([long]$Since)
    $n = $Since + 1
    return @(
        $null,
        "a bare string",
        [pscustomobject]@{ seq = "$n"; key = "k-text-seq"; text = "seq as text" },
        [pscustomobject]@{ seq = [double]$n; key = "k-double-seq"; text = "seq as a double" },
        [pscustomobject]@{ seq = -1; key = "k-negative"; text = "negative seq" },
        [pscustomobject]@{ seq = [long]9007199254740992; key = "k-huge"; text = "seq past 2^53-1" },
        [pscustomobject]@{ key = "k-no-seq"; text = "no seq" },
        [pscustomobject]@{ seq = $n; key = "bad key with spaces"; text = "bad key" },
        [pscustomobject]@{ seq = $n; key = "k-non-ascii"; text = ("caf" + [char]0x00e9) },
        [pscustomobject]@{ seq = $n; key = "k-line-break"; text = "two`nlines" },
        [pscustomobject]@{ seq = $n; key = "k-empty"; text = "" },
        [pscustomobject]@{ seq = $n; key = "k-oversize"; text = ("x" * 4097) },
        [pscustomobject]@{ seq = $n; key = "k-number-text"; text = 42 }
    )
}

function Get-HordeHostileRelayBatch {
    param([string]$Mailbox, [long]$Since, [int]$Max)
    $faults = $script:HordeHostileRelayFaults
    if ($faults -ccontains "throw") { throw "the hostile relay threw on purpose" }
    if ($faults -ccontains "bad-answer") { return "not an answer" }
    $all = @()
    if ($script:HordeHostileRelayStore.ContainsKey($Mailbox)) { $all = @($script:HordeHostileRelayStore[$Mailbox]) }
    $after = @($all | Where-Object { $_.seq -gt $Since })
    if (-not ($faults -ccontains "overbatch")) { $after = @($after | Select-Object -First $Max) }
    if ($faults -ccontains "drop") { $after = @($after | Where-Object { ($_.seq % 2) -ne 0 }) }
    $out = New-Object System.Collections.ArrayList
    if ($faults -ccontains "stale") { foreach ($i in @($all | Where-Object { $_.seq -le $Since })) { [void]$out.Add($i) } }
    foreach ($i in $after) {
        [void]$out.Add($i)
        if ($faults -ccontains "duplicate") { [void]$out.Add([pscustomobject]@{ seq = $i.seq; key = $i.key; text = $i.text }) }
    }
    if ($faults -ccontains "conflict" -and $after.Count -gt 0) { [void]$out.Add([pscustomobject]@{ seq = $after[0].seq; key = $after[0].key; text = "forged conflicting text" }) }
    if ($faults -ccontains "garbage") { foreach ($g in @(New-HordeHostileRelayGarbage -Since $Since)) { [void]$out.Add($g) } }
    $items = @($out.ToArray())
    if ($faults -ccontains "reorder") { [array]::Reverse($items) }
    return (New-HordeKnown -Value ([pscustomobject]@{ items = $items }) -ObservedAt ([datetime]::UtcNow))
}

$null = Register-HordeRelay -Folder $script:HordeHostileRelayFolder `
    -Connect { param($Options) return (New-HordeKnown -Value @{ hostile = $true }) } `
    -Put {
        param($State, [string]$Mailbox, [string]$Key, [string]$Text)
        if (-not $script:HordeHostileRelayStore.ContainsKey($Mailbox)) { $script:HordeHostileRelayStore[$Mailbox] = New-Object System.Collections.ArrayList }
        $list = $script:HordeHostileRelayStore[$Mailbox]
        foreach ($i in $list) { if ($i.key -ceq $Key) { return (New-HordeKnown -Value ([pscustomobject]@{ seq = $i.seq; duplicate = $true })) } }
        $seq = [long]($list.Count + 1)
        [void]$list.Add([pscustomobject]@{ seq = $seq; key = $Key; text = $Text })
        return (New-HordeKnown -Value ([pscustomobject]@{ seq = $seq; duplicate = $false }))
    } `
    -Get { param($State, [string]$Mailbox, [long]$Since, [int]$Max) return (Get-HordeHostileRelayBatch -Mailbox $Mailbox -Since $Since -Max $Max) } `
    -Watch { param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs) return (Get-HordeHostileRelayBatch -Mailbox $Mailbox -Since $Since -Max $Max) } `
    -Ack { param($State, [string]$Mailbox, [long]$Through) return (New-HordeKnown -Value ([pscustomobject]@{ through = $Through })) }
