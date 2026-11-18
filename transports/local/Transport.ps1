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
# THE HUB'S OWN PIPE (remote plan R17a). A node on another machine reaches the hub through the hub's
# listener, whose forced command (`horde attach`) relays the session to \\.\pipe\horde-hub-<hubId>, the
# hub id being the hub's device id; transports/local/Relay.ps1 is that relay. Its endpoint is
# "hub:<hubId>". Here the HUB listens and attach dials, and every rule below holds for it unchanged:
# the same ACL, label, first-instance flag and checks of who is at the other end. Only the name
# differs, so a hub, which is always also a node (remote design decision 1), holds both pipes at once.
#
# WHO MAY CONNECT (auth.peer). The pipe is made with CreateNamedPipe (transports/local/Native.ps1),
# because System.IO.Pipes on .NET Framework cannot set what follows. Measured 2026-09-30 on Windows
# PowerShell 5.1.26100.9444 unless said otherwise:
#   - DACL, protected, in canonical order: Deny NETWORK (S-1-5-2) first, then Allow this user's SID
#     full control (0x1F019F, PipeAccessRights.FullControl). No other user can open it.
#   - MANDATORY LABEL, No-Write-Up and No-Read-Up, at the node's OWN integrity level. Without a label a
#     pipe gets the default, No-Write-Up only, and the review of PR #42 measured a LOW-integrity process
#     of this user opening the node's pipe read-only and reading what the node sent. With a fixed
#     Medium label, its second round measured a MEDIUM process adding an instance to a HIGH node's
#     pipe and being the instance the hub reached. At the node's own level, any process below it can
#     neither read, write, nor add an instance.
#   - THE TRUST BOUNDARY IS THIS USER AT THE NODE'S LEVEL. A process of this user at the node's own
#     level can add an instance, and GetNamedPipeServerProcessId names the first instance's creator,
#     not the instance a client reached - so at the same level nothing here can tell which instance the
#     hub got. That process can equally read the user's files, inject into the node, or run as the
#     node; Windows draws no line between them. A per-node secret checked in hello was considered and
#     not added: the remote design's hello (schema/link-frame.v1, step R1) carries none, and any file
#     holding it that the node can read, a process at the node's level can read too, while one below
#     that level is already stopped by the label. The ssh transport's peers are authenticated by
#     enrolled keys instead (plan step R17).
#   - PIPE_REJECT_REMOTE_CLIENTS. Over \\localhost\pipe a connection is a network logon; the previous
#     ACL-only pipe ACCEPTED one (measured: connected in 4 ms), so its NETWORK deny alone did not hold.
#     With the flag the same connect is refused at once as access denied, while an ordinary pipe opened
#     the same way connects - test-local.ps1 measures both.
#   - THE HUB CHECKS WHO IT REACHED. A pipe name is first come, first served, and the review of PR #42
#     measured a low-integrity process of this user creating the node's pipe first: its owner is this
#     user, so the old owner check passed it as verified and the hub sent it session.spawn. Now the
#     client also asks GetNamedPipeServerProcessId who serves the pipe and refuses unless that process
#     runs at an integrity level at least its own and its image is the node's interpreter
#     (Test-HordeLocalNodeImage). The image check alone would not have stopped the reviewer - the
#     squatter was powershell.exe too - which is why integrity is the deciding test. THE IMAGE CHECK IS
#     ADVISORY: it is the first instance's creator's image, so a process at the node's level that
#     adds an instance to the node's real pipe passes it. It refuses a foreign program that made the
#     pipe itself, and nothing relies on it beyond that.
#   - THE NODE CHECKS WHO REACHED IT. On accept, GetNamedPipeClientProcessId gives the client; one
#     whose integrity is below the node's own is disconnected and refused. The label already stops a
#     low client at open; this is the second line.
#   - NO GAP BETWEEN LINKS. Listening creates the first instance with FILE_FLAG_FIRST_PIPE_INSTANCE, so
#     a name someone already holds is refused, not shared. Each accept creates the next waiting instance
#     BEFORE it hands over the connected one, so while the node listens the name is never free. The
#     review of PR #42 found the old code released the name between one link and the next accept.
#   - ONE INSTANCE WAITS AT A TIME, AND THAT LEAVES A WINDOW, documented rather than closed. A client
#     that connects and closes uses up the waiting instance; it is replaced only when the node next
#     calls Accept. The review of PR #42 (round 3) measured a burst of 50 connect-and-close clients
#     making the next open time out until the next accept. Closing it needs instances re-armed the
#     moment a client leaves, which means a thread of the transport's own racing the caller's - not
#     simple, so not done. What bounds it: only a process of this user at the node's own level can
#     connect at all (the label refuses everything below), which is the same trust as the node; the
#     cost is availability, never a wrong peer; and the hub's open fails with a reason and is retried
#     (lifecycle reconnect, remote design 7.1), while the node's serve loop calls Accept again at once.
#   - GetImpersonationUserName throws until a byte is read, so it is not used.
#
# KEEPALIVE. A read is always pending on the pipe; when the far end's handle closes - its process
# exited, crashed, or closed the link - that read completes with 0 bytes at once. So a dead peer shows
# without a frame being sent.
#
# Nothing here is used by the port's code by name: the port loads every transports/*/Transport.ps1.

. (Join-Path $PSScriptRoot "Native.ps1")

$script:HordeLocalFolder = $PSScriptRoot
$script:HordeLocalPipeRoot = '\\.\pipe\'
$script:HordeLocalPipePrefix = "horde-node-"
$script:HordeLocalHubPipePrefix = "horde-hub-"
$script:HordeLocalHubEndpointPrefix = "hub:"
# \A and \z, not ^ and $: in .NET, $ also matches before a final LF (review of PR #39).
$script:HordeLocalIdPattern = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
$script:HordeLocalBufferBytes = 65536
# The interpreters a node runs in: Windows PowerShell 5.1, and PowerShell 7 from its MSI install (remote
# design 12.2; T-0450). Each path is writable only with admin rights, so the bar is the same for both.
# Exactly one pwsh path: no Store package (CONTRIBUTING 16), no preview build, nothing found on PATH.
# ProgramW6432 names the 64-bit Program Files even in a 32-bit process, where ProgramFiles names the x86
# one; where it is not set, ProgramFiles is it.
$script:HordeLocalProgramFiles = $(if ("$env:ProgramW6432" -ne "") { $env:ProgramW6432 } else { $env:ProgramFiles })
$script:HordeLocalNodeImages = @(
    (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"),
    (Join-Path $env:WINDIR "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"),
    (Join-Path $script:HordeLocalProgramFiles "PowerShell\7\pwsh.exe")
)

function Get-HordeLocalPipeName {
    # The pipe for an endpoint, or $null when it is neither a device id (one lowercase UUID: a node's
    # pipe) nor "hub:" followed by one (the hub's pipe) - so "..\x" or a name with a wildcard can never
    # become a pipe name.
    param([string]$DeviceId)
    if ($DeviceId.StartsWith($script:HordeLocalHubEndpointPrefix, [System.StringComparison]::Ordinal)) {
        $hub = $DeviceId.Substring($script:HordeLocalHubEndpointPrefix.Length)
        if ($hub -cnotmatch $script:HordeLocalIdPattern) { return $null }
        return ($script:HordeLocalHubPipePrefix + $hub)
    }
    if ($DeviceId -cnotmatch $script:HordeLocalIdPattern) { return $null }
    return ($script:HordeLocalPipePrefix + $DeviceId)
}

function Get-HordeLocalUserSid {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().User
}

function New-HordeLocalPipeSddl {
    # Owner this user; DACL protected: this user full control, NETWORK denied; label NWNR at THIS
    # process's own integrity level, as its SID S-1-16-<rid> (SDDL reads it back as LW, ME, HI or SI).
    # Not a fixed Medium: under ME a Medium process of this user added an instance to a High node's
    # pipe, and since GetNamedPipeServerProcessId names the first instance's creator, not the instance
    # a client reached, the hub accepted the adder and sent it session.spawn (review of PR #42, round
    # 2; measured: HI refuses the Medium add, ME allows it).
    $me = "$(Get-HordeLocalUserSid)"
    # The deny comes first: Windows reads a DACL in order and canonical order puts explicit denies
    # before allows. The first version wrote allow-then-deny, which reads back as non-canonical
    # (review of PR #42, round 2).
    return ("O:" + $me + "D:P(D;;0x1f019f;;;NU)(A;;0x1f019f;;;" + $me + ")S:(ML;;NWNR;;;S-1-16-" + (Get-HordeLocalOwnIntegrity) + ")")
}

function Test-HordeLocalPipeOwner {
    # Does the pipe's owner match the user we expect? A pipe owned by anyone else was created by
    # someone else, whatever its name says.
    param($Owner, $Expected)
    if ($null -eq $Owner -or $null -eq $Expected) { return $false }
    return ("$Owner" -ceq "$Expected")
}

function Get-HordeLocalPipeSecurity {
    # A pipe's security descriptor, in either shell (T-0450). In .NET Framework (5.1) GetAccessControl is
    # a method of the pipe; in .NET Core (pwsh 7) it is the extension method PipesAclExtensions, which
    # PowerShell cannot call as a method - measured 2026-11-11 on 7.6.7, the call threw, the old
    # `catch { }` left the owner '', and every dial to this user's own node was refused as a squatter.
    # Chosen by whether the method is there, not by the shell's version (the repo's pattern:
    # cli/HubRegistry.ps1). Throws when the descriptor cannot be read; the caller decides what that means.
    param([Parameter(Mandatory = $true)]$Pipe)
    if ($Pipe.PSObject.Methods["GetAccessControl"]) { return $Pipe.GetAccessControl() }
    return [System.IO.Pipes.PipesAclExtensions]::GetAccessControl($Pipe)
}

function Get-HordeLocalOwnerRefusal {
    # Why a dialled pipe is refused on its owner, or "" when its owner is the expected user.
    # FAIL-CLOSED: an owner that cannot be read refuses the link, as one owned by someone else does; only
    # the reason differs, so a broken read is never reported as a squatter (T-0450).
    param([Parameter(Mandatory = $true)]$Pipe, [string]$Name, $Expected)
    $owner = $null
    try { $owner = (Get-HordeLocalPipeSecurity -Pipe $Pipe).GetOwner([System.Security.Principal.SecurityIdentifier]) }
    catch {
        $e = $_.Exception
        while ($null -ne $e.InnerException) { $e = $e.InnerException }
        return ("refused: the owner of " + $Name + " could not be read (" + $e.Message + "); a pipe whose owner cannot be read is not dialled")
    }
    if ($null -eq $owner) { return ("refused: the owner of " + $Name + " could not be read (no owner in its security descriptor); a pipe whose owner cannot be read is not dialled") }
    if (-not (Test-HordeLocalPipeOwner -Owner $owner -Expected $Expected)) { return ("refused: " + $Name + " is owned by '" + $owner + "', not by this user; it may be a squatter") }
    return ""
}

function Test-HordeLocalPeerIntegrity {
    # Is the peer's integrity level at least this end's? -1 means it could not be read, which is below
    # every level.
    param([int]$Peer, [int]$Own)
    if ($Peer -lt 0 -or $Own -lt 0) { return $false }
    return ($Peer -ge $Own)
}

function Test-HordeLocalNodeImage {
    # Is this executable one a node runs in? Compared as Windows compares paths, without case.
    param([string]$Image)
    if ("$Image".Trim() -eq "") { return $false }
    foreach ($ok in $script:HordeLocalNodeImages) { if ([string]::Equals($Image, $ok, [System.StringComparison]::OrdinalIgnoreCase)) { return $true } }
    return $false
}

function Get-HordeLocalOwnIntegrity {
    return [HordeLocalNative]::Integrity([uint32]$PID)
}

function New-HordeLocalServer {
    # One server instance of -Pipe as a NamedPipeServerStream, or a reason it could not be made.
    # -First: the first instance - refused if anyone already holds the name. Returns { stream; reason }.
    param([string]$Pipe, [switch]$First)
    $err = 0
    $h = [HordeLocalNative]::CreateServer(($script:HordeLocalPipeRoot + $Pipe), (New-HordeLocalPipeSddl), [bool]$First, [uint32]$script:HordeLocalBufferBytes, [ref]$err)
    if ($h.IsInvalid) {
        $why = "Win32 error " + $err
        if ($First -and $err -eq 5) { $why = "the name is already held by another pipe instance (access denied to a first instance)" }
        return [pscustomobject]@{ stream = $null; reason = ($Pipe + " is already in use: " + $why) }
    }
    return [pscustomobject]@{ stream = (New-Object System.IO.Pipes.NamedPipeServerStream([System.IO.Pipes.PipeDirection]::InOut, $true, $false, $h)); reason = "" }
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
    param([bool]$Ok, $Channel = $null, $Peer = $null, $Listener = $null, [string]$Reason = "", [bool]$Refused = $false)
    return [pscustomobject]@{ ok = $Ok; channel = $Channel; peer = $Peer; listener = $Listener; reason = $Reason; refused = $Refused }
}

$null = Register-HordeTransport -Folder $script:HordeLocalFolder `
    -Open {
        param($Endpoint, [int]$TimeoutMs)
        $pipe = Get-HordeLocalPipeName -DeviceId $Endpoint
        if ($null -eq $pipe) { return (New-HordeLocalResult -Ok $false -Reason ("'" + $Endpoint + "' is not a device id (one lowercase UUID) or hub: followed by one")) }
        $cli = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipe, [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous)
        try { $cli.Connect([Math]::Max(1, $TimeoutMs)) }
        catch {
            $cli.Dispose()
            $e = $_.Exception
            while ($null -ne $e.InnerException) { $e = $e.InnerException }
            if ($e -is [System.TimeoutException]) { return (New-HordeLocalResult -Ok $false -Reason ("no " + $(if ($pipe.StartsWith($script:HordeLocalHubPipePrefix, [System.StringComparison]::Ordinal)) { "hub" } else { "node" }) + " answered on " + $pipe + " within " + $TimeoutMs + " ms")) }
            # A denied open cannot say which of two things denied it: the pipe's ACL (another user's
            # pipe), or its label (a node at a higher integrity level than this hub). The label cannot be
            # read to tell them apart - measured 2026-10-01, a Medium process's GetNamedSecurityInfo of a
            # High node's label fails with access denied too - so both are named (review of PR #42, round 3).
            if ($e -is [System.UnauthorizedAccessException]) { return (New-HordeLocalResult -Ok $false -Reason ("refused: " + $pipe + " denied the open. Either its ACL does not admit this user, or the node runs at a higher integrity level than this end (this end runs at integrity " + (Get-HordeLocalOwnIntegrity) + "); if it is the real node, run the hub and node at the same integrity level")) }
            return (New-HordeLocalResult -Ok $false -Reason ("could not connect to " + $pipe + ": " + $e.Message))
        }
        $me = Get-HordeLocalUserSid
        $ownerRefusal = Get-HordeLocalOwnerRefusal -Pipe $cli -Name $pipe -Expected $me
        if ($ownerRefusal -ne "") {
            $cli.Dispose()
            return (New-HordeLocalResult -Ok $false -Reason $ownerRefusal)
        }
        # Who serves it: the owner is the same for a low-integrity process of this user (see header).
        $serverPid = [HordeLocalNative]::ServerPid($cli.SafePipeHandle)
        $own = Get-HordeLocalOwnIntegrity
        $sil = -1
        $img = ""
        if ($serverPid -gt 0) { $sil = [HordeLocalNative]::Integrity([uint32]$serverPid); $img = [HordeLocalNative]::Image([uint32]$serverPid) }
        if (-not (Test-HordeLocalPeerIntegrity -Peer $sil -Own $own)) {
            $cli.Dispose()
            return (New-HordeLocalResult -Ok $false -Reason ("refused: " + $pipe + " is served by process " + $serverPid + " at integrity " + $sil + ", below this end's " + $own + "; it may be a squatter. If it is the real node, run the hub and node at the same integrity level"))
        }
        if (-not (Test-HordeLocalNodeImage -Image $img)) {
            $cli.Dispose()
            return (New-HordeLocalResult -Ok $false -Reason ("refused: " + $pipe + " is served by '" + $img + "', which is not a node's interpreter"))
        }
        $peer = [pscustomobject]@{ verified = $true; identity = "$me"; how = ("the pipe's owner is this user, and its server, process " + $serverPid + " (" + $img + "), runs at integrity " + $sil + ", not below this end's " + $own) }
        return (New-HordeLocalResult -Ok $true -Channel (New-HordeLocalChannel -Stream $cli) -Peer $peer)
    } `
    -Probe {
        param($Endpoint)
        $pipe = Get-HordeLocalPipeName -DeviceId $Endpoint
        if ($null -eq $pipe) { return (New-HordeUnknown -Reason ("'" + $Endpoint + "' is not a device id")) }
        # A directory listing of the pipe namespace, filtered to this one name. It opens nothing: a
        # connect would take a server instance, and File.Exists on a pipe path connects.
        $hits = @([System.IO.Directory]::EnumerateFiles($script:HordeLocalPipeRoot, $pipe))
        if ($hits.Count -gt 0) { return (New-HordeKnown -Value $true -ObservedAt ([datetime]::UtcNow)) }
        return (New-HordeKnown -Value $false -ObservedAt ([datetime]::UtcNow))
    } `
    -Listen {
        param($Endpoint)
        $pipe = Get-HordeLocalPipeName -DeviceId $Endpoint
        if ($null -eq $pipe) { return (New-HordeLocalResult -Ok $false -Reason ("'" + $Endpoint + "' is not a device id (one lowercase UUID) or hub: followed by one")) }
        $made = New-HordeLocalServer -Pipe $pipe -First
        if ($null -eq $made.stream) { return (New-HordeLocalResult -Ok $false -Reason $made.reason) }
        return (New-HordeLocalResult -Ok $true -Listener @{ pipe = $pipe; server = $made.stream; wait = $null; broken = "" })
    } `
    -Accept {
        param($ListenerState, [int]$TimeoutMs)
        $st = $ListenerState
        if ($null -eq $st.server) { return (New-HordeLocalResult -Ok $false -Reason ("the listener on " + $st.pipe + " has no waiting instance (" + $st.broken + "); stop it and listen again")) }
        # A client that connects and closes before this wait starts leaves the instance dead:
        # WaitForConnectionAsync then throws "The pipe is being closed" - synchronously, which the first
        # version did outside its try, so the dead instance was kept and every later accept failed the
        # same way, for ever (review of PR #42, round 2). Now any failure replaces the instance - the
        # fresh one is made while the dead one still holds the name - and the wait goes on until the
        # deadline.
        $deadline = [datetime]::UtcNow.AddMilliseconds([Math]::Max(0, $TimeoutMs))
        while ($true) {
            $failed = ""
            try {
                if ($null -eq $st.wait) { $st.wait = $st.server.WaitForConnectionAsync() }
                $came = $st.wait.Wait([int][Math]::Max(0, ($deadline - [datetime]::UtcNow).TotalMilliseconds))
            } catch {
                $e = $_.Exception
                while ($null -ne $e.InnerException) { $e = $e.InnerException }
                $failed = $e.Message
            }
            if ($failed -eq "") { break }
            $dead = $st.server
            $st.wait = $null
            $fresh = New-HordeLocalServer -Pipe $st.pipe
            try { $dead.Dispose() } catch { }
            $st.server = $fresh.stream
            if ($null -eq $fresh.stream) {
                $st.broken = "an instance failed (" + $failed + ") and could not be replaced: " + $fresh.reason
                return (New-HordeLocalResult -Ok $false -Reason $st.broken)
            }
            if ([datetime]::UtcNow -ge $deadline) { return (New-HordeLocalResult -Ok $false -Reason ("no peer connected within " + $TimeoutMs + " ms (an instance a client had closed was replaced)")) }
        }
        # Not connected in time: the wait stays pending on the same instance for the next call.
        if (-not $came) { return (New-HordeLocalResult -Ok $false -Reason ("no peer connected within " + $TimeoutMs + " ms")) }
        $server = $st.server
        $st.wait = $null
        # The next waiting instance is made BEFORE this one is handed over, so the name is never free
        # while the node listens (see header). Not -First: this instance still holds the name.
        $next = New-HordeLocalServer -Pipe $st.pipe
        $st.server = $next.stream
        if ($null -eq $next.stream) { $st.broken = $next.reason }
        $clientPid = [HordeLocalNative]::ClientPid($server.SafePipeHandle)
        $own = Get-HordeLocalOwnIntegrity
        $cil = -1
        if ($clientPid -gt 0) { $cil = [HordeLocalNative]::Integrity([uint32]$clientPid) }
        if (-not (Test-HordeLocalPeerIntegrity -Peer $cil -Own $own)) {
            try { $server.Dispose() } catch { }
            # A refusal, not a failure, only while the next waiting instance holds the name, so serve may
            # keep this listener (issue #85). When that instance could not be made the name is free and
            # the listener is broken: not refused, so serve restarts it (review of PR #90, F2).
            return (New-HordeLocalResult -Ok $false -Refused ($null -ne $st.server) -Reason ("refused a client: process " + $clientPid + " runs at integrity " + $cil + ", below this node's " + $own + "; run the hub and node at the same integrity level"))
        }
        $peer = [pscustomobject]@{ verified = $true; identity = "$(Get-HordeLocalUserSid)"; how = ("admitted by the pipe's ACL and label: this user only, no network logons, and its process " + $clientPid + " runs at integrity " + $cil + ", not below this node's " + $own) }
        return (New-HordeLocalResult -Ok $true -Channel (New-HordeLocalChannel -Stream $server) -Peer $peer)
    } `
    -Stop {
        param($ListenerState)
        if ($null -ne $ListenerState.server) { try { $ListenerState.server.Dispose() } catch { } }
        $ListenerState.server = $null
        $ListenerState.wait = $null
    }
