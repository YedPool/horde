# DOES EACH PERMISSION FRAGMENT IN agent.json GIVE THE MODE IT PROMISES, READ BACK FROM THE PROGRAM?
#
# Review of PR #60, F1: in a folder it does not trust, this harness overrides plan, edits and bypass
# to default - the ask mode - and says so only on a debug line. Folder trust is on by default. So the
# descriptor names folder-trusted as a precondition of those three, and this suite reads the program
# back both ways: trusted (GEMINI_CLI_TRUST_WORKSPACE=true), where no override may appear, and
# untrusted, where it must - which is also the control that the instrument sees the line at all.
#
# THE PROGRAM PRINTS NO EFFECTIVE MODE. It prints a line when it overrides one, and "YOLO mode is
# enabled" for bypass; the readback is those lines' presence or absence on a --debug headless run.
#
# NOTHING REAL IS TOUCHED, AND NO MODEL IS CALLED. HOME and USERPROFILE point at a folder this suite
# makes and removes (even --help writes temp files into the profile's settings folder, measured
# 2026-10-02), the key is fake, and the endpoint is a closed local port: a run ends in about 2 s. The
# real settings folder's entry count is compared before and after.
#
# WITHOUT THE PROGRAM INSTALLED THE SUITE SKIPS (T-0322): a missing gemini is the machine, not a fault, so it
# prints a SKIP line saying why and exits 0. HORDE_SKIP_READBACK=1 still skips by name and exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\AgentDescriptor.ps1")
. (Join-Path $root "test\lib\Program.ps1")

$d = Read-HordeAgentDescriptor -Path (Join-Path $root "agents\gemini-cli\agent.json")
$exe = Find-HordeTestProgram -Name "gemini"
if ($exe -eq "") {
    if ($env:HORDE_SKIP_READBACK -eq "1") {
        Write-Host "  [SKIP] the program is not installed, and HORDE_SKIP_READBACK=1 asked to skip the readback" -ForegroundColor Yellow
        Complete-HordeSuite -Success "READBACK SKIPPED (HORDE_SKIP_READBACK=1), EXIT 3" -PassCode 3
    }
    Write-Host "  [SKIP] gemini is not installed on this machine, so its modes cannot be read back here" -ForegroundColor Yellow
    Complete-HordeSuite -Success "READBACK SKIPPED (gemini not installed), EXIT 0"
}

$realDir = Join-Path $env:USERPROFILE ".gemini"
function Get-RealCount { if (Test-Path -LiteralPath $realDir) { return @(Get-ChildItem -LiteralPath $realDir -Force).Count } else { return -1 } }
$before = Get-RealCount
$work = Join-Path $env:TEMP ("horde-readback-gm-" + [guid]::NewGuid().ToString("N"))
$fakeHome = Join-Path $work "home"
[void](New-HordeTestProfile $fakeHome)
$override = 'Approval mode overridden to "default" because the current folder is not trusted'

function Read-Lines {
    # The override and YOLO lines a run printed, for one fragment, trusted or not, in a fresh folder.
    param([string[]]$Fragment, [bool]$Trusted, [string]$Tag)
    $cwd = Join-Path $work ("w-" + $Tag)
    New-Item -ItemType Directory -Path $cwd -Force | Out-Null
    $envFor = @{}
    foreach ($o in @($d.ownedEnv)) { $envFor[$o.name] = $null }
    $envFor["HOME"] = $fakeHome
    $envFor["USERPROFILE"] = $fakeHome
    $envFor["GEMINI_API_KEY"] = "fake-not-a-key"
    $envFor["GOOGLE_GEMINI_BASE_URL"] = "http://127.0.0.1:9"
    $envFor["GEMINI_CLI_TRUST_WORKSPACE"] = $(if ($Trusted) { "true" } else { $null })
    $r = Invoke-HordeTestProgram -Path $exe -ArgList (@($Fragment) + @("-p", "probe", "--debug")) -Env $envFor -WorkDir $cwd -TimeoutSeconds 90
    $all = $r.out + "`n" + $r.err
    return [pscustomobject]@{ overridden = [bool]($all.Contains($override)); yolo = [bool]($all.Contains("YOLO mode is enabled")); ran = (-not $r.timedOut) }
}
function Get-Fragment { param([string]$Level) $f = Get-HordePermissionArgs -Descriptor $d -Level $Level -EntryPoint "headless" -Verified @("folder-trusted"); Check ($f.state -eq "known") ("the descriptor gives a headless fragment for " + $Level); return @($f.value) }

try {
    foreach ($lv in @("plan", "ask", "edits", "bypass")) {
        $frag = Get-Fragment $lv
        $t = Read-Lines -Fragment $frag -Trusted $true -Tag ($lv + "-trusted")
        Check ($t.ran -and -not $t.overridden) ($lv + " (" + ($frag -join " ") + ") is not overridden in a trusted folder")
        if ($lv -eq "bypass") { Check ($t.yolo) "bypass reads back as YOLO mode in a trusted folder" }
        $u = Read-Lines -Fragment $frag -Trusted $false -Tag ($lv + "-untrusted")
        if ($lv -eq "ask") { Check ($u.ran -and -not $u.overridden) "ask is not overridden in an untrusted folder either: it is what the override gives" }
        else { Check ($u.ran -and $u.overridden) ("CONTROL: " + $lv + " IS overridden to default in an untrusted folder - why folder-trusted is its precondition") }
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Check ((Get-RealCount) -eq $before) "the real settings folder has as many entries as before: nothing was written there"

Complete-HordeSuite -Success "every permission fragment reads back as the mode it promises, and only in a trusted folder"
