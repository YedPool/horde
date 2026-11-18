# transports/memory - two ends of a link inside one process, for tests only.
#
# WHY IT EXISTS (remote-sessions design 2.3). The protocol, the journal and the verbs are tested end to
# end without a pipe or a network; this is the pair they run on. It DECLINES auth.peer in its
# capabilities.json, and the production path to a node requires auth.peer
# (Resolve-HordeLinkTransport in transports/Port.ps1), so no production path can pick it. The
# conformance suite proves both halves of that.
#
# SHARED ACROSS RUNSPACES. The listeners live in one process-wide table kept in the AppDomain's data
# slot, not in a script variable, so a second runspace in the same process - which is how the
# conformance suite runs the far end of a link on another thread - sees the same endpoints. Every
# structure in it is a thread-safe .NET collection. Each direction of a link is a queue of byte arrays
# with a semaphore to wait on, and two flags: the writer has closed (the reader drains, then sees
# end-of-stream) and the reader has closed (writes fail).

$script:HordeMemoryFolder = $PSScriptRoot
$script:HordeMemoryKey = "Horde.Transport.Memory.Listeners"
$script:HordeMemoryEndpointPattern = '^[a-z0-9][a-z0-9-]{0,63}$'

function Get-HordeMemoryListeners {
    $domain = [System.AppDomain]::CurrentDomain
    [System.Threading.Monitor]::Enter($domain)
    try {
        $table = $domain.GetData($script:HordeMemoryKey)
        if ($null -eq $table) {
            $table = New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string,object]'
            $domain.SetData($script:HordeMemoryKey, $table)
        }
        return ,$table
    } finally { [System.Threading.Monitor]::Exit($domain) }
}

function New-HordeMemoryDirection {
    return [hashtable]::Synchronized(@{
        queue = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[byte[]]')
        signal = (New-Object System.Threading.SemaphoreSlim(0))
        writerClosed = $false; readerClosed = $false
    })
}

function New-HordeMemoryChannel {
    param($Inbound, $Outbound)
    return [pscustomobject]@{
        state = @{ inbound = $Inbound; outbound = $Outbound }
        read = {
            param($Channel, [int]$WaitMs)
            $in = $Channel.state.inbound
            $got = $null
            for ($pass = 0; $pass -lt 2; $pass++) {
                if ($in.queue.TryDequeue([ref]$got)) { return [pscustomobject]@{ kind = "data"; bytes = $got; reason = "" } }
                if ($in.writerClosed -or $in.readerClosed) { return [pscustomobject]@{ kind = "eof"; bytes = $null; reason = "" } }
                if ($pass -eq 0) { [void]$in.signal.Wait([Math]::Max(0, $WaitMs)) }
            }
            return [pscustomobject]@{ kind = "none"; bytes = $null; reason = "" }
        }
        write = {
            param($Channel, [byte[]]$Bytes)
            $out = $Channel.state.outbound
            if ($out.writerClosed) { throw (New-Object System.IO.IOException("this end of the link is closed")) }
            if ($out.readerClosed) { throw (New-Object System.IO.IOException("the far end closed the link")) }
            $copy = New-Object byte[] $Bytes.Length
            [Array]::Copy($Bytes, $copy, $Bytes.Length)
            $out.queue.Enqueue($copy)
            [void]$out.signal.Release()
            return $null
        }
        close = {
            param($Channel)
            $Channel.state.outbound.writerClosed = $true
            $Channel.state.inbound.readerClosed = $true
            [void]$Channel.state.outbound.signal.Release()
            [void]$Channel.state.inbound.signal.Release()
        }
    }
}

function New-HordeMemoryPeer {
    return [pscustomobject]@{ verified = $false; identity = ""; how = "in-process: the far end is not identified (auth.peer declined)" }
}

function New-HordeMemoryResult {
    param([bool]$Ok, $Channel = $null, $Peer = $null, $Listener = $null, [string]$Reason = "")
    return [pscustomobject]@{ ok = $Ok; channel = $Channel; peer = $Peer; listener = $Listener; reason = $Reason }
}

$null = Register-HordeTransport -Folder $script:HordeMemoryFolder `
    -Open {
        param($Endpoint, [int]$TimeoutMs)
        if ($Endpoint -cnotmatch $script:HordeMemoryEndpointPattern) { return (New-HordeMemoryResult -Ok $false -Reason ("'" + $Endpoint + "' is not an endpoint name")) }
        $l = $null
        if (-not (Get-HordeMemoryListeners).TryGetValue($Endpoint, [ref]$l)) { return (New-HordeMemoryResult -Ok $false -Reason ("nothing is listening on '" + $Endpoint + "'")) }
        $a2b = New-HordeMemoryDirection
        $b2a = New-HordeMemoryDirection
        # Only data crosses to the accepting side - the two queues - never a script block: a script
        # block belongs to the runspace that made it, and the accepting side may be another runspace
        # on another thread (measured: invoking one across runspaces failed with "New-HordeKnown is
        # not recognized"). The accepting side wraps the queues in its own channel.
        $l.pending.Enqueue(@{ inbound = $a2b; outbound = $b2a })
        [void]$l.signal.Release()
        $peer = New-HordeMemoryPeer
        return (New-HordeMemoryResult -Ok $true -Channel (New-HordeMemoryChannel -Inbound $b2a -Outbound $a2b) -Peer $peer)
    } `
    -Probe {
        param($Endpoint)
        if ($Endpoint -cnotmatch $script:HordeMemoryEndpointPattern) { return (New-HordeUnknown -Reason ("'" + $Endpoint + "' is not an endpoint name")) }
        return (New-HordeKnown -Value ((Get-HordeMemoryListeners).ContainsKey($Endpoint)) -ObservedAt ([datetime]::UtcNow))
    } `
    -Listen {
        param($Endpoint)
        if ($Endpoint -cnotmatch $script:HordeMemoryEndpointPattern) { return (New-HordeMemoryResult -Ok $false -Reason ("'" + $Endpoint + "' is not an endpoint name")) }
        $l = [hashtable]::Synchronized(@{ endpoint = $Endpoint; pending = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'); signal = (New-Object System.Threading.SemaphoreSlim(0)) })
        if (-not (Get-HordeMemoryListeners).TryAdd($Endpoint, $l)) { return (New-HordeMemoryResult -Ok $false -Reason ("'" + $Endpoint + "' is already in use")) }
        return (New-HordeMemoryResult -Ok $true -Listener $l)
    } `
    -Accept {
        param($ListenerState, [int]$TimeoutMs)
        # WAIT UNTIL A DIAL IS TAKEN OR THE TIME IS UP, NOT UNTIL THE FIRST WAKE-UP (T-0421). Each dial queues itself
        # and releases the signal once, but an accept that finds a dial already queued takes it without waiting,
        # so that release stays unspent; one wait woke on it, found nothing, and said "no peer connected" at
        # once (measured 0 ms of 1500 in test-transport-conformance). The node's loop reads a quick failure as a
        # broken listener and replaces it, and a dial queued on the old one was never answered.
        $ch = $null
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $ListenerState.pending.TryDequeue([ref]$ch)) {
            $left = [Math]::Max(0, $TimeoutMs) - $clock.ElapsedMilliseconds
            if ($left -le 0) { return (New-HordeMemoryResult -Ok $false -Reason ("no peer connected within " + $TimeoutMs + " ms")) }
            [void]$ListenerState.signal.Wait([int]$left)
        }
        $peer = New-HordeMemoryPeer
        return (New-HordeMemoryResult -Ok $true -Channel (New-HordeMemoryChannel -Inbound $ch.inbound -Outbound $ch.outbound) -Peer $peer)
    } `
    -Stop {
        param($ListenerState)
        # Removed only if the table still holds THIS listener: a stopped listener must not take down
        # a newer one that has since started on the same endpoint.
        $pair = New-Object 'System.Collections.Generic.KeyValuePair[string,object]'($ListenerState.endpoint, $ListenerState)
        [void]([System.Collections.Generic.ICollection[System.Collections.Generic.KeyValuePair[string,object]]](Get-HordeMemoryListeners)).Remove($pair)
    }
