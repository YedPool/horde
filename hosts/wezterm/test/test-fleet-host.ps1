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
Check ($s.state -ceq "absent" -and $calls.Count -eq 0 -and $s.reason -like "*not made*") "a request that cannot be built makes no call, and is ABSENT: the one answer that means nothing was started (third review of PR 318)"
Reset-Calls
Reply -1 "" ("boom" + [Environment]::NewLine + ("e" * 900))
$s = Invoke-HordeWeztermFleetSpawn -Target $T -Request ([pscustomobject]@{ mode = "tab"; cwd = "C:\w"; line = $line; window = "9" }) -Program $prog -Runner $runner
Check ($s.state -ceq "unknown" -and $s.reason.Length -le 400 -and $s.reason -cnotmatch '[\x00-\x1F]') ("a spawn's long, multi-line stderr is trimmed to one short line in the reason (" + $s.reason.Length + " characters)")

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

Section "the shell a woken pane runs: the installed one, never the Store's while it is there"
# A Store update of PowerShell 7 closes every running copy of the Store's build, and so every pane that runs
# it (2026-10-16: every pane of the fleet). The founder ruled Horde never relies on the Store.
$store = { New-HordeKnown -Value "C:\Users\me\AppData\Local\Microsoft\WindowsApps\pwsh.exe" }
$msiPath = Join-Path "C:\PF" "PowerShell\7\pwsh.exe"
$sh = Resolve-HordeWeztermFleetShell -ProgramFiles "C:\PF" -Exists { param($p) $p -ceq $msiPath }.GetNewClosure() -OnPath $store
Check ($sh.state -ceq "known" -and $sh.value -ceq $msiPath) ("with the installed PowerShell 7 there, it is the shell, even when the Store's is first on PATH (" + $sh.value + ")")
$sh = Resolve-HordeWeztermFleetShell -ProgramFiles "C:\PF" -Exists { param($p) $false } -OnPath $store
Check ($sh.state -ceq "known" -and $sh.value -like "*\WindowsApps\pwsh.exe") ("CONTROL: without it, the one on PATH is used (" + $sh.value + ")")
$sh = Resolve-HordeWeztermFleetShell -ProgramFiles "" -Exists { param($p) $true } -OnPath $store
Check ($sh.state -ceq "known" -and $sh.value -like "*\WindowsApps\pwsh.exe") "and so when no Program Files folder is known"

Section "the terminal restore's no-restore marker"
# <profile>\.wezurrect\no-restore\<session id>.json tells the terminal's session restore never to bring that
# session back (park and hibernate write it). A wake removes the marker of the one session it is starting.
$nr = Join-Path $env:TEMP ("horde-test-fleet-host-norestore-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $nr -Force)
$sidA = "aaaaaaaa-1111-4111-8111-111111111111"; $sidB = "bbbbbbbb-2222-4222-8222-222222222222"
foreach ($x in @($sidA, $sidB)) { [System.IO.File]::WriteAllText((Join-Path $nr ($x + ".json")), ('{"v":1,"sessionId":"' + $x + '","by":"test","reason":"hibernated","at":"2026-10-16T10:00:00Z"}')) }
Check ((Get-HordeWeztermFleetNoRestoreDir -ProfileDir "C:\Users\me") -ceq "C:\Users\me\.wezurrect\no-restore") "the markers live in the profile's .wezurrect\no-restore"
$a = Remove-HordeWeztermFleetNoRestore -SessionId $sidA -Dir $nr
Check ($a.state -ceq "known" -and $a.value -ceq "removed" -and -not (Test-Path -LiteralPath (Join-Path $nr ($sidA + ".json"))) -and (Test-Path -LiteralPath (Join-Path $nr ($sidB + ".json")))) "the session's own marker is removed, and only that one"
$a = Remove-HordeWeztermFleetNoRestore -SessionId $sidA -Dir $nr
Check ($a.state -ceq "known" -and $a.value -ceq "none") "a missing marker is fine: nothing to remove"
$a = Remove-HordeWeztermFleetNoRestore -SessionId "..\x" -Dir $nr
Check ($a.state -ceq "unknown" -and (Test-Path -LiteralPath (Join-Path $nr ($sidB + ".json")))) "an id that is not a session id removes nothing"
[void](New-Item -ItemType Directory -Path (Join-Path $nr ($sidB + "x.json")) -Force)
$sidC = $sidB.Substring(0, 35) + "c"
[void](New-Item -ItemType Directory -Path (Join-Path (Join-Path $nr ($sidC + ".json")) "inner") -Force)
$a = Remove-HordeWeztermFleetNoRestore -SessionId $sidC -Dir $nr
Check ($a.state -ceq "unknown" -and $a.reason -like "*could not be removed*") ("a marker that cannot be removed is unknown, with the reason (" + $a.reason + ")")
Remove-Item -LiteralPath $nr -Recurse -Force -ErrorAction SilentlyContinue

Section "hibernate writes the marker a wake removes (T-0216)"
# {v:1, sessionId, by:"horde", reason:"hibernated", at}, at <profile>\.wezurrect\no-restore\<uuid>.json, written whole by
# rename so the terminal's restore never reads half of one.
# The markers folder sits one level down in a folder of its own, so an id that climbs out of it lands inside the
# folder this test removes, never in TEMP.
$nwRoot = Join-Path $env:TEMP ("horde-test-fleet-host-mark-" + [guid]::NewGuid().ToString("N"))
$nw = Join-Path $nwRoot "no-restore"
$sidW = "cccccccc-3333-4333-8333-333333333333"
$at = [datetime]::new(2026, 10, 16, 11, 30, 5, [System.DateTimeKind]::Utc)
$w = Write-HordeWeztermFleetNoRestore -SessionId $sidW -Reason "hibernated" -At $at -Dir $nw
$mp = Join-Path $nw ($sidW + ".json")
Check ($w.state -ceq "known" -and "" + $w.value -ceq $mp -and (Test-Path -LiteralPath $mp -PathType Leaf)) ("the marker is written, in a folder it makes, named by the session id (" + $w.state + ")")
$mj = ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($mp))
Check ($mj.v -eq 1 -and $mj.sessionId -ceq $sidW -and $mj.by -ceq "horde" -and $mj.reason -ceq "hibernated" -and $mj.at -ceq "2026-10-16T11:30:05Z") "it holds v 1, the session id, by horde, the reason hibernated and the time"
Check ((@($mj.PSObject.Properties.Name | Sort-Object) -join ",") -ceq "at,by,reason,sessionId,v") "and nothing else"
Check (@(Get-ChildItem -LiteralPath $nw -Force | Where-Object { $_.Name -ne ($sidW + ".json") }).Count -eq 0) "no temporary file is left beside it"
$bytes = [System.IO.File]::ReadAllBytes($mp)
Check (-not ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) "it has no byte-order mark, which the restore plugin's JSON reader would trip on"
$again = Write-HordeWeztermFleetNoRestore -SessionId $sidW -Reason "hibernated" -At $at.AddMinutes(1) -Dir $nw
Check ($again.state -ceq "known" -and (ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($mp))).at -ceq "2026-10-16T11:31:05Z") "a second write replaces the first, whole"
# A time given in local time is written as the same moment in UTC (the Z on the end says so).
$localAt = [datetime]::new(2026, 10, 16, 7, 30, 5, [System.DateTimeKind]::Local)
[void](Write-HordeWeztermFleetNoRestore -SessionId $sidW -Reason "parked" -At $localAt -Dir $nw)
$lj = ConvertFrom-HordeJson ([System.IO.File]::ReadAllText($mp))
Check ($lj.at -ceq $localAt.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [System.Globalization.CultureInfo]::InvariantCulture) -and $lj.reason -ceq "parked") ("a local time is written as UTC (" + $lj.at + ")")
$rm = Remove-HordeWeztermFleetNoRestore -SessionId $sidW -Dir $nw
Check ($rm.state -ceq "known" -and $rm.value -ceq "removed") "THE TWO MATCH: the wake's remover finds and removes exactly the marker the writer made"
$bad = Write-HordeWeztermFleetNoRestore -SessionId "..\x" -Reason "hibernated" -At $at -Dir $nw
Check ($bad.state -ceq "unknown" -and -not (Test-Path -LiteralPath (Join-Path $nwRoot "x.json"))) "an id that is not a session id writes nothing, not even beside the folder"
$bad = Write-HordeWeztermFleetNoRestore -SessionId $sidW -Reason "because" -At $at -Dir $nw
Check ($bad.state -ceq "unknown" -and -not (Test-Path -LiteralPath $mp)) "a reason that is not parked or hibernated writes nothing"
$blocked = Join-Path $env:TEMP ("horde-test-fleet-host-markfile-" + [guid]::NewGuid().ToString("N"))
[System.IO.File]::WriteAllText($blocked, "a file where the folder should be")
$bad = Write-HordeWeztermFleetNoRestore -SessionId $sidW -Reason "hibernated" -At $at -Dir $blocked
Check ($bad.state -ceq "unknown" -and $bad.reason -like "*could not be written*") ("a folder that cannot be made is unknown, with the reason (" + $bad.reason + ")")
Remove-Item -LiteralPath $blocked -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $nwRoot -Recurse -Force -ErrorAction SilentlyContinue
$hh2 = Resolve-HordeFleetAdapter -Kind "host"
Check ($null -ne $hh2.value.PSObject.Properties["mark"] -and $null -ne $hh2.value.mark) "the adapter registers its marker writer with the port"

Section "a stale hibernated marker of a session found running is removed, and only that (T-0216)"
# The watcher, a wake and a hibernate remove the marker of a session they find running, so a hand restart does not
# leave it barred from the next terminal restore. Only that exact file; only when it says hibernated and names the
# session; never a parked marker, which park wrote and which is not theirs to remove.
$ur = Join-Path $env:TEMP ("horde-test-fleet-host-unmark-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $ur -Force)
$sidH = "dddddddd-4444-4444-8444-444444444444"; $sidP = "eeeeeeee-5555-4555-8555-555555555555"; $sidO = "ffffffff-6666-4666-8666-666666666666"
$sidN = "99999999-7777-4777-8777-777777777777"; $sidJ = "88888888-8888-4888-8888-888888888888"
$mk = { param($sid, $inner, $reason) '{"v":1,"sessionId":"' + $inner + '","by":"horde","reason":"' + $reason + '","at":"2026-10-16T10:00:00Z"}' }
[System.IO.File]::WriteAllText((Join-Path $ur ($sidH + ".json")), (& $mk $sidH $sidH "hibernated"))
[System.IO.File]::WriteAllText((Join-Path $ur ($sidP + ".json")), (& $mk $sidP $sidP "parked"))
[System.IO.File]::WriteAllText((Join-Path $ur ($sidO + ".json")), (& $mk $sidO $sidH "hibernated"))
[System.IO.File]::WriteAllText((Join-Path $ur ($sidJ + ".json")), "{ not json")
$a = Remove-HordeWeztermFleetNoRestoreIf -SessionId $sidH -Reason "hibernated" -Dir $ur
Check ($a.state -ceq "known" -and $a.value -ceq "removed" -and -not (Test-Path -LiteralPath (Join-Path $ur ($sidH + ".json")))) ("a hibernated marker naming the session is removed (" + $a.state + " " + $a.value + ")")
Check ((Test-Path -LiteralPath (Join-Path $ur ($sidP + ".json"))) -and (Test-Path -LiteralPath (Join-Path $ur ($sidO + ".json")))) "no other marker is touched"
$a = Remove-HordeWeztermFleetNoRestoreIf -SessionId $sidP -Reason "hibernated" -Dir $ur
Check ($a.state -ceq "known" -and $a.value -ceq "kept" -and (Test-Path -LiteralPath (Join-Path $ur ($sidP + ".json")))) "a PARKED marker, which someone else wrote, is kept"
$a = Remove-HordeWeztermFleetNoRestoreIf -SessionId $sidO -Reason "hibernated" -Dir $ur
Check ($a.state -ceq "known" -and $a.value -ceq "kept" -and (Test-Path -LiteralPath (Join-Path $ur ($sidO + ".json")))) "a marker whose file names another session is kept, though its name is this session's"
$a = Remove-HordeWeztermFleetNoRestoreIf -SessionId $sidJ -Reason "hibernated" -Dir $ur
Check ($a.state -ceq "known" -and $a.value -ceq "kept" -and (Test-Path -LiteralPath (Join-Path $ur ($sidJ + ".json")))) "a marker that cannot be read is kept: nothing is removed on a guess"
$a = Remove-HordeWeztermFleetNoRestoreIf -SessionId $sidN -Reason "hibernated" -Dir $ur
Check ($a.state -ceq "known" -and $a.value -ceq "none") "no marker is fine: nothing to remove"
$a = Remove-HordeWeztermFleetNoRestoreIf -SessionId "..\x" -Reason "hibernated" -Dir $ur
Check ($a.state -ceq "unknown") "an id that is not a session id removes nothing"
$a = Remove-HordeWeztermFleetNoRestoreIf -SessionId $sidP -Reason "because" -Dir $ur
Check ($a.state -ceq "unknown" -and (Test-Path -LiteralPath (Join-Path $ur ($sidP + ".json")))) "a reason that is not parked or hibernated removes nothing"
Remove-Item -LiteralPath $ur -Recurse -Force -ErrorAction SilentlyContinue
$hu = Resolve-HordeFleetAdapter -Kind "host"
Check ($null -ne $hu.value.PSObject.Properties["unmark"] -and $null -ne $hu.value.unmark) "the adapter registers its conditional remover with the port"

Section "the live panes of every terminal, for the fleet.db sessions step (the port's Panes)"
$pd = Join-Path $env:TEMP ("horde-fleet-host-panes-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $pd | Out-Null
try {
    foreach ($n in @("gui-sock-4242", "gui-sock-5151", "gui-sock-6161", "gui-sock-7171", "gui-sock-abc", "notes.txt")) { [System.IO.File]::WriteAllText((Join-Path $pd $n), "x") }
    $aliveMany = { param($p) if (@(4242, 6161, 7171) -contains $p) { $guiStart } else { $null } }.GetNewClosure()
    $pcalls = New-Object System.Collections.ArrayList
    $panesRunner = { param($rest, $envMap, $target)
        [void]$pcalls.Add([pscustomobject]@{ rest = @($rest); target = $target })
        if ($target.socket -like "*6161") { return [pscustomobject]@{ code = -1; out = ""; err = "the terminal did not answer within 8000 ms"; timedOut = $true } }
        if ($target.socket -like "*7171") { return [pscustomobject]@{ code = 0; out = "[]"; err = ""; timedOut = $false } }
        return [pscustomobject]@{ code = 0; out = $listed; err = ""; timedOut = $false } }.GetNewClosure()
    $pa = Get-HordeWeztermFleetPanes -SockDir $pd -Runner $panesRunner -ProcessStart $aliveMany
    Check ($pa.state -ceq "known" -and @($pa.value).Count -eq 4) ("one entry per socket file named for a gui, and no other file (" + $pa.reason + ")")
    $byName = @{}; foreach ($e in @($pa.value)) { $byName[$e.instance] = $e }
    Check ($byName["gui-sock-4242"].state -ceq "listed" -and (@($byName["gui-sock-4242"].panes) -join ",") -ceq "17,18,19,20") "a terminal that answers is listed with its pane numbers"
    Check ($byName["gui-sock-5151"].state -ceq "closed" -and $byName["gui-sock-5151"].reason -like "*not running*") "a socket file whose gui is gone is closed, not asked"
    Check ($byName["gui-sock-6161"].state -ceq "unknown" -and $byName["gui-sock-6161"].reason -like "*did not list its panes*") "a terminal that does not answer in its limit is UNKNOWN, never closed"
    Check ($byName["gui-sock-7171"].state -ceq "listed" -and @($byName["gui-sock-7171"].panes).Count -eq 0) "a terminal that says it has no panes (an empty list) is listed with none"
    Check ($pcalls.Count -eq 3 -and (@($pcalls | ForEach-Object { ($_.rest -join " ") }) | Select-Object -Unique) -ceq "list --format json") "three terminals running: three calls, each exactly cli list --format json"
    Check (@($pcalls | Where-Object { "" + $_.target.socket -notlike (Join-Path $pd "gui-sock-*") }).Count -eq 0) "and each call named its own terminal's socket, never the environment's"
    $pcalls.Clear()
    $pb = Get-HordeWeztermFleetPanes -SockDir $pd -Runner $panesRunner -ProcessStart $aliveMany -BudgetMs -1
    $bn = @{}; foreach ($e in @($pb.value)) { $bn[$e.instance] = $e }
    Check ($pcalls.Count -eq 0 -and $bn["gui-sock-4242"].state -ceq "unknown" -and $bn["gui-sock-4242"].reason -like "*budget*" -and $bn["gui-sock-5151"].state -ceq "closed") "a pass whose budget ran out marks the rest unknown, asks nothing more, and still knows a closed gui"
    $pe = Get-HordeWeztermFleetPanes -SockDir (Join-Path $pd "nothing-here") -Runner $panesRunner -ProcessStart $aliveMany
    Check ($pe.state -ceq "unknown" -and $pe.reason -like "*no terminal socket folder*") "no socket folder is unknown as a whole, not an empty list"
    $junk = { param($rest, $envMap, $target) return [pscustomobject]@{ code = 0; out = "not json"; err = ""; timedOut = $false } }
    $pj = Get-HordeWeztermFleetPanes -SockDir $pd -Runner $junk -ProcessStart $aliveMany
    Check (@($pj.value | Where-Object { $_.instance -ceq "gui-sock-4242" -and $_.state -ceq "unknown" }).Count -eq 1) "output that is not a list is unknown"
} finally {
    if ((Split-Path -Leaf $pd) -match '\Ahorde-fleet-host-panes-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $pd)) { Remove-Item -LiteralPath $pd -Recurse -Force -ErrorAction SilentlyContinue }
}
$hp = Resolve-HordeFleetAdapter -Kind "host"
Check ($null -ne $hp.value.PSObject.Properties["panes"] -and $null -ne $hp.value.panes) "the adapter registers its pane list with the port"

Section "the adapter registers itself"
$h = Resolve-HordeFleetAdapter -Kind "host"
Check ($h.state -ceq "known" -and $h.value.name -ceq "wezterm") "loading the file registers the fleet host adapter"

Complete-HordeSuite -Success "the terminal's half of hibernation asks only the terminal named, reads placement whole or not at all, and builds exactly the spawn asked for"
