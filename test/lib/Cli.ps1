# test/lib/Cli.ps1 - run the real horde command as its own process, the way a script would.
#
# For end-to-end checks of a command that starts no pane and so needs no isolated terminal
# (CONTRIBUTING 2 and 3): the shipped horde.ps1, through powershell -File, with environment additions
# that reach only the child. Streams are read through the process API, never with 2>&1, which under
# PowerShell 5.1 turns the first stderr line into a terminating error (CONTRIBUTING 12).

function Invoke-HordeCliProcess {
    # Returns { code; out }, out holding stdout then stderr. An argument with a space is quoted.
    param([Parameter(Mandatory = $true)][string]$Root, [string[]]$HordeArgs = @(), [hashtable]$Env = @{})
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $quoted = @($HordeArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $Root "horde.ps1") + "`" " + ($quoted -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $errTask = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        return [pscustomobject]@{ code = $p.ExitCode; out = ($out + "`n" + $errTask.Result) }
    } finally { $p.Dispose() }
}

# A LONG-RUNNING COMMAND, READ AS IT GOES: for a command that prints, then waits for what is typed or
# for something to arrive (`horde relay pair`). Its stdin is closed at once - a command typed at goes
# through its own seam (-InputFile) - and its stdout is read line by line while it runs.

function Start-HordeCliRun {
    # Start horde as its own process: { p; lines; next; task; err; ended }. Read it with
    # Wait-HordeCliLine, end it with Complete-HordeCliRun or Stop-HordeCliRun.
    param([Parameter(Mandatory = $true)][string]$Root, [string[]]$HordeArgs = @(), [hashtable]$Env = @{})
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $quoted = @($HordeArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"" + (Join-Path $Root "horde.ps1") + "`" " + ($quoted -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    return [pscustomobject]@{ p = $p; lines = (New-Object System.Collections.ArrayList); next = 0; task = $null; err = $p.StandardError.ReadToEndAsync(); ended = $false }
}

function Wait-HordeCliLine {
    # The next line the run prints that is -Like the pattern (case-sensitive), after the last one this
    # returned; $null when the run ends or -Seconds pass first.
    param([Parameter(Mandatory = $true)]$Run, [Parameter(Mandatory = $true)][string]$Like, [int]$Seconds = 90)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ($true) {
        while ($Run.next -lt $Run.lines.Count) { $l = $Run.lines[$Run.next]; $Run.next++; if ($l -clike $Like) { return $l } }
        if ($Run.ended -or (Get-Date) -gt $deadline) { return $null }
        if ($null -eq $Run.task) { $Run.task = $Run.p.StandardOutput.ReadLineAsync() }
        if ($Run.task.Wait(200)) {
            $l = $Run.task.Result
            $Run.task = $null
            if ($null -eq $l) { $Run.ended = $true } else { [void]$Run.lines.Add($l) }
        }
    }
}

function Complete-HordeCliRun {
    # Wait up to -Seconds for the run to end: { code; out }, out every line it printed then its stderr;
    # code -1 when it had to be stopped.
    param([Parameter(Mandatory = $true)]$Run, [int]$Seconds = 90)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while (-not $Run.ended -and (Get-Date) -lt $deadline) { $null = Wait-HordeCliLine -Run $Run -Like "*" -Seconds ([int][System.Math]::Max(1, ($deadline - (Get-Date)).TotalSeconds)) }
    if (-not $Run.p.WaitForExit(10000)) { Stop-HordeCliRun $Run; $null = $Run.p.WaitForExit(10000); return [pscustomobject]@{ code = -1; out = (($Run.lines -join "`n") + "`n(stopped: it did not end in time)") } }
    return [pscustomobject]@{ code = $Run.p.ExitCode; out = (($Run.lines -join "`n") + "`n" + $Run.err.Result) }
}

function Stop-HordeCliRun {
    param($Run)
    if ($null -ne $Run -and -not $Run.p.HasExited) { try { $Run.p.Kill() } catch { } }
}
