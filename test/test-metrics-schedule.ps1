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
    Check ($job.script -eq $horde -and (@($job.arguments) -join " ") -eq "metrics collect" -and -not $job.environment.ContainsKey("HORDE_HOME") -and $job.hordeHome -eq $env:HORDE_HOME) "the job is this checkout's horde.ps1, metrics collect, with NO home baked in (it resolves HORDE_HOME, then the pointer, at each run); its marker records the home it was registered under"
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
        # T-0325: a shell refused new S4U tasks skips the real install checks, so what the task carries is
        # checked here, on what the scheduler is handed, in every shell.
        Check ($calls[0].task.Settings.Priority -eq 7 -and "$($calls[0].task.Settings.ExecutionTimeLimit)" -ceq "PT5M") ("the task is handed below-normal priority and the job's own time limit (" + $calls[0].task.Settings.Priority + ", " + $calls[0].task.Settings.ExecutionTimeLimit + ")")
        $otherHomeJob = New-HordeScheduledJob -Name ($testName + " boot") -Folder "HordeTest" -Script $stub -Arguments @("services", "tend") -HordeHome (Join-Path $env:TEMP ($testName + " other home")) -EveryMinutes 1 -TimeLimitMinutes 5 -MayOutlastInterval -AtStartup -Disabled
        $oldOtherHome = [pscustomobject]@{ Author = "Horde"; Description = $otherHomeJob.description; Principal = [pscustomobject]@{ LogonType = "S4U" } }
        $calls.Clear()
        # T-0299: the marker's home is a label, not a bake, so a Horde task registered under the OLD home is replaced (the one
        # re-register after horde home set), and the new task's marker names the home resolved now.
        $threw = $false
        try { Install-HordeTaskSchedulerJob -Job $bootJob -Find { param($Name, $Folder) return $oldOtherHome } -Register $keep } catch { $threw = $true }
        Check (-not $threw -and $calls.Count -eq 1) "a Horde task registered under another home is REPLACED (the flip's re-register), not refused"
        Check ($calls.Count -eq 1 -and (Read-HordeJobMarker -Description $calls[0].task.Description).home -ceq $bootJob.hordeHome) "and the new task's marker names the home resolved now"
        $notMine = [pscustomobject]@{ Author = "Someone"; Description = "their own task"; Principal = [pscustomobject]@{ LogonType = "S4U" } }
        $calls.Clear()
        Check (Throws { Install-HordeTaskSchedulerJob -Job $bootJob -Find { param($Name, $Folder) return $notMine } -Register $keep } "was not made by Horde") "CONTROL: a task Horde did not make is still left alone"
        Check ($calls.Count -eq 0) "and the scheduler was never asked"
        # The real registration overwrites Horde's own task (-Force); the cmdlet is stood in for, in this scope only.
        $script:forcedRegister = $null
        function Register-ScheduledTask { param($InputObject, [string]$TaskName, [string]$TaskPath, [switch]$Force, $ErrorAction) $script:forcedRegister = $Force.IsPresent }
        try { Install-HordeTaskSchedulerJob -Job $bootJob -Find { param($Name, $Folder) return $oldInteractive } -Elevated { $false } } finally { Remove-Item Function:\Register-ScheduledTask }
        Check ($script:forcedRegister -eq $true) "installing over Horde's own task asks the scheduler to replace it (-Force), so a second install does not fail"
        # The job that was there: Horde's, for this home, made in the person's session.
        $oldInteractive = [pscustomobject]@{ Author = "Horde"; Description = $bootJob.description; Principal = [pscustomobject]@{ LogonType = "Interactive" } }
        $calls.Clear()
        Install-HordeTaskSchedulerJob -Job $bootJob -Find { param($Name, $Folder) return $oldInteractive } -Register $keep
        Check ($calls.Count -eq 1 -and $calls[0].name -ceq $bootJob.name -and $calls[0].path -ceq "\HordeTest\" -and "$($calls[0].task.Principal.LogonType)" -ceq "S4U") "schedule replaces an existing interactive tend job, never two: one registration, under the very name and folder it had"
        $calls.Clear()
        $refuse = { param($Task, $Name, $Path) [void]$calls.Add([pscustomobject]@{ task = $Task; name = $Name; path = $Path; given = 0 }); throw "Access is denied." }
        $said = ""
        try { Install-HordeTaskSchedulerJob -Job $bootJob -Find { param($Name, $Folder) return $oldInteractive } -Register $refuse -Elevated { $false } } catch { $said = $_.Exception.Message }
        Check ($said -like "*refused to register*Access is denied.*the task that was there is left exactly as it was*run this again from an elevated prompt*") ("a failed S4U registration is reported plainly, with what to do (" + $said + ")")
        Check ($calls.Count -eq 1 -and "$($calls[0].task.Principal.LogonType)" -ceq "S4U") "with no silent fallback to interactive: the scheduler was asked once, for the S4U job, and never for another form"
        $refuseOther = { param($Task, $Name, $Path) throw "The RPC server is unavailable." }
        $calls.Clear(); $said = ""
        try { Install-HordeTaskSchedulerJob -Job $job -Find $none -Register $refuseOther -Elevated { $false } } catch { $said = $_.Exception.Message }
        Check ($said -like "*refused to register*nothing was registered.") ("CONTROL: a job that does not run at start-up is not told to need an elevated prompt (" + $said + ")")
        # T-0325: a non-elevated shell is refused a NEW S4U job of any kind (measured 2026-10-21), so
        # Access denied gets the hint for every job - but only when not elevated.
        $said = ""
        try { Install-HordeTaskSchedulerJob -Job $job -Find $none -Register $refuse -Elevated { $false } } catch { $said = $_.Exception.Message }
        Check ($said -like "*(Access is denied.)*nothing was registered.*may not be allowed*run this again from an elevated prompt*") ("a job that does not run at start-up, refused with Access denied in a shell that is not elevated, is told to elevate (" + $said + ")")
        $said = ""
        try { Install-HordeTaskSchedulerJob -Job $job -Find $none -Register $refuse -Elevated { $true } } catch { $said = $_.Exception.Message }
        Check ($said -like "*(Access is denied.)*nothing was registered." -and $said -notlike "*elevated prompt*") ("the same refusal in an elevated shell is not told to elevate (" + $said + ")")

        $calls.Clear(); $said = ""
        try { Install-HordeTaskSchedulerJob -Job $bootJob -Find $none -Register $refuse -Elevated { $true } } catch { $said = $_.Exception.Message }
        Check ($said -like "*refused to register*Access is denied.*nothing was registered." -and $said -notlike "*elevated prompt*") ("an elevated process that is refused is not told to elevate: the scheduler's own words say why (" + $said + ")")
        $calls.Clear(); $said = ""
        try { Install-HordeTaskSchedulerJob -Job $bootJob -Find $none -Register $refuse -Elevated { $false } } catch { $said = $_.Exception.Message }
        $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Check ($said -like ("*to run as " + $me + " (Access is denied.)*can be registered only by an administrator: run this again from an elevated prompt, signed in as " + $me + ", the account the job runs as."))("one that is not elevated is told to elevate, and which account the job runs as (" + $said + ")")
        $logonJob = New-HordeScheduledJob -Name ($testName + " logon") -Folder "HordeTest" -Script $stub -Arguments @("services", "tend") -HordeHome $env:HORDE_HOME -EveryMinutes 1 -TimeLimitMinutes 5 -MayOutlastInterval -WithPerson -AtLogon -Disabled
        $lt = @((New-HordeTaskSchedulerTask -Job $logonJob -UserId "someone").Triggers)
        Check ($logonJob.atLogon -eq $true -and $lt.Count -eq 2 -and "$($lt[0].Repetition.Interval)" -ceq "PT1M" -and "$($lt[1].CimClass.CimClassName)" -ceq "MSFT_TaskLogonTrigger" -and "$($lt[1].UserId)" -ceq "someone") "a job made -AtLogon also runs when the account it runs as signs in"
        Check ("$((New-HordeTaskSchedulerTask -Job $logonJob -UserId "someone").Principal.LogonType)" -ceq "Interactive") "a job made -WithPerson runs in the person's session (Interactive), never unseen"

        Write-Host ""
        Write-Host "--- what this machine's scheduler is asked, with its listing stood in for (review of PR 249, N1 and N2) ---" -ForegroundColor Cyan
        # A function of the cmdlet's name answers in its place, in this scope only, and is removed after.
        function Get-ScheduledTask { param([string]$TaskPath, [string]$TaskName, $ErrorAction) throw (New-Object System.InvalidOperationException "The RPC server is unavailable.") }
        $listErr = ""
        try { $null = Get-HordeTaskSchedulerTask -Name "x" -Folder "HordeTest" } catch { $listErr = $_.Exception.Message }
        Check ($listErr -like "*could not be read: The RPC server is unavailable.*") ("a listing that fails is an error, never read as no such task (" + $listErr + ")")
        $bootFirst = New-ScheduledTask -Action (New-ScheduledTaskAction -Execute "cmd.exe") -Trigger @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 7))) -Principal (New-ScheduledTaskPrincipal -UserId "PC\person" -LogonType S4U -RunLevel Limited) -Description $bootJob.description
        $bootFirst.Author = "Horde"
        $fakeTask = [pscustomobject]@{ TaskName = "x"; Author = "Horde"; Description = $bootJob.description; Triggers = $bootFirst.Triggers; Settings = $bootFirst.Settings; Principal = $bootFirst.Principal; State = "Ready"; Actions = $bootFirst.Actions }
        function Get-ScheduledTask { param([string]$TaskPath, [string]$TaskName, $ErrorAction) return $fakeTask }
        function Get-ScheduledTaskInfo { param([string]$TaskPath, [string]$TaskName, $ErrorAction) return $null }
        $fst = Get-HordeTaskSchedulerStatus -Name "x" -Folder "HordeTest"
        Check ($fst.state -ceq "known" -and $fst.value.everyMinutes -eq 7 -and $fst.value.atStartup -eq $true -and $fst.value.runsAs -ceq "PC\person") ("the interval is read from the trigger that repeats, wherever it stands, and status names the account it runs as (" + $fst.value.everyMinutes + ")")
        $plainTask = New-ScheduledTask -Action (New-ScheduledTaskAction -Execute "cmd.exe") -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 7)) -Principal (New-ScheduledTaskPrincipal -UserId "PC\person" -LogonType S4U -RunLevel Limited) -Description $bootJob.description
        $fakeTask = [pscustomobject]@{ TaskName = "x"; Author = "Horde"; Description = $bootJob.description; Triggers = $plainTask.Triggers; Settings = $plainTask.Settings; Principal = $plainTask.Principal; State = "Ready"; Actions = $plainTask.Actions }
        $pst = Get-HordeTaskSchedulerStatus -Name "x" -Folder "HordeTest"
        Check ($pst.state -ceq "known" -and $pst.value.atStartup -eq $false) "CONTROL: a task with no start-up trigger is not shown as running at start-up"
        Remove-Item Function:\Get-ScheduledTask, Function:\Get-ScheduledTaskInfo

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
            # A BARE PROBE FIRST (T-0325, measured 2026-10-21): this shell may not be allowed to register a NEW S4U task
            # at all (non-elevated: "Access is denied"), whatever Horde does. A task of no Horde code, disabled, TEST in
            # its name, removed in finally, says which case this is; only the probe may excuse the checks below.
            $probeName = $testName + " probe"
            $probeS4U = {
                Assert-TestName $probeName
                try {
                    $pa = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c rem probe"
                    $pp = New-ScheduledTaskPrincipal -UserId $user -LogonType S4U -RunLevel Limited
                    $ps = New-ScheduledTaskSettingsSet -Disable
                    $pt = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(30))
                    $null = Register-ScheduledTask -TaskName $probeName -TaskPath "\HordeTest\" -Action $pa -Principal $pp -Settings $ps -Trigger $pt -ErrorAction Stop
                    return ""
                } catch { return ("" + $_.Exception.Message).Trim() }
                finally { if (@(& $tasksIn "\HordeTest\" | Where-Object { $_.TaskName -ceq $probeName }).Count -gt 0) { Unregister-ScheduledTask -TaskName $probeName -TaskPath "\HordeTest\" -Confirm:$false } }
            }
            $probeSaid = & $probeS4U
            Check ($probeSaid -eq "" -or $probeSaid -like "*Access is denied*") ("CONTROL: the bare S4U probe either registers or is refused with Access is denied (" + $probeSaid + ")")
            $envs = @{ HORDE_HOME = $env:HORDE_HOME }
            if ($probeSaid -eq "") {
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
                $moved = "installed"
                try { $null = Invoke-HordeMetricsSchedule -Action install -TaskName $testName -Folder "HordeTest" -Disabled -HordeScript $horde } catch { $moved = $_.Exception.Message }
                Check ($moved -eq "installed" -and (& $sch.status $testName "HordeTest").value.home -eq $env:HORDE_HOME) "a job registered under one home is replaced for another (the flip), and its marker names the new home"
                $env:HORDE_HOME = $realHome
                $envs = @{ HORDE_HOME = $env:HORDE_HOME }
                $cs = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "status", "-TaskName", $testName, "-TaskFolder", "HordeTest") -Env $envs
                Check ($cs.code -eq 0 -and $cs.out -like "*metrics gate: usage*" -and $cs.out -like "*DISABLED*Horde's*") "horde metrics schedule status shows the gate and the job"
                $cr = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "remove", "-TaskName", $testName, "-TaskFolder", "HordeTest") -Env $envs
                Check ($cr.code -eq 0 -and $cr.out -like "*removed*" -and (& $sch.status $testName "HordeTest").state -eq "absent") "horde metrics schedule remove removes it"
            } else {
                Set-Gate '{ "schemaVersion": 1, "level": "usage", "enabledAt": "2026-10-01T00:00:00Z" }'
                $ci = Invoke-HordeCliProcess -Root $root -HordeArgs @("metrics", "schedule", "install", "-TaskName", $testName, "-TaskFolder", "HordeTest", "-Disabled") -Env $envs
                Check ($ci.code -ne 0 -and $ci.out -like "*refused to register*Access is denied*run this again from an elevated prompt*") ("refused by the scheduler, install exits non-zero and says to run elevated (" + $ci.out.Trim() + ")")
                Check (@(& $tasksIn "\HordeTest\").Count -eq 0 -and (& $sch.status $testName "HordeTest").state -eq "absent") "and it registered nothing: no job in Horde's folder, in any logon type"
                Write-Host "  [SKIP] this shell may not register S4U tasks (bare probe refused); the install/replace/status/remove checks need an elevated run"
            }
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
