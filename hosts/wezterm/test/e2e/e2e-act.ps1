# END TO END: the WezTerm host's acting half (hosts/wezterm/Act.ps1) against a real, isolated terminal.
#
# The act path's A2. Runs only inside an instance of its own (Isolation.ps1: socket pin, --skip-config,
# --no-auto-start), and starts NO harness: the program in every pane is test/lib/PaneTool.ps1's
# compiled tool, an absolute path under TEMP, and every pane's process is checked to be that file and
# nothing named after a harness. Nothing here reaches the user's terminal, agents or files.
#
# WHAT IT PROVES, in this order - nothing is spawned before step 1 has passed:
#   1. The in-pane environment check (Assert-HordePaneEnvironment, issue #95), through the production
#      spawn: a mapped variable reaches the pane; a variable of this process mapped to nothing does NOT
#      (the node's own variables never reach a session), with the control that, unmapped, it would.
#   2. Start-HordeWeztermPane starts the program with exactly its argv - quotes, line breaks and
#      & | ^ % included - in the folder asked for.
#   3. A graceful close - the text a harness ends on, typed into the pane - ends the program; the
#      process is gone by pid and start time, and the pane is gone.
#   4. A program that ignores it is still running after the bound (the control), and Stop ends it.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
. (Join-Path (Split-Path -Parent $here) "Isolation.ps1")
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "core\HostAct.ps1")
. (Join-Path $root "hosts\wezterm\Act.ps1")

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond -is [bool] -and $Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }

function Get-StartTicks { param([int]$Id) $p = Get-Process -Id $Id -ErrorAction SilentlyContinue; if ($p) { return $p.StartTime.ToUniversalTime().Ticks }; return $null }
function Test-Gone { param([int]$Id, $Ticks) $t = Get-StartTicks -Id $Id; return [bool]($null -eq $t -or $t -ne $Ticks) }
function Wait-Until { param([scriptblock]$Cond, [int]$Seconds) $d = (Get-Date).AddSeconds($Seconds); while ((Get-Date) -lt $d) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 250 }; return [bool](& $Cond) }
# Every harness's process image, read from the harnesses' own names.txt (CONTRIBUTING 14: this file
# names none of them), so a pane running any harness is caught by its image name.
$harnessImages = @(Get-ChildItem -Path (Join-Path $root "agents\*\names.txt") | ForEach-Object { Get-Content -LiteralPath $_.FullName } | Where-Object { $_ -match '^\s*([^|#]+?)\s*\|\s*processImage\s*\|' } | ForEach-Object { $Matches[1].Trim() })
function Test-IsTool {
    # Is the process -Id running exactly the pane tool, and no harness's image?
    param([int]$Id)
    $p = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $Id) -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    return [bool](("" + $p.ExecutablePath) -ieq $tool -and $harnessImages -notcontains ("" + $p.Name))
}

$tool = Get-HordePaneTool
Check ($harnessImages.Count -ge 1) ("CONTROL: the harnesses' process images were read, so the check below can see one (" + ($harnessImages -join ", ") + ")")
Check ([System.IO.Path]::IsPathRooted($tool) -and $harnessImages -notcontains (Split-Path -Leaf $tool) -and (Split-Path -Leaf $tool) -ceq "horde-panetool.exe") "the only program this scenario starts is the compiled pane tool, by absolute path, and it is no harness's image"
$work = Join-Path $env:TEMP ("horde-e2e-act-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$nodeOnly = "HORDE_NODE_ONLY"
[Environment]::SetEnvironmentVariable($nodeOnly, "node-" + [guid]::NewGuid().ToString("N").Substring(0, 8), "Process")
$mappedValue = "mapped-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$envMap = @{ HORDE_MAPPED = $mappedValue; $nodeOnly = $null }
$spawn = { param($prog, $argv, $cwd) $r = Start-HordeWeztermPane -Program $prog -Argv $argv -Cwd $cwd -Environment $envMap; if ($r.state -eq "known") { $r.value.handle } else { "" } }

$iso = Start-HordeIsolatedWezterm -TimeoutSeconds 45
Check ($null -ne $iso) "an isolated instance started and answered"
if ($iso) {
    $result = $null
    try {
        $count = $null
        try { $count = Assert-HordeIsolated -Instance $iso } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        Check ($count -eq 1) "it is isolated, measured: exactly one pane, in its own window"
        $envOk = $false
        if ($count -eq 1) {
            Write-Host ""
            Write-Host "=== 1. the pane's environment, before anything else runs ===" -ForegroundColor Cyan
            try { $envOk = Assert-HordePaneEnvironment -Instance $iso -Variables @{ HORDE_MAPPED = $mappedValue } -Tool $tool -Spawn $spawn } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
            Check ($envOk -eq $true) "through the production spawn, the pane has exactly the variable mapped to it"
        }
        if ($envOk) {
            $dump = Join-Path $work "strip.txt"
            $h = & $spawn $tool @("env-dump", $dump) $work
            $null = Wait-Until { Test-Path -LiteralPath $dump } 20; Start-Sleep -Milliseconds 300
            $seen = Read-HordePaneToolEnv -Path $dump
            Check ($null -ne $seen -and -not $seen.ContainsKey($nodeOnly) -and $seen["HORDE_MAPPED"] -ceq $mappedValue) "a variable this process holds and maps to nothing does NOT reach the pane"
            $dump2 = Join-Path $work "nostrip.txt"
            $r2 = Start-HordeWeztermPane -Program $tool -Argv @("env-dump", $dump2) -Cwd $work
            $null = Wait-Until { Test-Path -LiteralPath $dump2 } 20; Start-Sleep -Milliseconds 300
            $seen2 = Read-HordePaneToolEnv -Path $dump2
            Check ($null -ne $seen2 -and $seen2.ContainsKey($nodeOnly)) "CONTROL: unmapped, the same variable does reach the pane - the spawner's environment is inherited (issue #95)"

            Write-Host ""
            Write-Host "=== 2. the program gets exactly its argv, in its folder ===" -ForegroundColor Cyan
            $prompt = 'first line with "quotes" & pipe | caret ^ pct %PATH%' + "`n" + 'second line, trailing slash\'
            $rec1 = Join-Path $work "standin-1.txt"
            $s1 = Start-HordeWeztermPane -Program $tool -Argv @("standin", $rec1, "exit", "--name", "E e2e act", $prompt) -Cwd $work -Environment $envMap
            Check ($s1.state -eq "known") ("the pane started" + $(if ($s1.state -ne "known") { " (" + $s1.reason + ")" } else { "" }))
            $got = $null
            if ($s1.state -eq "known") { $null = Wait-Until { Test-Path -LiteralPath $rec1 } 20; Start-Sleep -Milliseconds 300; $got = Read-HordePaneToolArgs -Path $rec1 }
            Check ($null -ne $got -and @($got.args).Count -eq 3 -and $got.args[0] -ceq "--name" -and $got.args[1] -ceq "E e2e act" -and $got.args[2] -ceq $prompt) "every argument arrived exactly, the multi-line prompt with its quotes and & | ^ % included"
            $ticks1 = $null
            if ($got) { $ticks1 = Get-StartTicks -Id $got.pid; Check (Test-IsTool -Id $got.pid) "the pane's process is the pane tool itself, by its executable path" }
            Check ($null -ne $ticks1) "the program is running, with a pid and a start time"
            if ($s1.state -eq "known") { Check ((Test-HordeWeztermPaneLive -Handle $s1.value.handle).value -eq $true) "its pane is live" }

            Write-Host ""
            Write-Host "=== 3. a graceful close ends it, proven by pid and start time ===" -ForegroundColor Cyan
            if ($s1.state -eq "known" -and $null -ne $ticks1) {
                $t1 = Send-HordeWeztermText -Handle $s1.value.handle -Text "/exit"
                $t2 = Send-HordeWeztermText -Handle $s1.value.handle -Text "`r"
                Check ($t1.state -eq "known" -and $t2.state -eq "known") "the close text and Enter were typed into its pane"
                Check (Wait-Until { Test-Gone -Id $got.pid -Ticks $ticks1 } 10) "the program ended: no process has its pid and start time"
                Check (Wait-Until { (Test-HordeWeztermPaneLive -Handle $s1.value.handle).value -eq $false } 10) "and its pane is gone"
            }

            Write-Host ""
            Write-Host "=== 4. a program that ignores the close, then Stop ===" -ForegroundColor Cyan
            $rec2 = Join-Path $work "standin-2.txt"
            $s2 = Start-HordeWeztermPane -Program $tool -Argv @("standin", $rec2, "never") -Cwd $work -Environment $envMap
            $got2 = $null
            if ($s2.state -eq "known") { $null = Wait-Until { Test-Path -LiteralPath $rec2 } 20; Start-Sleep -Milliseconds 300; $got2 = Read-HordePaneToolArgs -Path $rec2 }
            $ticks2 = $null
            if ($got2) { $ticks2 = Get-StartTicks -Id $got2.pid; Check (Test-IsTool -Id $got2.pid) "the second pane's process is the pane tool too" }
            Check ($null -ne $ticks2) "a second program started"
            if ($null -ne $ticks2) {
                $null = Send-HordeWeztermText -Handle $s2.value.handle -Text "/exit"
                $null = Send-HordeWeztermText -Handle $s2.value.handle -Text "`r"
                Start-Sleep -Seconds 4
                Check (-not (Test-Gone -Id $got2.pid -Ticks $ticks2)) "CONTROL: it ignored the close and is still running after the bound, so the check above can see a failure"
                $st = Stop-HordeWeztermPane -Handle $s2.value.handle
                Check ($st.state -eq "known") "Stop was taken by the terminal"
                Check (Wait-Until { Test-Gone -Id $got2.pid -Ticks $ticks2 } 10) "and the program is gone, by pid and start time"
                Check (Wait-Until { (Test-HordeWeztermPaneLive -Handle $s2.value.handle).value -eq $false } 10) "and its pane"
            }
            $nl = Test-HordeWeztermPaneLive -Handle "987654"
            Check ($nl.state -eq "known" -and $nl.value -eq $false) "a pane this terminal never had is known not live"
        }
    }
    finally {
        # Teardown runs whatever happened above. A teardown that only runs on success is the leak.
        $result = Stop-HordeIsolatedWezterm -Instance $iso
        [Environment]::SetEnvironmentVariable($nodeOnly, $null, "Process")
    }
    Check (-not $result.refused) "teardown accepted the instance Start issued"
    Check ($result.stopped -and -not $result.survived -and @($result.orphansSurvived).Count -eq 0) "the terminal and everything that ran in it are gone"
    Check ($result.socketRemoved -and -not (Test-Path -LiteralPath $iso.store)) "its socket and its throwaway store are removed"
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Remove-HordePaneTool

Write-Host ""
if ($fails.Count -gt 0) { Write-Host ("==== " + $fails.Count + " FAILURE(S) ====") -ForegroundColor Red; foreach ($f in $fails) { Write-Host ("  - " + $f) -ForegroundColor Red }; exit 1 }
Write-Host "==== the host starts, types into, checks and ends its own panes exactly, in an isolated terminal ====" -ForegroundColor Green
exit 0
