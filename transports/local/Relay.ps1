# transports/local/Relay.ps1 - the relay a listener's forced command runs: stdio to the hub's own pipe.
#
# WHAT IT IS FOR (remote plan R17a). A node on another machine reaches the hub through the hub's
# listener, which admits its key only with a forced command, `horde attach`. That command relays the
# session's stdin and stdout to \\.\pipe\horde-hub-<hubId> (Transport.ps1, THE HUB'S OWN PIPE) and does
# nothing else: it reads no frame, so the protocol is the hub's alone, and it holds no state, so a link
# that drops leaves nothing behind but a process that ends. It dials through this transport's own Open,
# so every check of who serves the pipe applies (its owner, its integrity, its interpreter).
#
# ONE LINE BEFORE THE FIRST BYTE. The caller hands the relay a first line, the preamble
# (remote/LinkBinding.ps1), which tells the hub which enrolled device the session is for. The relay
# writes it and adds nothing to it; what it says is the caller's.
#
# STDIN ARRIVES AS LINES, AND THAT IS NOT A CHOICE. Measured 2026-10-06 (issue #100): inside a Windows
# remote session a .NET Console stream ([Console]::In, Console.OpenStandardInput) never returns the session's
# data, on 9.5p1 and 9.5p2 alike, while PowerShell's $input reads it and streams. So the caller passes
# $input - horde.ps1's own, handed down by the runner - and the relay enumerates it. Each item is one
# line without its line break, and the relay sends it with LF, the frame terminator. A line that is
# not ASCII ends the relay: the link carries only ASCII frames, and the relay never rewrites one.
#
# THE OTHER DIRECTION RUNS ON ITS OWN. The hub may speak first and at any time, while the enumeration
# of stdin blocks until the next line, so pipe-to-stdout is a .NET copy task (Stream.CopyToAsync) that
# needs no PowerShell thread.
#
# WHEN IT ENDS. stdin ends (the client went away): the pipe is closed, so the hub reads a closed link,
# and the relay returns. The hub closes the pipe: the copy ends - and the relay cannot notice from its
# own thread, which is blocked reading stdin. Measured 2026-10-07 under the listener: after the hub
# closed, the relay stayed alive until the client closed its stdin; closing the relay's stdout did not
# end the session; cancelling the stdin read (CancelIoEx) did, but PowerShell's reader then wrote "The
# operation was canceled." to stderr. So with -ExitWhenHubCloses the copy's own continuation ends the
# process, exit 0 when the copy completed and 1 when it failed (HordeLocalRelayEnd below). Only
# cli\attach.ps1 asks for it: it is always a process of its own, the forced command of one session,
# and when the hub is gone it has nothing left to do. This is the one place Horde ends a process
# with [Environment]::Exit, the exception horde.ps1's header allows no command.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeLocalRelayAscii = [System.Text.Encoding]::GetEncoding("us-ascii", (New-Object System.Text.EncoderExceptionFallback), (New-Object System.Text.DecoderExceptionFallback))

# The continuation that ends the process when the copy from the hub ends (WHEN IT ENDS, above). A .NET
# delegate, because a PowerShell script block has no runspace on a thread-pool thread.
if (-not ([System.Management.Automation.PSTypeName]"HordeLocalRelayEnd").Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Threading.Tasks;

public static class HordeLocalRelayEnd {
    // Cleared when the relay ends on its own (stdin ended), so closing the pipe then exits nothing.
    static volatile bool armed;
    public static void ExitWhenDone(Task copy) {
        armed = true;
        copy.ContinueWith(delegate(Task t) { if (armed) { Environment.Exit(t.Status == TaskStatus.RanToCompletion ? 0 : 1); } });
    }
    public static void Disarm() { armed = false; }
}
'@
}

function New-HordeLocalRelayResult {
    param([bool]$Ok, [string]$Reason = "", [int]$Lines = 0, [string]$Ended = "")
    return [pscustomobject]@{ ok = $Ok; reason = $Reason; lines = $Lines; ended = $Ended }
}

function Invoke-HordeLocalRelay {
    # Relay -Lines (each one line of the session's stdin) to the hub's pipe for -HubId, and the pipe's
    # bytes to -Output, after one -Preamble line. Returns { ok; reason; lines; ended } when either side
    # ends: ended is "stdin" or "hub". ok is $false only when the relay could not start or a line could
    # not be sent; a side ending is how every relay finishes.
    param(
        [Parameter(Mandatory = $true)][string]$HubId,
        [Parameter(Mandatory = $true)][string]$Preamble,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Lines,
        [Parameter(Mandatory = $true)][System.IO.Stream]$Output,
        [int]$TimeoutMs = 10000,
        # End this process when the hub closes the pipe (WHEN IT ENDS). Only for a relay that is a process of its own.
        [switch]$ExitWhenHubCloses
    )
    $t = Get-HordeTransport -Name "local"
    $o = Open-HordeTransportLink -Transport $t -Endpoint ($script:HordeLocalHubEndpointPrefix + $HubId) -Role "node" -TimeoutMs $TimeoutMs
    if ($o.state -cne "known") { return (New-HordeLocalRelayResult -Ok $false -Reason ("the hub's pipe could not be reached: " + $o.reason)) }
    $link = Get-HordeValue $o
    $stream = $link.channel.state.stream
    $sent = 0
    try {
        try { $first = $script:HordeLocalRelayAscii.GetBytes($Preamble + "`n") }
        catch { return (New-HordeLocalRelayResult -Ok $false -Reason "the preamble is not ASCII; nothing was sent") }
        if ($Preamble.Contains("`n") -or $Preamble.Contains("`r")) { return (New-HordeLocalRelayResult -Ok $false -Reason "the preamble holds a line break; nothing was sent") }
        $stream.Write($first, 0, $first.Length)
        $stream.Flush()
        $pump = $stream.CopyToAsync($Output, 65536)
        if ($ExitWhenHubCloses) { [HordeLocalRelayEnd]::ExitWhenDone($pump) }
        foreach ($line in $Lines) {
            if ($pump.IsCompleted) { return (New-HordeLocalRelayResult -Ok $true -Lines $sent -Ended "hub") }
            try { $bytes = $script:HordeLocalRelayAscii.GetBytes("$line" + "`n") }
            catch { return (New-HordeLocalRelayResult -Ok $false -Lines $sent -Ended "stdin" -Reason ("line " + ($sent + 1) + " of stdin is not ASCII; the link carries ASCII frames only, so the relay stopped")) }
            try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush() }
            catch { return (New-HordeLocalRelayResult -Ok $true -Lines $sent -Ended "hub") }
            $sent++
        }
        return (New-HordeLocalRelayResult -Ok $true -Lines $sent -Ended "stdin")
    } finally {
        if ($ExitWhenHubCloses) { [HordeLocalRelayEnd]::Disarm() }
        Close-HordeLink -Link $link
    }
}
