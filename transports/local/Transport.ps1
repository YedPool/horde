# transports/local - the degenerate transport: hub and node on the same machine, over a named pipe.
#
# WHY IT EXISTS (remote-sessions design 2.3, decision 1). The hub is always also a node, and its own
# sessions go through the same protocol as a remote node's, over this transport. So there is one
# actuation path, and the remote path is exercised by every local action. It is also the transport
# the protocol's own tests (tier T1) run on, with no ssh at all.
#
# THE ENDPOINT is the node's device id, one lowercase UUID; the pipe is \\.\pipe\horde-node-<deviceId>,
# in the global namespace. The node listens; the hub dials.
#
# WHO MAY CONNECT (auth.peer). Measured 2026-09-30 on Windows PowerShell 5.1.26100.9444:
#   - The server creates the pipe with a protected ACL (nothing inherited) holding exactly two rules:
#     Allow FullControl to the owning user's SID, Deny FullControl to NETWORK (S-1-5-2). Read back
#     from the live pipe, those are the only two rules. So no other local user, and no logon over the
#     network, can open it; a client whose ACL check fails gets "Access to the path is denied".
#   - A pipe name is first come, first served: any user may create \\.\pipe\horde-node-<id> before the
#     node does (squatting). So the CLIENT also checks the pipe's owner, read through its own handle,
#     is its own user, and refuses the link otherwise. The server creates at most one instance, so if
#     the name is already taken its creation fails ("All pipe instances are busy", Win32 231) and it
#     reports the name as in use rather than sharing it.
#   - GetImpersonationUserName on the server throws until a byte has been read from the client, so the
#     server's knowledge of its peer is the ACL, and it says so in the peer record.
#
# KEEPALIVE. A read is always pending on the pipe; when the far end's handle closes - its process
# exited, crashed, or closed the link - that read completes with 0 bytes at once (measured: under 2 s
# in the probe, immediately in practice). So a dead peer shows without a frame being sent.
#
# Nothing here is used by the port's code by name: the port loads every transports/*/Transport.ps1.

$script:HordeLocalFolder = $PSScriptRoot
$script:HordeLocalPipeRoot = '\\.\pipe\'
$script:HordeLocalPipePrefix = "horde-node-"
$script:HordeLocalIdPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$script:HordeLocalBufferBytes = 65536

function Get-HordeLocalPipeName {
    # The pipe for a device id, or $null when the id is not one lowercase UUID - so "..\x" or a name
    # with a wildcard can never become a pipe name.
    param([string]$DeviceId)
    if ($DeviceId -cnotmatch $script:HordeLocalIdPattern) { return $null }
    return ($script:HordeLocalPipePrefix + $DeviceId)
}

function Get-HordeLocalUserSid {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().User
}

function New-HordeLocalPipeSecurity {
    # This user, full control; NETWORK, denied; nothing inherited. See the file header.
    $sec = New-Object System.IO.Pipes.PipeSecurity
    $sec.SetAccessRuleProtection($true, $false)
    $me = Get-HordeLocalUserSid
    $sec.SetOwner($me)
    $sec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($me, [System.IO.Pipes.PipeAccessRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow)))
    $net = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::NetworkSid, $null)
    $sec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($net, [System.IO.Pipes.PipeAccessRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Deny)))
    return $sec
}

function Test-HordeLocalPipeOwner {
    # Does the pipe's owner match the user we expect? A pipe owned by anyone else was created by
    # someone else, whatever its name says.
    param($Owner, $Expected)
    if ($null -eq $Owner -or $null -eq $Expected) { return $false }
    return ("$Owner" -ceq "$Expected")
}

function New-HordeLocalChannel {
    # A byte channel over a connected pipe stream. One read is kept pending, so a closed far end is
    # seen at once (keepalive).
    param($Stream)
    $state = @{ stream = $Stream; buf = (New-Object byte[] $script:HordeLocalBufferBytes); pending = $null }
    return [pscustomobject]@{
        state = $state
        read = {
            param($Channel, [int]$WaitMs)
            $st = $Channel.state
            try {
                if ($null -eq $st.pending) { $st.pending = $st.stream.ReadAsync($st.buf, 0, $st.buf.Length) }
                if (-not $st.pending.Wait([Math]::Max(0, $WaitMs))) { return [pscustomobject]@{ kind = "none"; bytes = $null; reason = "" } }
                $n = $st.pending.Result
            } catch {
                $st.pending = $null
                $e = $_.Exception
                while ($null -ne $e.InnerException) { $e = $e.InnerException }
                return [pscustomobject]@{ kind = "error"; bytes = $null; reason = $e.Message }
            }
            $st.pending = $null
            if ($n -eq 0) { return [pscustomobject]@{ kind = "eof"; bytes = $null; reason = "" } }
            $copy = New-Object byte[] $n
            [Array]::Copy($st.buf, $copy, $n)
            return [pscustomobject]@{ kind = "data"; bytes = $copy; reason = "" }
        }
        write = {
            param($Channel, [byte[]]$Bytes)
            # Asynchronous, so the port can bound the wait: a pipe write blocks until the far end
            # reads once its buffer is full, and a far end that never reads must not hang the caller.
            return $Channel.state.stream.WriteAsync($Bytes, 0, $Bytes.Length)
        }
        close = {
            param($Channel)
            try { $Channel.state.stream.Dispose() } catch { }
        }
    }
}

function New-HordeLocalResult {
    param([bool]$Ok, $Channel = $null, $Peer = $null, $Listener = $null, [string]$Reason = "")
    return [pscustomobject]@{ ok = $Ok; channel = $Channel; peer = $Peer; listener = $Listener; reason = $Reason }
}

$null = Register-HordeTransport -Folder $script:HordeLocalFolder `
    -Open {
        param($Endpoint, [int]$TimeoutMs)
        $pipe = Get-HordeLocalPipeName -DeviceId $Endpoint
        if ($null -eq $pipe) { return (New-HordeLocalResult -Ok $false -Reason ("'" + $Endpoint + "' is not a device id: one lowercase UUID")) }
        $cli = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipe, [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous)
        try { $cli.Connect([Math]::Max(1, $TimeoutMs)) }
        catch {
            $cli.Dispose()
            $e = $_.Exception
            while ($null -ne $e.InnerException) { $e = $e.InnerException }
            if ($e -is [System.TimeoutException]) { return (New-HordeLocalResult -Ok $false -Reason ("no node answered on " + $pipe + " within " + $TimeoutMs + " ms")) }
            if ($e -is [System.UnauthorizedAccessException]) { return (New-HordeLocalResult -Ok $false -Reason ("refused: the ACL of " + $pipe + " does not admit this user")) }
            return (New-HordeLocalResult -Ok $false -Reason ("could not connect to " + $pipe + ": " + $e.Message))
        }
        $me = Get-HordeLocalUserSid
        $owner = $null
        try { $owner = $cli.GetAccessControl().GetOwner([System.Security.Principal.SecurityIdentifier]) } catch { }
        if (-not (Test-HordeLocalPipeOwner -Owner $owner -Expected $me)) {
            $cli.Dispose()
            return (New-HordeLocalResult -Ok $false -Reason ("refused: " + $pipe + " is owned by '" + $owner + "', not by this user; it may be a squatter"))
        }
        $peer = [pscustomobject]@{ verified = $true; identity = "$me"; how = "the pipe's owner is this user" }
        return (New-HordeLocalResult -Ok $true -Channel (New-HordeLocalChannel -Stream $cli) -Peer $peer)
    } `
    -Probe {
        param($Endpoint)
        $pipe = Get-HordeLocalPipeName -DeviceId $Endpoint
        if ($null -eq $pipe) { return (New-HordeUnknown -Reason ("'" + $Endpoint + "' is not a device id")) }
        # A directory listing of the pipe namespace, filtered to this one name. It opens nothing: a
        # connect would take the server's only instance, and File.Exists on a pipe path connects.
        $hits = @([System.IO.Directory]::EnumerateFiles($script:HordeLocalPipeRoot, $pipe))
        if ($hits.Count -gt 0) { return (New-HordeKnown -Value $true -ObservedAt ([datetime]::UtcNow)) }
        return (New-HordeKnown -Value $false -ObservedAt ([datetime]::UtcNow))
    } `
    -Listen {
        param($Endpoint)
        $pipe = Get-HordeLocalPipeName -DeviceId $Endpoint
        if ($null -eq $pipe) { return (New-HordeLocalResult -Ok $false -Reason ("'" + $Endpoint + "' is not a device id: one lowercase UUID")) }
        $state = @{ pipe = $pipe; server = $null; wait = $null }
        try { $state.server = New-Object System.IO.Pipes.NamedPipeServerStream($pipe, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous, $script:HordeLocalBufferBytes, $script:HordeLocalBufferBytes, (New-HordeLocalPipeSecurity)) }
        catch {
            $e = $_.Exception
            while ($null -ne $e.InnerException) { $e = $e.InnerException }
            return (New-HordeLocalResult -Ok $false -Reason ($pipe + " is already in use (" + $e.Message + ")"))
        }
        return (New-HordeLocalResult -Ok $true -Listener $state)
    } `
    -Accept {
        param($ListenerState, [int]$TimeoutMs)
        $st = $ListenerState
        if ($null -eq $st.server) {
            # The last accepted link took the pipe instance with it. One instance at a time: the next
            # is created only when asked for, and fails while the previous link is still open.
            try { $st.server = New-Object System.IO.Pipes.NamedPipeServerStream($st.pipe, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous, $script:HordeLocalBufferBytes, $script:HordeLocalBufferBytes, (New-HordeLocalPipeSecurity)) }
            catch {
                $e = $_.Exception
                while ($null -ne $e.InnerException) { $e = $e.InnerException }
                return (New-HordeLocalResult -Ok $false -Reason ($st.pipe + " cannot take another link now (" + $e.Message + ")"))
            }
        }
        if ($null -eq $st.wait) { $st.wait = $st.server.WaitForConnectionAsync() }
        try { $came = $st.wait.Wait([Math]::Max(0, $TimeoutMs)) }
        catch {
            $st.wait = $null
            try { $st.server.Dispose() } catch { }
            $st.server = $null
            return (New-HordeLocalResult -Ok $false -Reason ("waiting for a peer failed: " + $_.Exception.InnerException.Message))
        }
        # Not connected in time: the wait stays pending on the same instance for the next call.
        if (-not $came) { return (New-HordeLocalResult -Ok $false -Reason ("no peer connected within " + $TimeoutMs + " ms")) }
        $server = $st.server
        $st.server = $null
        $st.wait = $null
        $peer = [pscustomobject]@{ verified = $true; identity = "$(Get-HordeLocalUserSid)"; how = "admitted by the pipe's ACL: this user only, no network logons" }
        return (New-HordeLocalResult -Ok $true -Channel (New-HordeLocalChannel -Stream $server) -Peer $peer)
    } `
    -Stop {
        param($ListenerState)
        if ($null -ne $ListenerState.server) { try { $ListenerState.server.Dispose() } catch { } }
        $ListenerState.server = $null
        $ListenerState.wait = $null
    }
