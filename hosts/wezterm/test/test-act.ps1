# DOES THE WEZTERM HOST START, TYPE INTO, CHECK AND END PANES WITH EXACTLY THE CALLS IT MEANS?
#
# The fast half of hosts/wezterm/Act.ps1's tests (the act path's A2). No terminal is touched: every
# terminal call goes to a recording runner, and the command-line quoting is proven against the C
# runtime itself by a real process (test/lib/PaneTool.ps1's standin), which prints back what it got.
# The end-to-end half, in an isolated instance, is hosts/wezterm/test/e2e/e2e-act.ps1.

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
$rec = { param($rest, $envMap) [void]$script:calls.Add(@($rest)); $script:envSeen = $envMap; $script:reply }
$prog = "C:\Program Files\Harness\harness.exe"

Write-Host ""
Write-Host "--- every call carries --no-auto-start ---" -ForegroundColor Cyan
Check ((@(Get-HordeWeztermActArgv -Rest @("list")) -join " ") -ceq "cli --no-auto-start list") "the cli argv always begins cli --no-auto-start"
# The one place a call is made builds its argv there; a second spelling would be a second rule.
$src = [System.IO.File]::ReadAllText((Join-Path $root "hosts\wezterm\Act.ps1"))
Check (([regex]::Matches($src, 'Get-HordeWeztermActArgv -Rest')).Count -eq 1 -and $src.Contains('$psi.Arguments = ConvertTo-HordeWindowsCommandLine -Argv (Get-HordeWeztermActArgv -Rest $Rest)')) "the one process start builds its arguments from that argv"
Check (-not ($src -match '&\s*\$script:HordeWeztermActExe') -and -not ($src -match '(?m)^\s*&\s*wezterm\b')) "nothing calls the terminal by the call operator, which would skip the flag and PowerShell's quoting"

Write-Host ""
Write-Host "--- the command line reaches the program exactly (proven by a real process) ---" -ForegroundColor Cyan
$tool = Get-HordePaneTool
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
Check ((ConvertTo-HordeWindowsArgument -Arg "plain") -ceq "plain" -and (ConvertTo-HordeWindowsArgument -Arg "") -ceq '""') "a plain argument is passed bare, an empty one as two quotes"

Write-Host ""
Write-Host "--- start a pane ---" -ForegroundColor Cyan
$script:calls.Clear()
$r = Start-HordeWeztermPane -Program $prog -Argv @("--id", "x y") -Cwd "C:\work\app" -Runner $rec
Check ($r.state -eq "known" -and $r.value.handle -ceq "17") "the terminal's answer is the pane handle"
Check ((@($script:calls[0]) -join "|") -ceq ("spawn|--new-window|--cwd|C:\work\app|--|" + $prog + "|--id|x y")) "with no window, a new window; the working folder; then -- and the program and its argv, untouched"
$script:calls.Clear()
$r = Start-HordeWeztermPane -Program $prog -Cwd "C:\w" -WindowId "3" -Runner $rec
Check ((@($script:calls[0]) -join "|") -ceq ("spawn|--window-id|3|--cwd|C:\w|--|" + $prog)) "a window id puts it in a tab of that window"
$script:calls.Clear()
Check ((Start-HordeWeztermPane -Program "harness" -Cwd "C:\w" -Runner $rec).state -eq "unknown" -and $script:calls.Count -eq 0) "a program that is not a full path is refused before the terminal is asked"
Check ((Start-HordeWeztermPane -Program "C:\h\harness.cmd" -Cwd "C:\w" -Runner $rec).state -eq "unknown") "a program that is not an .exe is refused: no cmd.exe between Horde and the harness"
Check ((Start-HordeWeztermPane -Program $prog -Cwd "work" -Runner $rec).state -eq "unknown") "a relative working folder is refused"
Check ((Start-HordeWeztermPane -Program $prog -Cwd "C:\w" -WindowId "3; rm" -Runner $rec).state -eq "unknown") "a window id that is not a number is refused"
$script:reply = [pscustomobject]@{ code = 1; out = ""; err = "no mux"; timedOut = $false }
$r = Start-HordeWeztermPane -Program $prog -Cwd "C:\w" -Runner $rec
Check ($r.state -eq "unknown" -and $r.reason -like "*exit 1*no mux*") "a refused spawn is unknown with the terminal's own reason"
$script:reply = [pscustomobject]@{ code = 0; out = "Error: something"; err = ""; timedOut = $false }
$r = Start-HordeWeztermPane -Program $prog -Cwd "C:\w" -Runner $rec
Check ($r.state -eq "unknown" -and $r.reason -like "*not a pane id*") "an answer that is not a pane id leaves whether a pane started unknown"

Write-Host ""
Write-Host "--- the spawn's environment: set what is mapped, remove what is mapped to nothing (issue #95) ---" -ForegroundColor Cyan
$script:reply = [pscustomobject]@{ code = 0; out = "17"; err = ""; timedOut = $false }
$null = Start-HordeWeztermPane -Program $prog -Cwd "C:\w" -Environment @{ HORDE_MAPPED = "m"; HORDE_NODE_ONLY = $null } -Runner $rec
Check ($null -ne $script:envSeen -and $script:envSeen["HORDE_MAPPED"] -ceq "m" -and $script:envSeen.ContainsKey("HORDE_NODE_ONLY")) "the spawn is handed the environment map, removals included"
[Environment]::SetEnvironmentVariable("HORDE_NODE_ONLY", "node-secret", "Process")
try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    Check ($psi.EnvironmentVariables["HORDE_NODE_ONLY"] -ceq "node-secret") "CONTROL: a call's environment starts as the node's own, so a node-only variable would reach the pane"
    Set-HordeWeztermActEnvironment -Psi $psi -Environment @{ HORDE_MAPPED = "m"; HORDE_NODE_ONLY = $null }
    Check (-not $psi.EnvironmentVariables.ContainsKey("HORDE_NODE_ONLY") -and $psi.EnvironmentVariables["HORDE_MAPPED"] -ceq "m") "a variable mapped to nothing is removed from the call, and a mapped one is set"
} finally { [Environment]::SetEnvironmentVariable("HORDE_NODE_ONLY", $null, "Process") }
Check (Throws { Set-HordeWeztermActEnvironment -Psi (New-Object System.Diagnostics.ProcessStartInfo) -Environment @{ "A=B" = "x" } } "not an environment variable name") "a name that is not a variable name is refused"
# Through a real process: the pane tool stands in for the terminal's command, so what a cli call's
# process received is read back - the environment a spawned pane would inherit.
$saveExe = $script:HordeWeztermActExe
$script:HordeWeztermActExe = $tool
[Environment]::SetEnvironmentVariable("HORDE_NODE_ONLY", "node-secret", "Process")
$envWork = Join-Path $env:TEMP ("horde-act-env-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $envWork | Out-Null
try {
    $d1 = Join-Path $envWork "mapped.txt"
    $r = Invoke-HordeWeztermAct -Rest @("env-dump", $d1) -Environment @{ HORDE_MAPPED = "m"; HORDE_NODE_ONLY = $null }
    $seen = Read-HordePaneToolEnv -Path $d1
    Check ($r.code -eq 0 -and $null -ne $seen -and $seen["HORDE_MAPPED"] -ceq "m" -and -not $seen.ContainsKey("HORDE_NODE_ONLY")) "a terminal call's process gets the mapped variable and not the node-only one"
    $d2 = Join-Path $envWork "plain.txt"
    $null = Invoke-HordeWeztermAct -Rest @("env-dump", $d2)
    $seen2 = Read-HordePaneToolEnv -Path $d2
    Check ($null -ne $seen2 -and $seen2["HORDE_NODE_ONLY"] -ceq "node-secret") "CONTROL: without the map, the node's own variable would reach it"
} finally {
    $script:HordeWeztermActExe = $saveExe
    [Environment]::SetEnvironmentVariable("HORDE_NODE_ONLY", $null, "Process")
    Remove-Item -LiteralPath $envWork -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "--- type, check, end ---" -ForegroundColor Cyan
$script:reply = [pscustomobject]@{ code = 0; out = ""; err = ""; timedOut = $false }
$script:calls.Clear()
$r = Send-HordeWeztermText -Handle "17" -Text "/exit" -Runner $rec
Check ($r.state -eq "known" -and (@($script:calls[0]) -join "|") -ceq "send-text|--pane-id|17|--no-paste|/exit") "text is typed as keystrokes (--no-paste) into that pane"
Check ((Send-HordeWeztermText -Handle "17 --pane-id 1" -Text "x" -Runner $rec).state -eq "unknown") "a handle that is not a pane id is refused"
$script:calls.Clear()
$r = Stop-HordeWeztermPane -Handle "17" -Runner $rec
Check ($r.state -eq "known" -and (@($script:calls[0]) -join "|") -ceq "kill-pane|--pane-id|17") "ending a pane is kill-pane on that pane alone"
$script:reply = [pscustomobject]@{ code = 0; out = '[{"window_id":0,"tab_id":0,"pane_id":17,"title":"t","cwd":"file:///C:/w"},{"window_id":0,"tab_id":1,"pane_id":18,"title":"u","cwd":""}]'; err = ""; timedOut = $false }
Check ((Test-HordeWeztermPaneLive -Handle "17" -Runner $rec).value -eq $true) "a listed pane is live"
Check ((Test-HordeWeztermPaneLive -Handle "1" -Runner $rec).value -eq $false) "an unlisted pane is not; 1 is not 17 or 18"
$script:reply = [pscustomobject]@{ code = 0; out = "[]"; err = ""; timedOut = $false }
$l = Test-HordeWeztermPaneLive -Handle "17" -Runner $rec
Check ($l.state -eq "known" -and $l.value -eq $false) "a terminal that answers [] has no panes: the pane is gone"
$script:reply = [pscustomobject]@{ code = 0; out = ""; err = ""; timedOut = $false }
Check ((Test-HordeWeztermPaneLive -Handle "17" -Runner $rec).state -eq "unknown") "an empty answer is unknown, never 'gone'"
$script:reply = [pscustomobject]@{ code = 1; out = ""; err = "x"; timedOut = $false }
Check ((Test-HordeWeztermPaneLive -Handle "17" -Runner $rec).state -eq "unknown") "a terminal that did not list is unknown, never 'gone'"
$script:reply = [pscustomobject]@{ code = 0; out = '[{"window_id":0}]'; err = ""; timedOut = $false }
Check ((Test-HordeWeztermPaneLive -Handle "17" -Runner $rec).state -eq "unknown") "a list whose pane has no id is unknown"

Write-Host ""
Write-Host "--- the program: an .exe found on PATH, never a script shim ---" -ForegroundColor Cyan
$r = Resolve-HordeWeztermProgram -Name "harness" -Lookup { param($n) @("C:\n\harness.cmd", "C:\b\harness.exe") }
Check ($r.state -eq "known" -and $r.value -ceq "C:\b\harness.exe") "the .exe is chosen over a shim that comes first"
$r = Resolve-HordeWeztermProgram -Name "harness" -Lookup { param($n) @("C:\n\harness.cmd") }
Check ($r.state -eq "unknown" -and $r.reason -like "*script shim*cmd.exe*") "a harness installed only as a .cmd shim is refused, saying why"
$r = Resolve-HordeWeztermProgram -Name "harness" -Lookup { param($n) @() }
Check ($r.state -eq "unknown" -and $r.reason -like "*not on this node's PATH*") "a harness not installed is refused"
Check ((Resolve-HordeWeztermProgram -Name "..\x" -Lookup { param($n) @("C:\x.exe") }).state -eq "unknown") "a name with a path in it is refused"
$real = Resolve-HordeWeztermProgram -Name "powershell"
Check ($real.state -eq "known" -and $real.value -like "*\powershell.exe") "CONTROL: a real .exe on this machine's PATH resolves"

Write-Host ""
Write-Host "--- the port ---" -ForegroundColor Cyan
$a = Get-HordeHostActor -Name "wezterm"
Check ($a.state -eq "known") "the file registers itself as the wezterm host's actor"
Check (@(Get-HordeHostActorFiles -Root $root | Where-Object { $_ -like "*\hosts\wezterm\Act.ps1" }).Count -eq 1) "and is found by folder"
Check ((Get-HordeHostActor -Name "nonesuch").state -eq "unknown") "a host with no actor is unknown"

Remove-HordePaneTool
Complete-HordeSuite -Success "the WezTerm host makes exactly the calls it means, and the program gets exactly the arguments it is given"
