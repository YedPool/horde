# DOES `horde setup` KEEP HORDE OFF MICROSOFT STORE PACKAGES, DECIDING EVERY CASE FROM INJECTED ANSWERS?
#
# cli/SetupStore.ps1 and the store-updates-off and powershell-msi steps (CONTRIBUTING 16). 2026-10-16: a
# Store update of PowerShell closed every pwsh.exe and every fleet session. This suite holds the
# decisions and the install pipeline with stand-ins for everything real: the registry, the search
# path, winget, the download, msiexec. NOTHING HERE WRITES THE REAL STORE POLICY OR INSTALLS ANYTHING:
# the real AutoDownload value is only read, before and after, to prove it did not move.
#   1. WHAT IS A STORE PATH: a WindowsApps folder, any case, either slash; the MSI folder is not one.
#   2. THE POLICY: only AutoDownload = 2 is done; unset, 0 and 1 are not; not elevated says it needs an
#      elevated run and what it will set, elevated says nothing to wait for.
#   3. POWERSHELL 7: Store path with no MSI, Store path with the MSI (done, noted), missing, MSI only;
#      the Store copy is never asked to be removed by setup, only said it can be.
#   4. WINGET'S TEXT: address and SHA-256 read; no hash, a short hash, an http address each refused.
#   5. THE INSTALL: a wrong hash never reaches msiexec; each failing stage says which and stops; 3010 is
#      success; a pwsh that reports nothing is a failure.
#   6. THE STEPS, with counted stand-ins: not elevated tries nothing; elevated fixes once; a second run
#      changes nothing and says so; a failed install is a to-do with the reason, never a "fixed".

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "JsonText")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
foreach ($f in @("SetupStore", "Setup")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
Set-StrictMode -Version Latest

$realBefore = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsStore", "AutoDownload", $null)
$msiPath = "C:\Program Files\PowerShell\7\pwsh.exe"
$storePwsh = "C:\Program Files\WindowsApps\Microsoft.PowerShell_7.5.3.0_x64__8wekyb3d8bbwe\pwsh.exe"

Write-Host ""
Write-Host "--- 1. what is a Store path ---" -ForegroundColor Cyan
Check (Test-HordeSetupStorePath $storePwsh) "a package folder under WindowsApps is a Store path"
Check (Test-HordeSetupStorePath "c:/program files/windowsapps/x/pwsh.exe") "any case and forward slashes too"
Check (Test-HordeSetupStorePath "C:\Users\a\AppData\Local\Microsoft\WindowsApps\pwsh.exe") "the per-user alias folder is a Store path"
Check (-not (Test-HordeSetupStorePath $msiPath)) "MUST FAIL: the MSI folder is not a Store path"
Check (-not (Test-HordeSetupStorePath "")) "MUST FAIL: no path is not a Store path"
Check (-not (Test-HordeSetupStorePath "C:\tools\WindowsAppsX\pwsh.exe")) "MUST FAIL: a folder that only starts with the word is not one"

Write-Host "--- 2. the policy ---" -ForegroundColor Cyan
$d = Get-HordeSetupStorePolicyDecision -Policy 2 -Elevated $false
Check ($d.done -and $d.said -clike "*nothing to change*" -and $d.next -ceq "") "AutoDownload = 2 is done, and says nothing needs changing"
foreach ($bad in @($null, 0, 1, 4)) {
    $d = Get-HordeSetupStorePolicyDecision -Policy $bad -Elevated $false
    Check (-not $d.done -and $d.next -clike "this needs an elevated run*AutoDownload to 2*") ("MUST FAIL: policy " + $(if ($null -eq $bad) { "unset" } else { $bad }) + " is not done; not elevated, the one sentence says it needs an elevated run and what it will set")
}
$d = Get-HordeSetupStorePolicyDecision -Policy $null -Elevated $true
Check (-not $d.done -and $d.next -ceq "" -and $d.said -clike "*AutoDownload is unset*") "unset and elevated: not done, and no sentence about waiting for an elevated run"
Check ((Get-HordeSetupStorePolicyDecision -Policy 0 -Elevated $true).said -clike "*AutoDownload is 0*") "the value found is named"

Write-Host "--- 3. PowerShell 7 ---" -ForegroundColor Cyan
$d = Get-HordeSetupPowerShellDecision -Resolved $storePwsh -MsiPath $msiPath -MsiVersion "" -Elevated $true
Check (-not $d.done -and $d.kind -ceq "store" -and $d.said -clike "*Microsoft Store copy*no MSI install*" -and @($d.notes).Count -eq 1 -and $d.notes[0] -clike "*remove it when no session runs on it*") "Store path and no MSI: not done, the Store copy named, and it may be removed when no session runs on it"
$d = Get-HordeSetupPowerShellDecision -Resolved $storePwsh -MsiPath $msiPath -MsiVersion "7.5.3.0" -Elevated $false
Check ($d.done -and $d.kind -ceq "ok" -and @($d.notes).Count -eq 1 -and $d.notes[0] -clike "*Microsoft Store copy*by its full path*") "Store path first on the path but the MSI there: done, with the Store copy noted"
$d = Get-HordeSetupPowerShellDecision -Resolved "" -MsiPath $msiPath -MsiVersion "" -Elevated $true
Check (-not $d.done -and $d.kind -ceq "missing" -and $d.said -clike "PowerShell 7 is not installed*" -and @($d.notes).Count -eq 0) "no pwsh anywhere: missing, with no Store note"
$d = Get-HordeSetupPowerShellDecision -Resolved $msiPath -MsiPath $msiPath -MsiVersion "7.5.3.0" -Elevated $false
Check ($d.done -and @($d.notes).Count -eq 0 -and $d.said -clike "*7.5.3.0*nothing to change*") "the MSI copy only: done, no note, nothing to change"
$d = Get-HordeSetupPowerShellDecision -Resolved $storePwsh -MsiPath $msiPath -MsiVersion "" -Elevated $false
Check ($d.next -clike "this needs an elevated run*MSI*" -and $d.next -notlike "*uninstall*") "not elevated: one sentence says it needs an elevated run and what it will install, and no uninstall"
Check ((Get-HordeSetupPowerShellDecision -Resolved "" -MsiPath $msiPath -MsiVersion "" -Elevated $true).next -ceq "") "elevated: no wait sentence"

Write-Host "--- 4. winget's text ---" -ForegroundColor Cyan
$sha = "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789"
$good = "Found PowerShell [Microsoft.PowerShell]`n  Installer Type: wix`n  Installer Url: https://example.invalid/PowerShell-7.5.3-win-x64.msi`n  Installer SHA256: " + $sha + "`n"
$i = Read-HordeSetupWingetInstaller -Text $good
Check ($i.ok -and $i.url -ceq "https://example.invalid/PowerShell-7.5.3-win-x64.msi" -and $i.sha256 -ceq $sha.ToLowerInvariant()) "the address and the SHA-256 are read, the hash in lower case"
Check (-not (Read-HordeSetupWingetInstaller -Text "Installer Url: https://x/y.msi`n").ok) "MUST FAIL: no hash"
Check (-not (Read-HordeSetupWingetInstaller -Text ("Installer Url: https://x/y.msi`nInstaller SHA256: abc123`n")).ok) "MUST FAIL: a short hash"
Check (-not (Read-HordeSetupWingetInstaller -Text ("Installer Url: http://x/y.msi`nInstaller SHA256: " + $sha + "`n")).ok) "MUST FAIL: an http address"
Check (-not (Read-HordeSetupWingetInstaller -Text "").ok) "MUST FAIL: empty text"

Write-Host "--- 5. the install pipeline ---" -ForegroundColor Cyan
$script:calls = New-Object System.Collections.ArrayList
$script:msiBytes = "pretend-msi"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-setup-store-test-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($tmp)
$pretend = Join-Path $tmp "pretend.bin"
[System.IO.File]::WriteAllText($pretend, $script:msiBytes)
$script:hashOf = (Get-FileHash -LiteralPath $pretend -Algorithm SHA256).Hash
$script:wingetText = "Installer Url: https://example.invalid/p.msi`nInstaller SHA256: " + $script:hashOf + "`n"
function New-Stand {
    $script:calls.Clear()
    return @{
        winget   = { [void]$script:calls.Add("winget"); $script:wingetText }
        download = { param($Url, $Dir) [void]$script:calls.Add("download:" + $Url); $f = Join-Path $Dir "p.msi"; [System.IO.File]::WriteAllText($f, $script:msiBytes); $f }
        hash     = { param($Path) [void]$script:calls.Add("hash"); (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
        msiexec  = { param($Msi) [void]$script:calls.Add("msiexec"); 0 }
        run      = { param($Pwsh) [void]$script:calls.Add("run:" + $Pwsh); "7.5.3" }
    }
}
try {
    $r = Install-HordeSetupPowerShellMsi -Probes (New-Stand) -MsiPath $msiPath -Folder $tmp
    Check ($r.ok -and $r.version -ceq "7.5.3" -and ($script:calls -join ",") -ceq ("winget,download:https://example.invalid/p.msi,hash,msiexec,run:" + $msiPath)) ("the stages run in order: " + ($script:calls -join ","))
    $s = New-Stand
    $script:wingetText = "Installer Url: https://example.invalid/p.msi`nInstaller SHA256: " + ("0" * 64) + "`n"
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath -Folder $tmp
    Check (-not $r.ok -and $r.reason -clike "*SHA-256*it was not run" -and $script:calls -cnotcontains "msiexec") "MUST FAIL: a wrong hash never reaches msiexec"
    $script:wingetText = "Installer Url: https://example.invalid/p.msi`nInstaller SHA256: " + $script:hashOf + "`n"
    $s = New-Stand
    $s.winget = { throw "winget is not installed" }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath -Folder $tmp
    Check (-not $r.ok -and $r.reason -clike "winget show failed*not installed*" -and $script:calls.Count -eq 0) "MUST FAIL: no winget stops before any download"
    $s = New-Stand
    $s.winget = { "nothing useful" }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath -Folder $tmp
    Check (-not $r.ok -and $r.reason -clike "winget show did not give*") "MUST FAIL: winget text with no address stops"
    $s = New-Stand
    $s.download = { throw "offline" }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath -Folder $tmp
    Check (-not $r.ok -and $r.reason -clike "the download failed: offline" -and $script:calls -cnotcontains "msiexec") "MUST FAIL: a failed download stops"
    $s = New-Stand
    $s.msiexec = { param($Msi) [void]$script:calls.Add("msiexec"); 1603 }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath -Folder $tmp
    Check (-not $r.ok -and $r.reason -ceq "msiexec ended with exit 1603" -and @($script:calls | Where-Object { $_ -clike "run:*" }).Count -eq 0) "MUST FAIL: msiexec exit 1603 is a failure and pwsh is not run"
    $s = New-Stand
    $s.msiexec = { param($Msi) [void]$script:calls.Add("msiexec"); 3010 }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath -Folder $tmp
    Check ($r.ok) "exit 3010 (restart wanted) is success: the files are in place"
    $s = New-Stand
    $s.run = { param($Pwsh) "" }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath -Folder $tmp
    Check (-not $r.ok -and $r.reason -clike "*does not report a version") "MUST FAIL: a pwsh.exe that reports no version is not an install"
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "--- 6. the steps, with counted stand-ins ---" -ForegroundColor Cyan
$code = Get-HordeSetupStepCode
$script:state = @{ policy = $null; elevated = $false; msi = ""; resolved = $storePwsh; setCalls = 0; installCalls = 0; installOk = $true }
$probes = @{
    elevated       = { $script:state.elevated }
    storePolicy    = { $script:state.policy }
    setStorePolicy = { $script:state.setCalls++; $script:state.policy = 2 }
    pwshResolved   = { $script:state.resolved }
    msiVersion     = { $script:state.msi }
    installMsi     = { param($MsiPath) $script:state.installCalls++; if ($script:state.installOk) { $script:state.msi = "7.5.3"; [pscustomobject]@{ ok = $true; reason = ""; version = "7.5.3" } } else { [pscustomobject]@{ ok = $false; reason = "msiexec ended with exit 1603"; version = "" } } }
}
$ctx = [pscustomobject]@{ probes = $probes }
$st = $code["store-updates-off"]
$c = & $st.check $ctx
Check (-not $c.done -and $c.next -clike "this needs an elevated run*") "store policy unset, not elevated: to do, with the one sentence"
Check ($null -eq (& $st.fix $ctx) -and $script:state.setCalls -eq 0) "not elevated: the fix tries nothing and writes nothing"
$script:state.elevated = $true
$f = & $st.fix $ctx
Check ($f.done -and $script:state.setCalls -eq 1 -and (& $st.check $ctx).done) "elevated: the fix sets the policy once and the check then passes"
$c = & $st.check $ctx
Check ($c.done -and $c.said -clike "*nothing to change*" -and $script:state.setCalls -eq 1) "a second run on a fixed machine says nothing to change and sets nothing"

$ps = $code["powershell-msi"]
$script:state.elevated = $false
$c = & $ps.check $ctx
Check (-not $c.done -and $c.next -clike "this needs an elevated run*" -and $null -eq (& $ps.fix $ctx) -and $script:state.installCalls -eq 0) "Store pwsh, not elevated: to do, one sentence, nothing installed"
$script:state.elevated = $true
$script:state.installOk = $false
$f = & $ps.fix $ctx
Check (-not $f.done -and $f.said -clike "installing the PowerShell 7 MSI failed: msiexec ended with exit 1603" -and -not (& $ps.check $ctx).done) "a failed install is a failed fix with the reason, and the check still fails"
$script:state.installOk = $true
$f = & $ps.fix $ctx
$c = & $ps.check $ctx
Check ($f.done -and $script:state.installCalls -eq 2 -and $c.done -and @($c.notes).Count -eq 1 -and $c.notes[0] -clike "*Microsoft Store copy*") "elevated: installed from the MSI; the Store copy is still on the path, so it is only noted (never removed)"
$c = & $ps.check $ctx
Check ($c.done -and $script:state.installCalls -eq 2) "a second run installs nothing"
$script:state.msi = ""
$script:state.resolved = ""
$c = & $ps.check $ctx
Check (-not $c.done -and $c.said -clike "PowerShell 7 is not installed*") "no pwsh at all is to do too"

$realAfter = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsStore", "AutoDownload", $null)
Check (("" + $realBefore) -ceq ("" + $realAfter)) ("the real Store policy did not move (" + $(if ($null -eq $realAfter) { "unset" } else { $realAfter }) + ")")

Complete-HordeSuite -Success "the Store policy and PowerShell 7 steps decide every case from injected answers, never run an unchecked installer, never uninstall the Store copy, and change nothing on a second run"
