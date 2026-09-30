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

function Get-HordeWeztermGuiPids {
    # Every running wezterm-gui process id, as strings. Diffed before and after a launch to find the
    # instance we started, because WezTerm offers no other way to learn a new instance's pid.
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
    # EXACTLY ONE WINDOW is the signal that tells a fresh instance from a working terminal. It is a
    # heuristic and is named as one: a user with a single WezTerm window would not trip it, which is
    # why Assert-HordeIsolated checks the socket first and this second.
    param($Panes)
    $p = @($Panes | Where-Object { $null -ne $_ })
    if ($p.Count -eq 0) { return "no panes at all - that is unknown, not empty" }
    $windows = @($p | ForEach-Object { "$($_.window_id)" } | Sort-Object -Unique)
    if ($windows.Count -gt 1) { return "$($p.Count) panes across $($windows.Count) windows - this looks like the user's terminal" }
    return $null
}

function Start-HordeIsolatedWezterm {
    # Launch a WezTerm instance that is ours alone, pin this process to it, and point Horde's own
    # state at a throwaway store. Returns the instance, or $null if nothing answered in time.
    #
    # THE INSTANCE CARRIES WHAT MUST BE RESTORED, instead of a script-wide variable. The original kept
    # the saved socket in one shared variable, so a second harness started in the same process would
    # overwrite the first one's and teardown would restore the wrong value.
    param([int]$TimeoutSeconds = 30)

    $before = @{}
    foreach ($id in (Get-HordeWeztermGuiPids)) { $before[$id] = $true }
    $origSocket = $env:WEZTERM_UNIX_SOCKET
    $origRoot = $env:HORDE_ROOT

    # --always-new-process stops it attaching to the running GUI, which would defeat the point.
    # --skip-config is LOAD-BEARING: the user's wezterm.lua loads a session-restore plugin that, on a
    # fresh mux, either restores copies of their real sessions inside the test terminal or sits on a
    # modal prompt that looks exactly like a timeout.
    Start-Process -FilePath "wezterm" `
        -ArgumentList @("--skip-config", "start", "--always-new-process", "--class", "horde-iso") `
        -WindowStyle Minimized | Out-Null

    $sockDir = Join-Path $env:USERPROFILE ".local\share\wezterm"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        foreach ($id in (Get-HordeWeztermGuiPids)) {
            if ($before.ContainsKey($id)) { continue }
            $sock = Join-Path $sockDir ("gui-sock-" + $id)
            if (-not (Test-Path -LiteralPath $sock)) { continue }

            # THE PIN IS WEZTERM_UNIX_SOCKET, NOT --class. Inside any WezTerm pane this variable is
            # already set, and the CLI follows it and ignores --class. Measured on the system this
            # replaces: pinned, 1 pane visible; unpinned, 13. It is inherited by children, so every
            # wezterm call a test makes afterwards is pinned without being told.
            $env:WEZTERM_UNIX_SOCKET = $sock
            $probe = & wezterm cli list --format json 2>$null
            if ($LASTEXITCODE -eq 0 -and $probe) {
                # A SEPARATE MUX DOES NOT SEPARATE THE STORES. On the old system a real session started
                # in an isolated instance still wrote into the user's real pane-sessions and registry.
                # Horde's own state, at least, goes somewhere throwaway for the life of the instance.
                $store = Join-Path $env:TEMP ("horde-iso-store-" + $id)
                New-Item -ItemType Directory -Force -Path $store | Out-Null
                $env:HORDE_ROOT = $store
                return [pscustomobject]@{
                    pid = [int]$id; socket = $sock; store = $store
                    originalSocket = $origSocket; originalRoot = $origRoot
                }
            }
            # Not answering yet. UNPIN rather than leave this process aimed at a half-open socket,
            # which is the state in which a "safe" call quietly reaches the user's terminal instead.
            $env:WEZTERM_UNIX_SOCKET = $origSocket
        }
        Start-Sleep -Milliseconds 500
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
    # The socket's own name carries its GUI's pid. If it does not match the instance, this is not the
    # terminal we started, whatever the variable says.
    if ((Split-Path -Leaf "$($Instance.socket)") -ne ("gui-sock-" + $Instance.pid)) {
        throw "not isolated: socket '$($Instance.socket)' does not belong to pid $($Instance.pid)"
    }
    $raw = & wezterm cli list --format json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { throw "not isolated: the instance did not answer" }
    $why = Test-HordeIsolationPanes -Panes (ConvertFrom-HordeWeztermJson -Raw $raw)
    if ($why) { throw "not isolated: $why" }
    return @(ConvertFrom-HordeWeztermJson -Raw $raw).Count
}

function Get-HordeDescendantPids {
    # Every process descended from a pid, found by walking parent links. Taken BEFORE a kill, because
    # once the parent is gone its children's parent link points at nothing and they can no longer be
    # found this way.
    param([int]$RootPid)
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Select-Object ProcessId, ParentProcessId)
    $out = New-Object System.Collections.ArrayList
    $frontier = @($RootPid)
    while ($frontier.Count -gt 0) {
        $next = @()
        foreach ($p in $frontier) {
            foreach ($c in @($all | Where-Object { $_.ParentProcessId -eq $p -and $_.ProcessId -ne $p })) {
                if (-not $out.Contains([int]$c.ProcessId)) { [void]$out.Add([int]$c.ProcessId); $next += [int]$c.ProcessId }
            }
        }
        $frontier = $next
    }
    return @($out)
}

function Stop-HordeIsolatedWezterm {
    # TEAR THE INSTANCE DOWN AND PROVE IT WENT - the GUI, and everything that ran inside it.
    #
    # Returns { stopped; pid; survived; orphansKilled; orphansSurvived; socketRemoved; reason } so a
    # caller asserts rather than hopes.
    #
    # WHY CHILDREN ARE CHECKED, which the original did not do. On 2026-09-29 two isolated instances
    # "and their claude sessions" survived their probe runs - about 590 MB, found an hour later by
    # reading the process list. The same day, killing an editor left the agent session inside it
    # alive and beyond the reach of every kill mechanism tried. Killing a terminal is not evidence
    # that what ran in it died. So descendants are recorded before the kill and checked after it.
    #
    # MEASURED 2026-09-29, and it narrowed the worry without removing it: killing THIS instance's
    # wezterm-gui took its children with it - the end-to-end test found a long-lived child inside the
    # instance's tree before the kill and nothing afterwards. So the old system's 590 MB leak was the
    # teardown never running, not children outliving it. The check stays anyway, because the editor
    # measured the same day did leave an agent running, and hosts differ.
    #
    # And the original's actual fault that night was a NAME: a probe called a teardown function that
    # did not exist, so no check inside it ever ran. test/test-isolation.ps1 guards that class by
    # failing if any script that starts an instance does not also call this function by name.
    param($Instance)
    if (-not $Instance) {
        return [pscustomobject]@{ stopped = $false; pid = -1; survived = $false; orphansKilled = @(); orphansSurvived = @()
                                  socketRemoved = $false; reason = "no instance was passed - nothing was stopped and nothing was verified" }
    }

    $descendants = @(Get-HordeDescendantPids -RootPid $Instance.pid)

    try { Stop-Process -Id $Instance.pid -Force -ErrorAction SilentlyContinue } catch { }

    # UNPIN FIRST, so nothing after this point talks to a socket whose server is dying, and give
    # Horde its real store back.
    $env:WEZTERM_UNIX_SOCKET = $Instance.originalSocket
    $env:HORDE_ROOT = $Instance.originalRoot

    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline -and (Get-Process -Id $Instance.pid -ErrorAction SilentlyContinue)) {
        Start-Sleep -Milliseconds 200
    }
    $survived = [bool](Get-Process -Id $Instance.pid -ErrorAction SilentlyContinue)

    # Anything that outlived its terminal is killed now, and whatever still will not die is reported
    # by pid rather than assumed gone.
    $killed = @()
    foreach ($d in $descendants) {
        if (Get-Process -Id $d -ErrorAction SilentlyContinue) {
            try { Stop-Process -Id $d -Force -ErrorAction SilentlyContinue } catch { }
            $killed += $d
        }
    }
    if ($killed.Count -gt 0) { Start-Sleep -Milliseconds 500 }
    $still = @($killed | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })

    # The socket file outlives its process; left behind, the runtime directory collects one dead
    # socket per run.
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
    return [pscustomobject]@{
        stopped = (-not $survived -and $still.Count -eq 0); pid = $Instance.pid; survived = $survived
        orphansKilled = $killed; orphansSurvived = $still; socketRemoved = $socketRemoved; reason = $reason
    }
}
