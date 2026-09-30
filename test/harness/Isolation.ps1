# Isolation.ps1 - a WezTerm that is ours alone, for tests that are allowed to break a terminal.
#
# Ported from YedPool/wezfleet lib/Isolation.ps1. Every lesson it carried, and what Horde did with
# each, is in planning/ledger/test-harness-isolation.md. The short version of why this file exists:
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
# WHAT IS NOT ISOLATED, said plainly. The terminal and Horde's own store are. An AGENT started inside
# the isolated terminal is not: it runs the user's own hooks and writes the agent's own real state -
# on the old system, a real session started in an isolated instance wrote a pane-sessions file and a
# registry record into the user's real home directory. A scenario that starts a real agent must
# remove what it wrote, by session id, and must say so. None of the scenarios here starts one.
#
# NOTHING IS KILLED BY PID ALONE. An independent review of the first version found that it could
# force-kill a process that was never ours: Windows reuses process ids, and a process keeps recording
# its parent's pid after that parent dies, so walking parent links can wander into an unrelated
# process. Reproduced on real data before the fix: a Chrome born at 16:50 still recorded parent 24596,
# which by then belonged to a different Chrome born at 20:13 - and the old walker, asked for 24596's
# descendants, returned the older one. Every process this file might kill is now identified by its
# pid AND its creation time, and is killed only if both still match.
#
# NESTING. Two instances started by one process restore the environment correctly only if they are
# torn down in the reverse order of starting, because each remembers the environment it found.

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
    param([int]$RootPid, $Processes = $null)
    $all = $Processes
    if ($null -eq $all) { $all = Get-HordeProcessTable }
    $all = @($all)
    $root = @($all | Where-Object { $_.pid -eq $RootPid }) | Select-Object -First 1
    if (-not $root) { return @() }
    $out = New-Object System.Collections.ArrayList
    $seen = @{ "$RootPid" = $true }
    $frontier = @($root)
    while ($frontier.Count -gt 0) {
        $next = @()
        foreach ($par in $frontier) {
            foreach ($c in @($all | Where-Object { $_.ppid -eq $par.pid -and $_.pid -ne $par.pid })) {
                if ($seen.ContainsKey("$($c.pid)")) { continue }
                if ($c.created -lt $par.created) { continue }
                $seen["$($c.pid)"] = $true
                $o = [pscustomobject]@{ pid = $c.pid; created = $c.created }
                [void]$out.Add($o); $next += $c
            }
        }
        $frontier = $next
    }
    return @($out)
}

function Stop-HordeProcessIfSame {
    # Kill a process only if the pid still belongs to the SAME process that was recorded - same pid,
    # same creation time. Returns "killed", "gone" (no such pid, or it died), or "not-same" (the pid
    # now belongs to something else, which is left alone).
    param([int]$Id, $Created)
    $now = Get-HordeProcessInfo -Id $Id
    if (-not $now) { return "gone" }
    if ($null -eq $Created -or $now.created -ne $Created) { return "not-same" }
    try { Stop-Process -Id $Id -Force -ErrorAction Stop } catch { }
    Start-Sleep -Milliseconds 200
    $after = Get-HordeProcessInfo -Id $Id
    if ($after -and $after.created -eq $Created) { return "survived" }
    return "killed"
}

function New-HordeInstanceToken {
    # What proves an instance object came from Start-HordeIsolatedWezterm: its gui's pid and creation
    # time, which Stop re-reads from the live process before killing anything.
    param([int]$GuiPid, $Created)
    return ("horde-iso:" + $GuiPid + ":" + ([datetime]$Created).ToUniversalTime().Ticks)
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
    $launchedAt = Get-Date

    # --always-new-process stops it attaching to the running GUI, which would defeat the point.
    # --skip-config is LOAD-BEARING: the user's wezterm.lua loads a session-restore plugin that, on a
    # fresh mux, either restores copies of their real sessions inside the test terminal or sits on a
    # modal prompt that looks exactly like a timeout.
    $launcher = Start-Process -FilePath "wezterm" -PassThru `
        -ArgumentList @("--skip-config", "start", "--always-new-process", "--class", "horde-iso") `
        -WindowStyle Minimized
    $launcherInfo = $null
    if ($launcher) { $launcherInfo = Get-HordeProcessInfo -Id $launcher.Id }

    $sockDir = Join-Path $env:USERPROFILE ".local\share\wezterm"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        foreach ($g in @(Get-HordeProcessTable | Where-Object { $_.name -eq "wezterm-gui.exe" })) {
            if (-not $launcher -or $g.ppid -ne $launcher.Id) { continue }
            if ($g.created -lt $launchedAt.AddSeconds(-1)) { continue }
            $sock = Join-Path $sockDir ("gui-sock-" + $g.pid)
            if (-not (Test-Path -LiteralPath $sock)) { continue }

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
                    # registry. Horde's own state, at least, goes somewhere throwaway for the instance's life.
                    $store = Join-Path $env:TEMP ("horde-iso-store-" + $g.pid)
                    New-Item -ItemType Directory -Force -Path $store -ErrorAction Stop | Out-Null
                    $env:HORDE_ROOT = $store
                    return [pscustomobject]@{
                        pid = $g.pid; created = $g.created; socket = $sock; store = $store
                        launcherPid = $launcher.Id; launcherCreated = $(if ($launcherInfo) { $launcherInfo.created } else { $null })
                        originalSocket = $origSocket; originalRoot = $origRoot
                        token = (New-HordeInstanceToken -GuiPid $g.pid -Created $g.created)
                    }
                }
                # Not answering yet. UNPIN rather than leave this process aimed at a half-open socket,
                # which is the state in which a "safe" call quietly reaches the user's terminal instead.
                $env:WEZTERM_UNIX_SOCKET = $origSocket
            } catch {
                $env:WEZTERM_UNIX_SOCKET = $origSocket
                $env:HORDE_ROOT = $origRoot
                [void](Stop-HordeProcessIfSame -Id $g.pid -Created $g.created)
                throw
            }
        }
        Start-Sleep -Milliseconds 500
    }

    # TIMED OUT. The terminal may still come up after we stop waiting, and nobody would hold it, so the
    # launch is torn down now - identified by creation time, never by pid alone.
    $env:WEZTERM_UNIX_SOCKET = $origSocket
    if ($launcherInfo) {
        foreach ($d in @(Get-HordeDescendantPids -RootPid $launcherInfo.pid)) { [void](Stop-HordeProcessIfSame -Id $d.pid -Created $d.created) }
        [void](Stop-HordeProcessIfSame -Id $launcherInfo.pid -Created $launcherInfo.created)
    }
    return $null
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
    # WHY CHILDREN ARE CHECKED. On 2026-09-29 two isolated instances "and their claude sessions"
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
    # did not exist, so no check inside it ever ran. test/test-isolation.ps1 guards that class.
    param($Instance)
    $verdict = { param($stopped, $survived, $killed, $still, $sockOk, $refused, $reason, $id)
        [pscustomobject]@{ stopped = $stopped; pid = $id; survived = $survived; orphansKilled = @($killed)
                           orphansSurvived = @($still); socketRemoved = $sockOk; refused = $refused; reason = $reason } }

    if (-not $Instance) {
        return (& $verdict $false $false @() @() $false $true "no instance was passed - nothing was stopped and nothing was verified" -1)
    }
    $expect = $null
    if ($Instance.created) { $expect = New-HordeInstanceToken -GuiPid $Instance.pid -Created $Instance.created }
    if (-not $Instance.token -or $Instance.token -ne $expect) {
        return (& $verdict $false $false @() @() $false $true "not an instance this harness started (no valid token) - refusing to kill anything" $Instance.pid)
    }

    # UNPIN FIRST, so nothing after this point talks to a socket whose server is about to die, and give
    # Horde its real store back. (The first version's comment said "unpin first" and its code did it
    # after the kill.)
    $env:WEZTERM_UNIX_SOCKET = $Instance.originalSocket
    $env:HORDE_ROOT = $Instance.originalRoot

    # Descendants are recorded BEFORE the kill: once the gui is gone its children's parent link
    # points at nothing that can be walked.
    $descendants = @(Get-HordeDescendantPids -RootPid $Instance.pid)
    $gui = Stop-HordeProcessIfSame -Id $Instance.pid -Created $Instance.created
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $now = Get-HordeProcessInfo -Id $Instance.pid
        if (-not $now -or $now.created -ne $Instance.created) { break }
        Start-Sleep -Milliseconds 200
    }
    $nowGui = Get-HordeProcessInfo -Id $Instance.pid
    $survived = [bool]($nowGui -and $nowGui.created -eq $Instance.created)

    # Anything that outlived its terminal is killed now - each by pid AND creation time - and whatever
    # still will not die is reported by pid rather than assumed gone.
    $killed = @(); $still = @()
    foreach ($d in $descendants) {
        $r = Stop-HordeProcessIfSame -Id $d.pid -Created $d.created
        if ($r -eq "killed") { $killed += $d.pid }
        if ($r -eq "survived") { $still += $d.pid }
    }

    # The socket file outlives its process; left behind, the runtime directory collects one dead
    # socket per run. Only OUR socket, named by the verified token's pid.
    $socketRemoved = $true
    if (Test-Path -LiteralPath $Instance.socket) {
        Remove-Item -LiteralPath $Instance.socket -Force -ErrorAction SilentlyContinue
        $socketRemoved = -not (Test-Path -LiteralPath $Instance.socket)
    }
    if ($Instance.store -and (Test-Path -LiteralPath $Instance.store)) {
        Remove-Item -LiteralPath $Instance.store -Recurse -Force -ErrorAction SilentlyContinue
    }

    # SAY IT WHERE A HUMAN WILL SEE IT. A leaked instance can be holding a real agent session.
    if ($survived -or $still.Count -gt 0) {
        Write-Host ("  ISOLATED INSTANCE LEAKED: gui " + $Instance.pid + " survived=" + $survived +
                    ", processes that would not die: " + ($still -join ", ") + ". Kill them by hand.") -ForegroundColor Red
    }
    $reason = ""
    if ($survived) { $reason = "the terminal outlived a 10s wait" }
    elseif ($still.Count -gt 0) { $reason = "processes that ran inside it would not die" }
    return (& $verdict (-not $survived -and $still.Count -eq 0) $survived $killed $still $socketRemoved $false $reason $Instance.pid)
}
