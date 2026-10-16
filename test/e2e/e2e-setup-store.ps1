# END TO END: `horde setup` AND THE MICROSOFT STORE (CONTRIBUTING 16), THE SHIPPED COMMAND DRIVEN AS A USER DRIVES IT.
#
# 2026-10-16: a Store update of PowerShell closed every pwsh.exe and every fleet session. `horde setup`
# now holds the machine to two steps - Store automatic updates off, PowerShell 7 from the MSI - checked
# after every other step, and this scenario runs the real horde.ps1 through powershell.exe against a
# PRETEND MACHINE (a JSON file named by HORDE_SETUP_FAKE_MACHINE, cli/SetupStore.ps1):
# nothing real is read or changed for those two steps, no pane is spawned, no real policy is written, no
# installer is downloaded. The pretend install runs the REAL download-hash-install-verify pipeline over
# stand-ins, so a wrong hash is refused here too.
#   1. A machine as it was on the day (policy unset, the Store pwsh first, no MSI), not elevated:
#      setup says it is a pretend machine, runs EVERY other step first (the relay settings are made),
#      then lists BOTH Store steps as outstanding, each as one sentence naming the one elevated run and
#      what it will set, and changes nothing on the pretend machine.
#   2. -Check, even elevated: changes nothing.
#   3. The same machine, elevated: the policy is set, the MSI installed, the Store copy only noted
#      (never removed).
#   4. A second run: both steps done and say nothing to change; no action is recorded.
#   5. A wrong installer hash: the policy is set, the MSI is not installed, the reason is said.
#   6. -Steps lists both steps, last, and says setup fixes both.
# NOT THE REAL MACHINE: the real Store policy is read before and after only to show it did not move.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\Cli.ps1")
Set-StrictMode -Version Latest

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-e2e-setup-store-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
$prof = Join-Path $work "profile"
[void][System.IO.Directory]::CreateDirectory($prof)
$machine = Join-Path $work "pretend-machine.json"
$storePwsh = "C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.3.0_x64__8wekyb3d8bbwe\pwsh.exe"
$realBefore = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsStore", "AutoDownload", $null)

function Set-Machine {
    # The pretend machine's state, as a file. -GoodHash false makes winget publish a hash the download lacks.
    param([bool]$Elevated, $Policy, [string]$Resolved, [string]$MsiVersion, [bool]$GoodHash = $true)
    $content = "pretend installer bytes"
    $f = Join-Path $work "hash.bin"
    [System.IO.File]::WriteAllText($f, $content)
    $h = $(if ($GoodHash) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash } else { "0" * 64 })
    $m = [ordered]@{ elevated = $Elevated; storePolicy = $Policy; pwshResolved = $Resolved; msiVersion = $MsiVersion; msiWillBe = "7.5.3"
        wingetText = ("Installer Type: wix`nInstaller Url: https://example.invalid/PowerShell-7.5.3-win-x64.msi`nInstaller SHA256: " + $h + "`n"); msiContent = $content; actions = @() }
    [System.IO.File]::WriteAllText($machine, (ConvertTo-Json -InputObject $m -Depth 4), [System.Text.Encoding]::ASCII)
}
function Get-Actions {
    $m = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($machine))
    return (@($m.actions) -join ",")
}
function Run-Setup {
    # The shipped command: { code; out; lines; last }. HORDE_SETUP_FAKE_MACHINE names the pretend machine.
    param([string]$HordeHome, [string[]]$More = @())
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs (@("setup", "-NoFix", "machine-identity") + $More) -Env @{ HORDE_HOME = $HordeHome; USERPROFILE = $prof; HORDE_SETUP_FAKE_MACHINE = $machine }
    $lines = @($r.out -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
    return [pscustomobject]@{ code = $r.code; out = $r.out; lines = $lines; last = $(if ($lines.Count -gt 0) { $lines[-1] } else { "" }) }
}
function Has { param($R, [string]$Like) return (@($R.lines | Where-Object { $_ -clike $Like }).Count -ge 1) }

try {
    Write-Host ""
    Write-Host "--- 1. the machine as it was on the day, not elevated: every other step first ---" -ForegroundColor Cyan
    Set-Machine -Elevated $false -Policy $null -Resolved $storePwsh -MsiVersion ""
    $h1 = Join-Path $work "home1"
    $s = Run-Setup $h1
    Check ($s.code -eq 0 -and $s.lines[0] -clike "horde setup: using the pretend machine in *HORDE_SETUP_FAKE_MACHINE*") ("setup says first that it is a pretend machine (exit " + $s.code + ")")
    Check ((Has $s "  done  what Horde needs:*") -and (Has $s "  fixed Horde home:*") -and (Has $s "  fixed relay settings:*")) "the other steps ran and were fixed first, up to the one it was told not to fix"
    Check ((Has $s "  TO DO machine identity:*") -and (Has $s "  TO DO Microsoft Store automatic updates off: Microsoft Store automatic updates are not turned off (HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore AutoDownload is unset)") -and (Has $s "  TO DO PowerShell 7 from the MSI, not the Microsoft Store: the pwsh on the search path is the Microsoft Store copy*")) "a step stopped earlier, and BOTH Store steps are still reported as outstanding"
    Check ($s.last -clike "next: *needs one elevated run of horde setup (a PowerShell window opened as administrator); it will set HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore AutoDownload to 2*; needs one elevated run of horde setup*it will install the PowerShell 7 MSI*") "the closing line carries each, as one sentence naming the one elevated run and what it will set"
    Check ((Get-Actions) -ceq "") "and the pretend machine was changed in no way"

    Write-Host "--- 2. -Check, elevated, fixes nothing ---" -ForegroundColor Cyan
    Set-Machine -Elevated $true -Policy $null -Resolved $storePwsh -MsiVersion ""
    $s = Run-Setup $h1 @("-Check")
    Check ((Has $s "  TO DO Microsoft Store automatic updates off:*") -and (Get-Actions) -ceq "") "-Check reports the policy as to do and sets nothing"

    Write-Host "--- 3. elevated: the policy set, the MSI installed, the Store copy only noted ---" -ForegroundColor Cyan
    $s = Run-Setup $h1
    Check ((Has $s "  fixed Microsoft Store automatic updates off: set the Store policy AutoDownload to 2*") -and (Has $s "  fixed PowerShell 7 from the MSI, not the Microsoft Store: installed PowerShell 7.5.3 from the MSI at *")) "both steps are fixed, and say so"
    Check ((Get-Actions) -ceq "set-store-policy,install-msi") ("exactly the two changes were made, in order (" + (Get-Actions) + ")")
    Check (Has $s ("        note: pwsh on the search path is the Microsoft Store copy (" + $storePwsh + "); Horde starts *by its full path; removing the Microsoft Store copy closes every pwsh.exe running from it, so setup leaves it*")) "the Store copy still on the path is noted, with why setup leaves it"
    Check (-not (Has $s "*uninstall*") -and -not (Has $s "*Remove-AppxPackage*")) "setup never speaks of uninstalling the Store copy, and does not"
    Check ($s.last -ceq "next: horde relay identity -New") "and the closing line is the one step left, with no Store sentence"

    Write-Host "--- 4. a second run changes nothing and says so ---" -ForegroundColor Cyan
    $before = Get-Actions
    $s = Run-Setup $h1
    Check ((Has $s "  done  Microsoft Store automatic updates off: Store automatic updates are off by policy (AutoDownload = 2); nothing to change") -and (Has $s "  done  PowerShell 7 from the MSI, not the Microsoft Store: PowerShell 7.5.3 is installed from the MSI at *nothing to change")) "both steps are done and say nothing to change"
    Check ((Get-Actions) -ceq $before) "and no action was recorded"

    Write-Host "--- 5. a wrong installer hash is refused ---" -ForegroundColor Cyan
    Set-Machine -Elevated $true -Policy $null -Resolved $storePwsh -MsiVersion "" -GoodHash $false
    $h2 = Join-Path $work "home2"
    $s = Run-Setup $h2
    Check ((Get-Actions) -ceq "set-store-policy") ("the policy was set, the installer was NOT run (" + (Get-Actions) + ")")
    Check ((Has $s "  TO DO PowerShell 7 from the MSI, not the Microsoft Store: *installing the PowerShell 7 MSI failed: the downloaded installer's SHA-256 *was not run*")) "the reason is said"

    Write-Host "--- 5b. -Json names the pretend machine in the data ---" -ForegroundColor Cyan
    $j = Run-Setup $h2 @("-Json")
    $rep = $null
    try { $rep = ($j.out.Trim() | ConvertFrom-Json) } catch { $rep = $null }
    Check ($null -ne $rep -and "" + $rep.fakeMachine -ceq $machine) "-Json is one parseable document and its fakeMachine field names the pretend machine"

    Write-Host "--- 6. -Steps ---" -ForegroundColor Cyan
    $r = Invoke-HordeCliProcess -Root $root -HordeArgs @("setup", "-Steps", "-Json") -Env @{ HORDE_HOME = $h2; USERPROFILE = $prof; HORDE_SETUP_FAKE_MACHINE = $machine }
    $listed = $null
    try { $listed = (($r.out.Trim()) | ConvertFrom-Json) } catch { $listed = $null }
    $ids = $(if ($null -ne $listed) { @($listed.steps | ForEach-Object { $_.id }) } else { @() })
    $mine = $(if ($null -ne $listed) { @($listed.steps | Where-Object { @("store-updates-off", "powershell-msi") -ccontains $_.id }) } else { @() })
    Check ($r.code -eq 0 -and $mine.Count -eq 2 -and @($mine | Where-Object { $_.fixedBySetup }).Count -eq 2 -and ($ids[-2..-1] -join ",") -ceq "store-updates-off,powershell-msi") "-Steps lists both steps last, and says setup fixes both"

    $realAfter = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsStore", "AutoDownload", $null)
    Check (("" + $realBefore) -ceq ("" + $realAfter)) "the real Store policy did not move"
} finally {
    if ($work -like "*horde-e2e-setup-store-*" -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $work)) "the scenario's folder is gone"

Complete-HordeSuite -Success "horde setup checks Store updates off and PowerShell 7 from the MSI after every other step: not elevated it lists both as outstanding and changes nothing, elevated it fixes both once, a wrong hash installs nothing, and a second run changes nothing"
