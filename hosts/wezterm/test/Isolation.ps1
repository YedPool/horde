# Isolation.ps1 - a WezTerm that is ours alone, for tests that are allowed to break a terminal.
#
# Ported from YedPool/wezfleet lib/Isolation.ps1. Every lesson it carried, and what Horde did with
# each, is in planning/ledger/hosts-wezterm-isolation.md. The short version of why this file exists:
#
#   Every WezTerm window on a machine shares ONE mux server. The suite this replaces took down every
#   window on its machine twice - the second time while believing it had isolated itself, because it
#   had isolated the wrong thing: a window. A separate INSTANCE has its own mux and its own socket,
#   so the worst a test here can do is destroy the terminal it created.
#
# SCOPE. This isolates a TEST. It cannot isolate anything aimed at the live fleet, which lives in the
# user's own mux - "a second instance isolates a test; it cannot isolate a kill aimed at the live
# fleet" (YedPool/wezfleet planning/verified-delivery-and-safe-kill.md).
#
# ONE DEFINITION. Every script that needs an isolated terminal dot-sources this file. The old system
# once kept this logic inside a test file; a second copy is how a safety property rots, and this is
# the property that had already been broken twice.
#
# WHAT IS NOT ISOLATED, said plainly. The terminal is, and Horde's own store is FOR THE TEST PROCESS
# ONLY. NOTHING RUN INSIDE A PANE INHERITS THIS PROCESS'S ENVIRONMENT: measured 2026-10-05 (issue #95),
# a variable set here before the terminal started, or before `cli spawn`, was absent in the new pane,
# which got the user's own environment - so HORDE_ROOT below does not reach a pane, and neither does a
# harness's config redirect. That is how a probe started four real agent sessions on the user's own
# login in an isolated terminal. A program in a pane gets a redirected environment only through a
# wrapper that sets it INSIDE the pane (test/lib/PaneTool.ps1, wrap), and only after
# Assert-HordePaneEnvironment has proved, from inside a pane, that the wrapper delivers it.
# An AGENT started inside the isolated terminal also runs the user's own hooks and writes the agent's
# own real state unless its environment says otherwise - on the old system, a real session started in
# an isolated instance wrote a pane-sessions file and a registry record into the user's real home
# directory. A scenario that starts a real agent must prove its redirect first, must fail on any
# prompt it did not expect (a folder-trust prompt is the sign it is on the real config), and must
# remove what it wrote, by session id, and say so. None of the scenarios here starts one.
#
# NOTHING IS KILLED BY PID ALONE. An independent review of the first version found that it could
# force-kill a process that was never ours: Windows reuses process ids, and a process keeps recording
# its parent's pid after that parent dies, so walking parent links can wander into an unrelated
# process. Reproduced on real data before the fix: a Chrome born at 16:50 still recorded parent 24596,
# which by then belonged to a different Chrome born at 20:13 - and the old walker, asked for 24596's
# descendants, returned the older one. Every process this file might kill is now identified by its
# pid AND its creation time, and is killed only if both still match. And the one pid everything hangs
# from - the instance's own gui - is held by an open handle from adoption to teardown, so Windows
# cannot reuse it at all: a second review showed that without that, no rule over creation times can
# tell our orphans from a stranger's children.
#
# NESTING. Two instances started by one process restore the environment correctly only if they are
# torn down in the reverse order of starting, because each remembers the environment it found.

# The pane tool (test/lib/PaneTool.ps1): what Assert-HordePaneEnvironment runs inside a pane.
. (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "test\lib\PaneTool.ps1")

$script:HordeIsoCli = @("cli", "--no-auto-start")

function Invoke-HordeWeztermCli {
    # Every wezterm CLI call in this file goes through here, so none can forget --no-auto-start.
    #
    # WHY THAT FLAG, measured: `wezterm cli --help` lists it as "Don't automatically start the
    # server". Without it, a call aimed at a socket that is not answering may START a mux server - one
    # that loads the user's config and its session-restore plugin, the exact thing --skip-config is
    # there to prevent. An independent review raised it; the flag's existence was then confirmed.
    param([string[]]$Rest)
    return (& wezterm @($script:HordeIsoCli + $Rest) 2>$null)
}

function Get-HordeProcessTable {
    # A snapshot of every process: pid, parent pid, name, creation time. The walker and the kill take
    # this as a parameter so their decisions can be tested against a fixed table, without touching a
    # single real process.
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Select-Object @{ n = "pid"; e = { [int]$_.ProcessId } }, @{ n = "ppid"; e = { [int]$_.ParentProcessId } },
                      @{ n = "name"; e = { "$($_.Name)" } }, @{ n = "created"; e = { $_.CreationDate } })
}

function Get-HordeProcessInfo {
    # One process's identity right now, or $null if no process has that pid.
    param([int]$Id)
    $p = Get-CimInstance Win32_Process -Filter ("ProcessId = " + $Id) -ErrorAction SilentlyContinue
    if (-not $p) { return $null }
    return [pscustomobject]@{ pid = [int]$p.ProcessId; ppid = [int]$p.ParentProcessId; name = "$($p.Name)"; created = $p.CreationDate }
}

function Get-HordeWeztermGuiPids {
    # Every running wezterm-gui process id, as strings.
    return @(Get-Process -Name "wezterm-gui" -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Id)" })
}

function ConvertFrom-HordeWeztermJson {
    # `wezterm cli list --format json` output, as an array of panes.
    #
    # TWO TRAPS, BOTH MEASURED on the system this replaces:
    # 1. The CLI returns the JSON as LINES. Parse them unjoined and PowerShell 5.1 builds one object
    #    per line or fails outright, so they are joined first.
    # 2. ASSIGN FIRST, THEN WRAP. Against a real 29-pane list, `@($raw | ConvertFrom-Json)` returned
    #    count=1, while `$x = $raw | ConvertFrom-Json; @($x)` returned 29. The wrap around the
    #    PIPELINE collapsed every pane into one object - which meant the old multi-window guard, the
    #    one check that notices "I am talking to the user's terminal", could never fire.
    param($Raw)
    if ($null -eq $Raw) { return $null }
    $joined = ((@($Raw) -join "`n").Trim())
    if (-not $joined) { return $null }
    $parsed = $joined | ConvertFrom-Json
    return @($parsed)
}

function Test-HordeIsolationPanes {
    # The decision half of the isolation check, with no terminal in it, so every branch is testable.
    # Returns $null when the panes look like a fresh hermetic instance, or the reason they do not.
    #
    # ZERO PANES IS UNKNOWN, NOT EMPTY. A list that came back empty is a failure to read, not proof
    # of an idle terminal - so it refuses rather than passing.
    #
    # EVERY PANE MUST SAY WHICH WINDOW IT IS IN. Panes with no window_id would all count as "one
    # window", so a change in the CLI's JSON would silently disable the check below. Refused instead.
    #
    # EXACTLY ONE WINDOW is the signal that tells a fresh instance from a working terminal. It is a
    # heuristic and is named as one: a user with a single WezTerm window would not trip it, which is
    # why Assert-HordeIsolated checks the socket and the pid first and this last.
    param($Panes)
    $p = @($Panes | Where-Object { $null -ne $_ })
    if ($p.Count -eq 0) { return "no panes at all - that is unknown, not empty" }
    if (@($p | Where-Object { $null -eq $_.window_id -or "$($_.window_id)" -eq "" }).Count -gt 0) {
        return "a pane has no window_id, so windows cannot be counted - refusing rather than guessing"
    }
    $windows = @($p | ForEach-Object { "$($_.window_id)" } | Sort-Object -Unique)
    if ($windows.Count -gt 1) { return "$($p.Count) panes across $($windows.Count) windows - this looks like the user's terminal" }
    return $null
}

function Get-HordeDescendantPids {
    # Every process descended from a root, as { pid; created } - the creation time travels with the
    # pid so nothing is later killed on the pid alone.
    #
    # A CHILD COUNTS ONLY IF IT WAS CREATED AT OR AFTER ITS PARENT. A process created BEFORE the
    # process that now holds its recorded parent pid cannot be that process's child: its real parent
    # died and the pid was reused. That is the case the independent review reproduced on real data.
    #
    # THE ROOT IS THE ONE LEVEL THAT RULE CANNOT PROTECT, so it is not guessed at. Two reviews found
    # the ways a guess fails: if our root died and its pid was reused - even by a process that has
    # since died too - that process's children record our pid and were created after our root, and
    # nothing in a process table says when our root died. So:
    #   - root alive, same creation time: walk from it.
    #   - the pid is held by a DIFFERENT process: return nothing. Its children cannot be told apart
    #     from our orphans, and killing nothing is the safe error.
    #   - root gone: its orphans are returned ONLY with -RootPinned, which the caller passes only when
    #     it holds an open handle to the root. Windows never reuses a pid while a handle to it is open,
    #     so every process recording that pid as its parent, created after our root, really is ours.
    #     Registration takes that handle for every instance, so teardown can always pass it.
    #
    # Creation times are compared at microsecond precision, as everywhere else in this file; the
    # re-review measured a root 3 ticks off, read through .NET instead of CIM, silently walking nothing.
    param([int]$RootPid, [Parameter(Mandatory = $true)]$RootCreated, [switch]$RootPinned, $Processes = $null)
    $all = $Processes
    if ($null -eq $all) { $all = Get-HordeProcessTable }
    $all = @($all)
    $rootUs = Get-HordeMicroseconds $RootCreated
    $out = New-Object System.Collections.ArrayList
    $seen = @{ "$RootPid" = $true }
    $owner = @($all | Where-Object { $_.pid -eq $RootPid }) | Select-Object -First 1
    if ($owner -and $owner.created -and (Get-HordeMicroseconds $owner.created) -eq $rootUs) {
        $frontier = @($owner)
    } elseif ($owner -or -not $RootPinned) {
        return @()
    } else {
        $firstGen = @($all | Where-Object {
            $_.ppid -eq $RootPid -and $_.pid -ne $RootPid -and $_.created -and (Get-HordeMicroseconds $_.created) -ge $rootUs })
        foreach ($c in $firstGen) { $seen["$($c.pid)"] = $true; [void]$out.Add([pscustomobject]@{ pid = $c.pid; created = $c.created }) }
        $frontier = $firstGen
    }
    while ($frontier.Count -gt 0) {
        $next = @()
        foreach ($par in $frontier) {
            $parUs = Get-HordeMicroseconds $par.created
            foreach ($c in @($all | Where-Object { $_.ppid -eq $par.pid -and $_.pid -ne $par.pid })) {
                if ($seen.ContainsKey("$($c.pid)")) { continue }
                if (-not $c.created -or (Get-HordeMicroseconds $c.created) -lt $parUs) { continue }
                $seen["$($c.pid)"] = $true
                $o = [pscustomobject]@{ pid = $c.pid; created = $c.created }
                [void]$out.Add($o); $next += $c
            }
        }
        $frontier = $next
    }
    return @($out)
}

function Get-HordeMicroseconds {
    # A time at microsecond precision - the precision process creation times are reported in through
    # CIM, measured by the re-review: exact to the microsecond, so two reads of one process agree.
    #
    # INTEGER DIVISION, NEVER / : PowerShell divides two longs as doubles, and a tick count has 18
    # digits where a double holds about 16. Measured 2026-09-29: with / the CIM and .NET readings of
    # the same process disagreed for 304 of 365 processes, so the kill check refused our own processes.
    param($Time)
    $rem = [long]0
    return [Math]::DivRem([long]([datetime]$Time).ToUniversalTime().Ticks, [long]10, [ref]$rem)
}

function Stop-HordeProcessIfSame {
    # Kill a process only if the pid still belongs to the SAME process that was recorded - same pid,
    # same creation time. Returns "killed", "gone", "not-same" (the pid now belongs to something else,
    # which is left alone), "cannot-open" (no handle could be taken, so nothing was done), or
    # "survived".
    #
    # THE HANDLE IS TAKEN FIRST AND HELD. Windows does not reuse a pid while a handle to it is open, so
    # checking the creation time and killing through that same handle leaves no gap in which the pid
    # could come to name a different process. The first version checked, then killed by pid - a
    # millisecond window, but a window, found by the re-review. In .NET Framework the first read of
    # .Handle opens and caches the handle, and StartTime and Kill() then use it.
    #
    # AND "NO HANDLE" IS CHECKED BY VALUE, NOT CAUGHT. The third review measured that PowerShell 5.1
    # swallows the exception from the .Handle getter and returns $null - so the first version's
    # try/catch around it never caught anything, "cannot-open" could not happen, and StartTime and
    # Kill() each quietly opened a fresh handle by pid, reopening the gap.
    param([int]$Id, $Created)
    if ($null -eq $Created) { return "not-same" }
    $p = $null
    try { $p = [System.Diagnostics.Process]::GetProcessById($Id) } catch { return "gone" }
    try {
        $h = $null
        try { $h = $p.Handle } catch { $h = $null }
        if ($null -eq $h -or $h -eq [IntPtr]::Zero) { return "cannot-open" }
        if ($p.HasExited) { return "gone" }
        if ((Get-HordeMicroseconds $p.StartTime) -ne (Get-HordeMicroseconds $Created)) { return "not-same" }
        try { $p.Kill() } catch { }
        [void]$p.WaitForExit(3000)
        if ($p.HasExited) { return "killed" }
        return "survived"
    } finally { $p.Dispose() }
}

# THE INSTANCES THIS PROCESS STARTED, keyed by token. Teardown acts only on an instance found here,
# and takes the pid, creation time and socket from HERE rather than from the object it was handed.
#
# The first version's token was built from the gui's pid and creation time alone, so anyone could
# compute a valid one - and the fast suite did. A token now includes a value generated for that one
# instance and is honoured only if this process registered it. What that defends against, said
# plainly: an object that did not come from Start - the user's own terminal described by hand, a
# stale instance, a typo - being passed to teardown. It does not defend against code in this same
# process deliberately registering something; nothing in a test harness should, and nothing here does
# except the test that proves teardown refuses a registered process that is not a WezTerm.
#
# ONLY IF NOT ALREADY SET. Dot-sourcing this file a second time used to replace the registry with an
# empty one, after which teardown refused every live instance - killing nothing and leaking them all.
if ($null -eq $script:HordeIsoStarted) { $script:HordeIsoStarted = @{} }

function Register-HordeIsolatedInstance {
    # Record an instance as started by this process, and return its token.
    #
    # REGISTERING PINS THE PROCESS. It opens a handle to the gui and keeps it until teardown, and
    # Windows never reuses a pid while a handle to it is open. That turns "our pid was reused by a
    # stranger" from unlikely into impossible, for every question teardown asks: whose children to
    # kill, and whose socket file to delete. Throws if the pid is not the process described.
    #
    # The environment to restore is recorded here too, so teardown restores what Start found and not
    # whatever the object handed to it says.
    param([int]$GuiPid, $Created, [string]$Socket, [string]$Store = "", [string]$OriginalSocket = "", [string]$OriginalRoot = "")
    $pin = [System.Diagnostics.Process]::GetProcessById($GuiPid)
    $h = $null
    try { $h = $pin.Handle } catch { $h = $null }
    if ($null -eq $h -or $h -eq [IntPtr]::Zero) {
        $pin.Dispose()
        throw ("refusing to register pid " + $GuiPid + ": no handle could be held, so it cannot be pinned")
    }
    if ($pin.HasExited -or (Get-HordeMicroseconds $pin.StartTime) -ne (Get-HordeMicroseconds $Created)) {
        $pin.Dispose()
        throw ("refusing to register pid " + $GuiPid + ": it is not the process created at " + $Created)
    }
    $token = "horde-iso:" + $GuiPid + ":" + (Get-HordeMicroseconds $Created) + ":" + [guid]::NewGuid().ToString("N")
    $script:HordeIsoStarted[$token] = [pscustomobject]@{ pid = $GuiPid; created = $Created; socket = $Socket; store = $Store
                                                         originalSocket = $OriginalSocket; originalRoot = $OriginalRoot; pin = $pin }
    return $token
}

function Test-HordeOwnedPath {
    # Is Path exactly <Folder>\<a name matching LeafPattern>? Compared as full paths, ignoring case.
    param([string]$Path, [string]$Folder, [string]$LeafPattern)
    if (-not $Path) { return $false }
    if ((Split-Path -Leaf $Path) -notmatch $LeafPattern) { return $false }
    $parent = [System.IO.Path]::GetFullPath((Split-Path -Parent $Path)).TrimEnd('\')
    return [string]::Equals($parent, [System.IO.Path]::GetFullPath($Folder).TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-HordeKill {
    # The one place the harness kills a process. -KillWith lets a test put its own guard in the way:
    # the fast suite passes a killer that refuses - and records - any pid it did not start and still
    # hold, so even a deliberately broken walker (which mutation testing creates) can never reach a
    # process that is not the suite's own. The third review found that without it, mutation runs
    # executed broken kill code against real processes.
    param([int]$Id, $Created, [scriptblock]$KillWith = $null)
    if ($KillWith) { return (& $KillWith $Id $Created) }
    return (Stop-HordeProcessIfSame -Id $Id -Created $Created)
}

function Test-HordeAdoptableGui {
    # Is this wezterm-gui the one OUR launcher started? Its recorded parent is the launcher's pid, and
    # it was created no earlier than the launcher - a gui that predates the launcher had a different
    # parent that once held that pid. A pure decision, so every branch is testable without a terminal.
    param($Gui, [int]$LauncherPid, $LauncherUs)
    if ($null -eq $Gui -or $null -eq $LauncherUs -or -not $Gui.created) { return $false }
    if ("$($Gui.name)" -ne "wezterm-gui.exe") { return $false }
    if ([int]$Gui.ppid -ne $LauncherPid) { return $false }
    return ((Get-HordeMicroseconds $Gui.created) -ge [long]$LauncherUs)
}

function Stop-HordeLaunchTree {
    # Kill a launcher and everything it started, each by pid AND creation time, walking BEFORE killing
    # so nothing loses its parent link first.
    #
    # ONLY THE LAUNCHER START RECORDED. The launcher's start time is passed in as Start read it, and
    # the Process object must still report that same start time - through the handle it has held since
    # launch. Without that, a Process object holding no handle (what -NoNewWindow or a redirected
    # launch gives, measured) would open whatever process now has the pid, and its whole tree would be
    # walked as ours.
    param($Launcher, $LauncherUs, [scriptblock]$KillWith = $null)
    if (-not $Launcher -or $null -eq $LauncherUs) { return }
    $lc = $null
    try { $lc = $Launcher.StartTime } catch { return }
    if ($null -eq $lc -or (Get-HordeMicroseconds $lc) -ne [long]$LauncherUs) { return }
    foreach ($d in @(Get-HordeDescendantPids -RootPid $Launcher.Id -RootCreated $lc -RootPinned)) { [void](Invoke-HordeKill -Id $d.pid -Created $d.created -KillWith $KillWith) }
    [void](Invoke-HordeKill -Id $Launcher.Id -Created $lc -KillWith $KillWith)
}

function Start-HordeIsolatedWezterm {
    # Launch a WezTerm instance that is ours alone, pin this process to it, and point Horde's own
    # state at a throwaway store. Returns the instance, or $null if nothing answered in time.
    #
    # ONLY THE GUI OUR OWN LAUNCHER STARTED IS ADOPTED - a new wezterm-gui whose parent is the launch
    # process and which was created after the launch. The first version adopted ANY new wezterm-gui,
    # so a terminal the user opened, or one a parallel test started, during the wait could be taken
    # for ours - and then spawned into, and killed. (The original had the same weakness.)
    param([int]$TimeoutSeconds = 30)

    $origSocket = $env:WEZTERM_UNIX_SOCKET
    $origRoot = $env:HORDE_ROOT

    # --always-new-process stops it attaching to the running GUI, which would defeat the point.
    # --skip-config is LOAD-BEARING: the user's wezterm.lua loads a session-restore plugin that, on a
    # fresh mux, either restores copies of their real sessions inside the test terminal or sits on a
    # modal prompt that looks exactly like a timeout.
    #
    # THE LAUNCHER'S PROCESS OBJECT HOLDS ITS HANDLE FROM THE MOMENT IT IS CREATED. Started through
    # the shell (UseShellExecute), .NET asks for the process handle back and keeps it - the third
    # review measured that Start-Process -WindowStyle Minimized, which is this path, holds it, while
    # a redirected or -NoNewWindow start does not. So the launcher's pid cannot be reused while we
    # wait, and its start time, read at once, is its own. The first version looked it up again through
    # CIM, which misses a launcher that exits quickly and then adopted nothing and killed nothing.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wezterm"
    $psi.Arguments = "--skip-config start --always-new-process --class horde-iso"
    $psi.UseShellExecute = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized
    $launcher = $null
    try { $launcher = [System.Diagnostics.Process]::Start($psi) } catch { $launcher = $null }
    $launcherUs = $null
    if ($launcher) { try { $launcherUs = Get-HordeMicroseconds $launcher.StartTime } catch { $launcherUs = $null } }

    $sockDir = Join-Path $env:USERPROFILE ".local\share\wezterm"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        foreach ($g in @(Get-HordeProcessTable | Where-Object { $_.name -eq "wezterm-gui.exe" })) {
            if ($null -eq $launcher -or -not (Test-HordeAdoptableGui -Gui $g -LauncherPid $launcher.Id -LauncherUs $launcherUs)) { continue }
            $sock = Join-Path $sockDir ("gui-sock-" + $g.pid)
            if (-not (Test-Path -LiteralPath $sock)) { continue }

            $store = $null
            # FROM HERE ON, ANY FAILURE UNDOES EVERYTHING. A throw between pinning and returning used to
            # leave this process pinned to the new socket and the instance running with nobody holding
            # it - found by the same review.
            try {
                # THE PIN IS WEZTERM_UNIX_SOCKET, NOT --class. Inside any WezTerm pane this variable is
                # already set, and the CLI follows it and ignores --class. Measured on the system this
                # replaces: pinned, 1 pane visible; unpinned, 13. It is inherited by children, so every
                # wezterm call a test makes afterwards is pinned without being told.
                $env:WEZTERM_UNIX_SOCKET = $sock
                $probe = Invoke-HordeWeztermCli -Rest @("list", "--format", "json")
                if ($LASTEXITCODE -eq 0 -and $probe) {
                    # A SEPARATE MUX DOES NOT SEPARATE THE STORES. On the old system a real session
                    # started in an isolated instance still wrote into the user's real pane-sessions and
                    # registry. Horde's own state, at least, goes somewhere throwaway for the instance's life -
                    # in THIS process and its own children; a pane does not inherit it (issue #95).
                    #
                    # NAMED BY A FRESH GUID AND CREATED ONLY IF NEW. The first version named it by pid and
                    # created it with -Force, so a stale folder from an earlier run - or another run's live
                    # one - was silently reused.
                    $store = Join-Path $env:TEMP ("horde-iso-store-" + [guid]::NewGuid().ToString("N"))
                    New-Item -ItemType Directory -Path $store -ErrorAction Stop | Out-Null
                    $env:HORDE_ROOT = $store
                    $token = Register-HordeIsolatedInstance -GuiPid $g.pid -Created $g.created -Socket $sock -Store $store `
                                 -OriginalSocket "$origSocket" -OriginalRoot "$origRoot"
                    return [pscustomobject]@{
                        pid = $g.pid; created = $g.created; socket = $sock; store = $store
                        launcherPid = $launcher.Id; originalSocket = $origSocket; originalRoot = $origRoot; token = $token
                    }
                }
                # Not answering yet. UNPIN rather than leave this process aimed at a half-open socket,
                # which is the state in which a "safe" call quietly reaches the user's terminal instead.
                $env:WEZTERM_UNIX_SOCKET = $origSocket
            } catch {
                # Everything this launch produced goes, not only the gui: the first version's failure
                # path killed the gui and left the launcher and anything else it had started.
                # The launch tree is walked FIRST and the gui killed as part of it: killing the gui
                # before the walk (as the previous version did) cut its children off from the launcher
                # and leaked them. And a store made before registration failed is removed.
                $env:WEZTERM_UNIX_SOCKET = $origSocket
                $env:HORDE_ROOT = $origRoot
                Stop-HordeLaunchTree -Launcher $launcher -LauncherUs $launcherUs
                if ($store -and (Test-HordeOwnedPath -Path $store -Folder $env:TEMP -LeafPattern '^horde-iso-store-[0-9a-f]{32}$')) {
                    Remove-Item -LiteralPath $store -Recurse -Force -ErrorAction SilentlyContinue
                }
                throw
            }
        }
        Start-Sleep -Milliseconds 500
    }

    # TIMED OUT. The terminal may still come up after we stop waiting, and nobody would hold it, so the
    # launch is torn down now - identified by creation time, never by pid alone.
    $env:WEZTERM_UNIX_SOCKET = $origSocket
    Stop-HordeLaunchTree -Launcher $launcher -LauncherUs $launcherUs
    return $null
}

function Test-HordePaneEnvironment {
    # The decision half of the pane environment check, with no terminal in it: $null when the dump
    # taken inside a pane holds every expected variable with exactly its value, or the reason it does
    # not. No dump at all is a failure to look, never a pass.
    param($Dump, [Parameter(Mandatory = $true)][hashtable]$Expect)
    if ($null -eq $Dump) { return "no environment was read from inside the pane - unknown, not proven" }
    if ($Expect.Count -eq 0) { return "nothing was expected, so nothing was proven" }
    $bad = New-Object System.Collections.ArrayList
    foreach ($k in @($Expect.Keys | Sort-Object)) {
        if (-not $Dump.ContainsKey($k)) { [void]$bad.Add($k + " is not set inside the pane") }
        elseif ("" + $Dump[$k] -cne "" + $Expect[$k]) { [void]$bad.Add($k + " is set inside the pane to another value") }
    }
    if ($bad.Count -gt 0) { return ("the pane's environment is not the one asked for: " + ($bad -join "; ")) }
    return $null
}

function Assert-HordePaneEnvironment {
    # THE CONTROL BEFORE ANY HARNESS STARTS IN A PANE (coordinator's rule of 2026-10-05). Spawns the
    # pane tool's wrap, which sets -Variables inside the pane and runs the tool's env-dump as its child,
    # exactly as a harness would be run; then compares the dump. Throws on any doubt; returns $true.
    # -Tool is test/lib/PaneTool.ps1's Get-HordePaneTool.
    param($Instance, [Parameter(Mandatory = $true)][hashtable]$Variables, [Parameter(Mandatory = $true)][string]$Tool, [int]$TimeoutSeconds = 20)
    [void](Assert-HordeIsolated -Instance $Instance)
    $dir = Join-Path $env:TEMP ("horde-paneenv-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dir | Out-Null
    try {
        $envFile = Join-Path $dir "env.txt"
        $dumpFile = Join-Path $dir "dump.txt"
        Write-HordePaneToolEnvFile -Path $envFile -Variables $Variables
        $out = Invoke-HordeWeztermCli -Rest @("spawn", "--cwd", $dir, "--", $Tool, "wrap", $envFile, $Tool, "env-dump", $dumpFile)
        if ("$(@($out) -join '')".Trim() -notmatch '^\d+$') { throw "pane environment not proven: the terminal did not spawn the check" }
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not (Test-Path -LiteralPath $dumpFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250 }
        Start-Sleep -Milliseconds 300
        $why = Test-HordePaneEnvironment -Dump (Read-HordePaneToolEnv -Path $dumpFile) -Expect $Variables
        if ($null -ne $why) { throw ("pane environment not proven: " + $why) }
        return $true
    } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

function Assert-HordeIsolated {
    # THE CONTROL. Nothing destructive runs until this has passed.
    #
    # "Am I pinned?" is answered by MEASUREMENT, never by the fact that a variable was set a moment
    # ago. It checks the pin, then asks the instance for its own panes and refuses on anything that
    # looks like a working terminal. Throws on any doubt; returns the pane count when satisfied.
    param($Instance)
    if (-not $Instance) { throw "not isolated: no instance" }
    if ("$env:WEZTERM_UNIX_SOCKET" -ne "$($Instance.socket)") {
        throw "not isolated: WEZTERM_UNIX_SOCKET is '$env:WEZTERM_UNIX_SOCKET', expected '$($Instance.socket)'"
    }
    # The socket's own name carries its GUI's pid. A hand-built instance whose socket and pid disagree
    # is refused here. (For an instance Start made this always holds, because Start built the name.)
    if ((Split-Path -Leaf "$($Instance.socket)") -ne ("gui-sock-" + $Instance.pid)) {
        throw "not isolated: socket '$($Instance.socket)' does not belong to pid $($Instance.pid)"
    }
    $raw = Invoke-HordeWeztermCli -Rest @("list", "--format", "json")
    if ($LASTEXITCODE -ne 0 -or -not $raw) { throw "not isolated: the instance did not answer" }
    $why = Test-HordeIsolationPanes -Panes (ConvertFrom-HordeWeztermJson -Raw $raw)
    if ($why) { throw "not isolated: $why" }
    return @(ConvertFrom-HordeWeztermJson -Raw $raw).Count
}

function Stop-HordeIsolatedWezterm {
    # TEAR THE INSTANCE DOWN AND PROVE IT WENT - the GUI, and everything that ran inside it.
    #
    # Returns { stopped; pid; survived; orphansKilled; orphansSurvived; socketRemoved; refused; reason }
    # so a caller asserts rather than hopes.
    #
    # IT REFUSES AN INSTANCE IT CANNOT PROVE IS ITS OWN. The first version would kill whatever pid it
    # was handed and delete whatever socket file - so an object built from the user's own terminal,
    # which the fast suite builds to prove Assert refuses it, would have killed the user's whole
    # terminal had it ever been passed here. Now the instance must carry the token Start issued, and
    # the live gui must still have the pid and creation time that token names.
    #
    # WHY CHILDREN ARE CHECKED. On 2026-09-29 two isolated instances and the agent sessions in them
    # survived their probe runs - about 590 MB, found an hour later by reading the process list. The
    # same day, killing an editor left the agent session inside it alive and beyond the reach of every
    # kill mechanism tried. Killing a terminal is not evidence that what ran in it died.
    #
    # MEASURED 2026-09-29, and it narrowed the worry without removing it: killing THIS instance's
    # wezterm-gui took its children with it - the end-to-end test found a long-lived child inside the
    # instance's tree before the kill and nothing afterwards. So the old system's 590 MB leak was the
    # teardown never running, not children outliving it. The check stays anyway, because the editor
    # measured the same day did leave an agent running, and hosts differ.
    #
    # And the original's actual fault that night was a NAME: a probe called a teardown function that
    # did not exist, so no check inside it ever ran. hosts/wezterm/test/test-isolation.ps1 guards it.
    #
    # -KillWith: see Invoke-HordeKill. Tests pass a guard; real use leaves it out.
    param($Instance, [scriptblock]$KillWith = $null)
    # A REFUSAL IS SAID OUT LOUD. It kills nothing and restores nothing, so an instance refused by
    # mistake is a leaked terminal and a process still pinned to it - which nobody would notice if the
    # refusal were only a field in a return value.
    $verdict = { param($stopped, $survived, $killed, $still, $sockOk, $refused, $reason, $id)
        if ($refused) { Write-Host ("  isolated teardown REFUSED (" + $reason + ") - nothing was killed and the environment was not restored") -ForegroundColor Red }
        [pscustomobject]@{ stopped = $stopped; pid = $id; survived = $survived; orphansKilled = @($killed)
                           orphansSurvived = @($still); socketRemoved = $sockOk; refused = $refused; reason = $reason } }

    if (-not $Instance) {
        return (& $verdict $false $false @() @() $false $true "no instance was passed - nothing was stopped and nothing was verified" -1)
    }
    # ONLY AN INSTANCE THIS PROCESS REGISTERED, and the pid, creation time and socket come from the
    # REGISTRY, not from the object passed in - so an object that names someone else's socket, or
    # someone else's process, cannot steer what is killed or deleted.
    $known = $null
    if ($Instance.token -and $script:HordeIsoStarted.ContainsKey("$($Instance.token)")) { $known = $script:HordeIsoStarted["$($Instance.token)"] }
    if (-not $known) {
        return (& $verdict $false $false @() @() $false $true "not an instance this process started (no registered token) - refusing to kill anything" $Instance.pid)
    }
    $gpid = [int]$known.pid; $gcreated = $known.created

    # IF OUR PROCESS IS STILL RUNNING, IT MUST BE A WEZTERM. A registered token whose process turns
    # out to be something else is refused rather than killed.
    $live = Get-HordeProcessInfo -Id $gpid
    if ($live -and (Get-HordeMicroseconds $live.created) -eq (Get-HordeMicroseconds $gcreated) -and $live.name -ne "wezterm-gui.exe") {
        return (& $verdict $false $false @() @() $false $true ("the registered process " + $gpid + " is " + $live.name + ", not a WezTerm - refusing to kill it") $gpid)
    }

    # UNPIN FIRST, so nothing after this point talks to a socket whose server is about to die, and give
    # Horde its real store back. (The first version's comment said "unpin first" and its code did it
    # after the kill.)
    # From the registry, as recorded by Start - not from the object handed in.
    $env:WEZTERM_UNIX_SOCKET = $known.originalSocket
    $env:HORDE_ROOT = $known.originalRoot

    # Descendants are recorded BEFORE the kill. The registry holds a handle to the gui, so its pid
    # cannot have been reused, and orphans of a gui that already died can be attributed to it safely.
    $pinned = [bool]$known.pin
    $descendants = @(Get-HordeDescendantPids -RootPid $gpid -RootCreated $gcreated -RootPinned:$pinned)
    $gui = Invoke-HordeKill -Id $gpid -Created $gcreated -KillWith $KillWith
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $now = Get-HordeProcessInfo -Id $gpid
        if (-not $now -or (Get-HordeMicroseconds $now.created) -ne (Get-HordeMicroseconds $gcreated)) { break }
        Start-Sleep -Milliseconds 200
    }
    $nowGui = Get-HordeProcessInfo -Id $gpid
    $survived = [bool]($nowGui -and (Get-HordeMicroseconds $nowGui.created) -eq (Get-HordeMicroseconds $gcreated))

    # Anything that outlived its terminal is killed now - each by pid AND creation time - and whatever
    # still will not die is reported by pid rather than assumed gone.
    #
    # AND THE WALK IS REPEATED AFTER THE KILL. Anything started between the first walk and the kill, or
    # by a surviving orphan afterwards, was never killed - the third review's leak. The pin is still
    # held, so a second walk from our dead gui is as safe as the first.
    $killed = @(); $still = @()
    $done = @{}
    foreach ($pass in 1..2) {
        if ($pass -eq 2) { $descendants = @(Get-HordeDescendantPids -RootPid $gpid -RootCreated $gcreated -RootPinned:$pinned) }
        foreach ($d in $descendants) {
            $key = "" + $d.pid + ":" + (Get-HordeMicroseconds $d.created)
            if ($done.ContainsKey($key)) { continue }
            $done[$key] = $true
            $r = Invoke-HordeKill -Id $d.pid -Created $d.created -KillWith $KillWith
            if ($r -eq "killed") { $killed += $d.pid }
            if ($r -eq "survived") { $still += $d.pid }
        }
    }

    # The socket file outlives its process; left behind, the runtime directory collects one dead
    # socket per run. ONLY OUR SOCKET: the one the registry recorded, only if it is gui-sock-<our pid>
    # in WezTerm's own socket folder, and only once our gui is gone. The handle held since
    # registration means no other WezTerm can have taken our pid, and so our socket's name. And a gui
    # that survived keeps its socket, so it can still be reached to be cleaned up by hand.
    $sockDir = Join-Path $env:USERPROFILE ".local\share\wezterm"
    $ourSock = "$($known.socket)"
    $sockOk = Test-HordeOwnedPath -Path $ourSock -Folder $sockDir -LeafPattern ('^gui-sock-' + $gpid + '$')
    $socketRemoved = $true
    if ($ourSock -and (Test-Path -LiteralPath $ourSock)) {
        if ($sockOk -and -not $survived) {
            Remove-Item -LiteralPath $ourSock -Force -ErrorAction SilentlyContinue
            $socketRemoved = -not (Test-Path -LiteralPath $ourSock)
        } else {
            $socketRemoved = $false
        }
    }
    # The same for the throwaway store: only the one Start made, horde-iso-store-<guid> directly in TEMP.
    $ourStore = "$($known.store)"
    if ((Test-HordeOwnedPath -Path $ourStore -Folder $env:TEMP -LeafPattern '^horde-iso-store-[0-9a-f]{32}$') -and (Test-Path -LiteralPath $ourStore)) {
        Remove-Item -LiteralPath $ourStore -Recurse -Force -ErrorAction SilentlyContinue
    }

    # A token is used once. Leaving it registered would let a stale object be torn down twice. The
    # handle is released only now, after every decision that relied on it.
    $script:HordeIsoStarted.Remove("$($Instance.token)")
    if ($known.pin) { $known.pin.Dispose() }

    # SAY IT WHERE A HUMAN WILL SEE IT. A leaked instance can be holding a real agent session.
    if ($survived -or $still.Count -gt 0) {
        Write-Host ("  ISOLATED INSTANCE LEAKED: gui " + $gpid + " survived=" + $survived +
                    ", processes that would not die: " + ($still -join ", ") + ". Kill them by hand.") -ForegroundColor Red
    }
    $reason = ""
    if ($survived) { $reason = "the terminal outlived a 10s wait" }
    elseif ($still.Count -gt 0) { $reason = "processes that ran inside it would not die" }
    return (& $verdict (-not $survived -and $still.Count -eq 0) $survived $killed $still $socketRemoved $false $reason $gpid)
}
