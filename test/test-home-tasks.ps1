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
New-Item -ItemType Directory -Path $homeA, $homeB, (Join-Path $work "profile") -Force | Out-Null

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
    $tasks = @(
        (New-FakeTask "Fine" $none.description (ConvertTo-HordeTaskAction -Job $none).arguments)
        (New-FakeTask "Baked" $oldJob.description $bakedArgs)
        (New-FakeTask "Meter" "x" ('--headless "p" -EncodedCommand ' + (Encode-Command $plain)))
    )
    $r = Get-HordeHomeTaskFindings -Effective $homeA -ListTasks { $tasks }
    Check ($r.checked -and @($r.lines).Count -eq 3) ("three findings: the baked job (action and marker) and the meter task, not the fine one (" + @($r.lines).Count + ")")
    Check (@($r.lines | Where-Object { $_ -like "*\Horde\Baked is baked into its action the home *homeB*not *homeA*" }).Count -eq 1) "the baked job is named with the home it keeps"
    Check (@($r.lines | Where-Object { $_ -like "*\Horde\Meter is baked*" }).Count -eq 1) "and the meter task"
    Check (@($r.lines | Where-Object { $_ -like "*\Horde\Fine*" }).Count -eq 0) "a task on the effective home is not named"
    $r = Get-HordeHomeTaskFindings -Effective ($homeA + "\") -ListTasks { @($tasks[0]) }
    Check ($r.checked -and ($r.lines -join " ") -like "*none names another home*") "a trailing separator on the effective home makes no difference"
    $r = [pscustomobject]@{ checked = $true; lines = @("threw") }
    try { $r = Get-HordeHomeTaskFindings -Effective $homeA -ListTasks { throw "Access is denied." } } catch { }
    Check (-not $r.checked -and @($r.lines).Count -eq 1 -and $r.lines[0] -like "tasks: not checked*Access is denied*") "a refused query is one line and does not throw"
    $r = Get-HordeHomeTaskFindings -Effective $homeA -ListTasks { @() }
    Check ($r.checked -and $r.lines[0] -like "*0 under*none names another home*") "no tasks: said so"

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
