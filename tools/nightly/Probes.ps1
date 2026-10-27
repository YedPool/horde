# tools/nightly/Probes.ps1 - what this machine's night can do, asked once a night by tools/NightlyNet.ps1. T-0331.
#
# A suite declares what it needs in its own header ("# nightly-needs: symlink"; core/NightlyNet.ps1,
# Read-HordeNightlyNeeds). Each probe here answers one need as { ok; why } by TRYING it where it can, never by
# inferring it from a setting: on the night of 2026-10-26 the scheduled task (non-elevated) had none of these, and 15
# units went red for it. A probe that throws answers ok = false with the error as its why, so a need is never taken
# as met on a probe that did not finish. Every probe is read-only on the machine, apart from the symbolic link probe's
# own temporary folder, which it removes.
# Windows PowerShell 5.1 and PowerShell 7. ASCII only.

function Test-HordeNightlySymlinkProbe {
    # May this account make a symbolic link? Tried the way the suites make theirs (cmd.exe mklink, a file link, no /D /J
    # /H), in a folder of its own under the temp path, then the link and the folder are removed. A junction needs no
    # privilege, so it is not tried: no suite that only makes junctions declares this need.
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-nightly-probe-" + [guid]::NewGuid().ToString("N"))
    $target = Join-Path $dir "target.txt"
    $link = Join-Path $dir "link.txt"
    try {
        [void][System.IO.Directory]::CreateDirectory($dir)
        [System.IO.File]::WriteAllText($target, "probe")
        $said = @(& cmd.exe /d /c ("mklink `"" + $link + "`" `"" + $target + "`" 2>&1"))
        $isLink = [System.IO.File]::Exists($link) -and (([System.IO.File]::GetAttributes($link) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($isLink) { return [pscustomobject]@{ ok = $true; why = "a symbolic link was made and removed" } }
        $text = ((@($said | ForEach-Object { ("" + $_).Trim() }) | Where-Object { $_ -ne "" }) -join " ")
        if ($text -eq "") { $text = "mklink made no link" }
        return [pscustomobject]@{ ok = $false; why = ("this account may not make a symbolic link (" + $text + ")") }
    } catch {
        return [pscustomobject]@{ ok = $false; why = ("the symbolic link probe failed: " + $_.Exception.Message) }
    } finally {
        try { if ([System.IO.File]::Exists($link)) { [System.IO.File]::Delete($link) } } catch { }
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-HordeNightlyElevatedProbe {
    # Is this process's token elevated? By the token: Administrators is an ENABLED group of it. Under UAC a filtered
    # token holds Administrators as deny-only, so IsInRole is false there, as it is for a user who is no administrator.
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) { return [pscustomobject]@{ ok = $true; why = "the token is elevated" } }
        return [pscustomobject]@{ ok = $false; why = "the token is not elevated (Administrators is not an enabled group of it)" }
    } catch { return [pscustomobject]@{ ok = $false; why = ("the elevation probe failed: " + $_.Exception.Message) } }
}

function Test-HordeNightlyWslProbe {
    # Is WSL here and working? wsl.exe in System32 (a stub of it is there even where WSL is not installed), and its distro
    # list (wsl.exe --list --quiet) answers exit 0 with at least one name, inside -TimeoutSeconds.
    param([int]$TimeoutSeconds = 60)
    try {
        $wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
        if (-not (Test-Path -LiteralPath $wsl -PathType Leaf)) { return [pscustomobject]@{ ok = $false; why = ("there is no " + $wsl) } }
        # Its own process with standard input redirected and closed: started by Start-Process under PowerShell 7 (as
        # Invoke-HordeNightlyProcess does) wsl.exe never exited and ran into the time limit, where 5.1 answered in under
        # a second (measured 2026-10-27 on a machine with no WSL). Ended by ITS PID past the limit, never by name.
        $psi = New-Object System.Diagnostics.ProcessStartInfo($wsl, "--list --quiet")
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        # wsl.exe writes UTF-16 with no byte order mark.
        $psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode; $psi.StandardErrorEncoding = [System.Text.Encoding]::Unicode
        $p = [System.Diagnostics.Process]::Start($psi)
        $r = [pscustomobject]@{ code = $null; timedOut = $false; lines = @() }
        try {
            $p.StandardInput.Close()
            $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
            if (-not $p.WaitForExit([math]::Max(1, $TimeoutSeconds) * 1000)) { $r.timedOut = $true; try { $p.Kill() } catch { } }
            else { $p.WaitForExit(); $r.code = $p.ExitCode; $r.lines = @(($outTask.Result + "`n" + $errTask.Result) -split "`r?`n") }
        } finally { $p.Dispose() }
        $lines = @(@($r.lines) | ForEach-Object { (("" + $_) -replace "`0", "").Trim() } | Where-Object { $_ -ne "" })
        if ($r.timedOut) { return [pscustomobject]@{ ok = $false; why = ("wsl.exe --list did not answer in " + $TimeoutSeconds + " s") } }
        if ($r.code -eq 0 -and $lines.Count -gt 0) { return [pscustomobject]@{ ok = $true; why = ("WSL lists " + $lines.Count + " distro(s)") } }
        $text = ($lines -join " "); if ($text.Length -gt 200) { $text = $text.Substring(0, 200) }
        return [pscustomobject]@{ ok = $false; why = ("WSL has no working distro list (exit " + $r.code + ": " + $text + ")") }
    } catch { return [pscustomobject]@{ ok = $false; why = ("the WSL probe failed: " + $_.Exception.Message) } }
}

function Test-HordeNightlyWezfleetRepoProbe {
    # Is a wezfleet checkout named for the suites that read its source? HORDE_WEZFLEET_REPO set, and its lib\Hierarchy.ps1
    # there (what test/test-roles.ps1 reads). The night's clone has no checkout beside it, so the variable is the one way.
    try {
        $r = "" + $env:HORDE_WEZFLEET_REPO
        if ($r.Trim() -eq "") { return [pscustomobject]@{ ok = $false; why = "HORDE_WEZFLEET_REPO is not set" } }
        $h = Join-Path $r "lib\Hierarchy.ps1"
        if (Test-Path -LiteralPath $h -PathType Leaf) { return [pscustomobject]@{ ok = $true; why = ("the checkout at " + $r + " has lib\Hierarchy.ps1") } }
        return [pscustomobject]@{ ok = $false; why = ("HORDE_WEZFLEET_REPO names " + $r + ", which has no lib\Hierarchy.ps1") }
    } catch { return [pscustomobject]@{ ok = $false; why = ("the wezfleet checkout probe failed: " + $_.Exception.Message) } }
}

function Get-HordeNightlyProbes {
    # Every need's probe answer, as a hashtable name -> { ok; why }, one key per Get-HordeNightlyNeedNames.
    return @{
        "symlink"       = (Test-HordeNightlySymlinkProbe)
        "elevated"      = (Test-HordeNightlyElevatedProbe)
        "wsl"           = (Test-HordeNightlyWslProbe)
        "wezfleet-repo" = (Test-HordeNightlyWezfleetRepoProbe)
    }
}
