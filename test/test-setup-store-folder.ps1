# DOES THE INSTALLER'S SECURE FOLDER GET MADE, WITH ITS ACCESS LIST, UNDER BOTH POWERSHELLS?
#
# cli/SetupStore.ps1, New-HordeSetupSecureFolder (CONTRIBUTING 16). Windows PowerShell 5.1 makes a folder
# with its access list through Directory.CreateDirectory(path, security); PowerShell 7 has no such
# overload (measured 2026-10-16: "Cannot find an overload for CreateDirectory and the argument count:
# 2") and uses FileSystemAclExtensions.Create. This suite runs one probe under powershell.exe and, when
# it is installed, pwsh.exe: each makes ONE real folder under a subfolder of this suite's own temp
# folder (never ProgramData), and reports whether its rules are protected from inheritance and name
# only SYSTEM and Administrators. The folder is deleted afterwards. A pwsh that is not here is a
# partial run (exit 3), said, not a pass for it.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-setup-folder-test-" + [guid]::NewGuid().ToString("N"))
$fakeProgramData = Join-Path $work "ProgramData"
[void][System.IO.Directory]::CreateDirectory($fakeProgramData)
$store = Join-Path $root "cli\SetupStore.ps1"
$probe = Join-Path $work "probe.ps1"
[System.IO.File]::WriteAllText($probe, @'
param([string]$Store, [string]$Dir)
$ErrorActionPreference = "Stop"
. $Store
try {
    [void](New-HordeSetupSecureFolder -Path $Dir)
    $acl = Get-Acl -LiteralPath $Dir
    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    $sids = @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
    Write-Output ("RESULT exists=" + [System.IO.Directory]::Exists($Dir) + " protected=" + $acl.AreAccessRulesProtected + " sids=" + ($sids -join ",") + " rules=" + $rules.Count)
} catch { Write-Output ("RESULT error=" + $_.Exception.Message) }
'@, (New-Object System.Text.UTF8Encoding($false)))

function Invoke-Engine {
    # Run the probe under -Exe: { code; line }.
    param([string]$Exe, [string]$Dir)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + $probe + "`" -Store `"" + $store + "`" -Dir `"" + $Dir + "`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $err = $p.StandardError.ReadToEndAsync()
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        $line = @($out -split "`r?`n" | Where-Object { $_ -clike "RESULT *" } | Select-Object -First 1)
        return [pscustomobject]@{ code = $p.ExitCode; line = $(if ($line.Count -eq 1) { "" + $line[0] } else { "no RESULT line; stderr: " + $err.Result }) }
    } finally { $p.Dispose() }
}

$partial = $false
try {
    $engines = @(@{ name = "Windows PowerShell 5.1"; exe = (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") })
    $pw = @(Get-Command -Name "pwsh" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($pw.Count -eq 1) { $engines += @{ name = "PowerShell 7"; exe = $pw[0].Source } }
    else { $partial = $true; Write-Host "  pwsh is not installed here: only Windows PowerShell 5.1 is proved" -ForegroundColor Yellow }
    Check ($engines.Count -ge 1 -and [System.IO.File]::Exists($engines[0].exe)) "CONTROL: Windows PowerShell 5.1 is found"
    $n = 0
    foreach ($e in $engines) {
        $n++
        $dir = Join-Path $fakeProgramData ("horde-setup-pwsh-" + $n)
        $r = Invoke-Engine -Exe $e.exe -Dir $dir
        Check ($r.line -ceq "RESULT exists=True protected=True sids=S-1-5-18,S-1-5-32-544 rules=2") ($e.name + " makes the folder with its access list: protected, SYSTEM and Administrators only (" + $r.line + ")")
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        Check (-not (Test-Path -LiteralPath $dir)) ($e.name + ": the folder is deleted afterwards")
    }
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
Check (-not (Test-Path -LiteralPath $work)) "the suite's folder is gone"

if ($partial) { Complete-HordeSuite -Success "the secure folder is made with its access list under Windows PowerShell 5.1 (a partial run: no pwsh here)" -PassCode 3 }
Complete-HordeSuite -Success "the installer's secure folder is made with its access list, protected and for SYSTEM and Administrators only, under both Windows PowerShell 5.1 and PowerShell 7"
