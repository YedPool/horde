# IS THE COLLECT JOB DEFINED AS DATA, PASSED WITHOUT QUOTING, AND INSTALLED, SHOWN AND REMOVED ONLY AS
# HORDE'S OWN?
#
# core/Schedule.ps1, core/schedule/*.ps1 and Invoke-HordeMetricsSchedule (core/MetricsCollect.ps1).
#
# NEVER THE REAL JOB (CONTRIBUTING 9). Every job this suite installs lives in the scheduler folder
# HordeTest, never Horde, under a name with "TEST" in it, DISABLED, so it never runs even for the
# seconds it exists; its home is this suite's fake HORDE_HOME. The "foreign" tasks it makes to prove
# Horde leaves them alone are named with TEST too. Everything is removed in a finally block, and the
# HordeTest folder is checked to be gone. The seam itself is tested with a fake scheduler.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "ReadShared", "Home", "Transcript", "Price", "Metrics", "MetricsStore", "MetricsReport", "MetricsCollect", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "test\lib\Cli.ps1")

$work = Join-Path $env:TEMP ("horde-schedule-" + [guid]::NewGuid().ToString("N"))
$savedHome = $env:HORDE_HOME
$testName = "Horde metrics collect TEST " + [guid]::NewGuid().ToString("N").Substring(0, 12)
function Assert-TestName { param([string]$Name) if ($Name -notlike "*TEST*") { throw ("refusing to act on a job this suite did not name: '" + $Name + "'") } }
function Set-Gate { param([string]$Text) [void][System.IO.Directory]::CreateDirectory((Get-HordeMetricsDir)); [System.IO.File]::WriteAllText((Join-Path (Get-HordeMetricsDir) "gate.json"), $Text) }
$horde = Join-Path $root "horde.ps1"

try {
    $env:HORDE_HOME = Join-Path $work "home"

    Write-Host ""
    Write-Host "--- the job is data ---" -ForegroundColor Cyan
    $job = New-HordeCollectJob -HordeScript $horde -Name $testName -Folder "HordeTest" -Disabled
    Check ($job.script -eq $horde -and (@($job.arguments) -join " ") -eq "metrics collect" -and $job.environment["HORDE_HOME"] -eq $env:HORDE_HOME) "the job is this checkout's horde.ps1, metrics collect, with this shell's Horde home"
    Check ($job.everyMinutes -eq 30 -and $job.timeLimitMinutes -eq 20 -and $job.lowPriority -and $job.disabled) "every 30 minutes, at low priority, stopped after 20 minutes; disabled when asked"
    $mark = Read-HordeJobMarker -Description $job.description
    Check ($mark.marked -and $mark.home -eq $env:HORDE_HOME) "its description carries Horde's marker and the home it serves"
    Check (-not (Read-HordeJobMarker -Description "someone's own task").marked) "CONTROL: a description without the marker is not Horde's"
    Check ($job.withPerson -eq $false -and (New-HordeScheduledJob -Name "x" -Script "s" -HordeHome "h" -WithPerson).withPerson -eq $true) "a job runs where nobody sees it unless it is made -WithPerson, for work that needs the person's own session"
    Check (Throws { New-HordeScheduledJob -Name "x" -Script "s" -HordeHome "h" -EveryMinutes 30 -TimeLimitMinutes 45 } "stops before") "a job allowed to run longer than its interval is refused"
    Check (Throws { New-HordeScheduledJob -Name "bad\name" -Script "s" -HordeHome "h" } "not a job name") "a job name that is not plain is refused"
    Check (Throws { New-HordeScheduledJob -Name "x" -Folder "Microsoft" -Script "s" -HordeHome "h" } "not one of Horde's scheduler folders") "a folder that is not Horde's is refused"
    Check (Throws { New-HordeScheduledJob -Name "x" -Script "s" -HordeHome "h" -Environment @{ "A;B" = "1" } } "not an environment variable name") "an environment name that is not a plain name is refused"
    # Review of #70, NEW-2: an argument starting with "-" reaches the script as a plain string, not a
    # switch, and the run fails with exit 2; it is refused when the job is made, not every 30 minutes.
    Check (Throws { New-HordeScheduledJob -Name "x" -Script "s" -HordeHome "h" -Arguments @("metrics", "-Json") } "cannot start with") "an argument that starts with a dash is refused when the job is made"
    Check (-not (Throws { New-HordeScheduledJob -Name "x" -Script "s" -HordeHome "h" -Arguments @("metrics", "a-b") } "cannot start with")) "CONTROL: a dash inside an argument is fine"
    # PowerShell reads the Unicode dashes U+2010 to U+2015 and the minus sign U+2212 as "-" too.
    $lookAlikes = @(0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212)
    $refusedAll = $true
    foreach ($c in $lookAlikes) { if (-not (Throws { New-HordeScheduledJob -Name "x" -Script "s" -HordeHome "h" -Arguments @("metrics", ([string][char]$c + "Json")) } "cannot start with")) { $refusedAll = $false } }
    Check $refusedAll "and so is one that starts with any of the dashes PowerShell reads as one (U+2010 to U+2015, U+2212)"

    Write-Host ""
    Write-Host "--- the seam, with a fake scheduler ---" -ForegroundColor Cyan
    $saveSchedulers = @($script:HordeSchedulers)
    $script:HordeSchedulers.Clear()
    $fake = @{ jobs = @{}; installs = 0 }
    Register-HordeScheduler -Name "fake" -Available { $true } -Install { param($j) $fake.installs++; $fake.jobs[$j.folder + "\" + $j.name] = $j } -Remove { param($n, $f) if ($fake.jobs.ContainsKey($f + "\" + $n)) { $fake.jobs.Remove($f + "\" + $n); $true } else { $false } } -Status { param($n, $f) if ($fake.jobs.ContainsKey($f + "\" + $n)) { $j = $fake.jobs[$f + "\" + $n]; New-HordeKnown -Value ([pscustomobject]@{ enabled = (-not $j.disabled); state = "Ready"; everyMinutes = $j.everyMinutes; marked = $true; home = $j.hordeHome; logonType = "fake"; lastRunAt = $null; lastResult = 0; nextRunAt = $null }) } else { New-HordeAbsent -Note "none" } }
    Check (Throws { Invoke-HordeMetricsSchedule -Action install -TaskName "fake job" -Folder "HordeTest" -HordeScript $horde } "not installed") "with metrics off, install refuses: a job that records nothing is not installed"
    Set-Gate '{ not json'
    Check (Throws { Invoke-HordeMetricsSchedule -Action install -TaskName "fake job" -Folder "HordeTest" -HordeScript $horde } "refused") "and with the gate refused"
    Check ($fake.installs -eq 0) "CONTROL: the scheduler was never asked"
    Set-Gate '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-10-01T00:00:00Z" }'
    $out = @(Invoke-HordeMetricsSchedule -Action install -TaskName "fake job" -Folder "HordeTest" -HordeScript $horde)
    Check ($fake.installs -eq 1 -and $fake.jobs.ContainsKey("HordeTest\fake job") -and $out[0] -like "installed 'fake job' in fake folder HordeTest*every 30 minutes*") "with the gate on usage, install hands the job to the scheduler and says what it did"
    $stat = @(Invoke-HordeMetricsSchedule -Action status -TaskName "fake job" -Folder "HordeTest" -HordeScript $horde)
    Check ($stat[0] -eq "metrics gate: usage" -and $stat[1] -like "'fake job' in fake folder HordeTest: enabled, Ready, every 30 minutes*Horde's") "status shows the gate and the job"
    Check ((@(Invoke-HordeMetricsSchedule -Action remove -TaskName "fake job" -Folder "HordeTest" -HordeScript $horde))[0] -like "removed*") "remove removes it"
    Check ((@(Invoke-HordeMetricsSchedule -Action status -TaskName "fake job" -Folder "HordeTest" -HordeScript $horde))[1] -like "*is not installed") "and then status says it is not installed"
    Check ((@(Invoke-HordeMetricsSchedule -Action remove -TaskName "fake job" -Folder "HordeTest" -HordeScript $horde))[0] -like "no job*") "removing what is not there says so"
    Check (Throws { Invoke-HordeMetricsSchedule -Action remove -TaskName "C:\Windows\x" -Folder "HordeTest" -HordeScript $horde } "not a job name") "remove applies the name rule too: no arbitrary name reaches a scheduler"
    Check (Throws { Invoke-HordeMetricsSchedule -Action remove -TaskName "fake job" -Folder "Microsoft" -HordeScript $horde } "not one of Horde's scheduler folders") "and acts only in Horde's own folders"
    Register-HordeScheduler -Name "fake" -Available { $true } -Install { param($j) } -Remove { param($n, $f) $false } -Status { param($n, $f) New-HordeAbsent -Note "none" }
    Check (Throws { Invoke-HordeMetricsSchedule -Action install -TaskName "fake job" -Folder "HordeTest" -HordeScript $horde } "did not keep") "a scheduler that does not keep the job makes install fail; it never reports success it did not see"
    Register-HordeScheduler -Name "fake" -Available { $false } -Install { } -Remove { } -Status { }
    Check (Throws { Invoke-HordeMetricsSchedule -Action status -TaskName "fake job" -Folder "HordeTest" -HordeScript $horde } "no scheduler works") "with no scheduler that works here, every action says so"
    $script:HordeSchedulers.Clear()
    foreach ($s in $saveSchedulers) { [void]$script:HordeSchedulers.Add($s) }

    foreach ($s in (Get-HordeSchedulerFiles)) { . $s }
    $real = Get-HordeScheduler
    if ($real.state -ne "known") {
        Write-Host ("  [SKIP] " + $real.reason)
    } else {
        $sch = $real.value

        Write-Host ""
        Write-Host "--- no value is ever parsed as code (review of PR #70, F2) ---" -ForegroundColor Cyan
        # Each hostile home is set on a job whose script is a stub that writes back what it received; the
        # action this scheduler would register is run directly, and must hand the stub exactly the value.
        $stubDir = Join-Path $work "stub dir & 50% `$(x) 'q'"
        [void][System.IO.Directory]::CreateDirectory($stubDir)
        $stub = Join-Path $stubDir "stub.ps1"
        $seen = Join-Path $work "seen.txt"
        [System.IO.File]::WriteAllText($stub, ('[System.IO.File]::WriteAllText("' + $seen + '", ($env:HORDE_HOME + "|" + ($args -join ",")), (New-Object System.Text.UTF8Encoding($false)))'))
        $pwnedName = "pwned.txt"
        $hostile = @(
            ("curly single " + [char]0x2019 + "; Set-Content -LiteralPath (Join-Path '" + $work + "' '" + $pwnedName + "') x; " + [char]0x2018),
            ("curly double " + [char]0x201D + "; Set-Content -LiteralPath (Join-Path '" + $work + "' '" + $pwnedName + "') x; " + [char]0x201C),
            "amp & pct %USERNAME% bang!",
            ("backtick `` `$(Set-Content -LiteralPath (Join-Path '" + $work + "' '" + $pwnedName + "') x) end"),
            "plain 'single' and ""double"" quotes"
        )
        foreach ($h in $hostile) {
            if (Test-Path -LiteralPath $seen) { Remove-Item -LiteralPath $seen -Force }
            $j = New-HordeScheduledJob -Name "x TEST" -Folder "HordeTest" -Script $stub -Arguments @("metrics", "collect") -Environment @{ HORDE_HOME = (Join-Path $work $h) } -HordeHome (Join-Path $work $h)
            $act = ConvertTo-HordeTaskAction -Job $j
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $act.program; $psi.Arguments = $act.arguments; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $p = [System.Diagnostics.Process]::Start($psi); $p.WaitForExit(); $p.Dispose()
            $got = ""; if (Test-Path -LiteralPath $seen) { $got = [System.IO.File]::ReadAllText($seen) }
            Check ($got -ceq ((Join-Path $work $h) + "|metrics,collect") -and -not (Test-Path -LiteralPath (Join-Path $work $pwnedName))) ("the job's program receives the home exactly, and runs nothing it holds: " + $h.Substring(0, [Math]::Min(14, $h.Length)))
        }
        $personJob = New-HordeScheduledJob -Name ($testName + " person") -Folder "HordeTest" -Script $stub -Arguments @("services", "tend") -Environment @{ HORDE_HOME = $env:HORDE_HOME } -HordeHome $env:HORDE_HOME -EveryMinutes 1 -TimeLimitMinutes 1 -WithPerson -Disabled
        $personAct = ConvertTo-HordeTaskAction -Job $personJob
        $sysDir = [System.Environment]::SystemDirectory
        Check ($personAct.program -ceq (Join-Path $sysDir "conhost.exe") -and $personAct.arguments.StartsWith('--headless "' + (Join-Path $sysDir "WindowsPowerShell\v1.0\powershell.exe") + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand ') -and $personAct.arguments -match ' -EncodedCommand [A-Za-z0-9+/=]+\z' -and (ConvertTo-HordeTaskAction -Job $job).program -ceq (Join-Path $sysDir "WindowsPowerShell\v1.0\powershell.exe")) "a -WithPerson job is run by the headless console host, so no window flashes in the person's session - the console host and the shell it runs both by their FULL paths in the system folder, never a bare name a search path could answer; any other job by PowerShell itself, by its full path too"
        Check ((ConvertTo-HordeTaskAction -Job $job).arguments -match '\A[A-Za-z -]+-EncodedCommand [A-Za-z0-9+/=]+\z') "the arguments are fixed switches and base64 only: no quote, no %, nothing a shell or the scheduler could read"

        Write-Host ""
        Write-Host "--- a job that runs at start-up, whether or not anyone is signed in: built, and registered only through a stand-in ---" -ForegroundColor Cyan
        # Nothing here reaches the real scheduler: the task is built and read, and -Find and -Register
        # are this suite's own blocks, which record what they were handed.
        Check (Throws { New-HordeScheduledJob -Name "x" -Script "s" -HordeHome "h" -AtStartup -WithPerson } "cannot run at start-up") "a job in the person's own session cannot also run at start-up, before anyone has signed in"
        $bootJob = New-HordeScheduledJob -Name ($testName + " boot") -Folder "HordeTest" -Script $stub -Arguments @("services", "tend") -Environment @{ HORDE_HOME = $env:HORDE_HOME } -HordeHome $env:HORDE_HOME -EveryMinutes 1 -TimeLimitMinutes 5 -MayOutlastInterval -AtStartup -Disabled
        Check ($bootJob.atStartup -eq $true -and $bootJob.withPerson -eq $false -and $job.atStartup -eq $false) "-AtStartup is carried on the job; a job made without it has none"
        $bootTask = New-HordeTaskSchedulerTask -Job $bootJob -UserId "someone"
        $trig = @($bootTask.Triggers)
        Check ($trig.Count -eq 2 -and "$($trig[0].CimClass.CimClassName)" -ceq "MSFT_TaskTimeTrigger" -and "$($trig[0].Repetition.Interval)" -ceq "PT1M" -and "$($trig[1].CimClass.CimClassName)" -ceq "MSFT_TaskBootTrigger") "schedule registers the tend job with a startup trigger and a one-minute repetition - the repetition first, where status reads the interval"
        Check ("$($bootTask.Principal.LogonType)" -ceq "S4U" -and "$($bootTask.Principal.RunLevel)" -ceq "Limited" -and "$($bootTask.Principal.UserId)" -ceq "someone") "logon type S4U, run level Limited, as the user named: it runs whether or not anyone is signed in, and no password is stored"
        Check ("$(@($bootTask.Actions)[0].Execute)" -ceq (Join-Path ([System.Environment]::SystemDirectory) "WindowsPowerShell\v1.0\powershell.exe") -and "$(@($bootTask.Actions)[0].Arguments)" -match '\A-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand [A-Za-z0-9+/=]+\z') "it runs PowerShell itself, by its full path, hidden and non-interactive: no console host, which would answer 0 whatever the pass did"
        Check (@((New-HordeTaskSchedulerTask -Job $job -UserId "someone").Triggers).Count -eq 1) "CONTROL: a job not made -AtStartup has the repetition alone"
        $calls = New-Object System.Collections.ArrayList
        $none = { param($Name, $Folder) return $null }
        $keep = { param($Task, $Name, $Path) [void]$calls.Add([pscustomobject]@{ task = $Task; name = $Name; path = $Path; given = $args.Count }) }
        Install-HordeTaskSchedulerJob -Job $bootJob -Find $none -Register $keep
        Check ($calls.Count -eq 1 -and $calls[0].name -ceq $bootJob.name -and $calls[0].path -ceq "\HordeTest\" -and "$($calls[0].task.Principal.LogonType)" -ceq "S4U" -and $calls[0].given -eq 0 -and @($calls[0].task.Triggers).Count -eq 2) "install registers the task once, by its name in Horde's folder, S4U, with nothing else handed over - no password"
        # The job that was there: Horde's, for this home, made in the person's session.
        $oldInteractive = [pscustomobject]@{ Author = "Horde"; Description = $bootJob.description; Principal = [pscustomobject]@{ LogonType = "Interactive" } }
        $calls.Clear()
        Install-HordeTaskSchedulerJob -Job $bootJob -Find { param($Name, $Folder) return $oldInteractive } -Register $keep
        Check ($calls.Count -eq 1 -and $calls[0].name -ceq $bootJob.name -and $calls[0].path -ceq "\HordeTest\" -and "$($calls[0].task.Principal.LogonType)" -ceq "S4U") "schedule replaces an existing interactive tend job, never two: one registration, under the very name and folder it had"
        $calls.Clear()
        $refuse = { param($Task, $Name, $Path) [void]$calls.Add([pscustomobject]@{ task = $Task; name = $Name; path = $Path; given = 0 }); throw "Access is denied." }
        $said = ""
        try { Install-HordeTaskSchedulerJob -Job $bootJob -Find { param($Name, $Folder) return $oldInteractive } -Register $refuse } catch { $said = $_.Exception.Message }
        Check ($said -like "*refused to register*Access is denied.*the task that was there is left exactly as it was*run this again from an elevated prompt*") ("a failed S4U registration is reported plainly, with what to do (" + $said + ")")
        Check ($calls.Count -eq 1 -and "$($calls[0].task.Principal.LogonType)" -ceq "S4U") "with no silent fallback to interactive: the scheduler was asked once, for the S4U job, and never for another form"
        $calls.Clear(); $said = ""
        try { Install-HordeTaskSchedulerJob -Job $job -Find $none -Register $refuse } catch { $said = $_.Exception.Message }
        Check ($said -like "*refused to register*nothing was registered.") ("CONTROL: a job that does not run at start-up is not told to need an elevated prompt (" + $said + ")")

        Write-Host ""
        Write-Host "--- this machine's scheduler: Horde's own folder, Horde's own tasks (review of PR #70, F1) ---" -ForegroundColor Cyan
        Assert-TestName $testName
        $foreignRoot = $testName + " foreign"
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $foreignTask = { param($n, $p) $a = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c rem foreign"; $pr = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited; $st = New-ScheduledTaskSettingsSet -Disable; $null = Register-ScheduledTask -TaskName $n -TaskPath $p -Action $a -Principal $pr -Settings $st -Description "FOREIGN, not Horde's" -Force }
        $tasksIn = { param($p) @(Get-ScheduledTask -TaskPath $p -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "*TEST*" }) }
        try {
            # A task of the very name, in Horde's folder, that Horde did not make.
            & $foreignTask $testName "\HordeTest\"
            Check (Throws { Invoke-HordeMetricsSchedule -Action install -TaskName $testName -Folder "HordeTest" -Disabled -HordeScript $horde } "not made by Horde") "install refuses to overwrite a task of that name Horde did not make"
            Check (Throws { Invoke-HordeMetricsSchedule -Action remove -TaskName $testName -Folder "HordeTest" -HordeScript $horde } "not made by Horde") "and remove refuses to delete it"
            Check ((@(& $tasksIn "\HordeTest\" | Where-Object { $_.TaskName -ceq $testName -and $_.Description -like "FOREIGN*" })).Count -eq 1) "the task the user made is still there, as it was"
            Unregister-ScheduledTask -TaskName $testName -TaskPath "\HordeTest\" -Confirm:$false
            # A task of the same name outside Horde's folder is never seen.
            & $foreignTask $testName "\"
            $i1 = "installed"; try { $null = Invoke-HordeMetricsSchedule -Action install -TaskName $testName -Folder "HordeTest" -Disabled -HordeScript $horde } catch { $i1 = $_.Exception.Message }
            Check ($i1 -eq "installed") ("install succeeds and sees its own job afterwards (" + $i1 + ")")
            $st = & $sch.status $testName "HordeTest"
            Check ($st.state -eq "known" -and $st.value.marked -and $st.value.author -eq "Horde" -and $st.value.enabled -eq $false -and $st.value.home -eq $env:HORDE_HOME) "install makes the job in Horde's folder, marked as Horde's, for this home, disabled"
            Check ($st.value.everyMinutes -eq 30 -and "$($st.value.priority)" -eq "7" -and $st.value.timeLimit -eq "PT20M" -and $st.value.logonType -eq "S4U" -and $st.value.atStartup -eq $false) "every 30 minutes, priority 7, stopped after 20 minutes, as the current user with no window, and not at start-up"
            $again = "installed"
            try { $null = Invoke-HordeMetricsSchedule -Action install -TaskName $testName -Folder "HordeTest" -Disabled -HordeScript $horde } catch { $again = $_.Exception.Message }
            Check ($again -eq "installed" -and @(& $tasksIn "\HordeTest\").Count -eq 1) ("installing again replaces Horde's own job: one job, not two (" + $again + ")")
            $realHome = $env:HORDE_HOME
            $env:HORDE_HOME = Join-Path $work "another home"
            Set-Gate '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-10-01T00:00:00Z" }'
            Check (Throws { Invoke-HordeMetricsSchedule -Action install -TaskName $testName -Folder "HordeTest" -Disabled -HordeScript $horde } "serves the Horde home") "a job serving one home is not taken over for another"
            $env:HORDE_HOME = $realHome
            $envs = @{ HORDE_HOME = $env:HORDE_HOME }
            $cs = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "status", "-TaskName", $testName, "-TaskFolder", "HordeTest") -Env $envs
            Check ($cs.code -eq 0 -and $cs.out -like "*metrics gate: usage*" -and $cs.out -like "*DISABLED*Horde's*") "horde metrics schedule status shows the gate and the job"
            $cr = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "remove", "-TaskName", $testName, "-TaskFolder", "HordeTest") -Env $envs
            Check ($cr.code -eq 0 -and $cr.out -like "*removed*" -and (& $sch.status $testName "HordeTest").state -eq "absent") "horde metrics schedule remove removes it"
            # A -WithPerson job (core/Schedule.ps1): the person's own session, and only while logged on.
            Assert-TestName $personJob.name
            & $sch.install $personJob
            $pst = & $sch.status $personJob.name "HordeTest"
            Check ($pst.state -eq "known" -and $pst.value.logonType -eq "Interactive" -and $pst.value.program -ceq (Join-Path ([System.Environment]::SystemDirectory) "conhost.exe") -and $pst.value.everyMinutes -eq 1 -and $pst.value.enabled -eq $false -and $pst.value.marked) "a -WithPerson job is installed with an interactive logon, run by the console host, and disabled when asked"
            Check ((& $sch.remove $personJob.name "HordeTest") -eq $true -and (& $sch.status $personJob.name "HordeTest").state -eq "absent") "and removed like any Horde job"
            Check ((@(& $tasksIn "\" | Where-Object { $_.TaskName -ceq $testName -and $_.Description -like "FOREIGN*" })).Count -eq 1) "and the task of the same name outside Horde's folder was never touched"
            $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
            $folderGone = $false; try { $null = $svc.GetFolder("\HordeTest") } catch { $folderGone = $true }
            Check $folderGone "removing the last job removes Horde's test folder too"
            $cb = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "remove", "-TaskName", $testName, "-TaskFolder", "Microsoft") -Env $envs
            Check ($cb.code -ne 0) "a folder that is not Horde's is refused by the command"
        } finally {
            Assert-TestName $testName
            foreach ($p in @("\HordeTest\", "\")) { foreach ($t in @(& $tasksIn $p)) { if ($t.TaskName -like ($testName + "*")) { Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $p -Confirm:$false } } }
            try { $svc2 = New-Object -ComObject Schedule.Service; $svc2.Connect(); $f2 = $svc2.GetFolder("\HordeTest"); if ($f2.GetTasks(1).Count -eq 0) { $svc2.GetFolder("\").DeleteFolder("HordeTest", 0) } } catch { }
        }
        Check (@(& $tasksIn "\HordeTest\").Count -eq 0 -and @(& $tasksIn "\" | Where-Object { $_.TaskName -like ($testName + "*") }).Count -eq 0) "nothing this suite made is left in the scheduler"
    }
} finally {
    $env:HORDE_HOME = $savedHome
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "the collect job is data, passed without quoting, and installed, shown and removed only as Horde's own"
