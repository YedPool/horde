# test/lib/CountingRelay.ps1 - an honest relay in memory that COUNTS EVERY REQUEST made of it, for proving
# what the runner costs a relay that counts them.
#
# WHY IT EXISTS (cli/RelayRun.ps1, SENDING DURING THE WATCH). The hosted relay allows an account 20,000
# requests a day, and an always-on machine's watches are already 1,440 of them. The runner now looks for
# something to send while its watch is open, and the whole point is that this costs the relay NOTHING
# unless something is sent. That is a claim about a number of requests, so it is tested by counting
# them, in a relay where every one is seen: the real hosted relay must never be contacted by a suite, and
# the disk relay (relays/local) has no notion of a request at all.
#
# WHAT IT IS. A relay registered through the port like any other, because the port refuses anything that
# was not. It stores honestly, in this process's memory, and waits honestly: a watch returns within its
# 20 ms poll of a put, and runs out at its own time. It watches in slices (relays/Port.ps1, A WATCH IN
# SLICES), and a suite can take that away for a while to watch the same thing through the blocking
# watch (Set-HordeCountingRelaySlices), which is how "exactly as before" is shown and not assumed.
#
# WHAT IT RECORDS, in order, in one log a suite reads with Get-HordeCountingRelayLog:
#   A REQUEST - what a relay that counts would count:
#     put          one item put (also one refused, and one that was a duplicate) - and one put that also
#                  trims its sender's stream (relays/Port.ps1, A SENDER TRIMS ITS OWN STREAM): THE TRIM
#                  IS NOT A REQUEST OF ITS OWN, which is the whole point of carrying it on a put
#     get          one read
#     watch        one blocking watch, begun
#     watch-open   one watch in slices, opened: THE ONE REQUEST THE WHOLE WATCH COSTS
#     ack          one ack
#   NOT A REQUEST - what happens on this side of the wire, and costs the relay nothing:
#     wait         one slice of an open watch waited on
#     watch-close  an open watch let go of
#     watch-end    a blocking watch returned
# Each entry is { n; op; request; mailbox; at; keepFrom } - at the moment it was made (UTC), so a suite can say how
# long after something a put was made.
#
# WHAT A SUITE CAN MAKE HAPPEN DURING A WATCH. Set-HordeCountingRelayHook hands over a block that is run
# at the start of every slice, and every 20 ms poll of a blocking watch, with how many times it has
# been run in this watch (1, 2, ...). The watch is in flight while it runs - which is exactly when a
# Thrall writes a reply in real life - so a suite writes its reply there. The block runs in the test's
# own process and thread; it must not call the relay's watch itself.
#
# FAULTS, each off unless set (Set-HordeCountingRelayFaults):
#   refuse-put  every put is refused, as an unknown (and still counted: the relay was asked)
#   instant     a slice comes back at once without waiting, "not ended" - a relay that would make a
#               caller spin if the caller let it
#   full        every put is refused as the hosted relay refuses one into a full mailbox: unknown, with
#               status 507 (and still counted)
#   busy        every put is refused as a relay refuses one for a rate: unknown, with status 429 (and
#               still counted) - a refusal that carries a status and is NOT a full mailbox
#   no-trim     a put that asks for a trim is taken and nothing is trimmed, and the answer says nothing
#               of a trim: the hosted relay as it was deployed before it could
# And Set-HordeCountingRelayTrim -On $false takes the trimming block away altogether, as the watch in
# slices can be taken away: a relay that never had it. Set-HordeCountingRelayPutsLeft -Puts <n> lets n
# more puts through and refuses every one after them (still counted), until it is set to -1: how a
# snapshot of several pages is left with only some of them at the relay.
# Set-HordeCountingRelayCap -Items <n> gives every mailbox THE HOSTED RELAY'S OWN CAP RULE, not a blanket
# refusal: a put that would leave more than n items is refused with 507 - counted after what that put's
# own trim would delete, a put with no trim getting no such credit, a duplicate always taken, and a
# refused put trimming nothing. 0 is no cap. Set-HordeCountingRelayFullFor -Channels names the channels
# whose envelopes are refused with 507 while every other's are taken: a mailbox that is full for a large
# envelope and not for a small one. A put's log entry also says what it asked to keep from (keepFrom).
# Set-HordeCountingRelayTextChars makes it hold shorter texts, so that a channel that pages its body
# makes several pages of a little; Reset puts back the declared limit.
#
# WHY IT LIVES UNDER test/ AND NOT relays/. Every folder under relays/ is an adapter a caller may pick and
# the conformance suite holds to its claims. This one declines every capability
# (test/fixtures/relays/counting/capabilities.json), so no caller that requires anything picks it.
#
# Requires relays/Port.ps1 to be loaded first.

$script:HordeCountingRelayFolder = Join-Path (Split-Path -Parent $PSScriptRoot) "fixtures\relays\counting"
$script:HordeCountingRelayStore = @{}
# The highest seq acked in each mailbox: what is at or before it is no longer handed over, so a run that
# starts again from cursor 0 is not handed what an earlier run already acked.
$script:HordeCountingRelayFloor = @{}
# The highest seq ever given in each mailbox: a trim deletes items, and no number is used twice.
$script:HordeCountingRelayHead = @{}
# A key that names its stream, as relays/Port.ps1 reads one.
$script:HordeCountingRelayStreamKeyPattern = '\A([0-9a-f]{32}/[a-z][a-z0-9-]{0,31}/)([1-9][0-9]{0,15})/[0-9a-f]{24}\z'
$script:HordeCountingRelayTrimBlock = $null
# How many more puts are let through before every one is refused; -1 is no such limit.
$script:HordeCountingRelayPutsLeft = -1
# The most items a mailbox holds, 0 for no cap; and the channels refused as full whatever it holds.
$script:HordeCountingRelayCap = 0
$script:HordeCountingRelayFullFor = @()
$script:HordeCountingRelayDeclaredTextChars = 0
$script:HordeCountingRelayLog = New-Object System.Collections.ArrayList
$script:HordeCountingRelayHook = $null
$script:HordeCountingRelayFaults = @()
$script:HordeCountingRelayPollMs = 20
$script:HordeCountingRelayRequests = @("put", "get", "watch", "watch-open", "ack")
# The three slice blocks, kept so a suite can take them away from the registered relay and put them back.
$script:HordeCountingRelaySliceBlocks = $null

function Reset-HordeCountingRelay {
    # Empty mailboxes, an empty log, no hook, no fault, and the watch in slices as it was registered.
    $script:HordeCountingRelayStore = @{}
    $script:HordeCountingRelayFloor = @{}
    $script:HordeCountingRelayHead = @{}
    $script:HordeCountingRelayLog = New-Object System.Collections.ArrayList
    $script:HordeCountingRelayHook = $null
    $script:HordeCountingRelayFaults = @()
    Set-HordeCountingRelaySlices -On $true
    Set-HordeCountingRelayTrim -On $true
    $script:HordeCountingRelayPutsLeft = -1
    $script:HordeCountingRelayCap = 0
    $script:HordeCountingRelayFullFor = @()
    if ($script:HordeCountingRelayDeclaredTextChars -gt 0) { (Get-HordeRelay -Name "counting").limits.maxTextChars = $script:HordeCountingRelayDeclaredTextChars }
}

function Set-HordeCountingRelayPutsLeft {
    param([Parameter(Mandatory = $true)][int]$Puts)
    $script:HordeCountingRelayPutsLeft = $Puts
}

function Set-HordeCountingRelayCap {
    param([Parameter(Mandatory = $true)][int]$Items)
    $script:HordeCountingRelayCap = $Items
}

function Set-HordeCountingRelayFullFor {
    param([AllowEmptyCollection()][string[]]$Channels = @())
    $script:HordeCountingRelayFullFor = @($Channels)
}

function Set-HordeCountingRelayTextChars {
    # The longest text the registered relay holds, for a suite that wants small pages (the header).
    param([Parameter(Mandatory = $true)][int]$Chars)
    $r = Get-HordeRelay -Name "counting"
    if ($script:HordeCountingRelayDeclaredTextChars -eq 0) { $script:HordeCountingRelayDeclaredTextChars = [int]$r.limits.maxTextChars }
    $r.limits.maxTextChars = $Chars
}

function Set-HordeCountingRelayTrim {
    # Give the registered relay its trimming put, or take it away: without it the port makes the plain
    # put, as it does on every relay that never had one.
    param([Parameter(Mandatory = $true)][bool]$On)
    $r = Get-HordeRelay -Name "counting"
    if ($null -eq $script:HordeCountingRelayTrimBlock) { $script:HordeCountingRelayTrimBlock = $r.putKeeping }
    $r.putKeeping = $(if ($On) { $script:HordeCountingRelayTrimBlock } else { $null })
}

function Get-HordeCountingRelayHeld {
    # The items a mailbox holds now, in seq order - what the hosted relay's cap counts - looked at from
    # this side of the wire: it is no request, and nothing is logged.
    param([Parameter(Mandatory = $true)][string]$Mailbox)
    if (-not $script:HordeCountingRelayStore.ContainsKey($Mailbox)) { return @() }
    return @($script:HordeCountingRelayStore[$Mailbox].ToArray())
}

function Add-HordeCountingRelayItem {
    # The put, honest, and with -KeepFrom over 0 the sender's trim after it: known { seq; duplicate },
    # and trimmed when a trim was asked and the fault no-trim is off.
    param([string]$Mailbox, [string]$Key, [string]$Text, [long]$KeepFrom = 0)
    Add-HordeCountingRelayEntry -Op "put" -Mailbox $Mailbox -KeepFrom $KeepFrom
    if ($script:HordeCountingRelayFaults -ccontains "refuse-put") { return (New-HordeUnknown -Reason "put refused by the counting relay, on purpose") }
    if ($script:HordeCountingRelayPutsLeft -eq 0) { return (New-HordeUnknown -Reason "put refused by the counting relay: no more puts are let through, on purpose") }
    if ($script:HordeCountingRelayPutsLeft -gt 0) { $script:HordeCountingRelayPutsLeft-- }
    if ($script:HordeCountingRelayFaults -ccontains "busy") {
        $busy = New-HordeUnknown -Reason "the counting relay answered the put with 429: too many puts, on purpose"
        $busy | Add-Member -NotePropertyName status -NotePropertyValue 429
        return $busy
    }
    if ($script:HordeCountingRelayFaults -ccontains "full") {
        $full = New-HordeUnknown -Reason "the counting relay answered the put with 507: this mailbox holds its most, on purpose"
        $full | Add-Member -NotePropertyName status -NotePropertyValue 507
        return $full
    }
    if (-not $script:HordeCountingRelayStore.ContainsKey($Mailbox)) { $script:HordeCountingRelayStore[$Mailbox] = New-Object System.Collections.ArrayList; $script:HordeCountingRelayHead[$Mailbox] = [long]0 }
    $list = $script:HordeCountingRelayStore[$Mailbox]
    $named = [regex]::Match($Key, $script:HordeCountingRelayStreamKeyPattern)
    if ($named.Success -and $script:HordeCountingRelayFullFor -ccontains $named.Groups[1].Value.Split([char]'/')[1]) {
        $forIt = New-HordeUnknown -Reason "the counting relay answered the put with 507: this mailbox holds its most for this channel's envelopes, on purpose"
        $forIt | Add-Member -NotePropertyName status -NotePropertyValue 507
        return $forIt
    }
    $seq = [long]0
    $duplicate = $false
    foreach ($i in $list) { if ($i.key -ceq $Key) { $seq = $i.seq; $duplicate = $true } }
    # What this put's own trim would delete: found first, deleted last, as the hosted relay does.
    $trims = ($KeepFrom -gt 0 -and $script:HordeCountingRelayFaults -cnotcontains "no-trim")
    $older = @()
    if ($trims) {
        $stream = $named.Groups[1].Value
        $older = @($list | Where-Object { $m = [regex]::Match($_.key, $script:HordeCountingRelayStreamKeyPattern); $m.Success -and $m.Groups[1].Value -ceq $stream -and [long]$m.Groups[2].Value -lt $KeepFrom })
    }
    if (-not $duplicate) {
        # THE CAP, as the hosted relay keeps it: what the trim frees counts first, and a refused put trims nothing.
        if ($script:HordeCountingRelayCap -gt 0 -and ($list.Count - $older.Count + 1) -gt $script:HordeCountingRelayCap) {
            $capped = New-HordeUnknown -Reason ("the counting relay answered the put with 507: this mailbox holds " + $list.Count + " envelopes, its most")
            $capped | Add-Member -NotePropertyName status -NotePropertyValue 507
            return $capped
        }
        $seq = [long]$script:HordeCountingRelayHead[$Mailbox] + 1
        $script:HordeCountingRelayHead[$Mailbox] = $seq
        [void]$list.Add([pscustomobject]@{ seq = $seq; key = $Key; text = $Text })
    }
    $out = [pscustomobject]@{ seq = $seq; duplicate = $duplicate }
    if ($trims) {
        foreach ($o in $older) { $list.Remove($o) }
        $out | Add-Member -NotePropertyName trimmed -NotePropertyValue ([long]$older.Count)
    }
    return (New-HordeKnown -Value $out -ObservedAt ([datetime]::UtcNow))
}

function Clear-HordeCountingRelayLog {
    $script:HordeCountingRelayLog = New-Object System.Collections.ArrayList
}

function Get-HordeCountingRelayLog {
    # Every entry so far, in order; -Requests only what a relay that counts would count.
    param([switch]$Requests)
    $all = @($script:HordeCountingRelayLog.ToArray())
    if ($Requests) { return @($all | Where-Object { $_.request }) }
    return $all
}

function Set-HordeCountingRelayHook {
    # The block run at the start of every slice, and every poll of a blocking watch (the header).
    # $null takes it away.
    param([scriptblock]$Hook = $null)
    $script:HordeCountingRelayHook = $Hook
}

function Set-HordeCountingRelayFaults {
    param([AllowEmptyCollection()][string[]]$Faults = @())
    $script:HordeCountingRelayFaults = @($Faults)
}

function Set-HordeCountingRelaySlices {
    # Give the registered relay its watch in slices, or take it away: without it the port watches by the
    # blocking watch, as it does every relay that never had one.
    param([Parameter(Mandatory = $true)][bool]$On)
    $r = Get-HordeRelay -Name "counting"
    if ($null -eq $script:HordeCountingRelaySliceBlocks) { $script:HordeCountingRelaySliceBlocks = @($r.watchOpen, $r.watchWait, $r.watchClose) }
    if ($On) { $r.watchOpen = $script:HordeCountingRelaySliceBlocks[0]; $r.watchWait = $script:HordeCountingRelaySliceBlocks[1]; $r.watchClose = $script:HordeCountingRelaySliceBlocks[2] }
    else { $r.watchOpen = $null; $r.watchWait = $null; $r.watchClose = $null }
}

function Add-HordeCountingRelayEntry {
    param([string]$Op, [string]$Mailbox = "", [long]$KeepFrom = 0)
    [void]$script:HordeCountingRelayLog.Add([pscustomobject]@{ n = $script:HordeCountingRelayLog.Count + 1; op = $Op; request = ($script:HordeCountingRelayRequests -ccontains $Op); mailbox = $Mailbox; at = [datetime]::UtcNow; keepFrom = $KeepFrom })
}

function Get-HordeCountingRelayAfter {
    # The items of a mailbox after -Since that no ack has covered, at most -Max: honest, in order.
    param([string]$Mailbox, [long]$Since, [int]$Max)
    if (-not $script:HordeCountingRelayStore.ContainsKey($Mailbox)) { return @() }
    $floor = [long]0
    if ($script:HordeCountingRelayFloor.ContainsKey($Mailbox)) { $floor = [long]$script:HordeCountingRelayFloor[$Mailbox] }
    return @(@($script:HordeCountingRelayStore[$Mailbox]) | Where-Object { $_.seq -gt $Since -and $_.seq -gt $floor } | Select-Object -First $Max)
}

function Wait-HordeCountingRelayWatch {
    # One slice of a watch (-WaitMs), or with -Whole the whole of a blocking one: { ended; items }.
    param($Watch, [int]$WaitMs, [switch]$Whole)
    $slice = [System.Diagnostics.Stopwatch]::StartNew()
    $first = $true
    while ($true) {
        # THE HOOK, while the watch is in flight: once a slice, and every poll of a blocking watch.
        if ($null -ne $script:HordeCountingRelayHook -and ($first -or $Whole)) { $Watch.hooked++; $null = & $script:HordeCountingRelayHook $Watch.hooked }
        $first = $false
        $items = @(Get-HordeCountingRelayAfter -Mailbox $Watch.mailbox -Since $Watch.since -Max $Watch.max)
        if ($items.Count -gt 0) { return [pscustomobject]@{ ended = $true; items = $items } }
        $left = $Watch.timeoutMs - $Watch.began.ElapsedMilliseconds
        if ($left -le 0) { return [pscustomobject]@{ ended = $true; items = @() } }
        $leftOfSlice = $WaitMs - $slice.ElapsedMilliseconds
        if (-not $Whole -and ($leftOfSlice -le 0 -or $script:HordeCountingRelayFaults -ccontains "instant")) { return [pscustomobject]@{ ended = $false; items = @() } }
        $nap = [Math]::Min($script:HordeCountingRelayPollMs, $left)
        if (-not $Whole) { $nap = [Math]::Min($nap, $leftOfSlice) }
        Start-Sleep -Milliseconds ([Math]::Max(1, $nap))
    }
}

$null = Register-HordeRelay -Folder $script:HordeCountingRelayFolder `
    -Connect { param($Options) return (New-HordeKnown -Value @{ counting = $true }) } `
    -Put {
        param($State, [string]$Mailbox, [string]$Key, [string]$Text)
        return (Add-HordeCountingRelayItem -Mailbox $Mailbox -Key $Key -Text $Text)
    } `
    -PutKeeping {
        param($State, [string]$Mailbox, [string]$Key, [string]$Text, [long]$KeepFrom)
        return (Add-HordeCountingRelayItem -Mailbox $Mailbox -Key $Key -Text $Text -KeepFrom $KeepFrom)
    } `
    -Get {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max)
        Add-HordeCountingRelayEntry -Op "get" -Mailbox $Mailbox
        return (New-HordeKnown -Value ([pscustomobject]@{ items = @(Get-HordeCountingRelayAfter -Mailbox $Mailbox -Since $Since -Max $Max) }) -ObservedAt ([datetime]::UtcNow))
    } `
    -Watch {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
        Add-HordeCountingRelayEntry -Op "watch" -Mailbox $Mailbox
        $w = [pscustomobject]@{ mailbox = $Mailbox; since = $Since; max = $Max; timeoutMs = $TimeoutMs; began = [System.Diagnostics.Stopwatch]::StartNew(); hooked = 0 }
        $got = Wait-HordeCountingRelayWatch -Watch $w -WaitMs $TimeoutMs -Whole
        Add-HordeCountingRelayEntry -Op "watch-end" -Mailbox $Mailbox
        return (New-HordeKnown -Value $got -ObservedAt ([datetime]::UtcNow))
    } `
    -Ack {
        param($State, [string]$Mailbox, [long]$Through)
        Add-HordeCountingRelayEntry -Op "ack" -Mailbox $Mailbox
        if (-not $script:HordeCountingRelayFloor.ContainsKey($Mailbox) -or [long]$script:HordeCountingRelayFloor[$Mailbox] -lt $Through) { $script:HordeCountingRelayFloor[$Mailbox] = $Through }
        return (New-HordeKnown -Value ([pscustomobject]@{ through = $Through }) -ObservedAt ([datetime]::UtcNow))
    } `
    -WatchOpen {
        param($State, [string]$Mailbox, [long]$Since, [int]$Max, [int]$TimeoutMs)
        Add-HordeCountingRelayEntry -Op "watch-open" -Mailbox $Mailbox
        return (New-HordeKnown -Value ([pscustomobject]@{ mailbox = $Mailbox; since = $Since; max = $Max; timeoutMs = $TimeoutMs; began = [System.Diagnostics.Stopwatch]::StartNew(); hooked = 0 }) -ObservedAt ([datetime]::UtcNow))
    } `
    -WatchWait {
        param($State, $Handle, [int]$WaitMs)
        Add-HordeCountingRelayEntry -Op "wait" -Mailbox $Handle.mailbox
        return (New-HordeKnown -Value (Wait-HordeCountingRelayWatch -Watch $Handle -WaitMs $WaitMs) -ObservedAt ([datetime]::UtcNow))
    } `
    -WatchClose {
        param($State, $Handle)
        Add-HordeCountingRelayEntry -Op "watch-close" -Mailbox $Handle.mailbox
    }
