# test/lib/Program.ps1 - start an installed program once, with a changed environment, and read what it
# printed. For suites that read a harness's effective behaviour back from the real program (the
# permission readbacks in agents/<name>/test/, review of PR #60): the descriptor's flags alone did
# not decide what the program did, so the program itself is asked.
#
# Streams are read through the process API, never with 2>&1, which under PowerShell 5.1 turns the
# first stderr line into a terminating error (CONTRIBUTING 12). An npm-installed program is a .cmd
# shim, which CreateProcess cannot start directly, so a .cmd or .bat is run through cmd.exe.
#
# ONLY ITS OWN PROCESS IS EVER STOPPED (tasks/lessons.md, "anything that kills"): a run past
# -TimeoutSeconds kills the process this function started, by the handle it holds, and nothing found
# by name or by a recorded pid. Anything that process started is left alone and the run says it
# timed out, so a person can look.

function Find-HordeTestProgram {
    # The full path of a program on PATH, or "" when there is none.
    param([Parameter(Mandatory = $true)][string]$Name)
    $c = @(Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)
    if ($c.Count -eq 0) { return "" }
    return "" + $c[0].Source
}

function Invoke-HordeTestProgram {
    # Returns { code; out; err; timedOut }. -Env sets a variable for the child alone; a $null value
    # removes it from the child's environment. An argument with a space or a quote is quoted.
    param([Parameter(Mandatory = $true)][string]$Path, [string[]]$ArgList = @(), [hashtable]$Env = @{},
        [Parameter(Mandatory = $true)][string]$WorkDir, [int]$TimeoutSeconds = 90)
    $quoted = @($ArgList | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } })
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -eq ".cmd" -or $ext -eq ".bat") {
        $psi.FileName = Join-Path $env:SystemRoot "System32\cmd.exe"
        $psi.Arguments = '/d /s /c ""' + $Path + '" ' + ($quoted -join " ") + '"'
    } else {
        $psi.FileName = $Path
        $psi.Arguments = ($quoted -join " ")
    }
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    foreach ($k in @($Env.Keys)) {
        if ($null -eq $Env[$k]) { if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) } }
        else { $psi.EnvironmentVariables[$k] = "" + $Env[$k] }
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        # stdin closed at once: a program that waits for input reads end of file, never a person.
        $p.StandardInput.Close()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $timedOut = $false
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) { $timedOut = $true; try { $p.Kill() } catch { } ; $null = $p.WaitForExit(10000) }
        else { $p.WaitForExit() }
        $code = $null
        if ($p.HasExited) { $code = $p.ExitCode }
        $out = ""; $err = ""
        if ($outTask.Wait(10000)) { $out = $outTask.Result }
        if ($errTask.Wait(10000)) { $err = $errTask.Result }
        return [pscustomobject]@{ code = $code; out = $out; err = $err; timedOut = $timedOut }
    } finally { $p.Dispose() }
}
