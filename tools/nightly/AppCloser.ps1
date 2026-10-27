# tools/nightly/AppCloser.ps1 - the nightly net's app closer: at the start of the night, close the desktop apps the
# founder named, so the night's memory goes to the agent sessions and the tests. T-0331.
#
# THE FOUNDER'S ORDER (2026-10-26, relayed by M). The night of 2026-10-25 ran 0 of 462 units: free memory stayed
# under the floor all night, and the report named the holders - the browser 66 processes 8.5 GB, the agent sessions
# 6.7 GB, ClickUp 7 processes 2.0 GB. So, once a night, before the first unit:
#   - ONLY THE NAMED APPS (Get-HordeNightlyCloseAppNames): Chrome, Slack, WhatsApp, ClickUp, Teams and Zoom, matched
#     on the EXACT process name (no wildcard), and only those running. This is the one exception to the fleet's
#     rule never to close a process by its name; nothing else is ever closed.
#   - ONLY WHEN THE PC IS IDLE: 10 minutes without keyboard or mouse input (core/IdleState.ps1 Read-HordeIdleSeconds,
#     GetLastInputInfo; idleSeconds of <HORDE_HOME>\settings\idle.json). If he is at it, or the input clock cannot be
#     read, nothing is closed and the closer tries again every 15 minutes until the cutoff.
#   - ONLY IN THE NIGHT WINDOW (22:00 to 06:30), by the real clock.
#   - GRACEFUL FIRST: WM_CLOSE to every VISIBLE top-level window of those processes, found with EnumWindows by
#     process id (the browser has one process with many windows, so its main window alone is not enough), then up
#     to 60 s for them to end. The window's own program closes it, as a click on its close button would.
#   - FULLY QUIT, AT NIGHT, ONLY Slack, WhatsApp and ClickUp (Get-HordeNightlyForceQuitAppNames; founder's YES of
#     2026-10-26: "the night closeup should fully quit clickup slack and whatsapp"). Those hide to the tray on
#     WM_CLOSE, so a process of theirs still alive after the wait is ended by its process id (checked to be the
#     same process: same id AND same start time). Chrome, Teams and Zoom are NEVER forced: one still running is
#     left alone and reported with its memory.
#   - Every process closed, forced or still running is logged with name, id and working set; the report gets a
#     CLOSED line. Nothing is reopened in the morning.
#   - Read only: whether Chrome reopens the last session on startup (Get-HordeNightlyChromeRestore): the machine
#     policy RestoreOnStartup first (HKLM, then HKCU), which decides for every profile; only without one each
#     profile's session.restore_on_startup == 1. It is reported, never changed.
#
# EVERYTHING THAT ACTS TAKES ITS PROCESSES AS INPUT (Close-HordeNightlyApps -Targets): the name match is a separate,
# pure step (Select-HordeNightlyAppProcesses), so test/test-nightly-apps.ps1 closes only stand-in processes it
# started itself and never looks the real apps up. Windows PowerShell 5.1 and PowerShell 7. ASCII only.
# No Set-StrictMode here: this file is dot-sourced.

function Get-HordeNightlyCloseAppNames {
    # The exact process names closed at night, as this box runs them (read with Get-Process on 2026-10-26: chrome,
    # Slack, WhatsApp.Root, ClickUp). WhatsApp is the desktop build's name, WhatsApp.Root the Store build's; ms-teams
    # is the new Teams, Teams the classic one. Windows process names are not case sensitive.
    return @("chrome", "Slack", "WhatsApp", "WhatsApp.Root", "ClickUp", "ms-teams", "Teams", "Zoom")
}

function Get-HordeNightlyForceQuitAppNames {
    # The only names a process of which is ended by force after the graceful wait (header). Every one is also in
    # Get-HordeNightlyCloseAppNames.
    return @("Slack", "WhatsApp", "WhatsApp.Root", "ClickUp")
}

function Test-HordeNightlyAppName {
    # Is this process name exactly one of -Names (case-insensitive, whole name, no wildcard)? Returns the listed name
    # or "".
    param([string]$Name, [string[]]$Names)
    foreach ($n in @($Names)) { if ([string]::Equals(("" + $Name), ("" + $n), [System.StringComparison]::OrdinalIgnoreCase)) { return ("" + $n) } }
    return ""
}

function Select-HordeNightlyAppProcesses {
    # The processes of the named apps: -Processes are objects with ProcessName, Id, WorkingSet64 and StartTime (what
    # Get-Process returns); the result is [{ name; pid; gb; started }] for each whose name is exactly one of -Names,
    # name being the listed spelling. A start time that cannot be read is $null.
    param([object[]]$Processes, [string[]]$Names)
    $out = @()
    foreach ($p in @($Processes)) {
        if ($null -eq $p) { continue }
        $n = Test-HordeNightlyAppName -Name ("" + $p.ProcessName) -Names $Names
        if ($n -eq "") { continue }
        $started = $null
        try { $started = [datetime]$p.StartTime } catch { $started = $null }
        $out += [pscustomobject]@{ name = $n; pid = [int]$p.Id; gb = ([double]$p.WorkingSet64 / 1GB); started = $started }
    }
    return $out
}

function Get-HordeNightlyAppSource { return @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class HordeNightlyAppWindowsV1 {
    delegate bool EnumProc(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr data);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", SetLastError = true)] static extern bool PostMessage(IntPtr window, uint message, IntPtr w, IntPtr l);
    // Every visible top-level window of the given processes, as "handle:pid".
    public static string[] VisibleWindows(int[] pids) {
        var want = new HashSet<uint>();
        foreach (int p in pids) { want.Add((uint)p); }
        var found = new List<string>();
        EnumWindows(delegate (IntPtr w, IntPtr d) {
            uint owner;
            GetWindowThreadProcessId(w, out owner);
            if (want.Contains(owner) && IsWindowVisible(w)) { found.Add(w.ToInt64().ToString() + ":" + owner.ToString()); }
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }
    // 0: WM_CLOSE (0x0010) was posted. 1: not a window any more. 2: a window of another process. Negative: the
    // post failed, the Win32 error negated.
    public static int AskToClose(long handle, int processId) {
        var window = new IntPtr(handle);
        if (!IsWindow(window)) { return 1; }
        uint owner;
        GetWindowThreadProcessId(window, out owner);
        if (owner != (uint)processId) { return 2; }
        if (!PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero)) { int e = Marshal.GetLastWin32Error(); return e == 0 ? -1 : -e; }
        return 0;
    }
}
"@ }

function Initialize-HordeNightlyAppType {
    if (-not ("HordeNightlyAppWindowsV1" -as [type])) { Add-Type -TypeDefinition (Get-HordeNightlyAppSource) }
}

function Get-HordeNightlyAppWindows {
    # The visible top-level windows of -Pids: [{ handle; pid }].
    param([int[]]$Pids)
    if (@($Pids).Count -eq 0) { return @() }
    Initialize-HordeNightlyAppType
    return @([HordeNightlyAppWindowsV1]::VisibleWindows([int[]]@($Pids)) | ForEach-Object { $a, $b = ("" + $_) -split ':', 2; [pscustomobject]@{ handle = [long]$a; pid = [int]$b } })
}

function Test-HordeNightlyAppAlive {
    # Is this target's process still the one it was? The same id with another start time is a new process that got
    # the id again: the target is gone.
    param($Target)
    $p = Get-Process -Id $Target.pid -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $false }
    if ($null -ne $Target.started) {
        try { if ([math]::Abs(([datetime]$p.StartTime - [datetime]$Target.started).TotalSeconds) -gt 1) { return $false } } catch { }
    }
    return $true
}

function Close-HordeNightlyApps {
    # Close -Targets (from Select-HordeNightlyAppProcesses) as the header says. Returns
    #   { asked; windows; closed = [target]; forced = [target]; running = [target]; failed = [string]; dryRun }
    # -DryRun touches nothing: closed and forced are empty, running is every target, and wouldForce lists the
    # targets that would be ended by force if still running after the wait. -WaitSeconds is the graceful wait;
    # -Sleep (milliseconds) is injectable. -ForceNames: the names that may be ended by force (Get-HordeNightlyForceQuitAppNames).
    param([object[]]$Targets, [string[]]$ForceNames = @(), [int]$WaitSeconds = 60, [switch]$DryRun, [scriptblock]$Sleep = { param($ms) Start-Sleep -Milliseconds $ms })
    # Only targets that are still the process they were: an id given out again is never asked or ended.
    $t = @($Targets | Where-Object { $null -ne $_ -and (Test-HordeNightlyAppAlive $_) })
    $wouldForce = @($t | Where-Object { (Test-HordeNightlyAppName -Name $_.name -Names $ForceNames) -ne "" })
    $res = [pscustomobject]@{ asked = 0; windows = 0; closed = @(); forced = @(); running = @(); failed = @(); dryRun = [bool]$DryRun; wouldForce = $wouldForce }
    if ($t.Count -eq 0) { return $res }
    $wins = @()
    try { $wins = @(Get-HordeNightlyAppWindows -Pids @($t | ForEach-Object { $_.pid })) } catch { $res.failed += ("the windows could not be listed: " + $_.Exception.Message) }
    $res.windows = $wins.Count
    if ($DryRun) { $res.running = $t; return $res }
    foreach ($w in $wins) {
        $r = [HordeNightlyAppWindowsV1]::AskToClose($w.handle, $w.pid)
        if ($r -eq 0) { $res.asked++ } elseif ($r -lt 0) { $res.failed += ("window " + $w.handle + " of process " + $w.pid + " would not take WM_CLOSE (error " + (0 - $r) + ")") }
    }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $WaitSeconds) {
        if (@($t | Where-Object { Test-HordeNightlyAppAlive $_ }).Count -eq 0) { break }
        & $Sleep 1000
    }
    foreach ($x in $t) { if (-not (Test-HordeNightlyAppAlive $x)) { $res.closed += $x } }
    # FULLY QUIT, the three tray apps only, each by its own id and only while it is still the same process.
    foreach ($x in @($t | Where-Object { Test-HordeNightlyAppAlive $_ })) {
        if ((Test-HordeNightlyAppName -Name $x.name -Names $ForceNames) -eq "") { continue }
        try { Stop-Process -Id $x.pid -Force -ErrorAction Stop } catch { $res.failed += ("process " + $x.pid + " (" + $x.name + ") could not be ended: " + $_.Exception.Message) }
    }
    $c2 = [System.Diagnostics.Stopwatch]::StartNew()
    while ($c2.Elapsed.TotalSeconds -lt 10) {
        if (@($t | Where-Object { (Test-HordeNightlyAppName -Name $_.name -Names $ForceNames) -ne "" -and (Test-HordeNightlyAppAlive $_) }).Count -eq 0) { break }
        & $Sleep 250
    }
    $closedIds = @{}; foreach ($x in $res.closed) { $closedIds[$x.pid] = $true }
    foreach ($x in $t) {
        if ($closedIds.ContainsKey($x.pid)) { continue }
        if (Test-HordeNightlyAppAlive $x) { $res.running += $x } else { $res.forced += $x }
    }
    return $res
}

function Format-HordeNightlyAppGroup {
    # "name N processes X.XX GB (pids a,b,c)" per app name, in the order first seen; at most -MaxPids ids each.
    param([object[]]$Targets, [int]$MaxPids = 8)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $order = @(); $by = @{}
    foreach ($x in @($Targets)) { if ($null -eq $x) { continue }; if (-not $by.ContainsKey($x.name)) { $by[$x.name] = @(); $order += $x.name }; $by[$x.name] += $x }
    $parts = @()
    foreach ($n in $order) {
        $g = @($by[$n]); $gb = 0.0; foreach ($x in $g) { $gb += [double]$x.gb }
        $ids = @($g | Select-Object -First $MaxPids | ForEach-Object { "" + $_.pid }) -join ","
        if ($g.Count -gt $MaxPids) { $ids += ",+" + ($g.Count - $MaxPids) }
        $parts += ($n + " " + $g.Count + " processes " + $gb.ToString("0.00", $inv) + " GB (pids " + $ids + ")")
    }
    return ($parts -join ", ")
}

function Get-HordeNightlyAppsGB {
    param([object[]]$Targets)
    $gb = 0.0; foreach ($x in @($Targets)) { if ($null -ne $x) { $gb += [double]$x.gb } }
    return $gb
}

function Format-HordeNightlyAppLines {
    # The report's lines from a Close-HordeNightlyApps result: CLOSED (with what was freed), FORCE-QUIT, STILL RUNNING.
    param($Result)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Result.dryRun) {
        $l = @("WOULD CLOSE (dry run, nothing closed): " + $(if (@($Result.running).Count -gt 0) { Format-HordeNightlyAppGroup @($Result.running) } else { "none of the named apps is running" }) + ", " + $Result.windows + " visible windows")
        $l += ("WOULD FORCE-QUIT if still running after the graceful wait: " + $(if (@($Result.wouldForce).Count -gt 0) { Format-HordeNightlyAppGroup @($Result.wouldForce) } else { "none" }))
        return $l
    }
    $freed = (Get-HordeNightlyAppsGB @($Result.closed)) + (Get-HordeNightlyAppsGB @($Result.forced))
    $lines = @("CLOSED: " + $(if (@($Result.closed).Count -gt 0) { Format-HordeNightlyAppGroup @($Result.closed) } else { "nothing closed on WM_CLOSE" }) + ". Freed " + $freed.ToString("0.00", $inv) + " GB, " + $Result.asked + " windows asked to close.")
    if (@($Result.forced).Count -gt 0) { $lines += ("FORCE-QUIT (tray apps, founder's order): " + (Format-HordeNightlyAppGroup @($Result.forced))) }
    if (@($Result.running).Count -gt 0) { $lines += ("STILL RUNNING (left alone): " + (Format-HordeNightlyAppGroup @($Result.running))) }
    foreach ($f in @($Result.failed | Select-Object -First 3)) { $lines += ("APP CLOSER: " + $f) }
    return $lines
}

function Get-HordeNightlyAppCloserStep {
    # What the closer does now: "close", "wait" (not yet time to try again), "busy" (the PC is in use or its input
    # clock is unknown: try again after the retry), "stop" (the cutoff has passed or it is not night: never tonight).
    # -Idle is what core/IdleState.ps1 Read-HordeIdleSeconds returns.
    param([datetime]$Now, [bool]$Night, $Idle, [int]$NeedSeconds, [datetime]$NextTry, [datetime]$Cutoff)
    if (-not $Night -or $Now -ge $Cutoff) { return "stop" }
    if ($Now -lt $NextTry) { return "wait" }
    if ($null -eq $Idle -or ("" + $Idle.state) -cne "known" -or [int]$Idle.seconds -lt $NeedSeconds) { return "busy" }
    return "close"
}

function Get-HordeNightlyChromeProfileRestore {
    # READ ONLY: session.restore_on_startup of one Chrome profile folder, or "" when it is not set. 1 means "continue
    # where you left off". Measured 2026-10-26 on this box: Chrome keeps it in the profile's "Secure Preferences" (the
    # Default profile's Preferences had no session key at all), so both files are read, Preferences first. A number
    # only: the same key also holds hash strings there. Read with a regex, not a JSON parser: the files are large and
    # may hold keys that differ only in case, which Windows PowerShell's parser refuses.
    param([string]$ProfileDir)
    foreach ($fn in @("Preferences", "Secure Preferences")) {
        $p = Join-Path $ProfileDir $fn
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $t = ""
        try { $t = [System.IO.File]::ReadAllText($p) } catch { continue }
        $m = [regex]::Match($t, '"restore_on_startup"\s*:\s*(\d+)')
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return ""
}

function Get-HordeNightlyChromeRestorePolicy {
    # READ ONLY, never changed: Chrome's RestoreOnStartup policy, in Chrome's own precedence, HKLM before HKCU. A set
    # policy applies to every profile and overrides each profile's own setting (T-0331, 2026-10-27: this box has
    # HKLM RestoreOnStartup = 1, and the line said 8 profiles did not restore). 1 restores the last session, 4 opens
    # URLs, 5 the new tab page. Returns { hive; key; value } or $null when neither hive sets it. -PolicyReader is
    # { param($Key) value-or-$null } so the suites never read this PC's registry; a reader that throws counts as not set.
    param([scriptblock]$PolicyReader)
    if ($null -eq $PolicyReader) {
        $PolicyReader = { param($Key) $v = Get-ItemProperty -LiteralPath $Key -Name "RestoreOnStartup" -ErrorAction SilentlyContinue; if ($null -eq $v) { return $null }; return $v.RestoreOnStartup }
    }
    foreach ($h in @("HKLM", "HKCU")) {
        $key = $h + ":\SOFTWARE\Policies\Google\Chrome"
        $v = $null
        try { $v = & $PolicyReader $key } catch { $v = $null }
        if ($null -ne $v -and ("" + $v).Trim() -ne "") { return [pscustomobject]@{ hive = $h; key = $key; value = ("" + $v).Trim() } }
    }
    return $null
}

function Get-HordeNightlyChromeRestore {
    # READ ONLY, never changed: does Chrome reopen the last session on startup, per profile? -UserDataDir is Chrome's
    # "User Data" folder. Returns { state = yes|no|some|unknown; profiles = [{ name; value }]; lastUsed; text }:
    # yes every profile restores, no none does, some a part does. Not set is Chrome's default (the new tab page).
    # A RestoreOnStartup policy (Get-HordeNightlyChromeRestorePolicy) decides first, for every profile; policy is
    # { hive; key; value } then, else $null. -PolicyReader is handed on (the suites hand in a fake).
    param([string]$UserDataDir, [scriptblock]$PolicyReader)
    $pol = Get-HordeNightlyChromeRestorePolicy -PolicyReader $PolicyReader
    if ($null -ne $pol) {
        $what = $(switch ($pol.value) { "1" { "restore the last session" } "4" { "open URLs" } "5" { "the new tab page" } default { "unknown value" } })
        $src = "(" + $pol.hive + "\" + $pol.key.Substring(6) + " RestoreOnStartup = " + $pol.value + ", " + $what + ")"
        if ($pol.value -ceq "1") { $text = "yes, every profile restores by policy " + $src + ", whatever each profile's own setting says" }
        else { $text = "NO profile restores, by policy " + $src + ", so tabs closed at night do not come back by themselves" }
        return [pscustomobject]@{ state = $(if ($pol.value -ceq "1") { "yes" } else { "no" }); profiles = @(); lastUsed = ""; policy = $pol; text = ("CHROME RESTORE (read only, not changed): " + $text + ".") }
    }
    $none = { param($why) [pscustomobject]@{ state = "unknown"; profiles = @(); lastUsed = ""; policy = $null; text = ("CHROME RESTORE: unknown, " + $why + ".") } }
    if ("" + $UserDataDir -eq "" -or -not (Test-Path -LiteralPath $UserDataDir)) { return (& $none "no Chrome profile folder was found") }
    $profiles = @()
    foreach ($d in @(Get-ChildItem -LiteralPath $UserDataDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($d.Name -ceq "System Profile" -or $d.Name -ceq "Guest Profile") { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName "Preferences"))) { continue }
        $profiles += [pscustomobject]@{ name = $d.Name; value = (Get-HordeNightlyChromeProfileRestore -ProfileDir $d.FullName) }
    }
    if ($profiles.Count -eq 0) { return (& $none "no Chrome profile has a Preferences file") }
    $last = ""
    try { $m = [regex]::Match([System.IO.File]::ReadAllText((Join-Path $UserDataDir "Local State")), '"last_used"\s*:\s*"([^"\\]*)"'); if ($m.Success) { $last = $m.Groups[1].Value } } catch { }
    $yes = @($profiles | Where-Object { $_.value -ceq "1" })
    $no = @($profiles | Where-Object { $_.value -cne "1" })
    $state = $(if ($no.Count -eq 0) { "yes" } elseif ($yes.Count -eq 0) { "no" } else { "some" })
    $text = "CHROME RESTORE (read only, not changed): "
    if ($state -ceq "yes") { $text += "yes, every profile reopens the last session on startup (session.restore_on_startup = 1)" }
    else {
        $text += $(if ($state -ceq "no") { "NO profile" } else { "NOT every profile" }) + " reopens the last session on startup, so tabs closed at night do not come back by themselves there."
        if ($yes.Count -gt 0) { $text += " Restores (1): " + (@($yes | ForEach-Object { $_.name }) -join ", ") + "." }
        $text += " Does not: " + (@($no | ForEach-Object { $_.name + " " + $(if ($_.value -eq "") { "(not set, the new tab page)" } else { "(" + $_.value + ")" }) }) -join ", ")
    }
    if ($last -ne "") { $lp = @($profiles | Where-Object { $_.name -ceq $last }); $text += ". Last used profile: " + $last + $(if ($lp.Count -gt 0) { $(if ($lp[0].value -ceq "1") { " (restores)" } else { " (does not restore)" }) } else { "" }) }
    return [pscustomobject]@{ state = $state; profiles = $profiles; lastUsed = $last; policy = $null; text = ($text + ".") }
}