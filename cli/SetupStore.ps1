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
# THE PRETEND MACHINE. The environment variable HORDE_SETUP_FAKE_MACHINE names a JSON file that stands
# in for the registry, the search path, winget and the installer, so `horde setup` can be driven end to
# end with nothing real read or changed (test\e2e\e2e-setup-store.ps1). It is an environment variable and
# not a home setting because a suite must give a home that does not exist yet (the first-run cases, and
# -Check "not even the home") the stand-in too; HORDE_HOME and USERPROFILE are already how those suites
# aim the shipped command, and a module setting would have to create the home first. Setup says so in
# its first line whenever it is set.
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
    # Anything but a whole number is treated as not set (a string in that value would throw on a cast).
    $n = 0
    if ($null -ne $Policy -and -not [int]::TryParse(("" + $Policy), [ref]$n)) { $Policy = $null }
    if ($null -ne $Policy -and $n -eq 2) { return [pscustomobject]@{ done = $true; said = "Store automatic updates are off by policy (AutoDownload = 2); nothing to change"; next = "" } }
    $now = $(if ($null -eq $Policy) { "unset" } else { "" + $Policy })
    $said = "Microsoft Store automatic updates are not turned off (" + $script:HordeSetupStoreKeyText + " AutoDownload is " + $now + ")"
    $next = $(if ($Elevated) { "" } else { "needs one elevated run of horde setup (a PowerShell window opened as administrator); it will set " + $script:HordeSetupStoreKeyText + " AutoDownload to 2 (Store automatic updates off)" })
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
    $next = $(if ($Elevated) { "" } else { "needs one elevated run of horde setup (a PowerShell window opened as administrator); it will install the PowerShell 7 MSI (the winget source's own address, checked against its SHA-256) to " + $MsiPath })
    return [pscustomobject]@{ done = $false; kind = $kind; said = $said; notes = [string[]]$notes; next = $next }
}

function Read-HordeSetupWingetInstaller {
    # The installer's address and SHA-256 from `winget show` text: { ok; url; sha256; reason }. Exactly
    # one of each label, or nothing is taken: a text with two installers (arm64 then x64) must not
    # hand the wrong one to msiexec as administrator.
    param([AllowEmptyString()][string]$Text)
    $none = { param($why) [pscustomobject]@{ ok = $false; url = ""; sha256 = ""; reason = $why } }
    $us = @([regex]::Matches($Text, '(?m)^\s*Installer Url:\s*(\S+)\s*$'))
    $hs = @([regex]::Matches($Text, '(?m)^\s*Installer SHA256:\s*([0-9A-Fa-f]{64})\s*$'))
    if ($us.Count -eq 0 -or $hs.Count -eq 0) { return (& $none "winget output not understood (a non-English winget prints other labels); nothing installed") }
    if ($us.Count -gt 1 -or $hs.Count -gt 1) { return (& $none "winget listed more than one installer; nothing installed") }
    $url = $us[0].Groups[1].Value
    if ($url -cnotlike "https://*" -or $url -notmatch '(?i)\.msi$' -or $url -notmatch '(?i)x64') { return (& $none "the installer address winget gave is not an https .msi for x64; nothing installed") }
    return [pscustomobject]@{ ok = $true; url = $url; sha256 = $hs[0].Groups[1].Value.ToLowerInvariant(); reason = "" }
}

function Get-HordeSetupSecureFolderSecurity {
    # The access list of the folder the installer is kept in: Administrators and SYSTEM, full control,
    # and nobody else - inheritance removed, so ProgramData's own list (which lets any user add to it)
    # does not apply. Built here so a suite can read the rules without a folder.
    $sec = New-Object System.Security.AccessControl.DirectorySecurity
    $sec.SetAccessRuleProtection($true, $false)
    $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    foreach ($sid in @("S-1-5-32-544", "S-1-5-18")) {
        $who = New-Object System.Security.Principal.SecurityIdentifier($sid)
        $sec.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($who, [System.Security.AccessControl.FileSystemRights]::FullControl, $inherit, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)))
    }
    return $sec
}

function New-HordeSetupSecureFolder {
    # Makes -Path WITH the secure access list in the one call, so there is no moment it is open to
    # other users. The two engines spell it differently: Windows PowerShell 5.1 (.NET Framework) has
    # Directory.CreateDirectory(path, security); PowerShell 7 (.NET Core) lacks that overload ("Cannot
    # find an overload for CreateDirectory and the argument count: 2", measured 2026-10-16) and has
    # FileSystemAclExtensions.Create on a DirectoryInfo instead. With neither, it throws a sentence and
    # nothing is made.
    param([Parameter(Mandatory = $true)][string]$Path)
    $sec = Get-HordeSetupSecureFolderSecurity
    $framework = [System.IO.Directory].GetMethod("CreateDirectory", [type[]]@([string], [System.Security.AccessControl.DirectorySecurity]))
    if ($null -ne $framework) { [void][System.IO.Directory]::CreateDirectory($Path, $sec); return $Path }
    $core = "System.IO.FileSystemAclExtensions" -as [type]
    if ($null -ne $core) { [void]$core::Create((New-Object System.IO.DirectoryInfo($Path)), $sec); return $Path }
    throw "this PowerShell cannot make a folder together with its access list, so nothing was downloaded"
}

function Install-HordeSetupPowerShellMsi {
    # winget show -> a folder only administrators can touch -> download -> HOLD the file open (nobody
    # else may write or delete it) -> SHA-256 of the held stream -> msiexec -> release -> verify.
    # { ok; reason; version }.
    # WHY THE FOLDER AND THE HOLD: a temp folder is writable by every process of the same user, which
    # could swap the file between the hash and msiexec, and msiexec runs as administrator. The folder
    # is made with its access list BEFORE the file is written, and the open handle (read, share read
    # only) is kept from before the hash until msiexec ends, so what is hashed is what is run.
    # -Probes: winget { -> text }, makeFolder { -> path }, download { param($Url, $Folder) -> file path },
    # hold { param($Path) -> stream }, hash { param($Stream) -> hex }, msiexec { param($Msi) -> exit
    # code }, release { param($Stream) }, removeFolder { param($Folder) }, run { param($Pwsh) -> version }.
    # Each step stops the rest: a hash that differs never reaches msiexec.
    param([Parameter(Mandatory = $true)][hashtable]$Probes, [Parameter(Mandatory = $true)][string]$MsiPath)
    $fail = { param($why) [pscustomobject]@{ ok = $false; reason = $why; version = "" } }
    $shown = ""
    try { $shown = "" + (& $Probes.winget) } catch { return (& $fail ("winget show failed: " + $_.Exception.Message)) }
    $inst = Read-HordeSetupWingetInstaller -Text $shown
    if (-not $inst.ok) { return (& $fail $inst.reason) }
    $folder = ""
    $held = $null
    try {
        try { $folder = "" + (& $Probes.makeFolder) } catch { return (& $fail ("the installer's folder could not be made: " + $_.Exception.Message)) }
        $msi = ""
        try { $msi = "" + (& $Probes.download $inst.url $folder) } catch { return (& $fail ("the download failed: " + $_.Exception.Message)) }
        try { $held = & $Probes.hold $msi } catch { return (& $fail ("the downloaded installer could not be held: " + $_.Exception.Message)) }
        $got = ("" + (& $Probes.hash $held)).ToLowerInvariant()
        if ($got -cne $inst.sha256) { return (& $fail ("the downloaded installer's SHA-256 (" + $got + ") is not the one winget published (" + $inst.sha256 + "); it was not run")) }
        $code = [int](& $Probes.msiexec $msi)
        # 3010 is "installed, restart wanted": the files are in place.
        if ($code -ne 0 -and $code -ne 3010) { return (& $fail ("msiexec ended with exit " + $code)) }
    } finally {
        if ($null -ne $held) { try { & $Probes.release $held } catch { } }
        if ($folder -ne "") { try { & $Probes.removeFolder $folder } catch { } }
    }
    $ver = ("" + (& $Probes.run $MsiPath)).Trim()
    if ($ver -eq "") { return (& $fail ("the installer ran but " + $MsiPath + " does not report a version")) }
    return [pscustomobject]@{ ok = $true; reason = ""; version = $ver }
}

function Get-HordeSetupStreamHash {
    # SHA-256 (hex) of everything in -Stream, from its start: the hash is of the held handle.
    param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)
    [void]$Stream.Seek(0, [System.IO.SeekOrigin]::Begin)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($Stream) | ForEach-Object { $_.ToString("x2") }) -join "") } finally { $sha.Dispose() }
}

function Get-HordeSetupHoldProbes {
    # The probes that hold, hash, release and remove, real in both the real and the pretend install.
    return @{
        hold         = { param($Path) [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read) }
        hash         = { param($Stream) Get-HordeSetupStreamHash -Stream $Stream }
        release      = { param($Stream) $Stream.Dispose() }
        removeFolder = { param($Folder) Remove-Item -LiteralPath $Folder -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Get-HordeSetupStoreDefaultProbes {
    # The real answers for the two steps, each a block a suite may replace.
    return @{
        # The raw value: a decision treats anything but a whole number as not set.
        storePolicy    = { [Microsoft.Win32.Registry]::GetValue($script:HordeSetupStoreKey, "AutoDownload", $null) }
        setStorePolicy = { [Microsoft.Win32.Registry]::SetValue($script:HordeSetupStoreKey, "AutoDownload", 2, [Microsoft.Win32.RegistryValueKind]::DWord) }
        pwshResolved   = { $c = @(Get-Command -Name "pwsh" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1); if ($c.Count -eq 1) { "" + $c[0].Source } else { "" } }
        msiVersion     = { $p = Get-HordeSetupMsiPwshPath; if ([System.IO.File]::Exists($p)) { "" + [System.Diagnostics.FileVersionInfo]::GetVersionInfo($p).ProductVersion } else { "" } }
        installMsi     = {
            param($MsiPath)
            $real = Get-HordeSetupHoldProbes
            # No `winget install`: it sees the Store copy as installed and refuses (see the header).
            $real.winget = { (& winget.exe show --id Microsoft.PowerShell --source winget --exact --installer-type wix --architecture x64 --disable-interactivity) -join "`n" }
            $real.makeFolder = {
                $dir = Join-Path ("" + $env:ProgramData) ("horde-setup-pwsh-" + [guid]::NewGuid().ToString("N"))
                if ([System.IO.Directory]::Exists($dir)) { throw "the folder already exists" }
                # Made WITH its access list: there is no moment it is open to other users.
                New-HordeSetupSecureFolder -Path $dir
            }
            # -TimeoutSec 300: a stalled download must fail the step with a sentence, never hang setup.
            $real.download = {
                param($Url, $Dir)
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                $f = Join-Path $Dir "PowerShell.msi"
                $ProgressPreference = "SilentlyContinue"
                try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 300 -Uri $Url -OutFile $f } catch { throw ("no complete download within 300 seconds (" + $_.Exception.Message + ")") }
                $f
            }
            $real.msiexec = {
                param($Msi)
                $p = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", ('"' + $Msi + '"'), "/qn", "/norestart", "ADD_PATH=1", "ENABLE_MU=0", "USE_MU=0") -Wait -PassThru
                $p.ExitCode
            }
            $real.run = { param($Pwsh) if ([System.IO.File]::Exists($Pwsh)) { (& $Pwsh -NoProfile -NoLogo -Command '$PSVersionTable.PSVersion.ToString()') -join "" } else { "" } }
            Install-HordeSetupPowerShellMsi -Probes $real -MsiPath $MsiPath
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
    # changed). The install runs the REAL pipeline (hold and hash included) over these stand-ins.
    param([Parameter(Mandatory = $true)][string]$Path)
    $script:HordeSetupFakePath = $Path
    return @{
        elevated       = { (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).elevated -eq $true }
        storePolicy    = { (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).storePolicy }
        setStorePolicy = { Add-HordeSetupFakeAction -Path $script:HordeSetupFakePath -Action "set-store-policy" -Set @{ storePolicy = 2 } }
        pwshResolved   = { "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).pwshResolved }
        msiVersion     = { "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).msiVersion }
        installMsi     = {
            param($MsiPath)
            $stand = Get-HordeSetupHoldProbes
            $stand.winget = { "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).wingetText }
            $stand.makeFolder = { $d = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-setup-fake-pwsh-" + [guid]::NewGuid().ToString("N")); [void][System.IO.Directory]::CreateDirectory($d); $d }
            $stand.download = { param($Url, $Dir) $f = Join-Path $Dir "PowerShell.msi"; [System.IO.File]::WriteAllText($f, ("" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).msiContent), [System.Text.Encoding]::ASCII); $f }
            $stand.msiexec = { param($Msi) Add-HordeSetupFakeAction -Path $script:HordeSetupFakePath -Action "install-msi" -Set @{ msiVersion = "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).msiWillBe }; 0 }
            $stand.run = { param($Pwsh) "" + (Read-HordeSetupFakeMachine -Path $script:HordeSetupFakePath).msiVersion }
            Install-HordeSetupPowerShellMsi -Probes $stand -MsiPath $MsiPath
        }
    }
}
