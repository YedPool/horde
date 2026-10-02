# core/OverlayCommand - ask the overlay its one question: `horde-overlay endpoint --name <name> --json`.
#
# WHY HERE AND NOT IN remote/ (remote plan step R8). remote/ is the link's code, and tools/ExecScan.ps1
# proves it can start no program; widening that scan to let it start one would undo the proof for every
# file in remote/. So the one process Horde starts for the overlay is started here, from a fixed command
# line, and remote/Overlay.ps1 reads its output as text.
#
# WHAT IT RUNS. Exactly one command line, built from data: the horde-overlay program found on PATH -
# an .exe, .cmd or .bat at a full path, nothing else - with `endpoint --name <name> --json`. The name is
# checked against schema/overlay-endpoint.v1's overlay pattern, anchored at the very end of the text,
# before anything starts, so no shell metacharacter and no line break can reach the line even when the
# program is a .cmd that cmd.exe reads. No other verb is ever sent: Horde never starts, stops or
# configures a tunnel.
#
# WHAT IT ANSWERS. The program's standard output as text (remote/Overlay.ps1 decides whether it is an
# endpoint), or unknown with the reason: not found, not startable, exited with an error (its first
# error line kept, cleaned and cut), silent past the timeout, or more output than the cap.
#
# THE TIMEOUT BOUNDS THE WHOLE CALL. Output is read in pieces against one deadline, so a program that
# exits while a child it started still holds the output pipe cannot keep the call waiting (review of
# this PR: a .cmd that started a 20 s child returned after 19 s against a 3 s timeout). Output is
# counted as it is read and the program stopped at the cap, so a program that never stops writing
# cannot fill memory.
#
# WHAT IT STOPS. Only the process this call started, by the handle it holds; never a process found by
# pid or name (tasks/lessons.md, an improvement to cleanup code is a change to what gets killed). A
# child that program started is not stopped here, and the reason says so rather than claim it was.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).
. (Join-Path $PSScriptRoot "Tristate.ps1")

# schema/overlay-endpoint.v1's overlay pattern, anchored with \z (a final $ also matches before a
# trailing newline in .NET), and held equal to the schema's by test/test-overlay.ps1.
$script:HordeOverlayNamePattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'
# remote/Overlay.ps1's cap on the answer, in bytes as read from the pipe.
$script:HordeOverlayCommandMaxBytes = 65536
# The kinds of program horde-overlay may be: ones Windows starts by itself or through cmd.exe.
$script:HordeOverlayProgramPattern = '\.(exe|cmd|bat)\z'
# The process the last call started, kept so the suite can see whether it was stopped. Read only.
$script:HordeOverlayLastProcess = $null

function ConvertTo-HordeOverlayLine {
    # One line of another program's error text, fit for a reason: printable ASCII, at most 200 chars.
    param([string]$Text)
    $first = @("$Text" -split "`r?`n" | Where-Object { $_.Trim() -ne "" }) | Select-Object -First 1
    $clean = ("$first" -replace '[^\x20-\x7E]', '?').Trim()
    if ($clean.Length -gt 200) { $clean = $clean.Substring(0, 200) }
    return $clean
}

function Stop-HordeOverlayStarted {
    # Stop the process this call started, by its handle; say whether it stopped.
    param([Parameter(Mandatory = $true)]$Process)
    try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }
    $null = $Process.WaitForExit(5000)
    if ($Process.HasExited) { return "the process it started was stopped (a process that one started is not stopped here)" }
    return "the process it started did not stop within 5 s"
}

function Invoke-HordeOverlayEndpoint {
    param([Parameter(Mandatory = $true)][string]$Name, [int]$TimeoutSeconds = 10)
    if ($Name -cnotmatch $script:HordeOverlayNamePattern) { return (New-HordeUnknown -Reason ("'" + ($Name -replace '[^\x20-\x7E]', '?') + "' is not an overlay name, so nothing was run")) }
    if ($TimeoutSeconds -lt 1) { return (New-HordeUnknown -Reason ("a timeout of " + $TimeoutSeconds + " s cannot be honoured, so nothing was run")) }
    $cmd = @(Get-Command -Name "horde-overlay" -CommandType Application -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($null -eq $cmd) { return (New-HordeUnknown -Reason "horde-overlay was not found on PATH, so the overlay cannot be asked") }
    $source = "$($cmd.Source)"
    if (-not [System.IO.Path]::IsPathRooted($source) -or $source -notmatch $script:HordeOverlayProgramPattern) { return (New-HordeUnknown -Reason ("horde-overlay was found at '" + $source + "', which is not a program at a full path (.exe, .cmd or .bat), so it was not run")) }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $source
    $psi.Arguments = "endpoint --name " + $Name + " --json"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Standard input is held open and never written, so a program that waits for input waits until the
    # timeout and is stopped, instead of reading this process's console.
    $psi.RedirectStandardInput = $true
    $p = $null
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return (New-HordeUnknown -Reason ("horde-overlay at '" + $source + "' could not be started: " + (ConvertTo-HordeOverlayLine $_.Exception.Message))) }
    $script:HordeOverlayLastProcess = $p
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $err = $p.StandardError.ReadToEndAsync()
    $stream = $p.StandardOutput.BaseStream
    $buf = New-Object byte[] 4096
    $got = New-Object System.IO.MemoryStream
    while ($true) {
        $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        $read = $stream.ReadAsync($buf, 0, $buf.Length)
        if (-not $read.Wait($left)) {
            $how = Stop-HordeOverlayStarted -Process $p
            return (New-HordeUnknown -Reason ("horde-overlay did not finish its answer within " + $TimeoutSeconds + " s; " + $how))
        }
        $n = $read.Result
        if ($n -eq 0) { break }
        $got.Write($buf, 0, $n)
        if ($got.Length -gt $script:HordeOverlayCommandMaxBytes) {
            $how = Stop-HordeOverlayStarted -Process $p
            return (New-HordeUnknown -Reason ("horde-overlay's answer is longer than " + $script:HordeOverlayCommandMaxBytes + " bytes; " + $how))
        }
    }
    $left = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
    if (-not $p.WaitForExit($left)) {
        $how = Stop-HordeOverlayStarted -Process $p
        return (New-HordeUnknown -Reason ("horde-overlay did not exit within " + $TimeoutSeconds + " s; " + $how))
    }
    if ($p.ExitCode -ne 0) {
        $line = ""
        if ($err.Wait(1000)) { $line = ConvertTo-HordeOverlayLine $err.Result }
        if ($line -eq "") { return (New-HordeUnknown -Reason ("horde-overlay exited " + $p.ExitCode + " and wrote no error")) }
        return (New-HordeUnknown -Reason ("horde-overlay exited " + $p.ExitCode + ": " + $line))
    }
    # Latin-1, one character per byte, so a byte above 0x7F reaches remote/Overlay.ps1 as a character it
    # refuses; ASCII decoding would turn it into a "?" that passes.
    return (New-HordeKnown -Value ([System.Text.Encoding]::GetEncoding(28591).GetString($got.ToArray())))
}
