# DOES THE WEZTERM HOST START, TYPE INTO, CHECK AND END PANES WITH EXACTLY THE CALLS IT MEANS, IN THE
# TERMINAL IT IS TOLD, AND NO OTHER?
#
# The fast half of hosts/wezterm/Act.ps1's tests (the act path's A2). No terminal is touched: every
# terminal call goes to a recording runner, or to test/lib/PaneTool.ps1's compiled tool standing in for
# the terminal's command, which prints back the arguments and environment it got.
#
# FAIL CLOSED: this suite's own pin names a socket that does not exist, set as its first act. A call
# that escaped a mock would then fail to connect instead of reaching whatever terminal this suite was
# started from (review of PR #96, finding 2).
#
# The end-to-end half, in an isolated instance, is hosts/wezterm/test/e2e/e2e-act.ps1.

$env:WEZTERM_UNIX_SOCKET = Join-Path $env:TEMP ("horde-test-act-no-terminal-" + [guid]::NewGuid().ToString("N"))
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "core\HostAct.ps1")
. (Join-Path $root "hosts\wezterm\Act.ps1")
. (Join-Path $root "test\lib\PaneTool.ps1")

$script:calls = New-Object System.Collections.ArrayList
$script:reply = [pscustomobject]@{ code = 0; out = "17`n"; err = ""; timedOut = $false }
$script:envSeen = $null
$script:targetSeen = $null
$rec = { param($rest, $envMap, $target) [void]$script:calls.Add(@($rest)); $script:envSeen = $envMap; $script:targetSeen = $target; $script:reply }
$prog = "C:\Program Files\Harness\harness.exe"
$guiStart = "133000000000000000"
$T = [pscustomobject]@{ socket = "C:\fake\wezterm\gui-sock-4242"; guiPid = 4242; guiStart = $guiStart }
$alive = { param($p) if ($p -eq 4242) { $guiStart } else { $null } }
$H = "4242." + $guiStart + ".17"
$in17 = { param($p) New-HordeKnown -Value "17" }
$listed = '[{"window_id":0,"tab_id":0,"pane_id":17,"title":"t","cwd":""},{"window_id":0,"tab_id":1,"pane_id":18,"title":"u","cwd":""}]'

Write-Host ""
Write-Host "--- every call carries --no-auto-start, from one place ---" -ForegroundColor Cyan
Check ((@(Get-HordeWeztermActArgv -Rest @("list")) -join " ") -ceq "cli --no-auto-start list") "the cli argv always begins cli --no-auto-start"
$src = [System.IO.File]::ReadAllText((Join-Path $root "hosts\wezterm\Act.ps1"))
Check (([regex]::Matches($src, 'Get-HordeWeztermActArgv -Rest')).Count -eq 1 -and $src.Contains('$psi.Arguments = ConvertTo-HordeWindowsCommandLine -Argv (Get-HordeWeztermActArgv -Rest $Rest)')) "the one process start builds its arguments from that argv"
Check (-not ($src -match '&\s*\$script:HordeWeztermActExe') -and -not ($src -match '(?m)^\s*&\s*wezterm\b')) "nothing calls the terminal by the call operator"

Write-Host ""
Write-Host "--- the terminal is always named, never inherited (review of PR #96) ---" -ForegroundColor Cyan
$tool = Get-HordePaneTool
$saveExe = $script:HordeWeztermActExe
$script:HordeWeztermActExe = $tool
$work = Join-Path $env:TEMP ("horde-act-pin-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $d0 = Join-Path $work "none.txt"
    $r = Invoke-HordeWeztermAct -Rest @("env-dump", $d0)
    Check ($r.code -eq -1 -and $r.err -like "refused: no terminal was named*" -and -not (Test-Path -LiteralPath $d0)) "a call with no named terminal is refused, and no process starts"
    $r = Invoke-HordeWeztermAct -Rest @("env-dump", $d0) -Target ([pscustomobject]@{ socket = ""; guiPid = 4242; guiStart = $guiStart })
    Check ($r.code -eq -1 -and $r.err -like "*empty pin*" -and -not (Test-Path -LiteralPath $d0)) "a named terminal with an empty socket is refused: an empty pin is no pin"
    $r = Invoke-HordeWeztermAct -Rest @("env-dump", $d0) -Target ([pscustomobject]@{ socket = "C:\fake\other-name"; guiPid = 4242; guiStart = $guiStart })
    Check ($r.code -eq -1 -and $r.err -like "*not named after a gui*") "a socket not named after its gui is refused"
    $d1 = Join-Path $work "pinned.txt"
    $r = Invoke-HordeWeztermAct -Rest @("env-dump", $d1) -Target $T
    $seen = Read-HordePaneToolEnv -Path $d1
    Check ($r.code -eq 0 -and $null -ne $seen -and $seen["WEZTERM_UNIX_SOCKET"] -ceq $T.socket) "the call's process is pinned to the named terminal's socket, whatever this process's own pin says"
    foreach ($name in @("WEZTERM_UNIX_SOCKET", "wezterm_unix_socket", "WEZTERM_PANE", "WEZTERM_CONFIG_FILE")) {
        foreach ($val in @($null, "C:\elsewhere\gui-sock-1")) {
            $dx = Join-Path $work ("m-" + [guid]::NewGuid().ToString("N") + ".txt")
            $r = Invoke-HordeWeztermAct -Rest @("env-dump", $dx) -Target $T -Environment @{ $name = $val }
            Check ($r.code -eq -1 -and $r.err -like "*decides which terminal is called*" -and -not (Test-Path -LiteralPath $dx)) ("an environment map naming " + $name + " (" + $(if ($null -eq $val) { "removed" } else { "redirected" }) + ") is refused, and no process starts")
        }
    }

    Write-Host ""
    Write-Host "--- the spawn's environment: set what is mapped, remove what is mapped to nothing ---" -ForegroundColor Cyan
    [Environment]::SetEnvironmentVariable("HORDE_NODE_ONLY", "node-secret", "Process")
    try {
        $d2 = Join-Path $work "mapped.txt"
        $r = Invoke-HordeWeztermAct -Rest @("env-dump", $d2) -Target $T -Environment @{ HORDE_MAPPED = "m"; HORDE_NODE_ONLY = $null }
        $seen = Read-HordePaneToolEnv -Path $d2
        Check ($r.code -eq 0 -and $null -ne $seen -and $seen["HORDE_MAPPED"] -ceq "m" -and -not $seen.ContainsKey("HORDE_NODE_ONLY")) "a terminal call's process gets the mapped variable and not the node-only one"
        $d3 = Join-Path $work "plain.txt"
        $null = Invoke-HordeWeztermAct -Rest @("env-dump", $d3) -Target $T
        $seen3 = Read-HordePaneToolEnv -Path $d3
        Check ($null -ne $seen3 -and $seen3["HORDE_NODE_ONLY"] -ceq "node-secret") "CONTROL: without the map, the node's own variable would reach it"
    } finally { [Environment]::SetEnvironmentVariable("HORDE_NODE_ONLY", $null, "Process") }
    $r = Invoke-HordeWeztermAct -Rest @("env-dump", (Join-Path $work "nul.txt")) -Target $T -Environment @{ HORDE_V = ("a" + [char]0 + "b") }
    Check ($r.code -eq -1 -and $r.err -like "*holds a NUL*") "a value holding NUL is refused, not silently cut"
    $r = Invoke-HordeWeztermAct -Rest @("env-dump", (Join-Path $work "big.txt")) -Target $T -Environment @{ HORDE_V = ("x" * 8193) }
    Check ($r.code -eq -1 -and $r.err -like "*8193 characters, over the cap of 8192*") "a value past the cap is refused"
    $d4 = Join-Path $work "cap.txt"
    $r = Invoke-HordeWeztermAct -Rest @("env-dump", $d4) -Target $T -Environment @{ HORDE_V = ("x" * 8192) }
    Check ($r.code -eq 0 -and (Read-HordePaneToolEnv -Path $d4)["HORDE_V"].Length -eq 8192) "CONTROL: a value at the cap arrives whole"
    $r = Invoke-HordeWeztermAct -Rest @("env-dump", (Join-Path $work "n.txt")) -Target $T -Environment @{ "A=B" = "x" }
    Check ($r.code -eq -1 -and $r.err -like "*not an environment variable name*") "a name that is not a variable name is refused"
} finally {
    $script:HordeWeztermActExe = $saveExe
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "--- the command line reaches the program exactly (proven by a real process) ---" -ForegroundColor Cyan
$work = Join-Path $env:TEMP ("horde-act-quote-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $cases = @("plain", "", "two words", 'a "quoted" word', 'trail\', 'trail\\', 'C:\path with space\', 'back\\"slash', ("line one`nline two"), "tab`there", 'amp & pipe | caret ^ pct %PATH% lt < gt >', "a`r`nb", ' leading', 'trailing ', '\\server\share', '"', '""', '\"')
    $out = Join-Path $work "args.txt"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $tool
    $psi.Arguments = ConvertTo-HordeWindowsCommandLine -Argv (@("standin", $out, "exit") + $cases)
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.WriteLine("/exit"); $p.StandardInput.Close()
    [void]$p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(15000); $p.Dispose()
    $got = Read-HordePaneToolArgs -Path $out
    Check ($null -ne $got -and @($got.args).Count -eq $cases.Count) ("the program received " + $cases.Count + " arguments, one per argument given (" + $(if ($got) { @($got.args).Count } else { "none" }) + ")")
    for ($i = 0; $i -lt $cases.Count; $i++) {
        $shown = ($cases[$i] -replace "`r", '\r' -replace "`n", '\n' -replace "`t", '\t')
        Check ($null -ne $got -and $i -lt @($got.args).Count -and $got.args[$i] -ceq $cases[$i]) ("argument [" + $shown + "] arrives exactly")
    }
} finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "--- start a pane: the handle carries the terminal's identity ---" -ForegroundColor Cyan
$script:calls.Clear()
$r = Start-HordeWeztermPane -Target $T -Program $prog -Argv @("--id", "x y") -Cwd "C:\work\app" -Environment @{ HORDE_MAPPED = "m" } -Runner $rec -ProcessStart $alive
Check ($r.state -eq "known" -and $r.value.handle -ceq $H) ("the handle is <gui pid>.<gui start>.<pane id> (" + $r.value.handle + ")")
Check ((@($script:calls[0]) -join "|") -ceq ("spawn|--new-window|--cwd|C:\work\app|--|" + $prog + "|--id|x y") -and $script:targetSeen -eq $T -and $script:envSeen["HORDE_MAPPED"] -ceq "m") "the spawn goes to the named terminal, with the map, the program after --"
$script:calls.Clear()
Check ((Start-HordeWeztermPane -Program $prog -Cwd "C:\w" -Runner $rec).state -eq "unknown" -and $script:calls.Count -eq 0) "a start with no named terminal is refused before the terminal is asked"
Check ((Start-HordeWeztermPane -Target $T -Program "harness" -Cwd "C:\w" -Runner $rec -ProcessStart $alive).state -eq "unknown" -and $script:calls.Count -eq 0) "a program that is not a full path is refused"
Check ((Start-HordeWeztermPane -Target $T -Program "C:\h\harness.cmd" -Cwd "C:\w" -Runner $rec -ProcessStart $alive).state -eq "unknown") "a program that is not an .exe is refused: no cmd.exe between Horde and the harness"
Check ((Start-HordeWeztermPane -Target $T -Program $prog -Cwd "work" -Runner $rec -ProcessStart $alive).state -eq "unknown") "a relative working folder is refused"
$script:reply = [pscustomobject]@{ code = 0; out = "Error: something"; err = ""; timedOut = $false }
Check ((Start-HordeWeztermPane -Target $T -Program $prog -Cwd "C:\w" -Runner $rec -ProcessStart $alive).reason -like "*not a pane id*") "an answer that is not a pane id leaves whether a pane started unknown"

Write-Host ""
Write-Host "--- a handle is acted on only in the terminal that made it ---" -ForegroundColor Cyan
$p = Resolve-HordeWeztermHandle -Target $T -Handle $H -ProcessStart $alive
Check ($p.state -eq "known" -and $p.value -ceq "17") "CONTROL: a handle of this terminal, still running with its start time, gives its pane id"
Check ((Resolve-HordeWeztermHandle -Target $T -Handle ("4242.133000000000000001.17") -ProcessStart $alive).reason -like "*belongs to another terminal*") "a handle from an earlier run of the terminal (another start time) is refused: pane ids restart"
Check ((Resolve-HordeWeztermHandle -Target $T -Handle $H -ProcessStart { param($p) "133000000000099999" }).reason -like "*now has another start time*") "a terminal whose gui now has another start time is another terminal"
Check ((Resolve-HordeWeztermHandle -Target $T -Handle "17" -ProcessStart $alive).state -eq "unknown") "a bare pane id is not a handle"

Write-Host ""
Write-Host "--- type: printable text after --, Enter only by -Submit (review of PR #96) ---" -ForegroundColor Cyan
$script:reply = [pscustomobject]@{ code = 0; out = ""; err = ""; timedOut = $false }
$script:calls.Clear()
$r = Send-HordeWeztermText -Target $T -Handle $H -Text "/exit" -Runner $rec -ProcessStart $alive
Check ($r.state -eq "known" -and $script:calls.Count -eq 1 -and (@($script:calls[0]) -join "|") -ceq "send-text|--pane-id|17|--no-paste|--|/exit") "text is typed as keystrokes, after --, and Enter is not pressed"
$script:calls.Clear()
$r = Send-HordeWeztermText -Target $T -Handle $H -Text "/exit" -Submit -Runner $rec -ProcessStart $alive
Check ($script:calls.Count -eq 2 -and (@($script:calls[1]) -join "|") -ceq ("send-text|--pane-id|17|--no-paste|--|" + "`r")) "with -Submit, Enter is pressed as a keystroke of its own"
$script:calls.Clear()
$r = Send-HordeWeztermText -Target $T -Handle $H -Text "--help" -Runner $rec -ProcessStart $alive
Check ($r.state -eq "known" -and (@($script:calls[0]) -join "|") -ceq "send-text|--pane-id|17|--no-paste|--|--help") "a body that looks like a flag is text: it comes after --"
foreach ($c in @(13, 10, 27, 3, 4, 0, 9, 127)) {
    $script:calls.Clear()
    $r = Send-HordeWeztermText -Target $T -Handle $H -Text ("a" + [char]$c + "b") -Runner $rec -ProcessStart $alive
    Check ($r.state -eq "unknown" -and $r.reason -like "*control character*" -and $script:calls.Count -eq 0) ("a body holding character " + $c + " is refused, and nothing is typed")
}
$r = Send-HordeWeztermText -Target $T -Handle $H -Text ("x" * 1025) -Runner $rec -ProcessStart $alive
Check ($r.state -eq "unknown" -and $r.reason -like "*1025 characters*") "a body past the cap is refused"
Check ((Send-HordeWeztermText -Target $T -Handle $H -Text "" -Runner $rec -ProcessStart $alive).state -eq "unknown") "nothing to type and no -Submit is refused"
$script:calls.Clear()
Check ((Send-HordeWeztermText -Target $T -Handle "4242.1.17" -Text "x" -Runner $rec -ProcessStart $alive).state -eq "unknown" -and $script:calls.Count -eq 0) "text for a handle of another terminal is refused, and nothing is typed"

Write-Host ""
Write-Host "--- end and check a pane: only with the expected process proven in this terminal ---" -ForegroundColor Cyan
# A fixture process table: the gui (4242), a conpty host under it, the pane's program (5000).
$table = @(
    [pscustomobject]@{ pid = 4242; ppid = 1; start = $guiStart },
    [pscustomobject]@{ pid = 4300; ppid = 4242; start = "133000000000000100" },
    [pscustomobject]@{ pid = 5000; ppid = 4300; start = "133000000000000200" },
    [pscustomobject]@{ pid = 6000; ppid = 999; start = "133000000000000300" },
    [pscustomobject]@{ pid = 7000; ppid = 4242; start = "132000000000000000" })
$ok = [pscustomobject]@{ pid = 5000; procStart = "133000000000000200" }
Check ((Test-HordeWeztermProcessInTerminal -Target $T -Expect $ok -Table $table).value -eq $true) "CONTROL: the pane's program, traced through its parents to this terminal's gui, is in it"
Check ((Test-HordeWeztermProcessInTerminal -Target $T -Expect ([pscustomobject]@{ pid = 5000; procStart = "133000000000000250" }) -Table $table).value -eq $false) "a pid now running with another start time is not the expected process"
Check ((Test-HordeWeztermProcessInTerminal -Target $T -Expect ([pscustomobject]@{ pid = 6000; procStart = "133000000000000300" }) -Table $table).state -eq "unknown") "a process not traced to this terminal's gui is never called in it"
Check ((Test-HordeWeztermProcessInTerminal -Target $T -Expect ([pscustomobject]@{ pid = 7000; procStart = "132000000000000000" }) -Table $table).state -eq "unknown") "a parent that started after its child is a reused pid, and is not believed"
Check ((Test-HordeWeztermProcessInTerminal -Target $T -Expect $null -Table $table).state -eq "unknown") "no expected process: unknown, never assumed"
# One instant read by two sources: the process table keeps microseconds, Get-Process 100 ns ticks.
Check ((Test-HordeWeztermProcessInTerminal -Target $T -Expect ([pscustomobject]@{ pid = 5000; procStart = "133000000000000207" }) -Table $table).value -eq $true) "a start time read to 100 ns matches the table's microseconds (measured: one gui read both ways differed by 2 ticks)"
Check ((Test-HordeWeztermSameStart "133000000000000200" "133000000000000210") -eq $false) "a microsecond apart is another start time"
Check ((Test-HordeWeztermSameStart "x" "x") -eq $false) "an unreadable start time is never the same"
$script:reply = [pscustomobject]@{ code = 0; out = $listed; err = ""; timedOut = $false }
$script:calls.Clear()
$r = Stop-HordeWeztermPane -Target $T -Handle $H -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17
Check ($r.state -eq "known" -and (@($script:calls[0]) -join "|") -ceq "list|--format|json" -and (@($script:calls[1]) -join "|") -ceq "kill-pane|--pane-id|17") "ending a pane is kill-pane on that pane, once its expected process is proven in this terminal"
$script:calls.Clear()
$r = Stop-HordeWeztermPane -Target $T -Handle $H -Expect ([pscustomobject]@{ pid = 6000; procStart = "133000000000000300" }) -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17
Check ($r.state -eq "unknown" -and $r.reason -like "nothing was ended: *not traced to the terminal's gui*" -and $script:calls.Count -eq 0) "a process not proven in this terminal: nothing is ended, saying it could not be traced"
$r = Stop-HordeWeztermPane -Target $T -Handle $H -Expect ([pscustomobject]@{ pid = 5000; procStart = "100" }) -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17
Check ($r.state -eq "unknown" -and $r.reason -like "*not running with its start time*" -and $script:calls.Count -eq 0) "an expected process that is gone: nothing is ended"
$r = Stop-HordeWeztermPane -Target $T -Handle $H -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17
Check ($r.state -eq "unknown" -and $r.reason -like "nothing was ended: no expected process*" -and $script:calls.Count -eq 0) "no expected process at all: nothing is ended, a pane id alone is never enough"
$r = Stop-HordeWeztermPane -Target $T -Handle "4242.1.17" -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17
Check ($r.state -eq "unknown" -and $script:calls.Count -eq 0) "a handle of another terminal: nothing is ended"
$script:reply = [pscustomobject]@{ code = 0; out = '[{"window_id":0,"tab_id":0,"pane_id":17,"title":"t","cwd":""},{"window_id":0,"tab_id":1,"pane_id":18,"title":"u","cwd":""}]'; err = ""; timedOut = $false }
Check ((Test-HordeWeztermPaneLive -Target $T -Handle $H -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17).value -eq $true) "a listed pane running the expected process is live"
Check ((Test-HordeWeztermPaneLive -Target $T -Handle $H -Expect ([pscustomobject]@{ pid = 5000; procStart = "1" }) -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17).value -eq $false) "a listed pane whose expected process is gone is not"
Check ((Test-HordeWeztermPaneLive -Target $T -Handle ("4242." + $guiStart + ".1") -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17).value -eq $false) "an unlisted pane is not live"
$script:reply = [pscustomobject]@{ code = 0; out = ""; err = ""; timedOut = $false }
Check ((Test-HordeWeztermPaneLive -Target $T -Handle $H -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17).state -eq "unknown") "an empty answer is unknown, never 'gone'"
$script:reply = [pscustomobject]@{ code = 1; out = ""; err = "x"; timedOut = $false }
Check ((Test-HordeWeztermPaneLive -Target $T -Handle $H -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17).state -eq "unknown") "a terminal that did not list is unknown, never 'gone'"

Write-Host ""
Write-Host "--- a pane is tied to its process by the process's own WEZTERM_PANE (review of #96, follow-up) ---" -ForegroundColor Cyan
$script:reply = [pscustomobject]@{ code = 0; out = $listed; err = ""; timedOut = $false }
$script:calls.Clear()
$r = Stop-HordeWeztermPane -Target $T -Handle ("4242." + $guiStart + ".555") -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf $in17
Check ($r.state -eq "unknown" -and $r.reason -clike "pane-claim-mismatch: *runs in another pane than 555*" -and @($script:calls | Where-Object { $_[0] -ceq "kill-pane" }).Count -eq 0) "the reviewer's case: a valid process and an unrelated pane id (555) end nothing"
$script:calls.Clear()
$r = Stop-HordeWeztermPane -Target $T -Handle ("4242." + $guiStart + ".555") -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf { param($p) New-HordeKnown -Value "555" }
Check ($r.state -eq "unknown" -and $r.reason -like "*lists no pane 555*" -and @($script:calls | Where-Object { $_[0] -ceq "kill-pane" }).Count -eq 0) "a process that names pane 555 when the terminal lists no pane 555 ends nothing"
$script:calls.Clear()
$r = Stop-HordeWeztermPane -Target $T -Handle $H -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf { param($p) New-HordeUnknown -Reason "the environment of process 5000 could not be read" }
Check ($r.state -eq "unknown" -and $r.reason -like "*environment of process 5000 could not be read*" -and $script:calls.Count -eq 0) "an environment that cannot be read ends nothing, and the reason names it"
$lv = Test-HordeWeztermPaneLive -Target $T -Handle $H -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf { param($p) New-HordeKnown -Value "18" }
Check ($lv.state -eq "unknown" -and $lv.reason -clike "pane-claim-mismatch: *") "a listed pane whose proven process names another pane is UNKNOWN, never called gone (review of #99, finding 1)"
Check ((Test-HordeWeztermPaneLive -Target $T -Handle $H -Expect $ok -Runner $rec -ProcessStart $alive -Table $table -PaneOf { param($p) New-HordeUnknown -Reason "unreadable" }).state -eq "unknown") "and is unknown when the process's pane cannot be read"
# THE REAL READER, against real children (review of #99, finding 3): one started with WEZTERM_PANE=4242
# must read 4242, and one started without it must read unknown. Plain processes; no terminal is involved.
function Start-PaneChild {
    param([string]$Pane)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")
    $psi.Arguments = "-NoProfile -NonInteractive -Command Start-Sleep -Seconds 60"
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    if ($psi.EnvironmentVariables.ContainsKey("WEZTERM_PANE")) { $psi.EnvironmentVariables.Remove("WEZTERM_PANE") }
    if ($Pane -ne "") { $psi.EnvironmentVariables["WEZTERM_PANE"] = $Pane }
    return [System.Diagnostics.Process]::Start($psi)
}
function Read-PaneOf {
    param($Proc)
    $r = $null
    for ($i = 0; $i -lt 10; $i++) { $r = Get-HordeWeztermProcessPane -ProcessId $Proc.Id; if ($r.state -eq "known") { break }; Start-Sleep -Milliseconds 300 }
    return $r
}
$withPane = $null; $without = $null
try {
    $withPane = Start-PaneChild "4242"
    $without = Start-PaneChild ""
    $rw = Read-PaneOf $withPane
    Check ($rw.state -eq "known" -and "" + $rw.value -ceq "4242") ("the real reader reads WEZTERM_PANE=4242 from a child's own environment block (" + $rw.state + ": " + $rw.reason + $rw.value + ")")
    $ro = Get-HordeWeztermProcessPane -ProcessId $without.Id
    Check ($ro.state -eq "unknown" -and $ro.reason -like "*no WEZTERM_PANE*") ("and a child without the variable reads unknown, saying so (" + $ro.reason + ")")
} finally {
    foreach ($c in @($withPane, $without)) { if ($null -ne $c) { try { if (-not $c.HasExited) { $c.Kill() } } catch { }; $c.Dispose() } }
}
$script:calls.Clear()
$r = Start-HordeWeztermPane -Target $T -Program $prog -Cwd "C:\w" -Runner $rec -ProcessStart { param($p) $null }
Check ($r.state -eq "unknown" -and $r.reason -like "*start time of the terminal's gui 4242 could not be read*" -and $script:calls.Count -eq 0) "a start re-reads the gui: a start time that cannot be read refuses, naming it, before the terminal is asked"
$r = Start-HordeWeztermPane -Target $T -Program $prog -Cwd "C:\w" -Runner $rec -ProcessStart { param($p) "133000000000099999" }
Check ($r.state -eq "unknown" -and $r.reason -like "*another start time*" -and $script:calls.Count -eq 0) "and a gui with another start time is another terminal: nothing is started"
$r = Send-HordeWeztermText -Target $T -Handle $H -Text ("a" + [char]0x9B + "2J") -Runner $rec -ProcessStart $alive
Check ($r.state -eq "unknown" -and $r.reason -like "*control character*" -and $script:calls.Count -eq 0) "U+009B, a C1 control (a one-character CSI), is refused"
$r = Send-HordeWeztermText -Target $T -Handle $H -Text ("a" + [char]0x85 + "b") -Runner $rec -ProcessStart $alive
Check ($r.state -eq "unknown") "U+0085, a C1 next-line, is refused"
$r = Send-HordeWeztermText -Target $T -Handle $H -Text ("caf" + [char]0xE9) -Runner $rec -ProcessStart $alive
Check ($r.state -eq "known") "CONTROL: a printable character above C1 (U+00E9) is typed"

Write-Host ""
Write-Host "--- this node's own terminal, named explicitly ---" -ForegroundColor Cyan
$sd = Join-Path $env:TEMP ("horde-act-socks-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $sd | Out-Null
try {
    New-Item -ItemType File -Path (Join-Path $sd "gui-sock-4242") | Out-Null
    $own = Resolve-HordeWeztermOwnMux -SockDir $sd -Guis { @(4242) } -ProcessStart $alive
    Check ($own.state -eq "known" -and $own.value.socket -ceq (Join-Path $sd "gui-sock-4242") -and "" + $own.value.guiStart -ceq $guiStart) "one terminal running: it is named, with its gui's start time"
    New-Item -ItemType File -Path (Join-Path $sd "gui-sock-5151") | Out-Null
    $two = Resolve-HordeWeztermOwnMux -SockDir $sd -Guis { @(4242, 5151) } -ProcessStart $alive
    Check ($two.state -eq "unknown" -and $two.reason -like "*2 terminals*") "two running: refused, none is chosen"
    Check ((Resolve-HordeWeztermOwnMux -SockDir $sd -Guis { @() } -ProcessStart $alive).state -eq "unknown") "none running: refused"
} finally { Remove-Item -LiteralPath $sd -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ""
Write-Host "--- the program: an .exe found on PATH, never a script shim ---" -ForegroundColor Cyan
$r = Resolve-HordeWeztermProgram -Name "harness" -Lookup { param($n) @("C:\n\harness.cmd", "C:\b\harness.exe") }
Check ($r.state -eq "known" -and $r.value -ceq "C:\b\harness.exe") "the .exe is chosen over a shim that comes first"
$r = Resolve-HordeWeztermProgram -Name "harness" -Lookup { param($n) @("C:\n\harness.cmd") }
Check ($r.state -eq "unknown" -and $r.reason -like "*script shim*cmd.exe*") "a harness installed only as a .cmd shim is refused, saying why"
Check ((Resolve-HordeWeztermProgram -Name "..\x" -Lookup { param($n) @("C:\x.exe") }).state -eq "unknown") "a name with a path in it is refused"
$real = Resolve-HordeWeztermProgram -Name "powershell"
Check ($real.state -eq "known" -and $real.value -like "*\powershell.exe") "CONTROL: a real .exe on this machine's PATH resolves"

Write-Host ""
Write-Host "--- the port ---" -ForegroundColor Cyan
$a = Get-HordeHostActor -Name "wezterm"
Check ($a.state -eq "known" -and $null -ne $a.value.own) "the file registers itself as the wezterm host's actor, with a way to name this node's own terminal"
Check (@(Get-HordeHostActorFiles -Root $root | Where-Object { $_ -like "*\hosts\wezterm\Act.ps1" }).Count -eq 1) "and is found by folder"
$pp = Join-Path $env:TEMP ("horde-act-profile-" + [guid]::NewGuid().ToString("N"))
try {
    $m = & $a.value.ownMarker $pp 4242
    Check ("" + $m -ceq (Join-Path $pp ".local\share\wezterm\gui-sock-4242")) "the port names the socket file that would make a terminal a profile's own"
    $empty = & $a.value.own $pp @([pscustomobject]@{ pid = 4242; start = "134350994347710308" })
    Check ($empty.state -eq "unknown") "an empty profile has no terminal of its own, even with one running"
    New-Item -ItemType Directory -Path (Split-Path -Parent $m) -Force | Out-Null
    New-Item -ItemType File -Path $m | Out-Null
    $hit = & $a.value.own $pp @([pscustomobject]@{ pid = 4242; start = "134350994347710308" })
    Check ($hit.state -eq "known" -and $hit.value.socket -ceq $m -and "" + $hit.value.guiStart -ceq "134350994347710308") "the port's Own, given a profile and a running terminal, names the socket planted there"
    Check ((& $a.value.own $pp @()).state -eq "unknown") "and none running: none is named, though the socket is there"
} finally { if ((Split-Path -Leaf $pp) -match '^horde-act-profile-[0-9a-f]{32}$') { Remove-Item -LiteralPath $pp -Recurse -Force -ErrorAction SilentlyContinue } }

Remove-HordePaneTool
Complete-HordeSuite -Success "the WezTerm host makes exactly the calls it means, in the terminal it is told, and the program gets exactly what it is given"
