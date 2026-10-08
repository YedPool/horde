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
# THIS SCENARIO CAN TAKE THE KEYBOARD FROM THE PERSON AT THE MACHINE, ONCE, AND SAYS SO. When Windows
# honours the ask, the foreground window becomes this scenario's own terminal window, which stands
# where no screen is, until that terminal is ended a moment later. That is the thing being proved; it
# is the last thing done before teardown, nothing is restored by force, and it is not a scenario to
# run in a loop. WHEN WINDOWS REFUSES - it gives the foreground only on behalf of a program the person
# is using, and here the key was made by the engine, not pressed by him, in a window that does not
# have the keyboard - nothing is done to get round the refusal. The scenario then still holds
# everything up to Windows' answer (the key, the page's ask, Horde's ask, and that what Horde says
# happened is what is seen from outside), SAYS IN ITS LAST LINE THAT THE HAND-OVER ITSELF WAS NOT
# PROVED, and exits 3, not 0.
# MEASURED 2026-10-07, the first run, with the person typing in another window: Windows said no
# (SetForegroundWindow answered false), the foreground window was the one it had been, and Horde
# answered "refused" in those words. The hand-over with the keyboard really in the companion - a
# person's own Escape - is not proved by any run yet.
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

$guisBefore = (@(Get-HordeWeztermGuiPids | Sort-Object) -join ",")
Write-Host ("  the gui processes running before this scenario: " + $guisBefore) -ForegroundColor DarkGray
$open = $null
$script:handed = $false
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
        Write-Host "--- 1. the window stands beside the test terminal's window, and nobody's keyboard was taken ---" -ForegroundColor Cyan
        $foregroundAtStart = Get-Foreground
        $open = Start-HordeProbeCommand -Root $root -HordeArgs @("decisions", "open", "-Report", $report, "-Probe", $probe) -Env @{ HORDE_HOME = $hordeHome; WEZFLEET_ROOT = (Join-Path $work "fleet"); USERPROFILE = $stand; PSModulePath = $null }
        $r = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 120 -Until { param($x) $null -ne $x.drawn -and $x.handle -gt 0 -and ($x.attachment.attached -eq $false -or $null -ne $x.attachment.placed) }
        Check ($null -ne $r -and $r.attachment.attached -eq $true -and $r.attachment.target -eq $terminal -and $r.attachment.follow -ceq "following") ("the window is attached to the instance's window and follows it" + $(if ($null -ne $r -and -not $r.attachment.attached) { " - NOT ATTACHED: " + $r.attachment.reason } else { "" }))
        if ($null -ne $r -and $r.attachment.attached) {
            $window = [long]$r.handle
            $before = Get-Foreground
            Check ($before -ne $terminal -and $before -ne $window) "THE CONTROL: before Escape the desktop's foreground window is neither the test terminal nor the Horde window"
            Check ($r.handBack.asked -eq 0 -and "$($r.drawn.foot)" -clike "*Esc: back to the terminal.") "nothing has asked for the keyboard to be handed back, and the page's last line offers Escape"

            Write-Host ""
            Write-Host "--- 2. a real Escape in the page: the keyboard goes to the terminal window ---" -ForegroundColor Cyan
            [System.IO.File]::WriteAllText($probe, '{"n":1,"keys":[{"key":"Escape","shift":false,"ctrl":false}],"steps":[]}')
            $after = Wait-HordeProbeReport -Path $report -Process $open.process -Seconds 40 -Until { param($x) $null -ne $x.handBack -and $x.handBack.asked -ge 1 }
            $now = Get-Foreground
            Write-Host ("  what happened: asked " + $after.handBack.asked + ", handed " + $after.handBack.handed + ", the port said '" + $after.handBack.last + "'" + $(if ("$($after.handBack.reason)" -ne "") { " (" + $after.handBack.reason + ")" } else { "" }) + "; foreground before " + $before + ", after " + $now + ", terminal " + $terminal + ", window " + $window) -ForegroundColor DarkGray
            Check ($after.handBack.asked -eq 1) "one real Escape in the page, and Horde was asked once to hand the keyboard back"
            Check (@("handed", "refused") -ccontains "$($after.handBack.last)") ("the follow port asked Windows, and answered what Windows did (" + $after.handBack.last + ")")
            if ("$($after.handBack.last)" -ceq "handed") {
                $script:handed = $true
                Check ($now -eq $terminal -and $after.handBack.handed -eq 1) "ESCAPE HANDED THE KEYBOARD BACK: read from outside, the desktop's foreground window is the test terminal's window"
            }
            else {
                Check ($now -eq $before -and $after.handBack.handed -eq 0 -and "$($after.handBack.reason)" -clike "the terminal window was not given the keyboard:*") "WHAT HORDE SAYS IS WHAT HAPPENED: it says Windows refused, and from outside the foreground window is the one it was"
                Write-Host "  [SKIP] ESCAPE HANDED THE KEYBOARD BACK: NOT PROVED on this run - Windows refused the ask of a window that did not have the keyboard" -ForegroundColor Yellow
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
if (-not $script:handed) {
    Write-Host "==== ESCAPE'S ASK REACHED WINDOWS AND WAS REFUSED, as Horde said in words; THE HAND-OVER ITSELF IS NOT PROVED BY THIS RUN - EXIT 3 ====" -ForegroundColor Yellow
    exit 3
}
Write-Host "==== Escape in the decisions window hands the keyboard to the terminal window it stands beside ====" -ForegroundColor Green
exit 0
