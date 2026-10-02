# DOES EACH PERMISSION FRAGMENT IN agent.json GIVE THE MODE IT PROMISES, READ BACK FROM THE PROGRAM?
#
# Review of PR #60: flags read off --help were not enough - another harness turned its plan mode into
# ask in an untrusted folder. So each fragment is handed to the installed program, and the program's
# own report of its effective mode is read back: the init event of a headless run, which carries
# permissionMode. The fragment comes from the descriptor through Get-HordePermissionArgs, so this
# tests the shipped mapping, not a copy of it.
#
# NOTHING REAL IS TOUCHED, AND NO MODEL IS CALLED. CLAUDE_CONFIG_DIR points at a folder this suite
# makes and removes, the key is fake, and the endpoint is a closed local port, so the run stops at
# its first request, about 6 s after the init event (measured 2026-10-02). The real profile is
# checked before and after: the number of entries in its projects folder must not change.
#
# WITHOUT THE PROGRAM INSTALLED THE SUITE FAILS, unless HORDE_SKIP_READBACK=1 asks by name to skip
# it; a skipped run exits 3, so a gate that expects 0 does not read it as a pass (as test-projection
# does with HORDE_SKIP_REALITY).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\AgentDescriptor.ps1")
. (Join-Path $root "test\lib\Program.ps1")

$d = Read-HordeAgentDescriptor -Path (Join-Path $root "agents\claude-code\agent.json")
$exe = Find-HordeTestProgram -Name "claude"
if ($exe -eq "") {
    if ($env:HORDE_SKIP_READBACK -eq "1") {
        Write-Host "  [SKIP] the program is not installed, and HORDE_SKIP_READBACK=1 asked to skip the readback" -ForegroundColor Yellow
        Complete-HordeSuite -Success "READBACK SKIPPED (HORDE_SKIP_READBACK=1), EXIT 3" -PassCode 3
    }
    Check $false "the program is installed on this machine, so its modes can be read back (HORDE_SKIP_READBACK=1 skips by name)"
    Complete-HordeSuite
}

$projects = Join-Path $env:USERPROFILE ".claude\projects"
function Get-ProjectCount { if (Test-Path -LiteralPath $projects) { return @(Get-ChildItem -LiteralPath $projects -Force).Count } else { return -1 } }
$before = Get-ProjectCount
$work = Join-Path $env:TEMP ("horde-readback-cc-" + [guid]::NewGuid().ToString("N"))
$cfg = Join-Path $work "config"
$cwd = Join-Path $work "work"
New-Item -ItemType Directory -Path $cfg, $cwd -Force | Out-Null
# Every variable the descriptor owns is removed, so no inherited endpoint or token reaches the child,
# and then the fake ones are set.
$envFor = @{}
foreach ($o in @($d.ownedEnv)) { $envFor[$o.name] = $null }
$envFor["CLAUDE_CODE_OAUTH_TOKEN"] = $null
$envFor["CLAUDE_CONFIG_DIR"] = $cfg
$envFor["ANTHROPIC_API_KEY"] = "sk-ant-fake-not-a-key"
$envFor["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:9"
$envFor["CLAUDE_CODE_MAX_RETRIES"] = "0"

function Read-Mode {
    param([string[]]$Fragment)
    $r = Invoke-HordeTestProgram -Path $exe -ArgList (@("-p", "probe") + $Fragment + @("--output-format", "stream-json", "--verbose")) -Env $envFor -WorkDir $cwd -TimeoutSeconds 90
    $m = [regex]::Match($r.out, '"permissionMode":"([A-Za-z]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ("(none; timedOut=" + $r.timedOut + ")")
}

try {
    $expect = [ordered]@{ plan = "plan"; ask = "default"; edits = "acceptEdits"; bypass = "bypassPermissions" }
    foreach ($lv in @($expect.Keys)) {
        $frag = Get-HordePermissionArgs -Descriptor $d -Level $lv -EntryPoint "headless"
        Check ($frag.state -eq "known") ("the descriptor gives a headless fragment for " + $lv)
        if ($frag.state -ne "known") { continue }
        $mode = Read-Mode -Fragment @($frag.value)
        Check ($mode -ceq $expect[$lv]) ($lv + " (" + (@($frag.value) -join " ") + ") reads back as " + $expect[$lv] + " (read: " + $mode + ")")
    }
    # CONTROL: the instrument tells modes apart. With no permission flag the empty profile's default
    # mode is read, which is not plan - so a reading of plan above came from the fragment.
    $none = Read-Mode -Fragment @()
    Check ($none -ceq "default") ("CONTROL: with no permission flag the same start reads back default (read: " + $none + ")")
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Check ((Get-ProjectCount) -eq $before) "the real profile's projects folder has as many entries as before: nothing was written there"

Complete-HordeSuite -Success "every permission fragment reads back as the mode it promises"
