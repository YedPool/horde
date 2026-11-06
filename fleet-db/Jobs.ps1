# fleet-db/Jobs.ps1 - the PowerShell half of `horde job` and `horde signal` (T-0412, piece 3 of T-0299).
#
# WHY A FILE OF ITS OWN: both commands do the same four things before node can run - find the home, find node 24, turn the
# named parameters into the flags jobs-cli.mjs takes, and report a failure - and a copy in each command is a copy that
# gets fixed in one. The rules of the verbs themselves are in fleet-db/jobs.mjs; this file only carries the call.
#
# EXIT CODES: horde.ps1 reports 0 or 1 whatever a command does (a command fails by throwing). The node side keeps the finer
# codes (2 no home, 3 busy, 4 no fleet.db yet): node's own one-line reason is printed first, and the throw names the code,
# so a caller that must tell "busy, try again" from "refused" reads the message, or runs fleet-db/jobs-cli.mjs directly.
#
# POWERSHELL 5.1 HAZARDS THAT SHAPE THE ARGUMENTS (CONTRIBUTING 12):
#   - an EMPTY string passed to a native program is dropped, so `--owner "" --by x` would reach node as `--owner --by x`
#     and give the owner the value "--by". An empty value is refused here, in words, before node starts;
#   - a double quote inside an argument is mangled by the native-argument quoting of 5.1 (and differs in 7), so a value
#     holding one is refused and the text goes in a file (-File), which is what -File is for.
# No Set-StrictMode here: this file is dot-sourced.

function Invoke-HordeJobsCli {
    # -Noun job or signal, -Verb the node verb, -Values an ordered map of node flag -> value (only the ones given),
    # -Switches the node flags that stand alone. Writes node's output lines; throws on a non-zero exit.
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Noun,
        [Parameter(Mandatory = $true)][string]$Verb,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Values,
        [string[]]$Switches = @()
    )
    . (Join-Path $Root "core\Home.ps1")
    $resolved = Resolve-HordeHome
    if ($resolved.source -eq "default") { throw ("horde " + $Noun + " needs HORDE_HOME set to the Horde home (or a home pointer: horde home set -Path <folder>): fleet.db is the fleet's one database and is never made in a default folder") }

    $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $node) { throw "fleet.db needs Node.js 24 or later, and node is not installed or not on this machine's PATH" }
    $major = 0
    $ver = "" + (& $node.Source --version)
    if ($ver -match '^v(\d+)\.') { $major = [int]$Matches[1] }
    if ($major -lt 24) { throw ("fleet.db needs Node.js 24 or later, and this machine has " + $ver.Trim()) }

    $nodeArgs = @($Noun, $Verb)
    foreach ($flag in $Values.Keys) {
        $value = [string]$Values[$flag]
        $name = "-" + (($flag.TrimStart("-") -split "-" | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join "")
        if ($value.Trim() -eq "") { throw ($name + " is empty; give it a value, or leave it out") }
        if ($value.Contains('"')) { throw ($name + " holds a double quote, which a command line cannot carry safely; put the text in a file and use -File") }
        if ($flag -eq "--file") { $value = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($value) }
        $nodeArgs += @($flag, $value)
    }
    foreach ($s in $Switches) { $nodeArgs += $s }

    # THE CALL IS MADE WITH A PROCESS OF OUR OWN, not with &, so both shells quote alike (fleet-db/Sync.ps1 does the same): every
    # argument is quoted, and backslashes just before the closing quote are doubled, or a value ending in one (an owner that is a
    # folder, C:\x\) would escape that quote in 5.1 and swallow the next argument.
    $script = Join-Path $Root "fleet-db\jobs-cli.mjs"
    $quoted = @(@($script) + $nodeArgs | ForEach-Object { '"' + ($_ -replace '(\\+)$', '$1$1') + '"' })
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = $quoted -join " "
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables["HORDE_HOME"] = $resolved.path
    $child = [System.Diagnostics.Process]::Start($psi)
    try {
        $errTask = $child.StandardError.ReadToEndAsync()
        $outText = $child.StandardOutput.ReadToEnd()
        $child.WaitForExit()
        $code = $child.ExitCode
        $errText = $errTask.Result
    } finally { $child.Dispose() }
    if ($outText.Trim() -ne "") { foreach ($line in ($outText.TrimEnd() -split "`r?`n")) { Write-Output $line } }
    if ($errText.Trim() -ne "") { foreach ($line in ($errText.TrimEnd() -split "`r?`n")) { [Console]::Error.WriteLine($line) } }
    if ($code -ne 0) { throw ("horde " + $Noun + " " + $Verb + " stopped with exit code " + $code) }
}
