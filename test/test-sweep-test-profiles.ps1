# DOES THE POST-MERGE NET'S SWEEP REMOVE ONLY HORDE'S OWN STALE TEST-BROWSER PROFILES?
#
# tools/SweepTestProfiles.ps1 deletes folders under %TEMP%, so every way it could delete the wrong thing
# is attacked here, in a folder of this suite's own standing in for %TEMP% (never the real one): a
# young folder, a near-miss name of every kind, a folder a live process names, a link at the top and a
# link inside, and -WhatIf. Each kept folder is checked to still be there with its contents, and each
# removed one to be gone. The process that "uses" a folder is one this suite starts (a sleeping
# PowerShell whose command line names the folder, as a browser's --user-data-dir does) and ends itself.
# test/mutations/sweep-test-profiles.psd1 holds the must-fail twins: each rule broken, this suite fails.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest

$tool = Join-Path $root "tools\SweepTestProfiles.ps1"
$ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-sweep-profiles-" + [guid]::NewGuid().ToString("N"))
$fakeTemp = Join-Path $work "temp"
$whatIfTemp = Join-Path $work "temp-whatif"
$outside1 = Join-Path $work "outside-inner-link"
$outside2 = Join-Path $work "outside-top-link"
$links = New-Object System.Collections.ArrayList
$sleeper = $null

function New-Hex { param([int]$Length) return [guid]::NewGuid().ToString("N").Substring(0, $Length) }

# A profile nests deep, and past 260 characters .NET Framework refuses a plain path (the first run of
# this suite, under a long %TEMP%, stopped on exactly that). Every file operation here uses the \\?\ form. (Not named Lp: lp is Windows PowerShell's alias of Out-Printer, and an alias wins over a function.)
function Get-LongPath { param([string]$P) if ($P.StartsWith("\\?\")) { return $P }; return "\\?\" + $P }
function Test-There { param([string]$P) return ([System.IO.Directory]::Exists((Get-LongPath $P)) -or [System.IO.File]::Exists((Get-LongPath $P))) }

function New-Profile {
    # A folder shaped like a browser profile: a nested Default\ with a file in it.
    param([string]$Parent, [string]$Name)
    $p = Join-Path $Parent $Name
    [void][System.IO.Directory]::CreateDirectory((Get-LongPath (Join-Path $p "Default")))
    [System.IO.File]::WriteAllText((Get-LongPath (Join-Path $p "Default\Preferences")), "{}")
    [System.IO.File]::WriteAllText((Get-LongPath (Join-Path $p "Local State")), "{}")
    return $p
}

function Set-Old {
    # Every entry of the tree, and the folder itself last, written 48 hours ago. Links are left alone.
    param([string]$Path)
    $Path = Get-LongPath $Path
    $old = [datetime]::UtcNow.AddHours(-48)
    $d = New-Object System.IO.DirectoryInfo -ArgumentList $Path
    foreach ($e in $d.GetFileSystemInfos()) {
        if (($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if ($e -is [System.IO.DirectoryInfo]) { Set-Old -Path $e.FullName } else { [System.IO.File]::SetLastWriteTimeUtc($e.FullName, $old) }
    }
    [System.IO.Directory]::SetLastWriteTimeUtc($Path, $old)
}

function New-Junction {
    param([string]$Link, [string]$Target)
    $null = New-Item -ItemType Junction -Path $Link -Value $Target
    [void]$script:links.Add($Link)
}

function Invoke-Sweep {
    # Runs the shipped tool in a child Windows PowerShell, as the net does. -Temp sets the child's TEMP
    # and TMP, so a run without -Root sweeps that folder as its %TEMP%. { code; out (lines) }.
    param([string[]]$ArgList = @(), [string]$Temp = "")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ps51
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $tool + '" ' + (($ArgList | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($Temp -ne "") { $psi.EnvironmentVariables["TEMP"] = $Temp; $psi.EnvironmentVariables["TMP"] = $Temp }
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $errTask = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        if (-not $p.WaitForExit(60000)) { $p.Kill(); return [pscustomobject]@{ code = -1; out = @("TIMEOUT"); err = "" } }
        $lines = @($out -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne "" })
        foreach ($l in $lines) { Write-Host ("         | " + $l) -ForegroundColor DarkGray }
        return [pscustomobject]@{ code = $p.ExitCode; out = $lines; err = $errTask.Result.Trim() }
    } finally { $p.Dispose() }
}

function Get-Line {
    # The one output line about Name, or "" (a name with a longer name after it is another folder).
    param($Run, [string]$Name)
    $hit = @($Run.out | Where-Object { $_ -cmatch ('\A(REMOVED|WOULD REMOVE|SKIPPED) ' + [regex]::Escape($Name) + '(:|\z)') })
    if ($hit.Count -ne 1) { return "" }
    return "" + $hit[0]
}

try {
    [void][System.IO.Directory]::CreateDirectory($fakeTemp)
    [void][System.IO.Directory]::CreateDirectory($whatIfTemp)

    # --- the folders ---
    $remove = @(
        ("horde-browser-" + (New-Hex 32)),
        ("horde-browser-cleanup-" + (New-Hex 32)),
        ("horde-cf-accounts-" + (New-Hex 12)),
        ("horde-pwa-browser-" + (New-Hex 32)),
        ("horde-decisions-browser-" + (New-Hex 32)),
        ("horde-empty-fleet-" + (New-Hex 32))
    )
    foreach ($n in $remove) { $null = New-Profile -Parent $fakeTemp -Name $n }
    # the empty fleet's own shape (test/lib/FleetPin.ps1): registry\sessions, empty
    [void][System.IO.Directory]::CreateDirectory((Get-LongPath (Join-Path $fakeTemp ($remove[5] + "\registry\sessions"))))
    # the leaked cf-accounts shape: the browser's own horde-browser-<32 hex> profile inside it, with a
    # file deeper than 260 characters (as a real Chrome profile's cache folders reach)
    $inner = New-Profile -Parent (Join-Path $fakeTemp $remove[2]) -Name ("horde-browser-" + (New-Hex 32))
    $deep = Join-Path $inner ("Default\Service Worker\CacheStorage\" + (New-Hex 32) + (New-Hex 8) + "\" + [guid]::NewGuid().ToString() + "\" + [guid]::NewGuid().ToString() + "\" + [guid]::NewGuid().ToString())
    [void][System.IO.Directory]::CreateDirectory((Get-LongPath $deep))
    [System.IO.File]::WriteAllText((Get-LongPath (Join-Path $deep "index-dir-the-real-ones-are-long")), "{}")
    Check ((Join-Path $deep "index-dir-the-real-ones-are-long").Length -gt 260 -and (Test-There (Join-Path $deep "index-dir-the-real-ones-are-long"))) ("CONTROL: the cf-accounts folder holds a file at a path over 260 characters (" + (Join-Path $deep "x").Length + ")")

    $young = "horde-browser-" + (New-Hex 32)
    $null = New-Profile -Parent $fakeTemp -Name $young
    $deepFresh = "horde-pwa-browser-" + (New-Hex 32)
    $null = New-Profile -Parent $fakeTemp -Name $deepFresh

    $h12 = New-Hex 12; $h32 = New-Hex 32
    $nearMiss = @(
        ("horde-cf-accountsX" + $h12),                     # the dash missing
        ("horde-cf-accounts-" + $h12.Substring(0, 11) + "g"), # not hex
        ("horde-cf-accounts-" + $h12 + "a"),               # one hex too many
        ("horde-cf-accounts-" + $h12.Substring(0, 11)),    # one too few
        ("horde-cf-accounts-home-" + $h32),                # another suite's HORDE_HOME, not a profile
        ("horde-browser-" + $h32.ToUpperInvariant()),      # upper-case hex: no suite names it so
        ("xhorde-browser-" + $h32),                        # something before the prefix
        ("horde-browsers-" + $h32),                        # a different prefix
        ("horde-pwa-browser-" + $h32 + "-old"),            # something after
        ("horde-pwa-browserX" + $h32),                     # the PWA suite's: the dash missing
        ("horde-pwa-browser-" + $h32.Substring(0, 31)),    # one hex too few
        ("horde-pwa-browser-" + $h32.Substring(0, 31) + "z"), # not hex
        ("horde-pwa-" + $h32),                             # a shorter prefix
        ("horde-empty-fleet-" + $h32 + "0"),               # the empty fleet's: one hex too many
        ("horde-empty-fleet-" + $h32.Substring(0, 31)),    # one too few
        ("horde-empty-fleet-" + $h32.Substring(0, 31) + "q"), # not hex
        ("horde-empty-fleets-" + $h32),                    # a different prefix
        ("horde-empty-fleet" + $h32),                      # the dash missing
        ("horde-empty-fleet-" + $h32.ToUpperInvariant())   # upper-case hex
    )
    foreach ($n in $nearMiss) { $null = New-Profile -Parent $fakeTemp -Name $n }
    $fileNamed = "horde-browser-" + (New-Hex 32)
    [System.IO.File]::WriteAllText((Join-Path $fakeTemp $fileNamed), "a file, not a folder")

    $inUse = "horde-decisions-browser-" + (New-Hex 32)
    $inUsePath = New-Profile -Parent $fakeTemp -Name $inUse

    # an old matching folder with a junction inside to a folder outside it
    [void][System.IO.Directory]::CreateDirectory($outside1)
    [System.IO.File]::WriteAllText((Join-Path $outside1 "sentinel.txt"), "must survive")
    $withLink = "horde-browser-" + (New-Hex 32)
    $withLinkPath = New-Profile -Parent $fakeTemp -Name $withLink
    # a one-letter name: New-Item cannot make a junction past the 248-character folder limit
    New-Junction -Link (Join-Path $withLinkPath "o") -Target $outside1

    # a top-level junction with a matching name
    [void][System.IO.Directory]::CreateDirectory($outside2)
    [System.IO.File]::WriteAllText((Join-Path $outside2 "sentinel.txt"), "must survive")
    $topLink = "horde-cf-accounts-" + (New-Hex 12)
    New-Junction -Link (Join-Path $fakeTemp $topLink) -Target $outside2

    foreach ($n in @($remove + $nearMiss + @($inUse, $withLink, $deepFresh))) { Set-Old -Path (Join-Path $fakeTemp $n) }
    [System.IO.File]::SetLastWriteTimeUtc((Join-Path $fakeTemp $fileNamed), [datetime]::UtcNow.AddHours(-48))
    Set-Old -Path $outside1; Set-Old -Path $outside2
    # one file deep in an otherwise old profile is fresh: the folder is in use by a run, and stays
    [System.IO.File]::WriteAllText((Get-LongPath (Join-Path $fakeTemp ($deepFresh + "\Default\Preferences"))), "{ fresh }")
    [System.IO.Directory]::SetLastWriteTimeUtc((Get-LongPath (Join-Path $fakeTemp ($deepFresh + "\Default"))), [datetime]::UtcNow.AddHours(-48))
    $topOld = (New-Object System.IO.DirectoryInfo -ArgumentList (Join-Path $fakeTemp $deepFresh)).LastWriteTimeUtc
    Check ($topOld -lt [datetime]::UtcNow.AddHours(-24)) "CONTROL: the deep-fresh folder's own time is old, so only its deep file can keep it"

    # a process of this suite's own that names the in-use folder in its command line, as a browser does
    $spsi = New-Object System.Diagnostics.ProcessStartInfo
    $spsi.FileName = $ps51
    $spsi.Arguments = '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 300 # --user-data-dir=' + $inUsePath + '"'
    $spsi.UseShellExecute = $false
    $spsi.CreateNoWindow = $true
    $sleeper = [System.Diagnostics.Process]::Start($spsi)
    $seen = $false
    for ($i = 0; $i -lt 50 -and -not $seen; $i++) {
        $c = Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId=" + $sleeper.Id) -ErrorAction SilentlyContinue
        $seen = $null -ne $c -and ("" + $c.CommandLine).Contains($inUse)
        if (-not $seen) { Start-Sleep -Milliseconds 100 }
    }
    Check $seen ("CONTROL: the suite's own sleeping process (pid " + $sleeper.Id + ") is running with the in-use folder in its command line")

    Write-Host ""
    Write-Host "--- one sweep of a stand-in %TEMP% (the child's TEMP and TMP), no -Root ---" -ForegroundColor Cyan
    $run = Invoke-Sweep -Temp $fakeTemp
    Check ($run.code -eq 0) ("the sweep exits 0 (" + $run.code + "; " + $run.err + ")")
    Check (@($run.out | Where-Object { $_.TrimEnd('\') -ceq ("sweeping Horde test-browser profiles in " + $fakeTemp) }).Count -eq 1) "with no -Root it sweeps %TEMP% - here the child's TEMP, the stand-in"
    foreach ($n in $remove) {
        Check ((Get-Line -Run $run -Name $n) -ceq ("REMOVED " + $n) -and -not (Test-There (Join-Path $fakeTemp $n))) ("an old " + ($n -replace '[0-9a-f]{12,32}\z', '<hex>') + " folder is removed, and said")
    }
    $yl = Get-Line -Run $run -Name $young
    Check ($yl -like "SKIPPED *within the last 24 hours" -and (Test-There (Join-Path $fakeTemp ($young + "\Default\Preferences")))) ("a young matching folder is kept, and why is said (" + $yl + ")")
    $dl = Get-Line -Run $run -Name $deepFresh
    Check ($dl -like "SKIPPED *within the last 24 hours" -and (Test-There (Join-Path $fakeTemp ($deepFresh + "\Default\Preferences")))) ("an old folder with one fresh file deep inside is kept: its newest write counts, not its own time (" + $dl + ")")
    foreach ($n in $nearMiss) {
        Check ((Test-There (Join-Path $fakeTemp ($n + "\Default\Preferences"))) -and (Get-Line -Run $run -Name $n) -eq "") ("an old near-miss name is kept whole and not listed: " + ($n -replace '[0-9a-fA-F]{11,32}', '<hex>'))
    }
    Check ([System.IO.File]::Exists((Get-LongPath (Join-Path $fakeTemp $fileNamed)))) "an old FILE with a matching name is kept: only folders are profiles"
    $ul = Get-Line -Run $run -Name $inUse
    Check ($ul -like "SKIPPED *in use*" -and (Test-There (Join-Path $inUsePath "Default\Preferences"))) ("an old folder a live process names in its command line is kept, and why is said (" + $ul + ")")
    $wl = Get-Line -Run $run -Name $withLink
    Check ($wl -ceq ("REMOVED " + $withLink) -and -not (Test-There $withLinkPath)) "an old folder holding a junction is removed"
    Check ((Test-There (Join-Path $outside1 "sentinel.txt"))) "and the junction inside it was removed as a link: the folder it pointed to, outside, keeps its file"
    $tl = Get-Line -Run $run -Name $topLink
    Check ($tl -like "SKIPPED *a link*" -and (Test-There (Join-Path $fakeTemp $topLink)) -and (Test-There (Join-Path $outside2 "sentinel.txt"))) ("a top-level junction with a matching name is skipped as a link, and its target keeps its file (" + $tl + ")")
    Check (@($run.out | Where-Object { $_ -like ("swept * " + ($remove.Count + 1) + " removed, 4 skipped") }).Count -eq 1) "the last line counts what was removed and what was skipped"

    Write-Host ""
    Write-Host "--- the in-use folder once its process has ended ---" -ForegroundColor Cyan
    $sleeper.Kill(); [void]$sleeper.WaitForExit(10000); $sleeper.Dispose(); $sleeper = $null
    $run2 = Invoke-Sweep -ArgList @("-Root", $fakeTemp)
    Check ((Get-Line -Run $run2 -Name $inUse) -ceq ("REMOVED " + $inUse) -and -not (Test-There $inUsePath)) "CONTROL: with the process gone, the same old folder is removed - the process was what kept it"

    Write-Host ""
    Write-Host "--- -WhatIf ---" -ForegroundColor Cyan
    $wiName = "horde-cf-accounts-" + (New-Hex 12)
    $null = New-Profile -Parent $whatIfTemp -Name $wiName
    Set-Old -Path (Join-Path $whatIfTemp $wiName)
    $run3 = Invoke-Sweep -ArgList @("-Root", $whatIfTemp, "-WhatIf")
    Check ($run3.code -eq 0 -and (Get-Line -Run $run3 -Name $wiName) -ceq ("WOULD REMOVE " + $wiName)) "-WhatIf lists an old matching folder as one it would remove"
    Check ((Test-There (Join-Path $whatIfTemp ($wiName + "\Default\Preferences")))) "and deletes nothing"
    $run4 = Invoke-Sweep -ArgList @("-Root", $whatIfTemp)
    Check ((Get-Line -Run $run4 -Name $wiName) -ceq ("REMOVED " + $wiName) -and -not (Test-There (Join-Path $whatIfTemp $wiName))) "CONTROL: the same folder, swept without -WhatIf, is removed"

    Write-Host ""
    Write-Host "--- a root that does not exist ---" -ForegroundColor Cyan
    $run5 = Invoke-Sweep -ArgList @("-Root", (Join-Path $work "no-such-folder"))
    Check ($run5.code -eq 0 -and @($run5.out | Where-Object { $_ -like "swept *0 removed, 0 skipped (the folder does not exist)" }).Count -eq 1) "a missing root is said, and the sweep still exits 0"
} finally {
    if ($null -ne $sleeper) { try { if (-not $sleeper.HasExited) { $sleeper.Kill() } } catch { }; $sleeper.Dispose() }
    # Links first, as links, so removing the work folder can never reach through one.
    foreach ($l in $links) { if (Test-Path -LiteralPath $l) { try { [System.IO.Directory]::Delete($l, $false) } catch { } } }
    if ((Split-Path -Leaf $work) -match '\Ahorde-sweep-profiles-[0-9a-f]{32}\z' -and (Test-There $work)) {
        try { [System.IO.Directory]::Delete((Get-LongPath $work), $true) } catch { Write-Host ("  (the work folder was not fully removed: " + $_.Exception.Message + ")") -ForegroundColor Yellow }
    }
}

Complete-HordeSuite -Success "the sweep removes only old, unused, real Horde test-browser profile folders, follows no link, and -WhatIf deletes nothing"
