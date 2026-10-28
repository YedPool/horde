# THE NIGHT'S FLOORS, ITS APP CLOSER AND ITS SUITE CUTOFF: DO THEY DECIDE AND ACT RIGHT?
#
# core/NightlyNet.ps1 (Get-HordeNightlyMemoryFloor, Test-HordeNightlyMayStartSuiteRun, the report's app lines) and
# tools/nightly/AppCloser.ps1 (T-0331; the founder's orders of 2026-10-26). The decisions are pure. The closer is
# driven for real ONLY against stand-in processes this suite starts itself (a small window in a Windows PowerShell
# child of its own), handed to it by process id with an app's name as their label; the suite never looks the real
# apps up and never closes anything it did not start. What is left of a stand-in is ended by its own id at the end.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\NightlyNet.ps1")
. (Join-Path $root "tools\nightly\AppCloser.ps1")

function Dt { param([string]$S) return [datetime]("2026-10-26 " + $S) }
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-nightly-apps-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
$started = @()

Write-Host ""
Write-Host "--- the night floors: per repo kind inside 22:00 to 07:00, the day floor outside ---" -ForegroundColor Cyan
$f = Get-HordeNightlyMemoryFloor -Now (Dt "23:00") -Kind "horde" -DayFreeGB 4.5 -DayCommitGB 2
Check ($f.freeGB -eq 1.0 -and $f.commitGB -eq 1.0 -and $f.night) ("a horde unit or the guards at 23:00: 1 GB free, 1 GB commit headroom (" + $f.freeGB + ", " + $f.commitGB + ")")
$f = Get-HordeNightlyMemoryFloor -Now (Dt "03:00") -Kind "pytest" -DayFreeGB 4.5 -DayCommitGB 2
Check ($f.freeGB -eq 2.5 -and $f.commitGB -eq 1.0) ("the pytest run at 03:00: 2.5 GB free, 1 GB commit headroom (" + $f.freeGB + ", " + $f.commitGB + ")")
$f = Get-HordeNightlyMemoryFloor -Now (Dt "22:00") -Kind "horde" -DayFreeGB 4.5 -DayCommitGB 2
Check ($f.freeGB -eq 1.0) "22:00 is night"
$f = Get-HordeNightlyMemoryFloor -Now (Dt "06:59") -Kind "horde" -DayFreeGB 4.5 -DayCommitGB 2
Check ($f.freeGB -eq 1.0) "06:59 is night"
$f = Get-HordeNightlyMemoryFloor -Now (Dt "07:00") -Kind "horde" -DayFreeGB 4.5 -DayCommitGB 2
Check ($f.freeGB -eq 4.5 -and $f.commitGB -eq 2 -and -not $f.night) "07:00 is day: the day floor, unchanged"
$f = Get-HordeNightlyMemoryFloor -Now (Dt "21:59") -Kind "pytest" -DayFreeGB 4.5 -DayCommitGB 2
Check ($f.freeGB -eq 4.5 -and $f.commitGB -eq 2) "21:59 is day"
$f = Get-HordeNightlyMemoryFloor -Now (Dt "23:00") -Kind "other" -DayFreeGB 4.5 -DayCommitGB 2
Check ($f.freeGB -eq 4.5) "a kind with no night floor keeps the day floor"
$nf = Get-HordeNightlyNightFloors
Check ($nf.freeGB.horde -eq 1.0 -and $nf.freeGB.pytest -eq 2.5 -and $nf.commitGB -eq 1.0) "the floors are set in one named table"

Write-Host ""
Write-Host "--- the suite cutoff: a unit may start until its wait ends at the suite cutoff, its worst case by the run cutoff ---" -ForegroundColor Cyan
$sc = [datetime]"2026-10-27 04:45"; $rc = [datetime]"2026-10-27 06:15"
# The night of 2026-10-25 tried its last unit at 04:18: the old rule wanted wait + RunSeconds before the suite cutoff.
Check ((Test-HordeNightlyMayStartRun -Now ([datetime]"2026-10-27 04:20") -Cutoff $sc -RunSeconds 1620) -eq $false) "CONTROL: the old rule starts nothing at 04:20"
Check ((Test-HordeNightlyMayStartSuiteRun -Now ([datetime]"2026-10-27 04:20") -SuiteCutoff $sc -RunCutoff $rc -WaitSeconds 120 -RunSeconds 1500) -eq $true) "the new one starts a unit at 04:20"
Check ((Test-HordeNightlyMayStartSuiteRun -Now ([datetime]"2026-10-27 04:43") -SuiteCutoff $sc -RunCutoff $rc -WaitSeconds 120 -RunSeconds 1500) -eq $true) "and at 04:43 on the short wait (it ends its wait by 04:45)"
Check ((Test-HordeNightlyMayStartSuiteRun -Now ([datetime]"2026-10-27 04:44") -SuiteCutoff $sc -RunCutoff $rc -WaitSeconds 120 -RunSeconds 1500) -eq $false) "not at 04:44 (its wait ends after 04:45)"
Check ((Test-HordeNightlyMayStartSuiteRun -Now ([datetime]"2026-10-27 04:30") -SuiteCutoff $sc -RunCutoff ([datetime]"2026-10-27 04:50") -WaitSeconds 120 -RunSeconds 1500) -eq $false) "never when its worst case would end after the run cutoff"
Check ((Test-HordeNightlyMayStartSuiteRun -Now ([datetime]"2026-10-27 04:00") -SuiteCutoff $sc -RunCutoff $rc -WaitSeconds 900 -RunSeconds 3600) -eq $true) "the guards (3600 s, 900 s wait) at 04:00: worst case 05:15, by 06:15"
# The run limit FITTED to the end of the night: a night with no bisect reserve (suite cutoff = run cutoff 06:15).
$e = [datetime]"2026-10-27 06:15"
Check ((Get-HordeNightlySuiteRunSeconds -Now ([datetime]"2026-10-27 05:00") -SuiteCutoff $e -RunCutoff $e -WaitSeconds 120 -RunSeconds 1500 -MinSeconds 600) -eq 1500) "with time left a unit gets its whole -RunSeconds"
$fit = Get-HordeNightlySuiteRunSeconds -Now ([datetime]"2026-10-27 05:55") -SuiteCutoff $e -RunCutoff $e -WaitSeconds 120 -RunSeconds 1500 -MinSeconds 600
Check ($fit -eq 1080) ("at 05:55 on the short wait it gets the 1080 s left, not nothing (" + $fit + ")")
Check ((Test-HordeNightlyMayStartSuiteRun -Now ([datetime]"2026-10-27 05:55") -SuiteCutoff $e -RunCutoff $e -WaitSeconds 120 -RunSeconds 1500) -eq $false) "CONTROL: the unfitted rule starts nothing at 05:55"
Check ((Get-HordeNightlySuiteRunSeconds -Now ([datetime]"2026-10-27 06:04") -SuiteCutoff $e -RunCutoff $e -WaitSeconds 120 -RunSeconds 1500 -MinSeconds 600) -eq 0) "under 600 s left: it does not start"
Check ((Get-HordeNightlySuiteRunSeconds -Now ([datetime]"2026-10-27 05:30") -SuiteCutoff $e -RunCutoff $e -WaitSeconds 120 -RunSeconds 3600 -MinSeconds 3600) -eq 0) "a run that may not be cut short (MinSeconds = its need) does not start without its whole time"
Check ((Get-HordeNightlySuiteRunSeconds -Now ([datetime]"2026-10-27 04:44") -SuiteCutoff $sc -RunCutoff $rc -WaitSeconds 120 -RunSeconds 1500 -MinSeconds 600) -eq 0) "nothing starts whose wait ends after the suite cutoff"

Write-Host ""
Write-Host "--- the named apps: exact names, force-quit only the three tray apps ---" -ForegroundColor Cyan
$names = Get-HordeNightlyCloseAppNames
$force = Get-HordeNightlyForceQuitAppNames
Check ((Test-HordeNightlyAppName -Name "chrome" -Names $names) -ceq "chrome") "chrome is named"
Check ((Test-HordeNightlyAppName -Name "SLACK" -Names $names) -ceq "Slack") "a name in another case is the same process name (Windows), given in the listed spelling"
Check ((Test-HordeNightlyAppName -Name "WhatsApp.Root" -Names $names) -ceq "WhatsApp.Root") "the Store build of WhatsApp is named"
foreach ($n in @("chrome_proxy", "notepad", "Slack Helper", "ms-teams-helper", "Zoomit", "powershell", "pwsh", "", "*")) { Check ((Test-HordeNightlyAppName -Name $n -Names $names) -eq "") ("'" + $n + "' is not named: no wildcard, no prefix") }
Check (@($force | Where-Object { (Test-HordeNightlyAppName -Name $_ -Names $names) -eq "" }).Count -eq 0) "every force-quit name is also a close name"
foreach ($n in @("chrome", "ms-teams", "Teams", "Zoom")) { Check ((Test-HordeNightlyAppName -Name $n -Names $force) -eq "") ($n + " is never forced") }
foreach ($n in @("Slack", "ClickUp", "WhatsApp", "WhatsApp.Root")) { Check ((Test-HordeNightlyAppName -Name $n -Names $force) -ne "") ($n + " is fully quit if still running") }
$fake = @(
    [pscustomobject]@{ ProcessName = "chrome"; Id = 11; WorkingSet64 = 1GB; StartTime = (Dt "08:00") },
    [pscustomobject]@{ ProcessName = "notepad"; Id = 12; WorkingSet64 = 1GB; StartTime = (Dt "08:00") },
    [pscustomobject]@{ ProcessName = "ClickUp"; Id = 13; WorkingSet64 = 512MB; StartTime = (Dt "09:00") })
$sel = @(Select-HordeNightlyAppProcesses -Processes $fake -Names $names)
Check ($sel.Count -eq 2 -and $sel[0].pid -eq 11 -and $sel[1].name -ceq "ClickUp" -and $sel[1].gb -eq 0.5) ("only the named processes are selected, with id and GB (" + $sel.Count + ")")

Write-Host ""
Write-Host "--- when it acts: idle 10 min, inside the night, until the cutoff ---" -ForegroundColor Cyan
$cut = [datetime]"2026-10-27 04:45"
$idle = [pscustomobject]@{ state = "known"; seconds = 600 }
$busy = [pscustomobject]@{ state = "known"; seconds = 599 }
$unk = [pscustomobject]@{ state = "unknown"; seconds = 99999 }
Check ((Get-HordeNightlyAppCloserStep -Now (Dt "22:00") -Night $true -Idle $idle -NeedSeconds 600 -NextTry ([datetime]::MinValue) -Cutoff $cut) -ceq "close") "idle 600 s at 22:00: close"
Check ((Get-HordeNightlyAppCloserStep -Now (Dt "22:00") -Night $true -Idle $busy -NeedSeconds 600 -NextTry ([datetime]::MinValue) -Cutoff $cut) -ceq "busy") "idle 599 s: busy, nothing closed"
Check ((Get-HordeNightlyAppCloserStep -Now (Dt "22:00") -Night $true -Idle $unk -NeedSeconds 600 -NextTry ([datetime]::MinValue) -Cutoff $cut) -ceq "busy") "an input clock that cannot be read is busy, never idle"
Check ((Get-HordeNightlyAppCloserStep -Now (Dt "22:00") -Night $true -Idle $null -NeedSeconds 600 -NextTry ([datetime]::MinValue) -Cutoff $cut) -ceq "busy") "no reading at all is busy"
Check ((Get-HordeNightlyAppCloserStep -Now (Dt "22:10") -Night $true -Idle $idle -NeedSeconds 600 -NextTry (Dt "22:15") -Cutoff $cut) -ceq "wait") "before the next try: wait (retry every 15 min)"
Check ((Get-HordeNightlyAppCloserStep -Now (Dt "22:15") -Night $true -Idle $idle -NeedSeconds 600 -NextTry (Dt "22:15") -Cutoff $cut) -ceq "close") "at the next try, idle: close"
Check ((Get-HordeNightlyAppCloserStep -Now $cut -Night $true -Idle $idle -NeedSeconds 600 -NextTry ([datetime]::MinValue) -Cutoff $cut) -ceq "stop") "at the cutoff: stop for the night"
Check ((Get-HordeNightlyAppCloserStep -Now (Dt "14:00") -Night $false -Idle $idle -NeedSeconds 600 -NextTry ([datetime]::MinValue) -Cutoff $cut) -ceq "stop") "outside the night: never"

Write-Host ""
Write-Host "--- the Chrome restore setting: read only, per profile ---" -ForegroundColor Cyan
$ud = Join-Path $work "userdata"
foreach ($p in @("Default", "Profile 1", "System Profile")) { [void][System.IO.Directory]::CreateDirectory((Join-Path $ud $p)); [System.IO.File]::WriteAllText((Join-Path $ud ($p + "\Preferences")), '{"browser":{"x":1}}') }
[System.IO.File]::WriteAllText((Join-Path $ud "Default\Secure Preferences"), '{"protection":{"macs":{"session":{"restore_on_startup":"AB12"}}},"session":{"restore_on_startup":1,"startup_urls":[]}}')
[System.IO.File]::WriteAllText((Join-Path $ud "Profile 1\Secure Preferences"), '{"protection":{"macs":{"session":{"restore_on_startup":"59BF"}}}}')
[System.IO.File]::WriteAllText((Join-Path $ud "Local State"), '{"profile":{"last_used":"Profile 1"}}')
$before = @(Get-ChildItem -LiteralPath $ud -Recurse -File | ForEach-Object { $_.FullName + "|" + $_.LastWriteTimeUtc.Ticks + "|" + $_.Length })
# Every call here hands in a policy reader: the default one reads THIS PC's registry (T-0331: this box has a policy).
$noPolicy = { param($Key) return $null }
$cr = Get-HordeNightlyChromeRestore -UserDataDir $ud -PolicyReader $noPolicy
Check ($cr.state -ceq "some" -and @($cr.profiles).Count -eq 2) ("one of two profiles restores: some, System Profile skipped (" + $cr.state + ", " + @($cr.profiles).Count + ")")
Check ((Get-HordeNightlyChromeProfileRestore -ProfileDir (Join-Path $ud "Default")) -ceq "1") "the number is read from Secure Preferences, never the hash string beside it"
Check ((Get-HordeNightlyChromeProfileRestore -ProfileDir (Join-Path $ud "Profile 1")) -ceq "") "a profile with only the hash has it not set"
Check ($cr.text -like "*NOT every profile*Restores (1): Default*Does not: Profile 1 (not set, the new tab page)*Last used profile: Profile 1 (does not restore)*") ("the report line says which and the last used one (" + $cr.text + ")")
$after = @(Get-ChildItem -LiteralPath $ud -Recurse -File | ForEach-Object { $_.FullName + "|" + $_.LastWriteTimeUtc.Ticks + "|" + $_.Length })
Check ((($before -join ";") -ceq ($after -join ";"))) "nothing in the profile folder was changed"
[System.IO.File]::WriteAllText((Join-Path $ud "Profile 1\Preferences"), '{"session":{"restore_on_startup":1}}')
Check ((Get-HordeNightlyChromeRestore -UserDataDir $ud -PolicyReader $noPolicy).state -ceq "yes") "every profile at 1: yes"
Check ((Get-HordeNightlyChromeRestore -UserDataDir (Join-Path $work "none") -PolicyReader $noPolicy).state -ceq "unknown") "no folder: unknown"

Write-Host ""
Write-Host "--- the Chrome restore setting: machine policy first, HKLM then HKCU (T-0331) ---" -ForegroundColor Cyan
[System.IO.File]::WriteAllText((Join-Path $ud "Profile 1\Preferences"), '{"browser":{"x":1}}')
$asked = New-Object System.Collections.ArrayList
function New-PolicyReader { param($Lm, $Cu) $a = $asked; $m = @{ "HKLM:\SOFTWARE\Policies\Google\Chrome" = $Lm; "HKCU:\SOFTWARE\Policies\Google\Chrome" = $Cu }; return { param($Key) [void]$a.Add($Key); return $m[$Key] }.GetNewClosure() }
$cr = Get-HordeNightlyChromeRestore -UserDataDir $ud -PolicyReader (New-PolicyReader -Lm 1 -Cu $null)
Check ($cr.state -ceq "yes") ("HKLM policy 1 with a profile not set: yes, the policy decides for every profile (" + $cr.state + ")")
Check ($cr.text -like "*every profile restores by policy (HKLM\SOFTWARE\Policies\Google\Chrome RestoreOnStartup = 1, restore the last session)*" -and $cr.text -notlike "*NOT every profile*" -and $cr.text -notlike "*Does not:*") ("the line says restores by policy and the hive (" + $cr.text + ")")
Check ($cr.policy.hive -ceq "HKLM" -and ("" + $cr.policy.value) -ceq "1") "the result names the deciding hive and value"
$cr = Get-HordeNightlyChromeRestore -UserDataDir $ud -PolicyReader (New-PolicyReader -Lm $null -Cu 5)
Check ($cr.state -ceq "no" -and $cr.text -like "*NO profile restores, by policy (HKCU*RestoreOnStartup = 5, the new tab page)*") ("HKCU policy 5 with Default at 1: no profile restores, by policy (" + $cr.text + ")")
$cr = Get-HordeNightlyChromeRestore -UserDataDir $ud -PolicyReader (New-PolicyReader -Lm 4 -Cu 1)
Check ($cr.state -ceq "no" -and $cr.text -like "*by policy (HKLM*RestoreOnStartup = 4, open URLs)*") ("HKLM is read before HKCU and wins (" + $cr.text + ")")
$asked.Clear()
$cr = Get-HordeNightlyChromeRestore -UserDataDir $ud -PolicyReader (New-PolicyReader -Lm $null -Cu $null)
Check (($asked -join "|") -ceq "HKLM:\SOFTWARE\Policies\Google\Chrome|HKCU:\SOFTWARE\Policies\Google\Chrome") ("both hives are asked, HKLM first (" + ($asked -join "|") + ")")
Check ($cr.state -ceq "some" -and $cr.text -like "*NOT every profile*Does not: Profile 1*" -and $null -eq $cr.policy) ("no policy: the per-profile reading as before (" + $cr.text + ")")
$cr = Get-HordeNightlyChromeRestore -UserDataDir (Join-Path $work "none") -PolicyReader (New-PolicyReader -Lm 1 -Cu $null)
Check ($cr.state -ceq "yes") "a policy decides even with no profile folder"
$cr = Get-HordeNightlyChromeRestore -UserDataDir $ud -PolicyReader { param($Key) throw "registry unreadable" }
Check ($cr.state -ceq "some") "a policy read that fails falls back to the per-profile reading"

Write-Host ""
Write-Host "--- the report's lines ---" -ForegroundColor Cyan
$r = [pscustomobject]@{ asked = 3; windows = 3; dryRun = $false; failed = @(); wouldForce = @()
    closed = @([pscustomobject]@{ name = "chrome"; pid = 11; gb = 1.0 }, [pscustomobject]@{ name = "chrome"; pid = 12; gb = 0.25 })
    forced = @([pscustomobject]@{ name = "ClickUp"; pid = 13; gb = 2.0 })
    running = @([pscustomobject]@{ name = "Zoom"; pid = 14; gb = 0.5 }) }
$al = @(Format-HordeNightlyAppLines -Result $r)
Check ($al[0] -ceq "CLOSED: chrome 2 processes 1.25 GB (pids 11,12). Freed 3.25 GB, 3 windows asked to close.") ("CLOSED names each app, its ids and what was freed (" + $al[0] + ")")
Check ($al[1] -like "FORCE-QUIT*ClickUp 1 processes 2.00 GB (pids 13)*") "FORCE-QUIT names the tray app"
Check ($al[2] -like "STILL RUNNING (left alone): Zoom 1 processes 0.50 GB (pids 14)*") "STILL RUNNING names what was left, with its memory"
$body = New-HordeNightlyReport -Date "2026-10-26" -Repos @() -AppLines $al
Check (($body -split "`n")[1] -like "CLOSED: chrome*") "the CLOSED line is the report's second line"
Check ($body -notmatch '[";<>]') "and the report stays tell-safe"

Write-Host ""
Write-Host "--- the closer for real, on stand-ins this suite started: WM_CLOSE, then force only the tray apps ---" -ForegroundColor Cyan
$ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
function Start-StandIn {
    # A process of this suite's own with one small visible window off screen. -Tray: its window refuses WM_CLOSE and
    # hides, as a tray app does. It writes a ready file once its window is shown.
    param([string]$Tag, [switch]$Tray)
    $ready = Join-Path $work ($Tag + ".ready")
    $code = 'Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.Form; $f.Text = "horde-standin-' + $Tag + '"; $f.ShowInTaskbar = $false; $f.StartPosition = "Manual"; $f.Location = New-Object System.Drawing.Point(-3000, -3000); $f.Size = New-Object System.Drawing.Size(120, 80); '
    if ($Tray) { $code += '$f.add_FormClosing({ param($s, $e) $e.Cancel = $true; $s.Hide() }); ' }
    $code += '$f.add_Shown({ [System.IO.File]::WriteAllText("' + $ready + '", "1") }); [System.Windows.Forms.Application]::Run($f)'
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($code))
    $p = Start-Process -FilePath $ps51 -ArgumentList ("-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand " + $enc) -PassThru
    $script:started += $p.Id
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $ready) -and $clock.Elapsed.TotalSeconds -lt 60) { Start-Sleep -Milliseconds 200 }
    $q = Get-Process -Id $p.Id
    return $q
}
function As { param($P, [string]$Name) return [pscustomobject]@{ name = $Name; pid = $P.Id; gb = ([double]$P.WorkingSet64 / 1GB); started = $P.StartTime } }
try {
    $a = Start-StandIn "a"
    $b = Start-StandIn "b" -Tray
    $c = Start-StandIn "c" -Tray
    $d = Start-StandIn "d" -Tray
    $wins = @(Get-HordeNightlyAppWindows -Pids @($a.Id, $b.Id, $c.Id))
    Check ($wins.Count -ge 3) ("EnumWindows finds the stand-ins' visible windows by process id (" + $wins.Count + ")")
    # DRY RUN first: nothing is touched.
    $dry = Close-HordeNightlyApps -Targets @((As $d "Slack")) -ForceNames $force -WaitSeconds 5 -DryRun
    Start-Sleep -Milliseconds 500
    Check ($null -ne (Get-Process -Id $d.Id -ErrorAction SilentlyContinue) -and @($dry.closed).Count -eq 0 -and @($dry.wouldForce).Count -eq 1 -and $dry.asked -eq 0) "a dry run closes nothing and lists what it would force-quit"
    Check ((@(Format-HordeNightlyAppLines -Result $dry) -join " ") -like "*WOULD CLOSE (dry run, nothing closed): Slack 1 processes*WOULD FORCE-QUIT*Slack*") "and says so"
    # FOR REAL: a closes on WM_CLOSE (labelled chrome), b hides to the tray (labelled ClickUp) and is fully quit, c
    # hides too but is labelled Zoom, so it is never forced and stays.
    $res = Close-HordeNightlyApps -Targets @((As $a "chrome"), (As $b "ClickUp"), (As $c "Zoom")) -ForceNames $force -WaitSeconds 8
    Check ($res.asked -ge 3) ("WM_CLOSE went to every visible window (" + $res.asked + ")")
    Check (@($res.closed | Where-Object { $_.pid -eq $a.Id }).Count -eq 1 -and $null -eq (Get-Process -Id $a.Id -ErrorAction SilentlyContinue)) "the window that takes WM_CLOSE ends by itself: closed"
    Check (@($res.forced | Where-Object { $_.pid -eq $b.Id }).Count -eq 1 -and $null -eq (Get-Process -Id $b.Id -ErrorAction SilentlyContinue)) "the tray app still running after the wait is fully quit"
    Check (@($res.running | Where-Object { $_.pid -eq $c.Id }).Count -eq 1 -and $null -ne (Get-Process -Id $c.Id -ErrorAction SilentlyContinue)) "an app off the force list is left running, never forced"
    Check (@($res.closed).Count -eq 1 -and @($res.forced).Count -eq 1 -and @($res.running).Count -eq 1) "and nothing else is in the result"
    Check ($null -ne (Get-Process -Id $d.Id -ErrorAction SilentlyContinue)) "a process not handed to the closer is untouched"
    # A target whose id was given out again (another start time) is gone, never ended.
    $ghost = [pscustomobject]@{ name = "Slack"; pid = $d.Id; gb = 0.1; started = $d.StartTime.AddHours(-1) }
    Check (-not (Test-HordeNightlyAppAlive $ghost)) "an id with another start time is not the same process"
    $res2 = Close-HordeNightlyApps -Targets @($ghost) -ForceNames $force -WaitSeconds 2
    Check ($null -ne (Get-Process -Id $d.Id -ErrorAction SilentlyContinue) -and $res2.asked -eq 0) "so a reused id is never asked to close or ended"
} finally {
    foreach ($id in $started) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the night gives each repo kind its own floor, starts units until the suite cutoff, closes only the named apps when the PC is idle, fully quits only the three tray apps, reads the Chrome restore setting without changing it, and reports what it closed"
