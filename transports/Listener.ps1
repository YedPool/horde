# transports/Listener.ps1 - the listener port: how the hub accepts links from other machines.
#
# WHY A PORT OF ITS OWN (remote plan R17a). The transport port (Port.ps1) listens and accepts in this
# process. A transport whose accepting end is a server program - one that authenticates the dialler
# and runs a forced command that relays to the hub's own pipe - cannot do that: its "accept" is no
# (transports/<name>/capabilities.json says so). What it can do is start that server, say whether it
# still runs, and stop it. `horde listen` does exactly that, through this file, without naming a
# transport (CONTRIBUTING rule 14). Kept out of Port.ps1 so the two registries change separately.
#
# ADAPTER CONTRACT. transports/<name>/Listen.ps1 is dot-sourced at script level (so its helpers outlive
# the call) and calls Register-HordeListener with three script blocks:
#   Start   param($Request)  -> { ok; listener; address; reason }
#           $Request is { hordeHome; hubId; port; root; register; address }: Horde's home (every file the
#           server reads is under it), the hub's device id, the port to bind on address (never 0:
#           Start-HordeListener picks one for -Port 0), the root of this Horde, whose attach every
#           admitted key must be forced to (the server refuses to start while a key is not held to it),
#           and register, the hub's register as this port read it just now: a hashtable, device id -> the
#           key enrolled for it, live devices only (cli/HubRegistry.ps1). The server admits a key only for
#           a device the register holds, with that key.
#           address is the one address to bind, checked here first (core/ListenAddress.ps1): loopback,
#           or a private address this machine holds, never a public one or every interface (mesh v1, the
#           founder's rule 4); the adapter checks it again where it writes it.
#   Health  is given the register afresh, read again by the port each time it asks (see Health below).
#   Health  param($Listener, $Register) -> a tristate answer: known $true while it serves, or known
#           $false with nothing to serve, or unknown with the reason. $Register is the hub's register as
#           Start's request carries it, read afresh for this check.
#   Stop    param($Listener) -> the server's own last words, a string; ends it and everything it started.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\ListenAddress.ps1")

if ($null -eq (Get-Variable -Name HordeListeners -Scope Script -ErrorAction SilentlyContinue)) { $script:HordeListeners = @{} }

function Get-HordeListenerFiles {
    # Every transport's Listen.ps1, for the caller to dot-source at script level:
    #   foreach ($f in @(Get-HordeListenerFiles)) { . $f }
    param([string]$Root = $PSScriptRoot)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName "Listen.ps1" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

function Register-HordeListener {
    # Called by a transport's own Listen.ps1, once per name; the first registration stands.
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][scriptblock]$Start,
        [Parameter(Mandatory = $true)][scriptblock]$Health,
        [Parameter(Mandatory = $true)][scriptblock]$Stop
    )
    $name = Split-Path -Leaf $Folder
    if ($script:HordeListeners.ContainsKey($name)) { throw ("a listener for transport '" + $name + "' is already registered; the first registration stands") }
    $l = [pscustomobject]@{ PSTypeName = "Horde.ListenerAdapter"; name = $name; start = $Start; health = $Health; stop = $Stop }
    $script:HordeListeners[$name] = $l
    return $l
}

function Get-HordeListenerAdapter {
    # The listener of -Name, or, with no name, of the one transport that has one. A tristate answer:
    # unknown when none is loaded, or several are and no name says which.
    param([string]$Name = "")
    if ($Name -ne "") {
        if ($script:HordeListeners.ContainsKey($Name)) { return (New-HordeKnown -Value $script:HordeListeners[$Name]) }
        return (New-HordeUnknown -Reason ("no transport named '" + $Name + "' has a listener"))
    }
    $all = @($script:HordeListeners.Keys | Sort-Object)
    if ($all.Count -eq 1) { return (New-HordeKnown -Value $script:HordeListeners[$all[0]]) }
    if ($all.Count -eq 0) { return (New-HordeUnknown -Reason "no transport with a listener is loaded") }
    return (New-HordeUnknown -Reason ("several transports have a listener (" + ($all -join ", ") + "); name one with -Transport"))
}

function Get-HordeListenerFreePort {
    # A port nothing listens on now on -Address: what -Port 0 asks for. Picked here, so an adapter is
    # always handed a real port and never opens a socket of its own to find one.
    param([string]$Address = "127.0.0.1")
    $l = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse($Address), 0)
    $l.Start()
    $p = $l.LocalEndpoint.Port
    $l.Stop()
    return $p
}

function Read-HordeListenerRegister {
    # The hub's register from -Register, as a tristate answer: known with a hashtable of device id ->
    # key, or unknown with the reason. A register that cannot be read admits nobody: never a guess.
    param([Parameter(Mandatory = $true)][scriptblock]$Register)
    $t = $null
    try { $t = & $Register } catch { return (New-HordeUnknown -Reason "the hub's register could not be read" -ErrorRecord $_) }
    if ($t -isnot [hashtable]) { return (New-HordeUnknown -Reason "the hub's register did not read as a table of devices and keys") }
    return (New-HordeKnown -Value $t)
}

function Start-HordeListener {
    # Start -Adapter's server for -HubId. A tristate answer: known { adapter; listener; address }, or
    # unknown with the reason. Never throws for the server's failure.
    # -Register is param() -> the hub's register as a hashtable (header, Start); it is read here and
    # again at every health check, so a revoke reaches a running server within a check.
    # -Address is the one address to bind (header); -LocalAddresses, this machine's (by default read from
    # its interfaces), is given only by a suite.
    param([Parameter(Mandatory = $true)]$Adapter, [Parameter(Mandatory = $true)][string]$HordeHome, [Parameter(Mandatory = $true)][string]$HubId, [Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][scriptblock]$Register, [int]$Port = 0, [string]$Address = "127.0.0.1", [string[]]$LocalAddresses = $null)
    if ($Port -lt 0 -or $Port -gt 65535) { return (New-HordeUnknown -Reason ("-Port " + $Port + " is not a TCP port")) }
    $where = Resolve-HordeListenAddress -Address $Address -LocalAddresses $LocalAddresses
    if ($where.state -cne "known") { return (New-HordeUnknown -Reason ("the listener did not start: " + $where.reason)) }
    $table = Read-HordeListenerRegister -Register $Register
    if ($table.state -cne "known") { return (New-HordeUnknown -Reason ("the listener did not start: " + $table.reason)) }
    if ($Port -eq 0) { $Port = Get-HordeListenerFreePort -Address $where.value.address }
    $req = [pscustomobject]@{ hordeHome = $HordeHome; hubId = $HubId; port = $Port; root = $Root; register = $table.value; address = $where.value.address }
    try { $r = & $Adapter.start $req }
    catch { return (New-HordeUnknown -Reason ("the " + $Adapter.name + " listener did not start") -ErrorRecord $_) }
    if ($null -eq $r -or -not $r.ok) { return (New-HordeUnknown -Reason ("the " + $Adapter.name + " listener did not start: " + "$($r.reason)")) }
    return (New-HordeKnown -Value ([pscustomobject]@{ PSTypeName = "Horde.RunningListener"; adapter = $Adapter; listener = $r.listener; address = "$($r.address)"; register = $Register }))
}

function Test-HordeListenerServing {
    # Does the running listener still serve? A tristate answer, from its adapter, given the hub's register
    # as it reads now: a revoke, an expiry or an entry removed reaches the server at the next check.
    param([Parameter(Mandatory = $true)]$Running)
    $table = Read-HordeListenerRegister -Register $Running.register
    if ($table.state -cne "known") { return $table }
    try { $a = & $Running.adapter.health $Running.listener $table.value }
    catch { return (New-HordeUnknown -Reason ("asking the " + $Running.adapter.name + " listener whether it serves") -ErrorRecord $_) }
    if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown -Reason ("the " + $Running.adapter.name + " listener answered with something that is not an answer")) }
    return $a
}

function Stop-HordeListener {
    # Stop the running listener and everything it started. Returns the server's last words.
    param([Parameter(Mandatory = $true)]$Running)
    return ("" + (& $Running.adapter.stop $Running.listener))
}
