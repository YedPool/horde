# DOES EACH PERMISSION FRAGMENT IN agent.json GIVE THE POLICY IT PROMISES, READ BACK FROM THE PROGRAM?
#
# Review of PR #60 found the edits fragment making the TEMP folder and /tmp writable unasked (F2), and
# the same fragment silently read-only without a [windows] sandbox setting (F3). So each fragment is
# handed to the installed program, and `debug prompt-input` renders the policy the program would
# give the model: its sandbox mode, its approval policy, whether it offers escalation, and its
# writable roots. The fragment comes from the descriptor through Get-HordePermissionArgs.
#
# NOTHING REAL IS TOUCHED, AND NO MODEL IS CALLED: prompt-input only renders. CODEX_HOME points at two
# folders this suite makes and removes - one plain, one with [windows] sandbox = "elevated", the only
# setting measured - and the real config file's hash is compared before and after. The real model
# setting is never read or written.
#
# WITHOUT THE PROGRAM INSTALLED THE SUITE FAILS, unless HORDE_SKIP_READBACK=1 asks by name; a skipped
# run exits 3.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\AgentDescriptor.ps1")
. (Join-Path $root "test\lib\Program.ps1")

$d = Read-HordeAgentDescriptor -Path (Join-Path $root "agents\codex\agent.json")
$exe = Find-HordeTestProgram -Name "codex"
if ($exe -eq "") {
    if ($env:HORDE_SKIP_READBACK -eq "1") {
        Write-Host "  [SKIP] the program is not installed, and HORDE_SKIP_READBACK=1 asked to skip the readback" -ForegroundColor Yellow
        Complete-HordeSuite -Success "READBACK SKIPPED (HORDE_SKIP_READBACK=1), EXIT 3" -PassCode 3
    }
    Check $false "the program is installed on this machine, so its policies can be read back (HORDE_SKIP_READBACK=1 skips by name)"
    Complete-HordeSuite
}

$realCfg = Join-Path $env:USERPROFILE ".codex\config.toml"
function Get-RealHash { if (Test-Path -LiteralPath $realCfg) { return (Get-FileHash -LiteralPath $realCfg -Algorithm SHA256).Hash } else { return "absent" } }
$before = Get-RealHash
$work = Join-Path $env:TEMP ("horde-readback-cx-" + [guid]::NewGuid().ToString("N"))
$plain = Join-Path $work "home-plain"
$elev = Join-Path $work "home-elevated"
$cwd = Join-Path $work "work"
New-Item -ItemType Directory -Path $plain, $elev, $cwd -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $elev "config.toml"), "[windows]`nsandbox = `"elevated`"`n", (New-Object System.Text.UTF8Encoding($false)))

function Read-Policy {
    # { sandbox; approval; escalation; writable } as the program renders them for this fragment.
    param([string[]]$Fragment, [string]$CodexHome)
    $envFor = @{ CODEX_HOME = $CodexHome }
    foreach ($o in @($d.ownedEnv)) { $envFor[$o.name] = $null }
    $r = Invoke-HordeTestProgram -Path $exe -ArgList (@($Fragment) + @("debug", "prompt-input", "probe")) -Env $envFor -WorkDir $cwd -TimeoutSeconds 120
    $text = ""
    try {
        foreach ($item in @($r.out | ConvertFrom-Json)) { foreach ($c in @($item.content)) { if ($null -ne $c -and $null -ne $c.PSObject.Properties["text"]) { $text += " " + $c.text } } }
    } catch { return [pscustomobject]@{ sandbox = "(unreadable: " + $_.Exception.Message + ")"; approval = ""; escalation = $false; writable = @() } }
    $sb = [regex]::Match($text, '`sandbox_mode` is `([^`]*)`')
    $ap = [regex]::Match($text, 'Approval policy is currently (\w+)')
    $roots = @([regex]::Matches($text, '<entry access="write">(.*?)</entry>') | ForEach-Object { ($_.Groups[1].Value -replace '<[^>]+>', '').Trim() })
    return [pscustomobject]@{
        sandbox = $(if ($sb.Success) { $sb.Groups[1].Value } else { "(none)" })
        approval = $(if ($ap.Success) { $ap.Groups[1].Value } else { "" })
        escalation = [bool]($text -like "*How to request escalation*")
        writable = $roots
    }
}
function Get-Fragment { param([string]$Level) $f = Get-HordePermissionArgs -Descriptor $d -Level $Level -EntryPoint "interactive" -Verified @("windows-sandbox-configured"); Check ($f.state -eq "known") ("the descriptor gives an interactive fragment for " + $Level); return @($f.value) }

try {
    foreach ($h in @($plain, $elev)) {
        $which = $(if ($h -eq $elev) { "with the sandbox setting" } else { "with a plain home" })
        $p = Read-Policy -Fragment (Get-Fragment "plan") -CodexHome $h
        Check ($p.sandbox -ceq "read-only" -and $p.approval -ceq "never" -and -not $p.escalation) ("plan reads back read-only, approval never, no escalation, " + $which + " (read: " + $p.sandbox + "/" + $p.approval + "/" + $p.escalation + ")")
        $p = Read-Policy -Fragment (Get-Fragment "ask") -CodexHome $h
        Check ($p.sandbox -ceq "read-only" -and $p.escalation) ("ask reads back read-only with escalation offered, " + $which + " (read: " + $p.sandbox + "/" + $p.escalation + ")")
        $p = Read-Policy -Fragment (Get-Fragment "bypass") -CodexHome $h
        Check ($p.sandbox -ceq "danger-full-access") ("bypass reads back danger-full-access, " + $which + " (read: " + $p.sandbox + ")")
    }
    $edits = Get-Fragment "edits"
    $p = Read-Policy -Fragment $edits -CodexHome $elev
    $one = (@($p.writable).Count -eq 1 -and [System.IO.Path]::GetFullPath(@($p.writable)[0]).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($cwd).TrimEnd('\'))
    Check ($p.sandbox -ceq "workspace-write" -and $one) ("edits reads back workspace-write with the working folder as its only writable root (read: " + $p.sandbox + " " + (@($p.writable) -join ", ") + ")")
    # CONTROL for the null result above: the same start without the two -c settings shows the extra
    # roots, so the instrument does see them when they are there (review r60, F2).
    $bare = @($edits[0..3])
    $q = Read-Policy -Fragment $bare -CodexHome $elev
    Check (@($q.writable).Count -gt 1 -and (@($q.writable) -join " ") -like "*tmpdir*") ("CONTROL: without the exclusions the same start also makes the temp folders writable (read: " + (@($q.writable) -join ", ") + ")")
    # THE PRECONDITION IS REAL: without the sandbox setting, edits is silently read-only (F3), which is
    # why Get-HordePermissionArgs refuses edits until the setting is verified.
    $q = Read-Policy -Fragment $edits -CodexHome $plain
    Check ($q.sandbox -ceq "read-only") ("without the sandbox setting the edits fragment reads back read-only - the precondition is not decorative (read: " + $q.sandbox + ")")
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Check ((Get-RealHash) -ceq $before) "the real configuration file is byte-identical before and after"

Complete-HordeSuite -Success "every permission fragment reads back as the policy it promises"
