# END TO END: Escape in the decisions window hands the keyboard back to the WezTerm window it stands
# beside - against a terminal this scenario starts, never the one in use.
#
# The person answers in the window and is done: Escape, and he is typing in the terminal again. Through
# the real command run as its own process: the window is found attached to this scenario's own
# terminal window (the composition e2e-decisions-window-attached.ps1 beside this file proves, and
# which is only relied on here), a REAL Escape is pressed in its page by the surface's own input
# (decisions/Window.ps1, -Probe: the engine makes the key, nothing is sent to the desktop), the page
# asks Horde to hand the keyboard back, and Horde asks Windows to make the terminal window the
# foreground one. WHAT WINDOWS THEN DID IS READ FROM OUTSIDE, by this process: the desktop's
# foreground window.
#
# THIS SCENARIO CAN MOVE THE KEYBOARD AWAY FROM THE PERSON AT THE MACHINE, AND SAYS SO. Each run
# asks Windows to move it at most twice, and only to windows of its own: to the Horde window (THE
# CONTROL), then - Escape's ask, the thing being proved - to its own terminal window, which stands
# where no screen is until it is ended a moment later. Nothing is restored by force: when that
# terminal ends, Windows gives the keyboard to a window of its choosing. Not a scenario to run in a loop.
#
# THE CONTROL IS THE REALISTIC CASE: the person presses Escape while the Horde window has the
# keyboard, so the process that asks Windows (the command's own, where the follow port runs) owns the
# foreground window, which is the first thing Windows lets do it (SetForegroundWindow, "the calling
# process is the foreground process"). So before Escape this scenario makes the Horde window the
# foreground one, and checks from outside that it is and that its process is the command's. Windows
# lets THIS process do that only under its own rules - as a rule, when the person has given no input
# for ForegroundLockTimeout (200000 ms on the measuring machine) - and when it will not, nothing is done
# to get round it: THE CONTROL IS SKIPPED IN WORDS, the rest still runs (the key, the page's ask,
# Horde's ask, and that what Horde says happened is what is seen from outside), the last line says
# the hand-over was not proved, and the exit is 3, not 0. With the control set, a refusal is a FAILURE.
# THE TEST TERMINAL MAY TAKE THE KEYBOARD WHEN IT STARTS, and the scenario prints whether it did. Read
# in WezTerm 20240203's source: the gui's window is shown with ShowWindow(SW_NORMAL), which activates
# it whenever Windows allows a new process to take the foreground (the same lock timeout); its focus()
# (SendInput of Alt, then SetForegroundWindow) is called only by window-activation actions, not at
# creation. The gui is started by the wezterm launcher, which hands it no show state of ours, so no
# option of the launch (test/Isolation.ps1) keeps it from that.
# MEASURED 2026-10-07, before the control, the person typing in another window: Windows said no
# (SetForegroundWindow answered false), the foreground window was the one it had been, and Horde
# answered "refused" in those words. MEASURED 2026-10-08, before the control: the test terminal had
# taken the keyboard when it started, so the "handed" Horde answered proved nothing.
#
# ISOLATION (CONTRIBUTING 3), as the scenario beside this one: an instance of its own, nothing done
# before Assert-HordeIsolated has measured that this process sees only that instance's panes, every
# gui's pid listed before and after. The command reads nothing of this machine's fleet: its home, its
# registry and its profile are folders of this scenario's.
#
# Standing free, Escape does nothing: test/e2e/e2e-decisions-answering-keys.ps1 proves that, with no
# terminal at all.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
$work = Join-Path $env:TEMP ("horde-e2e-escape-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$hordeHome = Join-Path $work "home"
$env:HORDE_HOME = $hordeHome
. (Join-Path (Split-Path -Parent $here) "Isolation.ps1")
. (Join-Path $root "core\Tristate.ps1")
. (Join-Path $root "hosts\wezterm\Window.ps1")
. (Join-Path $root "test\lib\WindowProbe.ps1")

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond -is [bool] -and $Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }
function Wait-Until { param([scriptblock]$Cond, [int]$Seconds) $d = (Get-Date).AddSeconds($Seconds); while ((Get-Date) -lt $d) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 200 }; return [bool](& $Cond) }
function Get-Foreground { return [HordeProbe.Native]::GetForegroundWindow().ToInt64() }
$noOrder = 0x0004; $noActivate = 0x0010
# The one call this scenario makes to move the keyboard: to the Horde window, its own (THE CONTROL).
Add-Type -Namespace HordeEscapeProbe -Name Native -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);'

$guisBefore = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Write-Host ("  the gui processes running before this scenario: " + $guisBefore) -ForegroundColor DarkGray
$open = $null
$script:controlSet = $false
$script:controlReason = "the scenario did not reach the control"
$report = Join-Path $work "report.json"
$probe = Join-Path $work "probe.json"

$iso = Start-HordeIsolatedWezterm -TimeoutSeconds 45
Check ($null -ne $iso) "an isolated instance started and answered"
if ($iso) {
    $result = $null
    try {
        $count = Assert-HordeIsolated -Instance $iso
        Check ($count -ge 1) ("THE CONTROL: this process can see only the isolated instance's panes (" + $count + ")")
        Check (@($guisBefore -split "," | Where-Object { $_ -ne "" }) -notcontains ("" + $iso.pid)) "the instance's gui is a process that was not running before"
        $instance = Split-Path -Leaf $iso.socket
        $panes = @(ConvertFrom-HordeWeztermJson (Invoke-HordeWeztermCli -Rest @("list", "--format", "json")))
        $paneOne = "" + $panes[0].pane_id
        Check ((Wait-Until { @(Get-HordeWeztermNativeWindows -ProcessId $iso.pid).Count -eq 1 } 20)) "the instance has one window"
        $terminal = [long]@(Get-HordeWeztermNativeWindows -ProcessId $iso.pid)[0].handle
        [void][HordeProbe.Native]::SetWindowPos([IntPtr]$terminal, [IntPtr]::Zero, -31000, -31000, 1040, 600, ($noOrder -bor $noActivate))
        [void][HordeProbe.Native]::ShowWindow([IntPtr]$terminal, 4)                                             # SW_SHOWNOACTIVATE
        Check ((Wait-Until { $t = Get-HordeProbeWindow -Handle $terminal; ($t.left -eq -31000 -and ($t.right - $t.left) -eq 1040) } 10)) "the test terminal's window stands where no screen is"

        $sessionId = "aaaaaaaa-0000-4000-8000-0000000000e5"
        $stand = Join-Path $work "profile"
        [void](New-HordeProbeRunningSession -Profile $stand -SessionId $sessionId -ProcessId $iso.pid)
        [void](New-HordeProbeRegistry -Root (Join-Path $work "fleet") -Records @(@{ id = $sessionId; role = "master"; pane = $paneOne; instance = $instance; lastSeen = [datetime]::UtcNow.ToString("o") }))
        New-Item -ItemType Directory -Path (Join-Path $hordeHome "settings") -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $hordeHome "settings\wezterm-window.json"), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; settings = [ordered]@{ socketFolder = (Split-Path -Parent $iso.socket) } }) -Compress))

        Write-Host ""
        Write-Host "--- 1. the window stands beside the test terminal's window ---" -ForegroundColor Cyan
        $foregroundAtStart = Get-Foreground
        $open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Report", $report, "-Probe", $probe) -Env @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $work "fleet"); USERPROFILE = $stand; PSModulePath = $null }
        $r = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 120 -Until { param($x) $null -ne $x.drawn -and $x.handle -gt 0 -and ($x.attachment.attached -eq $false -or $null -ne $x.attachment.placed) }
        Check ($null -ne $r -and $r.attachment.attached -eq $true -and $r.attachment.target -eq $terminal -and $r.attachment.follow -ceq "following") ("the window is attached to the instance's window and follows it" + $(if ($null -ne $r -and -not $r.attachment.attached) { " - NOT ATTACHED: " + $r.attachment.reason } else { "" }))
        if ($null -ne $r -and $r.attachment.attached) {
            $window = [long]$r.handle
            Check ($r.handBack.asked -eq 0 -and "$($r.drawn.foot)" -clike "*Esc: back to the terminal.") "nothing has asked for the keyboard to be handed back, and the page's last line offers Escape"
            $atAttach = Get-Foreground
            Write-Host ("  the foreground window: when this scenario began " + $foregroundAtStart + ", now " + $atAttach + " (" + $(if ($atAttach -eq $terminal) { "the test terminal took it when it started" } elseif ($atAttach -eq $window) { "the Horde window has it" } elseif ($atAttach -eq $foregroundAtStart) { "unchanged" } else { "another window" }) + ")") -ForegroundColor DarkGray

            Write-Host ""
            Write-Host "--- THE CONTROL: the Horde window has the keyboard before Escape, as when the person presses it ---" -ForegroundColor Cyan
            # The realistic case (header, THE CONTROL): the window is made the foreground one by this
            # scenario, and nothing else is done. Windows decides whether this process may; when it may
            # not, the control is skipped in words and the hand-over is not proved.
            $asked = [HordeEscapeProbe.Native]::SetForegroundWindow([IntPtr]$window)
            $before = Get-Foreground
            $byWindow = [uint32]0
            [void][HordeProbe.Native]::GetWindowThreadProcessId([IntPtr]$before, [ref]$byWindow)
            if ($before -eq $window) {
                $script:controlSet = $true
                Check ($before -ne $terminal -and [int]$byWindow -eq [int]$r.pid -and [int]$r.pid -eq [int]$open.process.Id) "THE CONTROL: before Escape the desktop's foreground window is the Horde window - the command's own process has the keyboard - and not the test terminal"
            }
            elseif ($before -eq 0) {
                # Read 2026-10-08 with the session locked (the lock screen's process running): the desktop
                # this process draws on has no foreground window, and Windows gives none of its windows the keyboard.
                $script:controlReason = ("the desktop has no foreground window at all (0), as when the session is locked or another desktop has the input, so no window of it can be given the keyboard (SetForegroundWindow answered " + $asked + ")")
                Write-Host ("  [SKIP] THE CONTROL: " + $script:controlReason) -ForegroundColor Yellow
            }
            else {
                $script:controlReason = ("Windows would not let this scenario give the Horde window the keyboard (SetForegroundWindow answered " + $asked + "; the foreground window is " + $before + "). Windows lets a process do that only while the person is not using the machine (ForegroundLockTimeout) or on behalf of the program he is using, and this scenario does nothing to get round it")
                Write-Host ("  [SKIP] THE CONTROL: " + $script:controlReason) -ForegroundColor Yellow
            }

            Write-Host ""
            Write-Host "--- 2. a real Escape in the page: the keyboard goes to the terminal window ---" -ForegroundColor Cyan
            [System.IO.File]::WriteAllText($probe, '{"n":1,"keys":[{"key":"Escape","shift":false,"ctrl":false}],"steps":[]}')
            $after = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 40 -Until { param($x) $null -ne $x.handBack -and $x.handBack.asked -ge 1 }
            $now = Get-Foreground
            Write-Host ("  what happened: asked " + $after.handBack.asked + ", handed " + $after.handBack.handed + ", the port said '" + $after.handBack.last + "'" + $(if ("$($after.handBack.reason)" -ne "") { " (" + $after.handBack.reason + ")" } else { "" }) + "; foreground before " + $before + ", after " + $now + ", terminal " + $terminal + ", window " + $window) -ForegroundColor DarkGray
            Check ($after.handBack.asked -eq 1) "one real Escape in the page, and Horde was asked once to hand the keyboard back"
            Check (@("handed", "refused") -ccontains "$($after.handBack.last)") ("the follow port asked Windows, and answered what Windows did (" + $after.handBack.last + ")")
            if ("$($after.handBack.last)" -ceq "handed") {
                Check ($now -eq $terminal -and $after.handBack.handed -eq 1) "WHAT HORDE SAYS IS WHAT HAPPENED: it says handed, and read from outside the desktop's foreground window is the test terminal's window"
                if ($script:controlSet) { Check ($before -eq $window -and $now -eq $terminal) "ESCAPE HANDED THE KEYBOARD BACK: the Horde window had it before, the test terminal's window has it after" }
                else { Write-Host "  [SKIP] ESCAPE HANDED THE KEYBOARD BACK: NOT PROVED - the Horde window did not have the keyboard before Escape" -ForegroundColor Yellow }
            }
            else {
                Check ($now -eq $before -and $after.handBack.handed -eq 0 -and "$($after.handBack.reason)" -clike "the terminal window was not given the keyboard:*") "WHAT HORDE SAYS IS WHAT HAPPENED: it says Windows refused, and from outside the foreground window is the one it was"
                if ($script:controlSet) { Check $false "ESCAPE HANDED THE KEYBOARD BACK: Windows REFUSED the ask although the Horde window had the keyboard" }
                else { Write-Host "  [SKIP] ESCAPE HANDED THE KEYBOARD BACK: NOT PROVED on this run - Windows refused the ask of a window that did not have the keyboard" -ForegroundColor Yellow }
            }
            Check ($after.attachment.attached -eq $true -and @($after.errors).Count -eq 0 -and $after.refused -eq 0) "the window is still attached, and nothing failed or was refused inside it"
        }
    }
    catch { Check $false ("the scenario stopped: " + $_.Exception.Message) }
    finally {
        # At once: while the test terminal lives it may hold the keyboard.
        $result = Stop-HordeIsolatedWezterm -Instance $iso
    }
    Check (-not $result.refused) "teardown accepted the instance Start issued"
    Check ($result.stopped -and -not $result.survived -and @($result.orphansSurvived).Count -eq 0) "the terminal and everything that ran in it are gone"
    if ($null -ne $open) {
        $lost = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 30 -Until { param($x) $x.attachment.attached -eq $false }
        if ($null -ne $lost) {
            $closed = Close-HordeProbeWindow -Process $open.process -Handle ([long]$lost.handle) -Seconds 40
            Check ($closed.exited -and $closed.code -eq 0 -and -not $closed.killed) ("asked to close, the command ends by itself and exits 0 (" + $closed.code + ")")
            Check ($open.err.Result.Trim() -ceq "") "with nothing on the error stream"
        }
    }
}
if ($null -ne $open -and -not $open.process.HasExited) { try { $open.process.Kill() } catch { } }
Start-Sleep -Milliseconds 800
$guisAfter = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Check ($guisAfter -ceq $guisBefore) ("the gui processes running are exactly those running before: " + $guisAfter)
for ($i = 0; $i -lt 20 -and (Test-Path -LiteralPath $work); $i++) { try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 } }
Check (-not (Test-Path -LiteralPath $work)) "the scenario's folder - its home, registry and profile - is removed"

Write-Host ""
if ($fails.Count -gt 0) { Write-Host ("==== " + $fails.Count + " FAILURE(S) ====") -ForegroundColor Red; foreach ($f in $fails) { Write-Host ("  - " + $f) -ForegroundColor Red }; exit 1 }
if (-not $script:controlSet) {
    Write-Host ("==== THE CONTROL WAS SKIPPED: " + $script:controlReason + ". THE HAND-OVER ITSELF IS NOT PROVED BY THIS RUN - EXIT 3 ====") -ForegroundColor Yellow
    exit 3
}
Write-Host "==== Escape in the decisions window hands the keyboard to the terminal window it stands beside ====" -ForegroundColor Green
exit 0
