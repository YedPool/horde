# gate-lock.ps1 - one heavy test job at a time across every agent of the D orchestrator.
# Why: several agents each waited for >=1.5 GB free, all started together when memory freed,
# and the harness reaped them for low memory (observed 2026-10-01, four reaps in one hour).
# A file opened with FileShare.None is held by exactly one process; the OS releases it if the
# holder dies, so a killed job can never leave the gate stuck.
#
# v2 (2026-10-01): the command now runs as a child whose stdout/stderr go to FILES, not the
# console. Measured under v1: when the reaper killed the calling bash, the child PowerShell died
# on a console HostException and still exited 0 - a false green. With redirected output the
# child never touches a console, and the gate echoes the files after the child exits.
#
# Usage (inside your background job):
#   powershell -NoProfile -File <this> -Label <who> -Command "<powershell command>"
# Exit code is the command's exit code. A run counts ONLY if the output ends with the line
#   GATE <label> released exit=<n>
# No such line means the gate itself was killed: the run proves nothing.
param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string]$Command,
    [int]$MinFreeMB = 1536,
    # v7 (2026-10-05): a hard wall-clock limit on the held gate. Measured: a review probe hung for
    # over 2 h holding the gate while three runs queued behind it; nothing ever released it.
    [double]$MaxMinutes = 120
)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class GateLockPower {
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_POWER_THROTTLING_STATE { public uint Version; public uint ControlMask; public uint StateMask; }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetProcessInformation(IntPtr hProcess, int ProcessInformationClass, ref PROCESS_POWER_THROTTLING_STATE info, uint size);
    public static string OptOut(IntPtr process) {
        var s = new PROCESS_POWER_THROTTLING_STATE { Version = 1, ControlMask = 1, StateMask = 0 };
        bool ok = SetProcessInformation(process, 4, ref s, (uint)Marshal.SizeOf(s));
        return ok ? "set" : ("failed, error " + Marshal.GetLastWin32Error());
    }
}
"@
$lockPath = Join-Path $PSScriptRoot 'gate.lock'
$holder = $null
while ($null -eq $holder) {
    try {
        $holder = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
    } catch {
        Start-Sleep -Seconds 15
    }
}
try {
    while ($true) {
        $freeMB = [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)
        if ($freeMB -ge $MinFreeMB) { break }
        Start-Sleep -Seconds 15
    }
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("$Label $stamp pid=$PID`r`n")
    $holder.SetLength(0); $holder.Write($bytes, 0, $bytes.Length); $holder.Flush()
    Write-Output ("GATE " + $Label + " acquired " + $stamp + " free=" + $freeMB + "MB")
    $runDir = Join-Path $PSScriptRoot ('gate-runs\' + $Label + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Force -Path $runDir)
    $cmdFile = Join-Path $runDir 'cmd.ps1'
    # The trap is v6 (2026-10-03). Without it, a parse error or an uncaught throw inside a
    # script run with & stopped only that statement, and 'exit $LASTEXITCODE' then exited 0:
    # a false green, measured on review probe rlws. A trap catches terminating errors only,
    # so a suite's non-terminating errors behave exactly as before.
    $trapLine = 'trap { [Console]::Error.WriteLine(''GATE-CHILD terminating error: '' + $_); exit 97 }'
    [System.IO.File]::WriteAllText($cmdFile, $trapLine + "`r`n" + $Command + "`r`nexit `$LASTEXITCODE`r`n", [System.Text.Encoding]::ASCII)
    $outFile = Join-Path $runDir 'stdout.txt'
    $errFile = Join-Path $runDir 'stderr.txt'
    $timedOut = $false
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $cmdFile) -RedirectStandardOutput $outFile -RedirectStandardError $errFile -WindowStyle Hidden -PassThru
    # v3 (2026-10-01): WaitForExit on the child alone, never Start-Process -Wait. Measured: -Wait in
    # PS 5.1 also waits for every descendant, so a mux server a suite leaked held the gate for 3 h
    # (gate-runs\pr59-5e977148, suite done 14:16, gate freed only when the leaked servers were killed).
    # v4: touch Handle at once. Measured: without it PS 5.1 returns a null ExitCode for a
    # Start-Process -PassThru child, and 'exit $null' is 0 - v3 reported a suite's exit 5 as 0
    # (repro-lock/repro.log, 2026-10-01T21:21Z). A null code is now a failure, never a pass.
    $null = $p.Handle
    # v5 (2026-10-02): opt the child out of execution-speed power throttling (EcoQoS). Measured on this
    # box by the SSH agent: a busy background process slows about 3 s in (an empty PowerShell call
    # 23 us -> 165 us, pure .NET at about half speed), and the opt-out removes it. Set from here on the
    # child's own handle, before it has run 3 s; the gate's line says whether it took.
    Write-Output ('GATE ' + $Label + ' throttling opt-out: ' + [GateLockPower]::OptOut($p.Handle))
    if (-not $p.WaitForExit([int]([math]::Min($MaxMinutes * 60000, [int]::MaxValue)))) {
        # Only the tree this gate started is killed: the child pid it holds a handle to, and its descendants.
        Write-Output ('GATE ' + $Label + ' TIMEOUT after ' + $MaxMinutes + ' minutes - killing child tree ' + $p.Id)
        & taskkill.exe /F /T /PID $p.Id | Out-Null
        $null = $p.WaitForExit(30000)
        $timedOut = $true
    }
    $code = $p.ExitCode
    if ($timedOut) { $code = 98 }
    if ($null -eq $code) { Write-Output ('GATE ' + $Label + ' exit code unreadable - treating as failure'); $code = 99 }
    if (Test-Path $outFile) { Get-Content -LiteralPath $outFile }
    if ((Test-Path $errFile) -and (Get-Item $errFile).Length -gt 0) { Write-Output '--- stderr ---'; Get-Content -LiteralPath $errFile }
    Write-Output ("GATE " + $Label + " released exit=" + $code)
    exit $code
} finally {
    $holder.Dispose()
}
