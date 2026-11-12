# DOES `horde home` NAME THE SCHEDULED TASKS THAT WOULD KEEP AN OLD HOME, AND DO NEW TASKS BAKE NONE IN? (T-0299, round 1)
#
# A task that bakes HORDE_HOME into its action outranks the pointer file and keeps the old folder after horde home
# set. core/HomeTasks.ps1 reads the tasks under \Horde\ (read only; here through a stand-in list, so no real task
# is read) and names each one whose recorded or baked home is not the effective one; the jobs Horde registers
# (core/Schedule.ps1, cli/ServicesTend.ps1) and the meter's register-schedule.ps1 no longer bake one.
# Every home here is a folder name under %TEMP%; the real profile, pointer and homes are never read.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Home", "HomeTasks", "Transcript", "Price", "Metrics", "MetricsStore", "MetricsReport", "MetricsCollect", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }

. (Join-Path $root "core\schedule\WindowsTaskScheduler.ps1")
$work = Join-Path $env:TEMP ("horde-home-tasks-" + [guid]::NewGuid().ToString("N"))
$homeA = Join-Path $work "homeA"
$homeB = Join-Path $work "homeB"
$savedHome = $env:HORDE_HOME
$savedProfile = $env:USERPROFILE
New-Item -ItemType Directory -Path $homeA, $homeB -Force | Out-Null
[void](New-HordeTestProfile (Join-Path $work "profile"))

function New-FakeTask {
    param([string]$Name, [string]$Description, [string]$Arguments)
    return [pscustomobject]@{ TaskPath = "\Horde\"; TaskName = $Name; Description = $Description; Actions = @([pscustomobject]@{ Arguments = $Arguments }) }
}
function Invoke-ScheduleScript {
    # register-schedule.ps1 as its own process (streams read through the process API, CONTRIBUTING 12): stdout then stderr.
    param([string[]]$ScriptArgs)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + (Join-Path $root "fleet-metrics\register-schedule.ps1") + "`" " + (($ScriptArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " ")
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    try { $e = $p.StandardError.ReadToEndAsync(); $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit(); return ($o + "`n" + $e.Result) } finally { $p.Dispose() }
}
function Encode-Command { param([string]$Text) return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Text)) }

try {
    $env:HORDE_HOME = $homeA
    $env:USERPROFILE = Join-Path $work "profile"

    Write-Host ""
    Write-Host "--- what a task names ---" -ForegroundColor Cyan
    $oldJob = New-HordeScheduledJob -Name "old baked" -Folder "HordeTest" -Script "C:\x\horde.ps1" -Arguments @("metrics", "collect") -Environment @{ HORDE_HOME = $homeB } -HordeHome $homeB
    $bakedArgs = (ConvertTo-HordeTaskAction -Job $oldJob).arguments
    $rows = @(Get-HordeTaskNamedHomes -Description $oldJob.description -Arguments $bakedArgs)
    Check (@($rows | Where-Object { $_.how -ceq "baked into its action" -and $_.home -ceq $homeB }).Count -eq 1) "a HORDE_HOME baked into a scheduler job's action is read back"
    Check (@($rows | Where-Object { $_.how -ceq "registered under" -and $_.home -ceq $homeB }).Count -eq 1) "and the home in its description's marker"
    $plain = '$env:HORDE_HOME = ''' + $homeB.Replace("'", "''") + '''; & ''C:\x\horde.ps1'' meter collect; exit $LASTEXITCODE'
    $rows = @(Get-HordeTaskNamedHomes -Description "own task" -Arguments ('--headless "powershell.exe" -NoProfile -EncodedCommand ' + (Encode-Command $plain)))
    Check ($rows.Count -eq 1 -and $rows[0].home -ceq $homeB -and $rows[0].how -ceq "baked into its action") "the meter's plain form (`$env:HORDE_HOME = '...') is read back"
    $none = New-HordeScheduledJob -Name "new" -Folder "HordeTest" -Script "C:\x\horde.ps1" -Arguments @("metrics", "collect") -HordeHome $homeA
    $rows = @(Get-HordeTaskNamedHomes -Description $none.description -Arguments (ConvertTo-HordeTaskAction -Job $none).arguments)
    Check ($rows.Count -eq 1 -and $rows[0].how -ceq "registered under") "a job with no home baked in names only the home in its marker"
    Check (@(Get-HordeTaskNamedHomes -Description "" -Arguments "-EncodedCommand not*base64").Count -eq 0) "text that is not a command names nothing, and does not throw"

    Write-Host ""
    Write-Host "--- the check ---" -ForegroundColor Cyan
    # A correct task that was registered under the OLD home and bakes none: it resolves the home at each run, so it is not stale.
    $unbakedOld = New-HordeScheduledJob -Name "unbaked old" -Folder "HordeTest" -Script "C:\x\horde.ps1" -Arguments @("metrics", "collect") -HordeHome $homeB
    # A task that bakes the EFFECTIVE home is right, and is not named either.
    $bakedGood = New-HordeScheduledJob -Name "baked good" -Folder "HordeTest" -Script "C:\x\horde.ps1" -Arguments @("metrics", "collect") -Environment @{ HORDE_HOME = $homeA } -HordeHome $homeA
    $tasks = @(
        (New-FakeTask "BakedGood" $bakedGood.description (ConvertTo-HordeTaskAction -Job $bakedGood).arguments)
        (New-FakeTask "UnbakedOldMarker" $unbakedOld.description (ConvertTo-HordeTaskAction -Job $unbakedOld).arguments)
        (New-FakeTask "Fine" $none.description (ConvertTo-HordeTaskAction -Job $none).arguments)
        (New-FakeTask "Baked" $oldJob.description $bakedArgs)
        (New-FakeTask "Meter" "x" ('--headless "p" -EncodedCommand ' + (Encode-Command $plain)))
    )
    $r = Get-HordeHomeTaskFindings -Effective $homeA -ListTasks { $tasks }
    Check ($r.checked -and @($r.lines).Count -eq 2) ("two findings: the baked job and the meter task; not the fine one, and not the unbaked one registered under the old home (" + @($r.lines).Count + ")")
    Check (@($r.lines | Where-Object { $_ -like "*\Horde\Baked is baked into its action the home *homeB*not *homeA*" }).Count -eq 1) "the baked job is named with the home it keeps"
    Check (@($r.lines | Where-Object { $_ -like "*\Horde\Meter is baked*" }).Count -eq 1) "and the meter task"
    Check (@($r.lines | Where-Object { $_ -like "*\Horde\Fine*" }).Count -eq 0) "a task on the effective home is not named"
    Check (@($r.lines | Where-Object { $_ -like "*BakedGood*" }).Count -eq 0) "a task that bakes the effective home is not named"
    Check (@($r.lines | Where-Object { $_ -like "*UnbakedOldMarker*" }).Count -eq 0) "an unbaked task whose marker names the old home is NOT named: it follows the pointer, so it is not stale"
    $r = Get-HordeHomeTaskFindings -Effective ($homeA + "\") -ListTasks { @($tasks[0]) }
    Check ($r.checked -and ($r.lines -join " ") -like "*none bakes in another home*") "a trailing separator on the effective home makes no difference"
    $r = [pscustomobject]@{ checked = $true; lines = @("threw") }
    try { $r = Get-HordeHomeTaskFindings -Effective $homeA -ListTasks { throw "Access is denied." } } catch { }
    Check (-not $r.checked -and @($r.lines).Count -eq 1 -and $r.lines[0] -like "tasks: not checked*Access is denied*") "a refused query is one line and does not throw"
    $r = Get-HordeHomeTaskFindings -Effective $homeA -ListTasks { @() }
    Check ($r.checked -and $r.lines[0] -like "*0 under*none bakes in another home*") "no tasks: said so"

    Write-Host ""
    Write-Host "--- a service still running blocks home set ---" -ForegroundColor Cyan
    $oldHome = Join-Path $work "svc-old"
    $newHome = Join-Path $work "svc-new"
    New-Item -ItemType Directory -Path (Join-Path $oldHome "settings"), $newHome -Force | Out-Null
    function Put-Definition { param([bool]$Enabled = $true)
        $d = [ordered]@{ checkout = $root; hordeHome = $oldHome; enabled = $Enabled; start = [ordered]@{ kind = "horde"; words = @("relay", "run") }; stop = [ordered]@{ kind = "horde"; words = @("relay", "stop"); waitSeconds = 30 }; alive = [ordered]@{ heartbeat = "relay/run-heartbeat.json"; tickSeconds = 60 } }
        $text = ConvertTo-Json -Depth 8 -InputObject ([ordered]@{ schemaVersion = 1; settings = [ordered]@{ "relay-runner" = $d } })
        [System.IO.File]::WriteAllText((Join-Path (Join-Path $oldHome "settings") "service-definitions.json"), $text, (New-Object System.Text.UTF8Encoding($false)))
    }
    $beatFile = Join-Path (Join-Path $oldHome "relay") "run-heartbeat.json"
    $env:HORDE_HOME = $oldHome
    # The guard compares POINTER-level homes (HORDE_HOME in this process is ignored), so the old home is named by a pointer.
    [System.IO.File]::WriteAllText((Join-Path $env:USERPROFILE ".horde-home.json"), ('{"v":1,"hordeHome":"' + $oldHome.Replace("\", "\\") + '"}'))
    Put-Definition
    Check (@(Get-HordeRunningHordeServices -Home2 $oldHome).Count -eq 0) "CONTROL: a defined service with no heartbeat is not running"
    Check (-not (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome $newHome } "")) "and home set is not refused"
    Write-HordeHeartbeat -Path $beatFile -At ([datetime]::UtcNow) -ProcessId 4242 -TickSeconds 60
    $run = @(Get-HordeRunningHordeServices -Home2 $oldHome)
    Check ($run.Count -eq 1 -and $run[0].name -ceq "relay-runner") "a fresh heartbeat of a horde-kind service: running"
    Check (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome $newHome } "relay-runner") "home set is refused while it runs under the current home, naming it"
    Check (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome $newHome } "horde services stop") "and the refusal says how: stop it first, then change the definition, then set"
    Check (-not (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome ($oldHome + "\") } "")) "setting the home it already is, is not refused"
    Write-HordeHeartbeat -Path $beatFile -At ([datetime]::UtcNow.AddHours(-2)) -ProcessId 4242 -TickSeconds 60
    Check (@(Get-HordeRunningHordeServices -Home2 $oldHome).Count -eq 0) "a stale heartbeat is a service that is not running"
    Write-HordeHeartbeat -Path $beatFile -At ([datetime]::UtcNow) -ProcessId 4242 -TickSeconds 60
    Put-Definition -Enabled $false
    Check (@(Get-HordeRunningHordeServices -Home2 $oldHome).Count -eq 0) "a disabled service is not counted"
    Remove-Item -LiteralPath (Join-Path (Join-Path $oldHome "settings") "service-definitions.json") -Force
    Check (@(Get-HordeRunningHordeServices -Home2 $oldHome).Count -eq 0) "no definitions file: nothing running, and no throw"
    $env:HORDE_HOME = $homeA

    Write-Host ""
    Write-Host "--- clear is guarded too, and a service stopped just now clears in a few seconds ---" -ForegroundColor Cyan
    Put-Definition
    $t0 = [datetime]::UtcNow
    Write-HordeHeartbeat -Path $beatFile -At $t0 -ProcessId 4242 -TickSeconds 60
    $env:HORDE_HOME = ""
    [System.IO.File]::WriteAllText((Join-Path $env:USERPROFILE ".horde-home.json"), ('{"v":1,"hordeHome":"' + $oldHome.Replace("\", "\\") + '"}'))
    Check ((Resolve-HordeHome).source -ceq "pointer" -and (Get-HordeHomeAfterClear) -eq (Join-Path $env:USERPROFILE ".horde")) "the pointer names the old home, and clear would leave the default"
    Check (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome (Get-HordeHomeAfterClear) -Verb clear } "home clear is refused") "home clear is refused while a service runs under the pointer's home"
    Check (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome $newHome -Now $t0.AddSeconds(5) } "clears in about 176 s") "the refusal says how long until the heartbeat goes stale (a 60 s tick goes stale after 180 s; 5 s after the beat that is 176 s)"
    Check (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome $newHome -Now $t0.AddSeconds(5) } "Stopped just now?") "and asks if it was stopped just now"
    Check (-not (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome $newHome -Now $t0.AddSeconds(400) } "")) "once the heartbeat is older than its stale time (a stubbed clock), set is no longer refused"
    Check (-not (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome (Get-HordeHomeAfterClear) -Verb clear -Now $t0.AddSeconds(400) } "")) "and neither is clear"
    # HORDE_HOME in THIS process does not matter: the pointer decides for every reader without it.
    $env:HORDE_HOME = $oldHome
    Check (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome (Get-HordeHomeAfterClear) -Verb clear } "home clear is refused") "with HORDE_HOME set here, clear is still refused: it moves every reader without it"
    Check (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome $newHome } "home set is refused") "and so is set"
    $env:HORDE_HOME = $homeA
    Check (Throws { Assert-HordeNoServiceRunsOnOldHome -NewHome (Get-HordeHomeAfterClear) -Verb clear } "home clear is refused") "whatever HORDE_HOME names"
    $env:HORDE_HOME = ""
    Remove-Item -LiteralPath (Join-Path $env:USERPROFILE ".horde-home.json") -Force
    $env:HORDE_HOME = $homeA

    Write-Host ""
    Write-Host "--- the lines horde home prints ---" -ForegroundColor Cyan
    $env:HORDE_HOME = $homeA
    $lines = @(Get-HordeHomeCheckLines -ListTasks { @() })
    Check (@($lines | Where-Object { $_ -like "WARNING*" }).Count -eq 0) "HORDE_HOME set and no pointer: nothing is overridden, no warning"
    [System.IO.File]::WriteAllText((Join-Path $env:USERPROFILE ".horde-home.json"), ('{"v":1,"hordeHome":"' + $homeB.Replace("\", "\\") + '"}'))
    $lines = @(Get-HordeHomeCheckLines -ListTasks { @() })
    Check (@($lines | Where-Object { $_ -like "WARNING: HORDE_HOME is set in this process*overrides the pointer*" }).Count -eq 1) "HORDE_HOME set while a pointer exists: a warning"
    $env:HORDE_HOME = ""
    $lines = @(Get-HordeHomeCheckLines -ListTasks { @() })
    Check (@($lines | Where-Object { $_ -like "WARNING*" }).Count -eq 0) "HORDE_HOME unset: no warning"

    Write-Host ""
    Write-Host "--- the jobs bake no home ---" -ForegroundColor Cyan
    $env:HORDE_HOME = $homeA
    $collect = New-HordeCollectJob -HordeScript (Join-Path $root "horde.ps1") -Name "x TEST" -Folder "HordeTest" -Disabled
    Check (-not $collect.environment.ContainsKey("HORDE_HOME")) "the metrics collect job has no HORDE_HOME in its environment"
    $takenCollect = New-HordeCollectJob -HordeScript (Join-Path $root "horde.ps1") -Name "x TEST" -Folder "HordeTest" -Disabled -TakeOver
    Check ($takenCollect.takeOver -eq $true -and $collect.takeOver -eq $false) "the metrics collect job carries -TakeOver, off by default"
    $acts = @(Get-HordeTaskNamedHomes -Description "own task" -Arguments (ConvertTo-HordeTaskAction -Job $collect).arguments)
    Check (@($acts | Where-Object { $_.how -ceq "baked into its action" }).Count -eq 0) "the metrics collect job's action holds no HORDE_HOME"
    $meter = Get-Content -LiteralPath (Join-Path $root "fleet-metrics\register-schedule.ps1") -Raw
    Check ($meter -notmatch 'env:HORDE_HOME = ') "the meter's register-schedule.ps1 no longer writes HORDE_HOME into a task's command"
    $o = Invoke-ScheduleScript @("-HordeHome", (Join-Path $work "elsewhere"), "-WhatIf")
    Check ($o -like "*resolves*") "register-schedule.ps1 refuses a -HordeHome that is not the home this shell resolves"
    $o = Invoke-ScheduleScript @("-HordeHome", $homeA, "-WhatIf")
    Check ($o -like "*What if*Fleet meter collect*" -and $o -notlike "*resolves*") "and with the home it resolves (or none given), -WhatIf lists the tasks"
} finally {
    $env:HORDE_HOME = $savedHome
    $env:USERPROFILE = $savedProfile
    if ((Split-Path -Leaf $work) -match '\Ahorde-home-tasks-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Complete-HordeSuite -Success "horde home names the tasks that keep an old home, and no new task bakes one in"
