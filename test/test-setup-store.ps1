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
#   4b. THE FOLDER AND THE HOLD: the installer's folder lists only SYSTEM and Administrators, with no
#      inheritance; a held file cannot be written or deleted by anyone else; the hash is of the held stream.
#   5. THE INSTALL: the folder before the file, the hold before the hash, the release after msiexec;
#      a wrong hash never reaches msiexec; each failing stage says which and stops; 3010 is
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
    Check (-not $d.done -and $d.next -clike "needs one elevated run of horde setup*AutoDownload to 2*") ("MUST FAIL: policy " + $(if ($null -eq $bad) { "unset" } else { $bad }) + " is not done; not elevated, the one sentence says it needs an elevated run and what it will set")
}
$d = Get-HordeSetupStorePolicyDecision -Policy $null -Elevated $true
Check (-not $d.done -and $d.next -ceq "" -and $d.said -clike "*AutoDownload is unset*") "unset and elevated: not done, and no sentence about waiting for an elevated run"
Check ((Get-HordeSetupStorePolicyDecision -Policy 0 -Elevated $true).said -clike "*AutoDownload is 0*") "the value found is named"
$d = Get-HordeSetupStorePolicyDecision -Policy "not a number" -Elevated $true
Check (-not $d.done -and $d.said -clike "*AutoDownload is unset*") "MUST FAIL: a value that is not a whole number is treated as not set, and does not throw"

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
Check ($d.next -clike "needs one elevated run of horde setup*MSI*" -and $d.next -notlike "*uninstall*") "not elevated: one sentence says it needs an elevated run and what it will install, and no uninstall"
Check ((Get-HordeSetupPowerShellDecision -Resolved "" -MsiPath $msiPath -MsiVersion "" -Elevated $true).next -ceq "") "elevated: no wait sentence"

Write-Host "--- 4. winget's text ---" -ForegroundColor Cyan
$sha = "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789"
$good = "Found PowerShell [Microsoft.PowerShell]`n  Installer Type: wix`n  Installer Url: https://example.invalid/PowerShell-7.5.3-win-x64.msi`n  Installer SHA256: " + $sha + "`n"
$i = Read-HordeSetupWingetInstaller -Text $good
Check ($i.ok -and $i.url -ceq "https://example.invalid/PowerShell-7.5.3-win-x64.msi" -and $i.sha256 -ceq $sha.ToLowerInvariant()) "the address and the SHA-256 are read, the hash in lower case"
$r = Read-HordeSetupWingetInstaller -Text "Installer Url: https://x/y-x64.msi`n"
Check (-not $r.ok) "MUST FAIL: no hash"
Check (-not (Read-HordeSetupWingetInstaller -Text ("Installer Url: https://x/y-x64.msi`nInstaller SHA256: abc123`n")).ok) "MUST FAIL: a short hash"
Check (-not (Read-HordeSetupWingetInstaller -Text ("Installer Url: http://x/y-x64.msi`nInstaller SHA256: " + $sha + "`n")).ok) "MUST FAIL: an http address"
Check (-not (Read-HordeSetupWingetInstaller -Text ("Installer Url: https://x/y-x64.exe`nInstaller SHA256: " + $sha + "`n")).ok) "MUST FAIL: an address that is not an .msi"
Check (-not (Read-HordeSetupWingetInstaller -Text ("Installer Url: https://x/y-arm64.msi`nInstaller SHA256: " + $sha + "`n")).ok) "MUST FAIL: an address with no x64 in it"
$r = Read-HordeSetupWingetInstaller -Text ""
Check (-not $r.ok -and $r.reason -ceq "winget output not understood (a non-English winget prints other labels); nothing installed") "MUST FAIL: empty text says the output was not understood"
$r = Read-HordeSetupWingetInstaller -Text ("Installateur-URL: https://x/y-x64.msi`nSHA256: " + $sha + "`n")
Check (-not $r.ok -and $r.reason -clike "winget output not understood*") "MUST FAIL: other labels (a non-English winget) say so"
$two = "  Installer Url: https://example.invalid/PowerShell-7.5.3-win-arm64.msi`n  Installer SHA256: " + ("1" * 64) + "`n  Installer Url: https://example.invalid/PowerShell-7.5.3-win-x64.msi`n  Installer SHA256: " + $sha + "`n"
$r = Read-HordeSetupWingetInstaller -Text $two
Check (-not $r.ok -and $r.reason -ceq "winget listed more than one installer; nothing installed") "MUST FAIL: two installers (arm64 then x64) are refused, not guessed between"
Check (-not (Read-HordeSetupWingetInstaller -Text ($good + "  Installer SHA256: " + $sha + "`n")).ok) "MUST FAIL: two hash lines are refused"

Write-Host "--- 4b. the installer's folder and the hold ---" -ForegroundColor Cyan
$sec = Get-HordeSetupSecureFolderSecurity
$rules = @($sec.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]))
$sids = @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object)
Check ($sec.AreAccessRulesProtected) "the folder's access list does not inherit ProgramData's"
Check (($sids -join ",") -ceq "S-1-5-18,S-1-5-32-544" -and $rules.Count -eq 2) ("only SYSTEM and Administrators are named (" + ($sids -join ",") + ")")
Check (@($rules | Where-Object { $_.AccessControlType -ne "Allow" -or ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -ne [System.Security.AccessControl.FileSystemRights]::FullControl }).Count -eq 0) "each has full control, as an allow"
Check (@($rules | Where-Object { -not ($_.InheritanceFlags -band [System.Security.AccessControl.InheritanceFlags]::ObjectInherit) }).Count -eq 0) "and it passes to the file made inside"
Check (-not ($sids -contains "S-1-5-32-545") -and -not ($sids -contains "S-1-1-0") -and -not ($sids -contains "S-1-5-11")) "MUST FAIL: Users, Everyone and Authenticated Users are not in it"
$holdTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-setup-hold-test-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($holdTmp)
try {
    $hf = Join-Path $holdTmp "h.bin"
    [System.IO.File]::WriteAllText($hf, "pretend-msi")
    $hp = Get-HordeSetupHoldProbes
    $stream = & $hp.hold $hf
    $writeRefused = $false
    try { $w = [System.IO.File]::Open($hf, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite); $w.Dispose() } catch { $writeRefused = $true }
    $delRefused = $false
    try { [System.IO.File]::Delete($hf) } catch { $delRefused = $true }
    $readOk = $false
    try { $rd = [System.IO.File]::Open($hf, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read); $rd.Dispose(); $readOk = $true } catch { $readOk = $false }
    $viaStream = & $hp.hash $stream
    Check ($writeRefused -and $delRefused) "MUST FAIL: while held, the file cannot be opened for writing or deleted by anyone else"
    Check ($readOk) "while held, it can still be read (msiexec can run it)"
    & $hp.release $stream
    Check ($viaStream -ceq (Get-FileHash -LiteralPath $hf -Algorithm SHA256).Hash.ToLowerInvariant()) "the hash of the held stream is the file's SHA-256"
    $writableAfter = $false
    try { $w2 = [System.IO.File]::Open($hf, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite); $w2.Dispose(); $writableAfter = $true } catch { $writableAfter = $false }
    Check ($writableAfter) "after the release the file is writable again (the hold was the only thing in the way)"
} finally { Remove-Item -LiteralPath $holdTmp -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "--- 5. the install pipeline ---" -ForegroundColor Cyan
$script:calls = New-Object System.Collections.ArrayList
$script:msiBytes = "pretend-msi"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-setup-store-test-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($tmp)
$pretend = Join-Path $tmp "pretend.bin"
[System.IO.File]::WriteAllText($pretend, $script:msiBytes)
$script:hashOf = (Get-FileHash -LiteralPath $pretend -Algorithm SHA256).Hash
$script:wingetText = "Installer Url: https://example.invalid/p-x64.msi`nInstaller SHA256: " + $script:hashOf + "`n"
$script:heldObject = [pscustomobject]@{ marker = "the held stream" }
function New-Stand {
    $script:calls.Clear()
    return @{
        winget       = { [void]$script:calls.Add("winget"); $script:wingetText }
        makeFolder   = { [void]$script:calls.Add("makeFolder"); $script:tmp2 = Join-Path $tmp ("f" + [guid]::NewGuid().ToString("N")); [void][System.IO.Directory]::CreateDirectory($script:tmp2); $script:tmp2 }
        download     = { param($Url, $Dir) [void]$script:calls.Add("download:" + $Url); $f = Join-Path $Dir "p.msi"; [System.IO.File]::WriteAllText($f, $script:msiBytes); $f }
        hold         = { param($Path) [void]$script:calls.Add("hold"); $script:heldObject }
        hash         = { param($Stream) [void]$script:calls.Add($(if ([object]::ReferenceEquals($Stream, $script:heldObject)) { "hash-of-held" } else { "hash-of-something-else" })); $script:hashOf }
        msiexec      = { param($Msi) [void]$script:calls.Add("msiexec"); 0 }
        release      = { param($Stream) [void]$script:calls.Add("release") }
        removeFolder = { param($Folder) [void]$script:calls.Add("removeFolder") }
        run          = { param($Pwsh) [void]$script:calls.Add("run:" + $Pwsh); "7.5.3" }
    }
}
try {
    $r = Install-HordeSetupPowerShellMsi -Probes (New-Stand) -MsiPath $msiPath
    Check ($r.ok -and $r.version -ceq "7.5.3" -and ($script:calls -join ",") -ceq ("winget,makeFolder,download:https://example.invalid/p-x64.msi,hold,hash-of-held,msiexec,release,removeFolder,run:" + $msiPath)) ("the stages run in order: the folder before the file, the hold before the hash, the hash of the held stream, the release after msiexec (" + ($script:calls -join ",") + ")")
    $s = New-Stand
    $script:wingetText = "Installer Url: https://example.invalid/p-x64.msi`nInstaller SHA256: " + ("0" * 64) + "`n"
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath
    Check (-not $r.ok -and $r.reason -clike "*SHA-256*it was not run" -and $script:calls -cnotcontains "msiexec" -and $script:calls -ccontains "release" -and $script:calls -ccontains "removeFolder") "MUST FAIL: a wrong hash never reaches msiexec, and the hold and the folder are still let go"
    $script:wingetText = "Installer Url: https://example.invalid/p-x64.msi`nInstaller SHA256: " + $script:hashOf + "`n"
    $s = New-Stand
    $s.winget = { throw "winget is not installed" }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath
    Check (-not $r.ok -and $r.reason -clike "winget show failed*not installed*" -and $script:calls.Count -eq 0) "MUST FAIL: no winget stops before any folder or download"
    $s = New-Stand
    $s.winget = { "nothing useful" }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath
    Check (-not $r.ok -and $r.reason -clike "winget output not understood*") "MUST FAIL: winget text with no address stops"
    $s = New-Stand
    $s.makeFolder = { throw "access denied" }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath
    Check (-not $r.ok -and $r.reason -clike "the installer's folder could not be made: access denied") "MUST FAIL: no secure folder, nothing is downloaded"
    $s = New-Stand
    $s.download = { throw "no complete download within 300 seconds" }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath
    Check (-not $r.ok -and $r.reason -clike "the download failed: no complete download within 300 seconds" -and $script:calls -cnotcontains "msiexec" -and $script:calls -ccontains "removeFolder") "MUST FAIL: a stalled download fails with a sentence, and the folder goes"
    $s = New-Stand
    $s.msiexec = { param($Msi) [void]$script:calls.Add("msiexec"); 1603 }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath
    Check (-not $r.ok -and $r.reason -ceq "msiexec ended with exit 1603" -and @($script:calls | Where-Object { $_ -clike "run:*" }).Count -eq 0 -and $script:calls -ccontains "release") "MUST FAIL: msiexec exit 1603 is a failure, pwsh is not run, the hold is released"
    $s = New-Stand
    $s.msiexec = { param($Msi) [void]$script:calls.Add("msiexec"); 3010 }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath
    Check ($r.ok) "exit 3010 (restart wanted) is success: the files are in place"
    $s = New-Stand
    $s.run = { param($Pwsh) "" }
    $r = Install-HordeSetupPowerShellMsi -Probes $s -MsiPath $msiPath
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
Check (-not $c.done -and $c.next -clike "needs one elevated run of horde setup*") "store policy unset, not elevated: to do, with the one sentence"
Check ($null -eq (& $st.fix $ctx) -and $script:state.setCalls -eq 0) "not elevated: the fix tries nothing and writes nothing"
$script:state.elevated = $true
$f = & $st.fix $ctx
Check ($f.done -and $script:state.setCalls -eq 1 -and (& $st.check $ctx).done) "elevated: the fix sets the policy once and the check then passes"
$c = & $st.check $ctx
Check ($c.done -and $c.said -clike "*nothing to change*" -and $script:state.setCalls -eq 1) "a second run on a fixed machine says nothing to change and sets nothing"

$ps = $code["powershell-msi"]
$script:state.elevated = $false
$c = & $ps.check $ctx
Check (-not $c.done -and $c.next -clike "needs one elevated run of horde setup*" -and $null -eq (& $ps.fix $ctx) -and $script:state.installCalls -eq 0) "Store pwsh, not elevated: to do, one sentence, nothing installed"
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
