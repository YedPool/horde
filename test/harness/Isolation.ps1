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
    #
    # AND THE ROOT ITSELF IS IDENTIFIED BY CREATION TIME, which is required. The re-review found the
    # rule above protected every level BUT the root: if our terminal had died and its pid been reused,
    # the walk started from whoever held that pid now and returned THAT process's children - and they
    # passed the same-process check, because their creation times came from the same fresh table.
    # So when the live owner of the root pid is not the recorded root, only processes that were
    # created while OUR root lived - after it, and before the new owner - are its orphaned children.
    param([int]$RootPid, [Parameter(Mandatory = $true)]$RootCreated, $Processes = $null)
    $all = $Processes
    if ($null -eq $all) { $all = Get-HordeProcessTable }
    $all = @($all)
    $out = New-Object System.Collections.ArrayList
    $seen = @{ "$RootPid" = $true }
    $owner = @($all | Where-Object { $_.pid -eq $RootPid }) | Select-Object -First 1
    if ($owner -and $owner.created -eq $RootCreated) {
        $frontier = @($owner)
    } else {
        # Our root is gone. Its orphans still record its pid; a newer owner's children record it too,
        # and are told apart by being created after that owner.
        $firstGen = @($all | Where-Object {
            $_.ppid -eq $RootPid -and $_.pid -ne $RootPid -and $_.created -ge $RootCreated -and
            (-not $owner -or $_.created -lt $owner.created) })
        foreach ($c in $firstGen) { $seen["$($c.pid)"] = $true; [void]$out.Add([pscustomobject]@{ pid = $c.pid; created = $c.created }) }
        $frontier = $firstGen
    }
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
    param([int]$Id, $Created)
    if ($null -eq $Created) { return "not-same" }
    $p = $null
    try { $p = [System.Diagnostics.Process]::GetProcessById($Id) } catch { return "gone" }
    try {
        try { $null = $p.Handle } catch { return "cannot-open" }
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
$script:HordeIsoStarted = @{}

function Register-HordeIsolatedInstance {
    # Record an instance as started by this process, and return its token.
    param([int]$GuiPid, $Created, [string]$Socket, [string]$Store = "")
    $token = "horde-iso:" + $GuiPid + ":" + (Get-HordeMicroseconds $Created) + ":" + [guid]::NewGuid().ToString("N")
    $script:HordeIsoStarted[$token] = [pscustomobject]@{ pid = $GuiPid; created = $Created; socket = $Socket; store = $Store }
    return $token
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
            if (-not $launcher -or -not $launcherInfo -or $g.ppid -ne $launcher.Id) { continue }
            if ($g.created -lt $launchedAt.AddSeconds(-1)) { continue }
            # AND CREATED NO EARLIER THAN OUR LAUNCHER. A gui whose recorded parent pid is our launcher's
            # but which predates it has a parent that was a different process holding that pid.
            if ($g.created -lt $launcherInfo.created) { continue }
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
                        token = (Register-HordeIsolatedInstance -GuiPid $g.pid -Created $g.created -Socket $sock -Store $store)
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
        foreach ($d in @(Get-HordeDescendantPids -RootPid $launcherInfo.pid -RootCreated $launcherInfo.created)) { [void](Stop-HordeProcessIfSame -Id $d.pid -Created $d.created) }
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
    $env:WEZTERM_UNIX_SOCKET = $Instance.originalSocket
    $env:HORDE_ROOT = $Instance.originalRoot

    # Descendants are recorded BEFORE the kill: once the gui is gone its children's parent link
    # points at nothing that can be walked. The walk starts from OUR root by creation time, so a
    # reused pid cannot hand it someone else's children.
    $descendants = @(Get-HordeDescendantPids -RootPid $gpid -RootCreated $gcreated)
    $gui = Stop-HordeProcessIfSame -Id $gpid -Created $gcreated
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
    $killed = @(); $still = @()
    foreach ($d in $descendants) {
        $r = Stop-HordeProcessIfSame -Id $d.pid -Created $d.created
        if ($r -eq "killed") { $killed += $d.pid }
        if ($r -eq "survived") { $still += $d.pid }
    }

    # The socket file outlives its process; left behind, the runtime directory collects one dead
    # socket per run. ONLY OUR SOCKET: the one the registry recorded, and only if it really is
    # gui-sock-<our pid> in WezTerm's own socket folder. The first version deleted whatever path the
    # instance object named, which the re-review flagged: teardown could be steered into deleting a
    # file that was never ours.
    $sockDir = [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE ".local\share\wezterm"))
    $ourSock = "$($known.socket)"
    $sockOk = ($ourSock -and (Split-Path -Leaf $ourSock) -eq ("gui-sock-" + $gpid) -and
               [string]::Equals([System.IO.Path]::GetFullPath((Split-Path -Parent $ourSock)), $sockDir, [System.StringComparison]::OrdinalIgnoreCase))
    $socketRemoved = $true
    if ($sockOk -and (Test-Path -LiteralPath $ourSock)) {
        Remove-Item -LiteralPath $ourSock -Force -ErrorAction SilentlyContinue
        $socketRemoved = -not (Test-Path -LiteralPath $ourSock)
    } elseif (-not $sockOk -and $ourSock -and (Test-Path -LiteralPath $ourSock)) {
        $socketRemoved = $false
    }
    # The same for the throwaway store: only the one Start made, horde-iso-store-<our pid> in TEMP.
    $ourStore = "$($known.store)"
    $storeOk = ($ourStore -and (Split-Path -Leaf $ourStore) -eq ("horde-iso-store-" + $gpid) -and
                [string]::Equals([System.IO.Path]::GetFullPath((Split-Path -Parent $ourStore)), [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase))
    if ($storeOk -and (Test-Path -LiteralPath $ourStore)) {
        Remove-Item -LiteralPath $ourStore -Recurse -Force -ErrorAction SilentlyContinue
    }

    # A token is used once. Leaving it registered would let a stale object be torn down twice.
    $script:HordeIsoStarted.Remove("$($Instance.token)")

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
