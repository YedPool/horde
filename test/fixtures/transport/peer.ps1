# The far end of a link, for test/test-transport-conformance.ps1. Not a suite: the suite runs this in
# a second runspace of its own process, on another thread, so the two ends of one link really are
# concurrent - a frame of a mebibyte cannot be written into a pipe that nobody is reading, and a
# single-threaded test would deadlock there instead of testing anything.
#
# -Mode listen: start a listener on -Endpoint, set Ready, accept one link. -Mode dial: open a link to
# -Endpoint, then set Ready. Then do -Behavior, and close. The suite's side is the one under test;
# this side misbehaves on purpose where the behaviour says so, writing raw bytes past the port with
# the transport's own byte channel.
#
# Events (System.Threading.ManualResetEventSlim), shared with the suite: Ready (this side is up),
# Go (the suite has finished looking; carry on or stop), Again (a restarted listener is up).
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [Parameter(Mandatory = $true)][string]$Mode,
    [Parameter(Mandatory = $true)][string]$Behavior,
    [Parameter(Mandatory = $true)]$Events
)
$ErrorActionPreference = "Stop"
. (Join-Path $Root "transports\Port.ps1")
foreach ($f in @(Get-HordeTransportFiles)) { . $f }
$t = Get-HordeTransport -Name $Name

function Send-Raw {
    # Bytes straight onto the transport's byte channel, past the port's own checks.
    param($Link, [byte[]]$Bytes)
    $task = & $Link.channel.write $Link.channel $Bytes
    # A write the suite's side refuses to finish reading (it closes the link on an oversize line) fails
    # here, and that is the case working, not the peer failing.
    if ($task -is [System.Threading.Tasks.Task]) { try { [void]$task.Wait(20000) } catch { } }
}

$listener = $null
$link = $null
try {
    if ($Mode -eq "listen") {
        $la = Start-HordeTransportListener -Transport $t -Endpoint $Endpoint
        if ($la.state -ne "known") { throw ("peer could not listen: " + $la.reason) }
        $listener = Get-HordeValue $la
        $Events.ready.Set()
        $ka = Receive-HordeTransportLink -Listener $listener -TimeoutMs 20000
        if ($ka.state -ne "known") { throw ("peer accepted nothing: " + $ka.reason) }
        $link = Get-HordeValue $ka
    } else {
        $ka = Open-HordeTransportLink -Transport $t -Endpoint $Endpoint -Role "node" -TimeoutMs 20000
        if ($ka.state -ne "known") { $Events.ready.Set(); throw ("peer could not dial: " + $ka.reason) }
        $link = Get-HordeValue $ka
        $Events.ready.Set()
    }
    switch ($Behavior) {
        "echo" {
            while ($true) {
                $r = Receive-HordeLinkFrame -Link $link -TimeoutMs 20000
                if ($r.state -ne "known") { break }
                $s = Send-HordeLinkFrame -Link $link -Frame (Get-HordeValue $r) -TimeoutMs 20000
                if ($s.state -ne "known") { break }
            }
        }
        "one-then-close" { $null = Send-HordeLinkFrame -Link $link -Frame "one" -TimeoutMs 20000 }
        "partial" { Send-Raw $link ([System.Text.Encoding]::ASCII.GetBytes("abc")) }
        "close" { }
        "oversize" {
            $big = New-Object byte[] ($link.maxFrameBytes + 1)
            for ($i = 0; $i -lt $big.Length; $i++) { $big[$i] = 0x61 }
            Send-Raw $link $big
            [void]$Events.go.Wait(20000)
        }
        "nonascii" { Send-Raw $link ([byte[]]@(0x61, 0xE9, 0x0A)); [void]$Events.go.Wait(20000) }
        "hold" {
            [void]$Events.go.Wait(20000)
            $null = Send-HordeLinkFrame -Link $link -Frame "late" -TimeoutMs 20000
            $null = Receive-HordeLinkFrame -Link $link -TimeoutMs 5000
        }
        "restart" {
            Close-HordeLink -Link $link
            Stop-HordeTransportListener -Listener $listener
            $la = Start-HordeTransportListener -Transport $t -Endpoint $Endpoint
            if ($la.state -ne "known") { throw ("peer could not listen again: " + $la.reason) }
            $listener = Get-HordeValue $la
            $Events.again.Set()
            $ka = Receive-HordeTransportLink -Listener $listener -TimeoutMs 20000
            if ($ka.state -eq "known") {
                $link = Get-HordeValue $ka
                $null = Send-HordeLinkFrame -Link $link -Frame "fresh" -TimeoutMs 20000
                [void]$Events.go.Wait(20000)
            }
        }
        default { throw ("no such behaviour: " + $Behavior) }
    }
} finally {
    if ($null -ne $link) { Close-HordeLink -Link $link }
    if ($null -ne $listener) { Stop-HordeTransportListener -Listener $listener }
    $Events.ready.Set()
}
"peer done"
