# END TO END: the WezTerm host's acting half (hosts/wezterm/Act.ps1) against a real, isolated terminal.
#
# The act path's A2. Runs only inside an instance of its own (Isolation.ps1: socket pin, --skip-config,
# --no-auto-start), and starts NO harness: the program in every pane is test/lib/PaneTool.ps1's
# compiled tool, an absolute path under TEMP, and every pane's process is checked to be that file and
# no harness's image. Every Act call NAMES the isolated terminal as its target (review of PR #96): none
# relies on this process's own pin. Nothing here reaches the user's terminal, agents or files.
#
# WHAT IT PROVES, in this order - nothing is spawned before step 1 has passed:
#   1. The in-pane environment check (Assert-HordePaneEnvironment, issue #95), through the production
#      spawn: a mapped variable reaches the pane; a variable of this process mapped to nothing does NOT,
#      with the control that, unmapped, it would.
#   2. Start-HordeWeztermPane starts the program with exactly its argv - quotes, line breaks and
#      & | ^ % included - in the folder asked for, and the program is traced to this terminal's gui.
#   3. A graceful close - the text a harness ends on, then -Submit - ends the program; the process is
#      gone by pid and start time, and the pane is gone.
#   4. A program that ignores it is still running after the bound (the control), and Stop - given the
#      process it expects - ends it.

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

function Wait-Until { param([scriptblock]$Cond, [int]$Seconds) $d = (Get-Date).AddSeconds($Seconds); while ((Get-Date) -lt $d) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 250 }; return [bool](& $Cond) }
function Test-Gone { param([long]$Id, [string]$Start) $now = Get-HordeWeztermProcessStart -ProcessId $Id; return [bool]($null -eq $now -or "" + $now -cne $Start) }
# Every harness's process image, read from the harnesses' own names.txt (CONTRIBUTING 14: this file
# names none of them), so a pane running any harness is caught by its image name.
$harnessImages = @(Get-ChildItem -Path (Join-Path $root "agents\*\names.txt") | ForEach-Object { Get-Content -LiteralPath $_.FullName } | Where-Object { $_ -match '^\s*([^|#]+?)\s*\|\s*processImage\s*\|' } | ForEach-Object { $Matches[1].Trim() })
function Test-IsTool {
    # Is the process -Id running exactly the pane tool, and no harness's image?
    param([long]$Id)
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
$T = $null
$spawn = { param($prog, $argv, $cwd) $r = Start-HordeWeztermPane -Target $T -Program $prog -Argv $argv -Cwd $cwd -Environment $envMap; if ($r.state -eq "known") { ($r.value.handle -split '\.')[2] } else { "" } }

$iso = Start-HordeIsolatedWezterm -TimeoutSeconds 45
Check ($null -ne $iso) "an isolated instance started and answered"
if ($iso) {
    $result = $null
    try {
        $count = $null
        try { $count = Assert-HordeIsolated -Instance $iso } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
        Check ($count -eq 1) "it is isolated, measured: exactly one pane, in its own window"
        $tt = New-HordeWeztermTarget -Socket $iso.socket
        Check ($tt.state -eq "known" -and $tt.value.guiPid -eq [long]$iso.pid) "the isolated terminal is named as the target, by its socket and its gui's start time"
        if ($tt.state -eq "known") { $T = $tt.value }
        $envOk = $false
        if ($count -eq 1 -and $null -ne $T) {
            Write-Host ""
            Write-Host "=== 1. the pane's environment, before anything else runs ===" -ForegroundColor Cyan
            try { $envOk = Assert-HordePaneEnvironment -Instance $iso -Variables @{ HORDE_MAPPED = $mappedValue } -Tool $tool -Spawn $spawn } catch { Write-Host ("         " + $_.Exception.Message) -ForegroundColor Red }
            Check ($envOk -eq $true) "through the production spawn, the pane has exactly the variable mapped to it"
        }
        if ($envOk) {
            $dump = Join-Path $work "strip.txt"
            $null = & $spawn $tool @("env-dump", $dump) $work
            $null = Wait-Until { Test-Path -LiteralPath $dump } 20; Start-Sleep -Milliseconds 300
            $seen = Read-HordePaneToolEnv -Path $dump
            Check ($null -ne $seen -and -not $seen.ContainsKey($nodeOnly) -and $seen["HORDE_MAPPED"] -ceq $mappedValue) "a variable this process holds and maps to nothing does NOT reach the pane"
            # The terminal sets a pane's own pin itself, spelling the same socket with forward slashes in
            # the middle (measured 2026-10-06: C:\Users\u\.local/share/wezterm\gui-sock-<pid>).
            Check ($null -ne $seen -and ("" + $seen["WEZTERM_UNIX_SOCKET"]).Replace("/", [string][char]92) -ieq $T.socket) "the pane's own pin is the named terminal's socket"
            $dump2 = Join-Path $work "nostrip.txt"
            $null = Start-HordeWeztermPane -Target $T -Program $tool -Argv @("env-dump", $dump2) -Cwd $work
            $null = Wait-Until { Test-Path -LiteralPath $dump2 } 20; Start-Sleep -Milliseconds 300
            $seen2 = Read-HordePaneToolEnv -Path $dump2
            Check ($null -ne $seen2 -and $seen2.ContainsKey($nodeOnly)) "CONTROL: unmapped, the same variable does reach the pane - the spawner's environment is inherited (issue #95)"

            Write-Host ""
            Write-Host "=== 2. the program gets exactly its argv, in its folder, in this terminal ===" -ForegroundColor Cyan
            $prompt = 'first line with "quotes" & pipe | caret ^ pct %PATH%' + "`n" + 'second line, trailing slash\'
            $rec1 = Join-Path $work "standin-1.txt"
            $s1 = Start-HordeWeztermPane -Target $T -Program $tool -Argv @("standin", $rec1, "exit", "--name", "E e2e act", $prompt) -Cwd $work -Environment $envMap
            Check ($s1.state -eq "known") ("the pane started" + $(if ($s1.state -ne "known") { " (" + $s1.reason + ")" } else { "" }))
            $got = $null
            if ($s1.state -eq "known") { $null = Wait-Until { Test-Path -LiteralPath $rec1 } 20; Start-Sleep -Milliseconds 300; $got = Read-HordePaneToolArgs -Path $rec1 }
            Check ($null -ne $got -and @($got.args).Count -eq 3 -and $got.args[0] -ceq "--name" -and $got.args[1] -ceq "E e2e act" -and $got.args[2] -ceq $prompt) "every argument arrived exactly, the multi-line prompt with its quotes and & | ^ % included"
            $e1 = $null
            if ($got) {
                Check (Test-IsTool -Id $got.pid) "the pane's process is the pane tool itself, by its executable path"
                $e1 = [pscustomobject]@{ pid = [long]$got.pid; procStart = (Get-HordeWeztermProcessStart -ProcessId $got.pid) }
                $in = Test-HordeWeztermProcessInTerminal -Target $T -Expect $e1
                Check ($in.state -eq "known" -and $in.value -eq $true) ("MEASURED: the pane's program is traced through its parents to this terminal's gui" + $(if ($in.state -ne "known") { " (" + $in.reason + ")" } else { "" }))
            }
            Check ($null -ne $e1 -and $null -ne $e1.procStart) "the program is running, with a pid and a start time"
            if ($s1.state -eq "known" -and $null -ne $e1) {
                $pp = Get-HordeWeztermProcessPane -ProcessId $e1.pid
                Check ($pp.state -eq "known" -and $pp.value -ceq ($s1.value.handle -split '\.')[2]) ("MEASURED: the program's own WEZTERM_PANE is its pane's id (" + $pp.state + " " + $pp.value + $pp.reason + ")")
                Check ((Test-HordeWeztermPaneLive -Target $T -Handle $s1.value.handle -Expect $e1).value -eq $true) "its pane is live, running that process"
            }

            Write-Host ""
            Write-Host "=== 3. a graceful close ends it, proven by pid and start time ===" -ForegroundColor Cyan
            if ($s1.state -eq "known" -and $null -ne $e1) {
                $t1 = Send-HordeWeztermText -Target $T -Handle $s1.value.handle -Text "/exit" -Submit
                Check ($t1.state -eq "known") "the close text was typed into its pane, then Enter by -Submit"
                Check (Wait-Until { Test-Gone -Id $e1.pid -Start $e1.procStart } 10) "the program ended: no process has its pid and start time"
                Check (Wait-Until { (Test-HordeWeztermPaneLive -Target $T -Handle $s1.value.handle -Expect $e1).value -eq $false } 10) "and its pane is not live"
            }

            Write-Host ""
            Write-Host "=== 4. a program that ignores the close, then Stop ===" -ForegroundColor Cyan
            $rec2 = Join-Path $work "standin-2.txt"
            $s2 = Start-HordeWeztermPane -Target $T -Program $tool -Argv @("standin", $rec2, "never") -Cwd $work -Environment $envMap
            $got2 = $null
            if ($s2.state -eq "known") { $null = Wait-Until { Test-Path -LiteralPath $rec2 } 20; Start-Sleep -Milliseconds 300; $got2 = Read-HordePaneToolArgs -Path $rec2 }
            $e2 = $null
            if ($got2) { Check (Test-IsTool -Id $got2.pid) "the second pane's process is the pane tool too"; $e2 = [pscustomobject]@{ pid = [long]$got2.pid; procStart = (Get-HordeWeztermProcessStart -ProcessId $got2.pid) } }
            Check ($null -ne $e2 -and $null -ne $e2.procStart) "a second program started"
            if ($null -ne $e2) {
                $null = Send-HordeWeztermText -Target $T -Handle $s2.value.handle -Text "/exit" -Submit
                Start-Sleep -Seconds 4
                Check (-not (Test-Gone -Id $e2.pid -Start $e2.procStart)) "CONTROL: it ignored the close and is still running after the bound, so the check above can see a failure"
                $wrong = Stop-HordeWeztermPane -Target $T -Handle $s2.value.handle -Expect ([pscustomobject]@{ pid = $e2.pid; procStart = "1" })
                Check ($wrong.state -eq "unknown" -and -not (Test-Gone -Id $e2.pid -Start $e2.procStart)) "Stop given another start time than the program's ends nothing"
                $other = ConvertTo-HordeWeztermHandle -Target $T -Pane "555"
                $cross = Stop-HordeWeztermPane -Target $T -Handle $other -Expect $e2
                Check ($cross.state -eq "unknown" -and $cross.reason -like "*another pane*" -and -not (Test-Gone -Id $e2.pid -Start $e2.procStart)) "Stop given a valid running process and an unrelated pane id (555) ends nothing (review of #96)"
                # Measured again before anything is ended: this process is still pinned to the instance it
                # started, and the named target is that instance. (Assert-HordeIsolated's one-window rule
                # does not hold here: the spawns above opened windows of their own.)
                Check ("$env:WEZTERM_UNIX_SOCKET" -ceq "$($iso.socket)" -and $T.socket -ceq $iso.socket -and $T.guiPid -eq [long]$iso.pid) "still pinned to the isolated instance, and the target is that instance, measured again before anything is ended"
                $st = Stop-HordeWeztermPane -Target $T -Handle $s2.value.handle -Expect $e2
                Check ($st.state -eq "known") "Stop, given the process it expects, was taken by the terminal"
                Check (Wait-Until { Test-Gone -Id $e2.pid -Start $e2.procStart } 10) "and the program is gone, by pid and start time"
            }
            $nl = Test-HordeWeztermPaneLive -Target $T -Handle (ConvertTo-HordeWeztermHandle -Target $T -Pane "987654") -Expect $e1
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
    if ($null -ne $T) {
        $after = Resolve-HordeWeztermHandle -Target $T -Handle (ConvertTo-HordeWeztermHandle -Target $T -Pane "1")
        Check ($after.state -eq "unknown" -and $after.reason -like "*no longer running*") "after teardown, a handle of that terminal is refused: its gui is gone"
    }
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Remove-HordePaneTool

Write-Host ""
if ($fails.Count -gt 0) { Write-Host ("==== " + $fails.Count + " FAILURE(S) ====") -ForegroundColor Red; foreach ($f in $fails) { Write-Host ("  - " + $f) -ForegroundColor Red }; exit 1 }
Write-Host "==== the host starts, types into, checks and ends its own panes exactly, in the terminal it names ====" -ForegroundColor Green
exit 0
