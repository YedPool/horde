# IS THE COLLECT JOB DEFINED RIGHT, AND DOES `horde metrics schedule` INSTALL, SHOW AND REMOVE IT?
#
# core/Schedule.ps1, core/schedule/*.ps1 and Invoke-HordeMetricsSchedule (core/MetricsCollect.ps1).
#
# NEVER THE REAL JOB (CONTRIBUTING 9). Every job this suite makes is named "Horde metrics collect TEST
# <guid>", and is installed DISABLED, so it never runs even for the seconds it exists; its action sets
# this suite's fake HORDE_HOME as well, so even a run would collect into a folder this suite removes. A
# guard refuses any name without "TEST" before anything is touched, and the job is removed in a finally
# block and checked to be gone. The seam itself is tested with a fake scheduler that touches nothing.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "Price", "Metrics", "MetricsStore", "MetricsReport", "MetricsCollect", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "test\lib\Cli.ps1")

$work = Join-Path $env:TEMP ("horde-schedule-" + [guid]::NewGuid().ToString("N"))
$savedHome = $env:HORDE_HOME
$testName = "Horde metrics collect TEST " + [guid]::NewGuid().ToString("N").Substring(0, 12)
function Assert-TestName { param([string]$Name) if ($Name -notlike "*TEST*" -or $Name -ceq $script:HordeCollectJobName) { throw ("refusing to act on a job this suite did not name: '" + $Name + "'") } }
function Set-Gate { param([string]$Text) [void][System.IO.Directory]::CreateDirectory((Get-HordeMetricsDir)); [System.IO.File]::WriteAllText((Join-Path (Get-HordeMetricsDir) "gate.json"), $Text) }
$horde = Join-Path $root "horde.ps1"

try {
    $env:HORDE_HOME = Join-Path $work "home"

    Write-Host ""
    Write-Host "--- the job ---" -ForegroundColor Cyan
    $env:HORDE_HOME = ""
    $plain = New-HordeCollectJob -HordeScript $horde -Name $testName
    Check ($plain.program -eq "powershell.exe" -and $plain.arguments -like ("*-File """ + $horde + """ metrics collect")) "with no HORDE_HOME the job runs this checkout's horde.ps1, metrics collect"
    Check ($plain.everyMinutes -eq 30 -and $plain.timeLimitMinutes -eq 20 -and $plain.lowPriority -and -not $plain.disabled) "every 30 minutes, at low priority, stopped after 20 minutes, enabled"
    Check ($plain.arguments -like "*-NonInteractive*" -and $plain.arguments -like "*-NoProfile*") "never waiting for input, and without the user's profile script"
    $env:HORDE_HOME = Join-Path $work "home"
    $homed = New-HordeCollectJob -HordeScript $horde -Name $testName -Disabled
    Check ($homed.arguments -like ("*`$env:HORDE_HOME = '" + $env:HORDE_HOME + "'*metrics collect*") -and $homed.disabled) "with HORDE_HOME set, the job sets the same home itself, since a scheduler does not pass this shell's environment on"
    Check (Throws { New-HordeCollectJob -HordeScript "C:\it's\horde.ps1" -Name $testName } "quote") "a path with a quote in it is refused rather than quoted wrongly"
    Check (Throws { New-HordeScheduledJob -Name "x" -Program "p" -Arguments "a" -EveryMinutes 30 -TimeLimitMinutes 45 } "stops before") "a job allowed to run longer than its interval is refused"
    Check (Throws { New-HordeScheduledJob -Name "bad\name" -Program "p" -Arguments "a" } "not a job name") "a job name that is not plain is refused"

    Write-Host ""
    Write-Host "--- the seam, with a fake scheduler ---" -ForegroundColor Cyan
    $saveSchedulers = @($script:HordeSchedulers)
    $script:HordeSchedulers.Clear()
    $fake = @{ jobs = @{}; installs = 0 }
    Register-HordeScheduler -Name "fake" -Available { $true } -Install { param($j) $fake.installs++; $fake.jobs[$j.name] = $j } -Remove { param($n) if ($fake.jobs.ContainsKey($n)) { $fake.jobs.Remove($n); $true } else { $false } } -Status { param($n) if ($fake.jobs.ContainsKey($n)) { $j = $fake.jobs[$n]; New-HordeKnown -Value ([pscustomobject]@{ installed = $true; enabled = (-not $j.disabled); state = "Ready"; everyMinutes = $j.everyMinutes; logonType = "fake"; lastRunAt = $null; lastResult = 0; nextRunAt = $null; program = $j.program; arguments = $j.arguments }) } else { New-HordeAbsent -Note "none" } }
    Check (Throws { Invoke-HordeMetricsSchedule -Action install -TaskName "fake job" -HordeScript $horde } "not installed") "with metrics off, install refuses: a job that records nothing is not installed"
    Set-Gate '{ not json'
    Check (Throws { Invoke-HordeMetricsSchedule -Action install -TaskName "fake job" -HordeScript $horde } "refused") "and with the gate refused"
    Check ($fake.installs -eq 0) "CONTROL: the scheduler was never asked"
    Set-Gate '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-10-01T00:00:00Z" }'
    $out = @(Invoke-HordeMetricsSchedule -Action install -TaskName "fake job" -HordeScript $horde)
    Check ($fake.installs -eq 1 -and $fake.jobs.ContainsKey("fake job") -and $out[0] -like "installed 'fake job' with fake*every 30 minutes*") "with the gate on usage, install hands the job to the scheduler and says what it did"
    $stat = @(Invoke-HordeMetricsSchedule -Action status -TaskName "fake job" -HordeScript $horde)
    Check ($stat[0] -eq "metrics gate: usage" -and $stat[1] -like "'fake job' in fake: enabled, Ready, every 30 minutes*") "status shows the gate and the job"
    Check ((@(Invoke-HordeMetricsSchedule -Action remove -TaskName "fake job" -HordeScript $horde))[0] -like "removed*") "remove removes it"
    Check ((@(Invoke-HordeMetricsSchedule -Action status -TaskName "fake job" -HordeScript $horde))[1] -like "*is not installed*") "and then status says it is not installed"
    Check ((@(Invoke-HordeMetricsSchedule -Action remove -TaskName "fake job" -HordeScript $horde))[0] -like "no job named*") "removing what is not there says so"
    Register-HordeScheduler -Name "fake" -Available { $true } -Install { param($j) } -Remove { param($n) $false } -Status { param($n) New-HordeAbsent -Note "none" }
    Check (Throws { Invoke-HordeMetricsSchedule -Action install -TaskName "fake job" -HordeScript $horde } "did not keep") "a scheduler that does not keep the job makes install fail; it never reports success it did not see"
    Register-HordeScheduler -Name "fake" -Available { $false } -Install { } -Remove { } -Status { }
    Check (Throws { Invoke-HordeMetricsSchedule -Action status -TaskName "fake job" -HordeScript $horde } "no scheduler works") "with no scheduler that works here, every action says so"
    $script:HordeSchedulers.Clear()
    foreach ($s in $saveSchedulers) { [void]$script:HordeSchedulers.Add($s) }

    Write-Host ""
    Write-Host "--- this machine's scheduler, with a disabled job under a test name ---" -ForegroundColor Cyan
    foreach ($s in (Get-HordeSchedulerFiles)) { . $s }
    $real = Get-HordeScheduler
    if ($real.state -ne "known") {
        Write-Host ("  [SKIP] " + $real.reason)
    } else {
        $sch = $real.value
        Assert-TestName $testName
        try {
            $env:HORDE_HOME = Join-Path $work "home"
            $i1 = @(Invoke-HordeMetricsSchedule -Action install -TaskName $testName -Disabled -HordeScript $horde)
            $st = & $sch.status $testName
            Check ($st.state -eq "known" -and $st.value.enabled -eq $false) ("install made the job, disabled (" + $sch.name + ")")
            Check ($st.value.everyMinutes -eq 30 -and "$($st.value.priority)" -eq "7" -and $st.value.timeLimit -eq "PT20M") "every 30 minutes, priority 7 (below normal), stopped after 20 minutes"
            Check ($st.value.logonType -eq "S4U") "as the current user, whether or not logged on, with no window"
            Check ($st.value.arguments -like ("*" + $env:HORDE_HOME + "*") -and $st.value.arguments -like "*metrics collect*") "and its action runs collect into this suite's home"
            $null = Invoke-HordeMetricsSchedule -Action install -TaskName $testName -Disabled -HordeScript $horde
            Check (@(Get-ScheduledTask -TaskPath "\" -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -ceq $testName }).Count -eq 1) "installing again replaces it: one job, not two"
            $sl = @(Invoke-HordeMetricsSchedule -Action status -TaskName $testName -HordeScript $horde)
            Check ($sl[1] -like ("'" + $testName + "'*DISABLED*every 30 minutes*")) "status shows it"
            # The same through the shipped command, as a person would type it.
            $envs = @{ HORDE_HOME = $env:HORDE_HOME }
            $cs = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "status", "-TaskName", $testName) -Env $envs
            Check ($cs.code -eq 0 -and $cs.out -like "*metrics gate: usage*" -and $cs.out -like "*DISABLED*") "horde metrics schedule status shows the gate and the job"
            $cr = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "remove", "-TaskName", $testName) -Env $envs
            Check ($cr.code -eq 0 -and $cr.out -like "*removed*" -and (& $sch.status $testName).state -eq "absent") "horde metrics schedule remove removes it, and it is gone"
            $ci = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "install", "-TaskName", $testName, "-Disabled") -Env $envs
            Check ($ci.code -eq 0 -and (& $sch.status $testName).state -eq "known") "horde metrics schedule install puts it back"
            $cb = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "start") -Env $envs
            Check ($cb.code -ne 0 -and $cb.out -like "*install, remove or status*") "an action schedule does not know is refused"
        } finally {
            Assert-TestName $testName
            $null = & $sch.remove $testName
        }
        Check ((& $sch.status $testName).state -eq "absent") "the test job is gone at the end"
    }
} finally {
    $env:HORDE_HOME = $savedHome
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the collect job is defined once, installed only with consent, and installed, shown and removed by name"
