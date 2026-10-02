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
