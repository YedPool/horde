# DOES THE TERMINAL'S HALF OF HIBERNATION ASK THE RIGHT TERMINAL, READ WHERE EACH PANE SAT, AND BUILD
# EXACTLY THE SPAWN EACH WOKEN SESSION NEEDS?
#
# hosts/wezterm/Fleet.ps1. Every call goes through Act.ps1's one call site with -Runner standing in for
# the process, so this suite sees the exact argv, environment and named terminal a real call would use -
# the shape the stand-in terminals of test/test-fleet-wake.ps1 must match. No terminal is reached: the
# socket variable is pointed at a folder that does not exist before anything is loaded, and every
# target here names a gui this suite says is running (-ProcessStart).

$env:WEZTERM_UNIX_SOCKET = Join-Path $env:TEMP ("horde-test-fleet-host-no-terminal-" + [guid]::NewGuid().ToString("N"))
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "hosts\wezterm\Fleet.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$guiStart = "133000000000000000"
$alive = { param($p) if ($p -eq 4242) { $guiStart } else { $null } }.GetNewClosure()
$sockDir = "C:\fake\sockets"
$T = [pscustomobject]@{ socket = (Join-Path $sockDir "gui-sock-4242"); guiPid = 4242; guiStart = $guiStart }
# Two windows: window 3 holds tab 10 (panes 17 and 18, side by side) and tab 11 (pane 19); window 4
# holds tab 12 (pane 20). The fields are those of a real `cli list --format json` (2026-10-16).
function Pane { param($w, $t, $p, $l, $top, $c, $r) return ('{"window_id":' + $w + ',"tab_id":' + $t + ',"pane_id":' + $p + ',"workspace":"default","size":{"rows":' + $r + ',"cols":' + $c + ',"pixel_width":1,"pixel_height":1,"dpi":96},"title":"t","cwd":"file:///C:/w/","left_col":' + $l + ',"top_row":' + $top + ',"is_active":true,"is_zoomed":false,"tty_name":null}') }
$listed = "[" + ((Pane 3 10 17 0 0 100 50), (Pane 3 10 18 101 0 59 50), (Pane 3 11 19 0 0 160 50), (Pane 4 12 20 0 0 80 24) -join ",") + "]"
$calls = New-Object System.Collections.ArrayList
$replies = New-Object System.Collections.ArrayList
$runner = { param($rest, $envMap, $target)
    [void]$calls.Add([pscustomobject]@{ rest = @($rest); env = $envMap; target = $target })
    if ($replies.Count -gt 0) { $x = $replies[0]; $replies.RemoveAt(0); return $x }
    return [pscustomobject]@{ code = 0; out = $listed; err = ""; timedOut = $false } }.GetNewClosure()
function Reply { param([int]$Code, [string]$Out, [string]$Err = "") [void]$replies.Add([pscustomobject]@{ code = $Code; out = $Out; err = $Err; timedOut = $false }) }
function Reset-Calls { $calls.Clear(); $replies.Clear() }
function Ref { param([string]$Id, [string]$Inst, [string]$Pane) return [pscustomobject]@{ sessionId = $Id; instance = $Inst; pane = $Pane } }

Section "placement: the terminal the registry names, and where each pane sits in it"
Reset-Calls
$a = Get-HordeWeztermFleetPlacement -Refs @((Ref "s17" "gui-sock-4242" "17"), (Ref "s18" "gui-sock-4242" "18"), (Ref "s19" "gui-sock-4242" "19"), (Ref "s20" "gui-sock-4242" "20")) -SockDir $sockDir -Runner $runner -ProcessStart $alive
Check ($a.state -ceq "known" -and $a.value.placed.Count -eq 4) ("every pane in the list is placed (" + $a.reason + ")")
Check ($calls.Count -eq 1 -and ((@($calls[0].rest) -join " ") -ceq "list --format json") -and $calls[0].target.socket -ceq $T.socket -and "" + $calls[0].target.guiStart -ceq $guiStart) "one list call per terminal, against the socket the registry names, with its gui's start time"
$p17 = $a.value.placed["s17"]; $p18 = $a.value.placed["s18"]; $p19 = $a.value.placed["s19"]; $p20 = $a.value.placed["s20"]
Check ($p17.windowKey -ceq "gui-sock-4242:3" -and $p17.tabIndex -eq 0 -and $p17.left -eq 0 -and $p17.cols -eq 100 -and $p17.tabCols -eq 160 -and $p17.tabRows -eq 50) "a pane's window, tab place, geometry and its tab's size are read"
Check ($p18.tabIndex -eq 0 -and $p18.left -eq 101 -and $p18.cols -eq 59) "its neighbour in the same tab keeps its own column"
Check ($p19.tabIndex -eq 1 -and $p19.windowKey -ceq "gui-sock-4242:3") "the window's second tab is index 1"
Check ($p20.windowKey -ceq "gui-sock-4242:4" -and $p20.tabIndex -eq 0) "another window's first tab is index 0 of that window"
Reset-Calls
$a = Get-HordeWeztermFleetPlacement -Refs @((Ref "gone" "gui-sock-5151" "17"), (Ref "bad" "C:\evil" "17"), (Ref "nopane" "gui-sock-4242" "77"), (Ref "nonum" "gui-sock-4242" "x")) -SockDir $sockDir -Runner $runner -ProcessStart $alive
Check ($a.state -ceq "known" -and $a.value.placed.Count -eq 0 -and @($a.value.notes).Count -eq 4) ("a terminal not running, a name that is not a socket's, a pane not listed and a pane that is not a number are each left out with a note (" + (@($a.value.notes) -join " | ") + ")")
Check ($calls.Count -eq 1 -and $calls[0].target.socket -ceq $T.socket) "only the running terminal was asked; the bad name never reached a call"
Reset-Calls
Reply 1 "" "no answer"
$a = Get-HordeWeztermFleetPlacement -Refs @((Ref "s17" "gui-sock-4242" "17")) -SockDir $sockDir -Runner $runner -ProcessStart $alive
Check ($a.state -ceq "known" -and $a.value.placed.Count -eq 0 -and @($a.value.notes | Where-Object { $_ -like "*did not list its panes*" }).Count -eq 1) "a terminal that fails its list places nothing and says so"
Reset-Calls
Reply 0 '[{"window_id":3,"tab_id":10,"pane_id":17}]'
$a = Get-HordeWeztermFleetPlacement -Refs @((Ref "s17" "gui-sock-4242" "17")) -SockDir $sockDir -Runner $runner -ProcessStart $alive
Check ($a.value.placed.Count -eq 0 -and @($a.value.notes | Where-Object { $_ -like "*no left_col*" }).Count -eq 1) "a list without geometry places nothing, never a guess"

Section "the spawn each request makes"
$prog = "C:\shells\pwsh.exe"
$line = "resume-line aaaaaaaa-1111-4111-8111-111111111111"
$rest = @(Get-HordeWeztermFleetSpawnRest -Request ([pscustomobject]@{ mode = "window"; cwd = "C:\lanes\k"; line = $line }) -Program $prog)
Check (($rest -join "|") -ceq ("spawn|--new-window|--cwd|C:\lanes\k|--|" + $prog + "|-NoLogo|-NoProfile|-NoExit|-Command|" + $line)) ("an orc: a new window, its folder, then the shell - without the person's profile - with the resume line as one argument (" + ($rest -join " ") + ")")
$rest = @(Get-HordeWeztermFleetSpawnRest -Request ([pscustomobject]@{ mode = "tab"; cwd = "C:\w"; line = $line; window = "9" }) -Program $prog)
Check (($rest[0..2] -join " ") -ceq "spawn --window-id 9") "a warg in another tab: a tab of the orc's window"
$rest = @(Get-HordeWeztermFleetSpawnRest -Request ([pscustomobject]@{ mode = "split"; cwd = "C:\w"; line = $line; pane = "41"; direction = "right"; percent = "38" }) -Program $prog)
Check (($rest[0..5] -join " ") -ceq "split-pane --pane-id 41 --right --percent 38") "a warg that shared the tab: a split of the pane it sat beside, on that side, in its share"
$rest = @(Get-HordeWeztermFleetSpawnRest -Request ([pscustomobject]@{ mode = "split"; cwd = "C:\w"; line = $line; pane = "41"; direction = "bottom"; percent = "" }) -Program $prog)
Check (($rest[0..5] -join " ") -ceq "split-pane --pane-id 41 --bottom --cwd C:\w") "a split with no share says no --percent"
foreach ($bad in @(
        @{ why = "a relative folder"; req = @{ mode = "window"; cwd = "lanes\k"; line = $line } },
        @{ why = "a line break in the line"; req = @{ mode = "window"; cwd = "C:\w"; line = ($line + "`r`ncalc") } },
        @{ why = "an empty line"; req = @{ mode = "window"; cwd = "C:\w"; line = "" } },
        @{ why = "a window that is not an id"; req = @{ mode = "tab"; cwd = "C:\w"; line = $line; window = "K" } },
        @{ why = "a pane that is not an id"; req = @{ mode = "split"; cwd = "C:\w"; line = $line; pane = "1;2"; direction = "right" } },
        @{ why = "a side that is not right or bottom"; req = @{ mode = "split"; cwd = "C:\w"; line = $line; pane = "4"; direction = "left" } },
        @{ why = "a mode that is not one"; req = @{ mode = "Window"; cwd = "C:\w"; line = $line } })) {
    Check (Throws { Get-HordeWeztermFleetSpawnRest -Request ([pscustomobject]$bad.req) -Program $prog }) ("no spawn is built for " + $bad.why)
}

Section "a spawn, through the one call site"
Reset-Calls
Reply 0 "41`n"
Reply 0 ("[" + (Pane 9 30 41 0 0 80 24) + "]")
$envMap = @{ HARNESS_SESSION = $null }
$s = Invoke-HordeWeztermFleetSpawn -Target $T -Request ([pscustomobject]@{ mode = "window"; cwd = "C:\lanes\k"; line = $line; environment = $envMap }) -Program $prog -Runner $runner
Check ($s.state -ceq "known" -and $s.value.pane -ceq "41" -and $s.value.window -ceq "9") ("a new window's pane id is the spawn's answer, its window read back from the list (" + $s.reason + ")")
Check ($calls.Count -eq 2 -and $calls[0].rest[0] -ceq "spawn" -and $calls[0].env.ContainsKey("HARNESS_SESSION") -and $null -eq $calls[0].env["HARNESS_SESSION"] -and $calls[0].target.socket -ceq $T.socket) "the spawn carries the harness's scrub to the pane, against the named terminal"
Reset-Calls
Reply 0 "42`n"
$s = Invoke-HordeWeztermFleetSpawn -Target $T -Request ([pscustomobject]@{ mode = "tab"; cwd = "C:\w"; line = $line; window = "9" }) -Program $prog -Runner $runner
Check ($s.state -ceq "known" -and $s.value.window -ceq "9" -and $calls.Count -eq 1) "a tab keeps the window it was given, with no second call"
Reset-Calls
Reply 0 "Error: no such window`n"
$s = Invoke-HordeWeztermFleetSpawn -Target $T -Request ([pscustomobject]@{ mode = "tab"; cwd = "C:\w"; line = $line; window = "9" }) -Program $prog -Runner $runner
Check ($s.state -ceq "unknown" -and $s.reason -like "*not a pane id*") "an answer that is not a pane id is unknown, never a pane"
Reset-Calls
Reply 2 "" "refused"
$s = Invoke-HordeWeztermFleetSpawn -Target $T -Request ([pscustomobject]@{ mode = "tab"; cwd = "C:\w"; line = $line; window = "9" }) -Program $prog -Runner $runner
Check ($s.state -ceq "unknown" -and $s.reason -like "*exit 2*") "a failed call is unknown, with its exit"
Reset-Calls
Reply 0 "43`n"
Reply 0 "[]"
$s = Invoke-HordeWeztermFleetSpawn -Target $T -Request ([pscustomobject]@{ mode = "window"; cwd = "C:\w"; line = $line }) -Program $prog -Runner $runner
Check ($s.state -ceq "known" -and $s.value.pane -ceq "43" -and "" + $s.value.window -ceq "" -and $s.value.note -like "*which window*") ("a new pane whose window cannot be read back is a pane that STARTED, with no window and the reason: it runs, and the wake must stop its group rather than call it not started (" + $s.reason + ")")
Reset-Calls
$s = Invoke-HordeWeztermFleetSpawn -Target $T -Request ([pscustomobject]@{ mode = "window"; cwd = "rel"; line = $line }) -Program $prog -Runner $runner
Check ($s.state -ceq "unknown" -and $calls.Count -eq 0) "a request that cannot be built makes no call"

Section "the dry run's words are the real command"
$d = Format-HordeWeztermFleetSpawn -Request ([pscustomobject]@{ mode = "window"; cwd = "C:\lanes\k"; line = $line }) -Program $prog
Check ($d -ceq ("wezterm cli --no-auto-start spawn --new-window --cwd C:\lanes\k -- " + $prog + " -NoLogo -NoProfile -NoExit -Command `"" + $line + "`"")) ("a window's command, quoted as Windows reads it back (" + $d + ")")
$d = Format-HordeWeztermFleetSpawn -Request ([pscustomobject]@{ mode = "tab"; cwd = "C:\w"; line = $line; window = "K (aaaaaaaa)" }) -Program $prog
Check ($d -like "*spawn --window-id <window of K (aaaaaaaa)> --cwd C:\w*") ("a window not made yet is named by its orc (" + $d + ")")
$d = Format-HordeWeztermFleetSpawn -Request ([pscustomobject]@{ mode = "split"; cwd = "C:\w"; line = $line; pane = "K (aaaaaaaa)"; direction = "right"; percent = "38" }) -Program $prog
Check ($d -like "*split-pane --pane-id <pane of K (aaaaaaaa)> --right --percent 38 --cwd C:\w*") ("a pane not made yet is named by its session (" + $d + ")")

Section "which terminal: this user's own, or the one a setting names"
# The wake spawns into "this node's own terminal", which is refused when two run - as they do whenever a
# test terminal stands beside the person's own. A setting in <HORDE_HOME>\settings\wezterm-fleet.json can
# name the terminal by its socket instead; the record then reads placement from that socket's folder.
$homeDir = Join-Path $env:TEMP ("horde-test-fleet-host-home-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path (Join-Path $homeDir "settings") -Force)
$setFile = Join-Path $homeDir "settings\wezterm-fleet.json"
function Set-FleetSetting { param([string]$Text) [System.IO.File]::WriteAllText($setFile, $Text) }
$two = { @([long]4242, [long]5151) }
$sockets = { param($p) $true }
Remove-Item -LiteralPath $setFile -Force -ErrorAction SilentlyContinue
$st = Get-HordeWeztermFleetSettings -HordeHome $homeDir
Check ($st.state -ceq "defaults" -and "" + $st.values.socket -ceq "") "with no file, no terminal is named"
$term = Resolve-HordeWeztermFleetTerminal -Settings $st -Guis $two -ProcessStart $alive -SockDir (Join-Path $homeDir "no-sockets")
Check ($term.state -ceq "unknown") ("CONTROL: and this user's own terminal is looked for, as before (" + $term.reason + ")")
Check ((Get-HordeWeztermFleetSockDir -Settings $st) -ceq (Get-HordeWeztermSockDir)) "and placement reads the terminal's own socket folder"
Set-FleetSetting ('{"schemaVersion":1,"settings":{"socket":' + (ConvertTo-Json -InputObject ("" + $T.socket)) + '}}')
$st = Get-HordeWeztermFleetSettings -HordeHome $homeDir
$term = Resolve-HordeWeztermFleetTerminal -Settings $st -Guis $two -ProcessStart $alive
Check ($st.state -ceq "read" -and $term.state -ceq "known" -and $term.value.socket -ceq $T.socket -and "" + $term.value.guiPid -ceq "4242" -and "" + $term.value.guiStart -ceq $guiStart) ("a named socket is the terminal, with its gui's start time, even with two running (" + $term.reason + ")")
Check ((Get-HordeWeztermFleetSockDir -Settings $st) -ceq $sockDir) "and placement reads that socket's folder"
Set-FleetSetting ('{"schemaVersion":1,"settings":{"socket":"C:\\fake\\sockets\\gui-sock-5151"}}')
$term = Resolve-HordeWeztermFleetTerminal -Settings (Get-HordeWeztermFleetSettings -HordeHome $homeDir) -Guis $two -ProcessStart $alive
Check ($term.state -ceq "unknown" -and $term.reason -like "*5151*not running*") ("a named terminal whose gui is not running is unknown, and no other is chosen (" + $term.reason + ")")
Set-FleetSetting ('{"schemaVersion":1,"settings":{"socket":"C:\\fake\\sockets\\my-socket"}}')
$term = Resolve-HordeWeztermFleetTerminal -Settings (Get-HordeWeztermFleetSettings -HordeHome $homeDir) -Guis $two -ProcessStart $alive
Check ($term.state -ceq "unknown" -and $term.reason -like "*not named after a gui*") ("a name that is not a terminal's socket is unknown (" + $term.reason + ")")
Set-FleetSetting ('{"schemaVersion":1,"settings":{"sockett":"x"}}')
$st = Get-HordeWeztermFleetSettings -HordeHome $homeDir
$term = Resolve-HordeWeztermFleetTerminal -Settings $st -Guis $two -ProcessStart $alive
Check ($st.state -cne "read" -and $st.state -cne "defaults" -and $term.state -ceq "unknown" -and $term.reason -like "*settings*") ("a settings file that is refused names no terminal and asks none: unknown, with its findings (" + $term.reason + ")")
Remove-Item -LiteralPath $homeDir -Recurse -Force -ErrorAction SilentlyContinue

Section "the adapter registers itself"
$h = Resolve-HordeFleetAdapter -Kind "host"
Check ($h.state -ceq "known" -and $h.value.name -ceq "wezterm") "loading the file registers the fleet host adapter"

Complete-HordeSuite -Success "the terminal's half of hibernation asks only the terminal named, reads placement whole or not at all, and builds exactly the spawn asked for"
