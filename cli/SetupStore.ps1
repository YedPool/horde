# cli/SetupStore.ps1 - the two `horde setup` steps that keep Horde off Microsoft Store packages
# (CONTRIBUTING 16): store-updates-off and powershell-msi. Their decisions are pure functions of
# injected answers, so a suite decides every case without touching the registry or installing.
#
# WHY (2026-10-16, 13:58). The Store auto-updated PowerShell 7 (Microsoft.PowerShell, running from a
# WindowsApps folder). An update closes every running process of the package: every pwsh.exe closed
# at once, and since the terminal's panes ran pwsh, every fleet session died with it.
#
# WHAT IS MEASURED, not assumed:
#   - `winget install` cannot be used to put the MSI beside a Store copy: it sees the Store package
#     as installed and refuses, and its default installer for this package is the msix. So the
#     installer's address and SHA-256 are read from `winget show ... --installer-type wix` and the
#     MSI is downloaded, hashed and run here.
#   - Setup NEVER uninstalls the Store copy: removing it closes every pwsh.exe running from it, which
#     is the incident again. It says the copy can be removed when no session runs on it.
#
# THE PRETEND MACHINE. HORDE_SETUP_FAKE_MACHINE names a JSON file that stands in for the registry, the
# search path, winget and the installer, so `horde setup` can be driven end to end with nothing real
# read or changed (test\e2e\e2e-setup-store.ps1). Setup says so in its first line whenever it is set.
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeSetupStoreKey = "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\WindowsStore"
$script:HordeSetupStoreKeyText = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"

function Test-HordeSetupStorePath {
    # True when -Path lies under a WindowsApps folder: where a Microsoft Store package runs from.
    param([AllowEmptyString()][string]$Path)
    if ($Path -eq "") { return $false }
    return ($Path.Replace("/", "\") -match '(?i)\\WindowsApps\\')
}

function Get-HordeSetupMsiPwshPath {
    # Where the PowerShell 7 MSI puts pwsh.exe (64-bit, per machine). ProgramW6432 first: a 32-bit
    # process sees ProgramFiles as the x86 folder.
    $pf = "" + $env:ProgramW6432
    if ($pf -eq "") { $pf = "" + $env:ProgramFiles }
    return (Join-Path $pf "PowerShell\7\pwsh.exe")
}

function Get-HordeSetupStorePolicyDecision {
    # The Store-updates step from its answers: { done; said; next }. -Policy is the AutoDownload value
    # ($null when unset), -Elevated whether this process can write HKLM. 2 is "never download
    # automatically" (the Store's own documented value).
    param($Policy, [bool]$Elevated)
    if ($null -ne $Policy -and [int]$Policy -eq 2) { return [pscustomobject]@{ done = $true; said = "Store automatic updates are off by policy (AutoDownload = 2); nothing to change"; next = "" } }
    $now = $(if ($null -eq $Policy) { "unset" } else { "" + $Policy })
    $said = "Microsoft Store automatic updates are not turned off (" + $script:HordeSetupStoreKeyText + " AutoDownload is " + $now + ")"
    $next = $(if ($Elevated) { "" } else { "this needs an elevated run: horde setup will set " + $script:HordeSetupStoreKeyText + " AutoDownload to 2 (Store automatic updates off), so run horde setup again from a PowerShell window opened as administrator" })
    return [pscustomobject]@{ done = $false; said = $said; next = $next }
}

function Get-HordeSetupPowerShellDecision {
    # The PowerShell 7 step from its answers: { done; kind; said; notes; next }. -Resolved is the pwsh
    # the search path finds ("" when none), -MsiPath where the MSI's pwsh.exe lives, -MsiVersion the
    # version that file reports ("" when it is not there). Done exactly when the MSI copy is there: a
    # Store copy first on the path is only noted, since Horde starts the MSI copy by its full path.
    param([AllowEmptyString()][string]$Resolved, [string]$MsiPath, [AllowEmptyString()][string]$MsiVersion, [bool]$Elevated)
    $store = Test-HordeSetupStorePath -Path $Resolved
    $removal = "removing the Microsoft Store copy closes every pwsh.exe running from it, so setup leaves it: remove it when no session runs on it"
    if ($MsiVersion -ne "") {
        $notes = @()
        if ($store) { $notes += ("note: pwsh on the search path is the Microsoft Store copy (" + $Resolved + "); Horde starts " + $MsiPath + " by its full path; " + $removal) }
        return [pscustomobject]@{ done = $true; kind = "ok"; said = ("PowerShell " + $MsiVersion + " is installed from the MSI at " + $MsiPath + "; nothing to change"); notes = [string[]]$notes; next = "" }
    }
    $kind = $(if ($store) { "store" } else { "missing" })
    $said = $(if ($store) { "the pwsh on the search path is the Microsoft Store copy (" + $Resolved + "), and there is no MSI install at " + $MsiPath } else { "PowerShell 7 is not installed (no pwsh on the search path, none at " + $MsiPath + ")" })
    $notes = @()
    if ($store) { $notes += ("note: " + $removal) }
    $next = $(if ($Elevated) { "" } else { "this needs an elevated run: horde setup will install the PowerShell 7 MSI (the winget source's own address, checked against its SHA-256) to " + $MsiPath + ", so run horde setup again from a PowerShell window opened as administrator" })
    return [pscustomobject]@{ done = $false; kind = $kind; said = $said; notes = [string[]]$notes; next = $next }
}

function Read-HordeSetupWingetInstaller {
    # The installer's address and SHA-256 from `winget show` text: { ok; url; sha256; reason }.
    param([AllowEmptyString()][string]$Text)
    $u = [regex]::Match($Text, '(?m)^\s*Installer Url:\s*(\S+)\s*$')
    $h = [regex]::Match($Text, '(?m)^\s*Installer SHA256:\s*([0-9A-Fa-f]{64})\s*$')
    if (-not $u.Success -or -not $h.Success) { return [pscustomobject]@{ ok = $false; url = ""; sha256 = ""; reason = "winget show did not give an installer address and SHA-256 for the PowerShell MSI" } }
    if ($u.Groups[1].Value -cnotlike "https://*") { return [pscustomobject]@{ ok = $false; url = ""; sha256 = ""; reason = "the installer address winget gave is not https" } }
    return [pscustomobject]@{ ok = $true; url = $u.Groups[1].Value; sha256 = $h.Groups[1].Value.ToLowerInvariant(); reason = "" }
}

function Install-HordeSetupPowerShellMsi {
    # winget show -> download -> SHA-256 -> msiexec -> run the new pwsh.exe: { ok; reason; version }.
    # -Probes: winget { -> text }, download { param($Url, $Folder) -> file path }, hash { param($Path) ->
    # hex }, msiexec { param($Msi) -> exit code }, run { param($Pwsh) -> version text }. Each step
    # stops the rest: a hash that differs never reaches msiexec.
    param([Parameter(Mandatory = $true)][hashtable]$Probes, [Parameter(Mandatory = $true)][string]$MsiPath, [Parameter(Mandatory = $true)][string]$Folder)
    $shown = ""
    try { $shown = "" + (& $Probes.winget) } catch { return [pscustomobject]@{ ok = $false; reason = "winget show failed: " + $_.Exception.Message; version = "" } }
    $inst = Read-HordeSetupWingetInstaller -Text $shown
    if (-not $inst.ok) { return [pscustomobject]@{ ok = $false; reason = $inst.reason; version = "" } }
    $msi = ""
    try { $msi = "" + (& $Probes.download $inst.url $Folder) } catch { return [pscustomobject]@{ ok = $false; reason = "the download failed: " + $_.Exception.Message; version = "" } }
    $got = ("" + (& $Probes.hash $msi)).ToLowerInvariant()
    if ($got -cne $inst.sha256) { return [pscustomobject]@{ ok = $false; reason = "the downloaded installer's SHA-256 (" + $got + ") is not the one winget published (" + $inst.sha256 + "); it was not run"; version = "" } }
    $code = [int](& $Probes.msiexec $msi)
    # 3010 is "installed, restart wanted": the files are in place.
    if ($code -ne 0 -and $code -ne 3010) { return [pscustomobject]@{ ok = $false; reason = "msiexec ended with exit " + $code; version = "" } }
    $ver = ("" + (& $Probes.run $MsiPath)).Trim()
    if ($ver -eq "") { return [pscustomobject]@{ ok = $false; reason = "the installer ran but " + $MsiPath + " does not report a version"; version = "" } }
    return [pscustomobject]@{ ok = $true; reason = ""; version = $ver }
}

function Get-HordeSetupStoreDefaultProbes {
    # The real answers for the two steps, each a block a suite may replace.
    return @{
        storePolicy    = { $v = [Microsoft.Win32.Registry]::GetValue($script:HordeSetupStoreKey, "AutoDownload", $null); if ($null -eq $v) { $null } else { [int]$v } }
        setStorePolicy = { [Microsoft.Win32.Registry]::SetValue($script:HordeSetupStoreKey, "AutoDownload", 2, [Microsoft.Win32.RegistryValueKind]::DWord) }
        pwshResolved   = { $c = @(Get-Command -Name "pwsh" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1); if ($c.Count -eq 1) { "" + $c[0].Source } else { "" } }
        msiVersion     = { $p = Get-HordeSetupMsiPwshPath; if ([System.IO.File]::Exists($p)) { "" + [System.Diagnostics.FileVersionInfo]::GetVersionInfo($p).ProductVersion } else { "" } }
        installMsi     = {
            param($MsiPath)
            $folder = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-setup-pwsh-" + [guid]::NewGuid().ToString("N"))
            [void][System.IO.Directory]::CreateDirectory($folder)
            try {
                $real = @{
                    # No `winget install`: it sees the Store copy as installed and refuses (see the header).
                    winget   = { (& winget.exe show --id Microsoft.PowerShell --source winget --exact --installer-type wix --architecture x64 --disable-interactivity) -join "`n" }
                    download = {
                        param($Url, $Dir)
                        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                        $f = Join-Path $Dir "PowerShell.msi"
                        (New-Object System.Net.WebClient).DownloadFile($Url, $f)
                        $f
                    }
                    hash     = { param($Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
                    msiexec  = {
                        param($Msi)
                        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", ('"' + $Msi + '"'), "/qn", "/norestart", "ADD_PATH=1", "ENABLE_MU=0", "USE_MU=0") -Wait -PassThru
                        $p.ExitCode
                    }
                    run      = { param($Pwsh) if ([System.IO.File]::Exists($Pwsh)) { (& $Pwsh -NoProfile -NoLogo -Command '$PSVersionTable.PSVersion.ToString()') -join "" } else { "" } }
                }
                Install-HordeSetupPowerShellMsi -Probes $real -MsiPath $MsiPath -Folder $folder
            } finally { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Read-HordeSetupFakeMachine {
    param([string]$Path)
    return (ConvertFrom-HordeJson -Text ([System.IO.File]::ReadAllText($Path)))
}

function Save-HordeSetupFakeMachine {
    param([string]$Path, $Machine)
    [System.IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Machine -Depth 4), [System.Text.Encoding]::ASCII)
}

function Add-HordeSetupFakeAction {
    # Records one change the pretend machine was asked to make, so a suite can prove a second run made none.
    param([string]$Path, [string]$Action, [hashtable]$Set = @{})
    $m = Read-HordeSetupFakeMachine -Path $Path
    $acts = @($m.actions) + $Action
    $m | Add-Member -NotePropertyName actions -NotePropertyValue ([string[]]$acts) -Force
    foreach ($k in @($Set.Keys)) { $m | Add-Member -NotePropertyName $k -NotePropertyValue $Set[$k] -Force }
    Save-HordeSetupFakeMachine -Path $Path -Machine $m
}

function Get-HordeSetupFakeStoreProbes {
    # The pretend machine's answers, from the JSON file -Path: elevated, storePolicy (number or null),
    # pwshResolved, msiVersion, wingetText, msiContent (what the "download" holds), actions (what was
    # changed). The install runs the REAL pipeline (hash check included) over these stand-ins.
    param([Parameter(Mandatory = $true)][string]$Path)
    $script:HordeSetupFakePath = $Path
    return @{
        elevated       = { (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).elevated -eq $true }
        storePolicy    = { $v = (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).storePolicy; if ($null -eq $v) { $null } else { [int]$v } }
        setStorePolicy = { Add-HordeSetupFakeAction -Path $script:HordeSetupFakePath -Action "set-store-policy" -Set @{ storePolicy = 2 } }
        pwshResolved   = { "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).pwshResolved }
        msiVersion     = { "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).msiVersion }
        installMsi     = {
            param($MsiPath)
            $folder = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-setup-fake-pwsh-" + [guid]::NewGuid().ToString("N"))
            [void][System.IO.Directory]::CreateDirectory($folder)
            try {
                $stand = @{
                    winget   = { "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).wingetText }
                    download = { param($Url, $Dir) $f = Join-Path $Dir "PowerShell.msi"; [System.IO.File]::WriteAllText($f, ("" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).msiContent), [System.Text.Encoding]::ASCII); $f }
                    hash     = { param($Path2) (Get-FileHash -LiteralPath $Path2 -Algorithm SHA256).Hash }
                    msiexec  = { param($Msi) Add-HordeSetupFakeAction -Path $script:HordeSetupFakePath -Action "install-msi" -Set @{ msiVersion = "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).msiWillBe }; 0 }
                    run      = { param($Pwsh) "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).msiVersion }
                }
                Install-HordeSetupPowerShellMsi -Probes $stand -MsiPath $MsiPath -Folder $folder
            } finally { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
