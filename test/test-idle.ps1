# IS "IDLE OR NIGHT" ANSWERED RIGHT AT EVERY EDGE, AND DOES `horde idle` SAY IT WITH THE RIGHT EXIT CODE?
#
# core/IdleState.ps1 and cli/commands/idle.ps1 (T-0331; the founder's rule of 2026-10-22: suites, guards,
# mutation runs and reviews start only after 10 minutes without input, or from 22:00 to 07:00 local).
# The clock and the input reader are injected, so no real wait and no real input is needed: 21:59 and
# 22:00, 06:59 and 07:00, 599 s and 600 s, an unreadable input clock by day and by night, a reader that
# throws, the settings file (defaults, a custom one, a refused one), the wait with a fake clock, and the
# real command line in a process of its own with a HORDE_HOME of its own.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\IdleState.ps1")

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-idle-test-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
function New-Home {
    param([string]$Tag, [string]$Json = "")
    $h = Join-Path $work $Tag
    [void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings"))
    if ($Json -ne "") { [System.IO.File]::WriteAllText((Join-Path $h "settings\idle.json"), $Json) }
    return $h
}
function At { param([string]$Clock) $v = [datetime]("2026-10-22 " + $Clock); return { $v }.GetNewClosure() }
function Known { param([int]$S) $v = $S; return { [pscustomobject]@{ state = "known"; seconds = $v; reason = "" } }.GetNewClosure() }
$unknown = { [pscustomobject]@{ state = "unknown"; seconds = 0; reason = "fake: no interactive session" } }

try {
    $cfgHome = New-Home "defaults"
    $cfg = Get-HordeIdleConfig -HordeHome $cfgHome
    Write-Host ""
    Write-Host "--- the settings: defaults, a custom file, a refused file ---" -ForegroundColor Cyan
    Check ($cfg.ok -and $cfg.idleSeconds -eq 600 -and $cfg.nightStartHour -eq 22 -and $cfg.nightEndHour -eq 7) "no file: 600 s, night 22 to 7"
    $c2 = Get-HordeIdleConfig -HordeHome (New-Home "custom" '{ "schemaVersion": 1, "settings": { "idleSeconds": 300, "nightStartHour": 23, "nightEndHour": 5 } }')
    Check ($c2.ok -and $c2.idleSeconds -eq 300 -and $c2.nightStartHour -eq 23 -and $c2.nightEndHour -eq 5) "a file overrides each of the three"
    $c3 = Get-HordeIdleConfig -HordeHome (New-Home "bad" '{ "schemaVersion": 1, "settings": { "idleSeconds": 0 } }')
    Check (-not $c3.ok -and ($c3.findings -join " ") -like "*idleSeconds*") "an out-of-range value refuses the file, naming the key, and no default stands in"
    $c4 = Get-HordeIdleConfig -HordeHome (New-Home "unknownkey" '{ "schemaVersion": 1, "settings": { "idleMinutes": 5 } }')
    Check (-not $c4.ok) "a key that is not declared refuses the file"

    Write-Host ""
    Write-Host "--- the night hour: both ends of 22 to 7, and the other shapes ---" -ForegroundColor Cyan
    Check ((Test-HordeNightHour -Hour 21) -eq $false) "21 (21:59) is day"
    Check ((Test-HordeNightHour -Hour 22) -eq $true) "22 (22:00) is night"
    Check ((Test-HordeNightHour -Hour 23) -eq $true -and (Test-HordeNightHour -Hour 0) -eq $true -and (Test-HordeNightHour -Hour 3) -eq $true) "23, 0 and 3 are night"
    Check ((Test-HordeNightHour -Hour 6) -eq $true) "6 (06:59) is night"
    Check ((Test-HordeNightHour -Hour 7) -eq $false) "7 (07:00) is day"
    Check ((Test-HordeNightHour -Hour 12) -eq $false) "noon is day"
    Check ((Test-HordeNightHour -Hour 2 -Start 1 -End 5) -eq $true -and (Test-HordeNightHour -Hour 5 -Start 1 -End 5) -eq $false -and (Test-HordeNightHour -Hour 0 -Start 1 -End 5) -eq $false) "a night that does not cross midnight (1 to 5)"
    Check ((Test-HordeNightHour -Hour 9 -Start 4 -End 4) -eq $false) "start equal to end is no night"
    $all = $true; foreach ($h in 0..23) { if (-not (Test-HordeNightHour -Hour $h -Start 0 -End 24)) { $all = $false } }
    Check $all "0 to 24 is every hour"

    Write-Host ""
    Write-Host "--- the state at the edges of the clock and of the idle seconds ---" -ForegroundColor Cyan
    $s = Get-HordeIdleState -Config $cfg -Now (At "21:59:00") -Reader (Known 599)
    Check ($s.allowed -eq $false -and $s.why -ceq "busy") "21:59, 599 s: not allowed (busy)"
    $s = Get-HordeIdleState -Config $cfg -Now (At "21:59:00") -Reader (Known 600)
    Check ($s.allowed -eq $true -and $s.why -ceq "idle") "21:59, 600 s: allowed (idle)"
    $s = Get-HordeIdleState -Config $cfg -Now (At "22:00:00") -Reader (Known 0)
    Check ($s.allowed -eq $true -and $s.why -ceq "night" -and $s.night) "22:00, 0 s: allowed (night)"
    $s = Get-HordeIdleState -Config $cfg -Now (At "06:59:59") -Reader (Known 0)
    Check ($s.allowed -eq $true -and $s.why -ceq "night") "06:59, 0 s: allowed (night)"
    $s = Get-HordeIdleState -Config $cfg -Now (At "07:00:00") -Reader (Known 599)
    Check ($s.allowed -eq $false -and $s.why -ceq "busy" -and $s.night -eq $false) "07:00, 599 s: not allowed"
    $s = Get-HordeIdleState -Config $cfg -Now (At "07:00:00") -Reader (Known 600)
    Check ($s.allowed -eq $true -and $s.why -ceq "idle") "07:00, 600 s: allowed (idle)"
    $s = Get-HordeIdleState -Config $cfg -Now (At "13:05:09") -Reader (Known 4000)
    Check ($s.time -ceq "13:05:09" -and $s.idleSeconds -eq 4000 -and $s.needSeconds -eq 600 -and $s.idleKnown) "the state carries the time, the seconds and the threshold it used"

    Write-Host ""
    Write-Host "--- an input clock that cannot be read is NOT idle, unless it is night ---" -ForegroundColor Cyan
    $s = Get-HordeIdleState -Config $cfg -Now (At "12:00:00") -Reader $unknown
    Check ($s.allowed -eq $false -and $s.why -ceq "unknown" -and -not $s.idleKnown -and $null -eq $s.idleSeconds) "by day, unknown is not allowed"
    Check ($s.reason -like "*interactive session*") "and it says why"
    $s = Get-HordeIdleState -Config $cfg -Now (At "23:30:00") -Reader $unknown
    Check ($s.allowed -eq $true -and $s.why -ceq "night") "by night, unknown is allowed (night needs no reading)"
    $s = Get-HordeIdleState -Config $cfg -Now (At "12:00:00") -Reader { throw "boom" }
    Check ($s.allowed -eq $false -and $s.why -ceq "unknown" -and $s.reason -like "*boom*") "a reader that throws is unknown, never an allowance"
    $s = Get-HordeIdleState -Config $cfg -Now (At "12:00:00") -Reader { $null }
    Check ($s.allowed -eq $false -and $s.why -ceq "unknown") "a reader that answers nothing is unknown"
    $lines = Format-HordeIdleState -State (Get-HordeIdleState -Config $cfg -Now (At "12:00:00") -Reader $unknown)
    Check (($lines -join "|") -like "*idle seconds: unknown*|*local time: 12:00:00*|*idle-or-night: no (unknown)*not known:*") "the printed lines for unknown"
    $lines = Format-HordeIdleState -State (Get-HordeIdleState -Config $cfg -Now (At "12:00:00") -Reader (Known 700))
    Check (($lines -join "|") -ceq "idle seconds: 700 (idle means 600 or more)|local time: 12:00:00|idle-or-night: yes (idle)") ("the printed lines for idle (" + ($lines -join "|") + ")")

    Write-Host ""
    Write-Host "--- the real reader answers in its own shape ---" -ForegroundColor Cyan
    $real = Read-HordeIdleSeconds
    Check (($real.state -ceq "known" -and $real.seconds -ge 0) -or ($real.state -ceq "unknown" -and "" + $real.reason -ne "")) ("known with seconds, or unknown with a reason (" + $real.state + ")")

    Write-Host ""
    Write-Host "--- the wait, on a fake clock ---" -ForegroundColor Cyan
    $script:t = 0.0; $script:polls = 0
    $got = Wait-HordeIdleState -GetState { $script:polls++; [pscustomobject]@{ allowed = ($script:polls -ge 4); why = "busy" } } -WaitSeconds 600 -Sleep { param($ms) $script:t += $ms / 1000.0 } -Elapsed { $script:t }
    Check ($got.allowed -and -not $got.timedOut -and $script:polls -eq 4) ("allowed on the 4th look (" + $script:polls + ")")
    $script:t = 0.0; $script:polls = 0
    $got = Wait-HordeIdleState -GetState { $script:polls++; [pscustomobject]@{ allowed = $false; why = "busy" } } -WaitSeconds 12 -Sleep { param($ms) $script:t += $ms / 1000.0 } -Elapsed { $script:t }
    Check ((-not $got.allowed) -and $got.timedOut -and $script:t -ge 12 -and $script:t -lt 18) ("never allowed: timed out at about 12 s (t=" + $script:t + ")")
    $script:t = 0.0; $script:polls = 0
    $got = Wait-HordeIdleState -GetState { $script:polls++; [pscustomobject]@{ allowed = $false; why = "busy" } } -WaitSeconds 0 -Sleep { param($ms) $script:t += $ms / 1000.0 } -Elapsed { $script:t }
    Check ($got.timedOut -and $script:polls -eq 1 -and $script:t -eq 0) "-WaitSeconds 0 looks once, and does not sleep"

    Write-Host ""
    Write-Host "--- horde idle, as a user runs it: the lines and the exit code ---" -ForegroundColor Cyan
    $exe = (Get-Process -Id $PID).Path
    $horde = Join-Path $root "horde.ps1"
    $oldHome = $env:HORDE_HOME
    function Run-Horde {
        param([string]$HomeDir, [string[]]$Words, [string]$Pin = "")
        $env:HORDE_HOME = $HomeDir
        # The "never" home needs the input clock pinned: the real one reads however long the PC was left alone
        # (33 h on 2026-10-31, past its 86400 s), and the suite failed on both shells. The wall clock does not
        # matter: that home has no night.
        $env:HORDE_IDLE_INPUT_SECONDS = $Pin
        $o = @(& $exe -NoProfile -ExecutionPolicy Bypass -File $horde @Words)
        return [pscustomobject]@{ code = $LASTEXITCODE; text = ($o -join "`n") }
    }
    try {
        $always = New-Home "always" '{ "schemaVersion": 1, "settings": { "nightStartHour": 0, "nightEndHour": 24 } }'
        # No night at all, and a threshold of a whole day: only a PC left alone for 24 hours would pass.
        $never = New-Home "never" '{ "schemaVersion": 1, "settings": { "nightStartHour": 5, "nightEndHour": 5, "idleSeconds": 86400 } }'
        $r = Run-Horde $always @("idle")
        Check ($r.code -eq 0 -and $r.text -like "*idle-or-night: yes (night)*" -and $r.text -like "*local time: *" -and $r.text -like "*idle seconds: *") ("allowed: exit 0 and the three lines (" + $r.code + ")")
        $r = Run-Horde $never @("idle") "0"
        Check ($r.code -eq 1 -and $r.text -like "*idle-or-night: no*") ("not allowed: exit 1, after the lines (" + $r.code + ")")
        $r = Run-Horde $never @("idle", "-Json") "0"
        Check ($r.code -eq 1 -and $r.text -like '*"allowed":false*') "-Json says allowed false, exit 1"
        $r = Run-Horde $always @("idle", "-Json")
        Check ($r.code -eq 0 -and $r.text -like '*"allowed":true*' -and $r.text -like '*"why":"night"*') "-Json says allowed true, exit 0"
        $r = Run-Horde $never @("idle", "-Wait", "-WaitSeconds", "1") "0"
        Check ($r.code -eq 1 -and $r.text -like "*gave up after 1 s*") ("-Wait gives up at -WaitSeconds, exit 1 (" + $r.code + ")")
        $r = Run-Horde $always @("idle", "-Wait", "-WaitSeconds", "1")
        Check ($r.code -eq 0 -and $r.text -like "*idle-or-night: yes*") "-Wait returns at once when it holds, exit 0"
        $r = Run-Horde $always @("idle", "-WaitSeconds", "5")
        Check ($r.code -eq 2) ("-WaitSeconds without -Wait is a wrong command line, exit 2 (" + $r.code + ")")
        $r = Run-Horde $never @("idle", "-Json") "86400"
        Check ($r.code -eq 0 -and $r.text -like '*"allowed":true*' -and $r.text -like '*"why":"idle"*') "a pinned 86400 s is idle: the pin is what the command read"
        $r = Run-Horde $never @("idle") "ten"
        Check ($r.code -eq 1 -and $r.text -notlike "*idle-or-night: yes*") "a pin that is not digits fails the command; it never answers yes"
        $bad = New-Home "refused" '{ "schemaVersion": 1, "settings": { "idleSeconds": "ten" } }'
        $r = Run-Horde $bad @("idle")
        Check ($r.code -eq 1 -and $r.text -notlike "*idle-or-night: yes*") "a refused settings file fails the command; it never answers yes on defaults"
    } finally { $env:HORDE_HOME = $oldHome; $env:HORDE_IDLE_INPUT_SECONDS = $null }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "idle-or-night is answered right at every edge, unknown is not idle by day, the settings refuse bad files, and horde idle exits 0 or 1 with its lines"
