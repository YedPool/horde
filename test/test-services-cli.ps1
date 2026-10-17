# END TO END, THE WAY A PERSON WOULD: DOES `horde services` KEEP A SERVICE RUNNING, SAY SO, AND SCHEDULE
# ITSELF - AND DOES `horde rollout` REFUSE WHAT IT SHOULD?
#
# The shipped horde.ps1, run as its own process (test/lib/Cli.ps1), against Horde homes this suite
# makes in temp. cli/commands/services.ps1 and cli/commands/rollout.ps1.
#
# NOTHING OF THIS MACHINE'S IS STARTED, STOPPED, SCHEDULED FOR REAL OR TOLD (CONTRIBUTING 9):
#   - THE ONE SERVICE the real supervisor starts here is a STUB this suite writes: a script named
#     horde.ps1 in a temp folder that is not horde, writes a heartbeat into the suite's folder, and
#     ends by itself after 90 s or as soon as the suite's stop file appears. The stop file is written
#     in the finally block whatever happened, so a stub started again would end at once; and what the
#     supervisor recorded as its process is ended there by pid AND start time, never by a name.
#   - EVERY HOME SETS tellWarchief FALSE, so no pass of this suite can post to a session.
#   - THE SCHEDULED JOB is made in the scheduler folder HordeTest, never Horde, under a name with TEST
#     in it, DISABLED, so it never runs; it is removed, and the folder checked to be gone.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "cli\ServicesAct.ps1")
. (Join-Path $root "test\lib\Cli.ps1")

$work = Join-Path $env:TEMP ("horde-services-cli-" + [guid]::NewGuid().ToString("N"))
[void][System.IO.Directory]::CreateDirectory($work)
function Esc { param([string]$Path) return $Path.Replace("\", "\\") }
function New-Home {
    param([string]$Name, [string]$Definitions = "")
    $h = Join-Path $work $Name
    [void][System.IO.Directory]::CreateDirectory((Join-Path $h "settings"))
    [System.IO.File]::WriteAllText((Join-Path $h "settings\services.json"), '{ "schemaVersion": 1, "settings": { "tellWarchief": false } }')
    if ($Definitions -ne "") { [System.IO.File]::WriteAllText((Join-Path $h "settings\service-definitions.json"), ('{ "schemaVersion": 1, "settings": { ' + $Definitions + ' } }')) }
    return $h
}
# WEZFLEET_ROOT is where a seat would be looked up: every command of this suite is pointed at an empty
# folder of the suite's own, so a tell could find no session even if both other guards failed -
# tellWarchief false in every home, and the teller's own refusal of a home under the temp folder.
function Horde { param([string]$HordeHome, [string[]]$A) return (Invoke-HordeCliProcess -Root $root -HordeArgs $A -Env @{ HORDE_HOME = $HordeHome; WEZFLEET_ROOT = (Join-Path $work "no-fleet-here") }) }
$testName = "Horde services tend TEST " + [guid]::NewGuid().ToString("N").Substring(0, 12)
function Assert-TestName { param([string]$Name) if ($Name -notlike "*TEST*") { throw ("refusing to act on a job this suite did not name: '" + $Name + "'") } }
$stubHome = Join-Path $work "stub served"
$stopFile = Join-Path $stubHome "stop"
$sup = $null

try {
    Write-Host ""
    Write-Host "--- the commands are listed, and take only what is theirs ---" -ForegroundColor Cyan
    $empty = New-Home "empty"
    $help = Horde $empty @("help")
    Check ($help.code -eq 0 -and $help.out -like "*long-lived pieces kept running and current*" -and $help.out -like "*services tend*" -and $help.out -like "*rollout*") "help lists services and rollout under their own heading"
    Check ((Horde $empty @("services")).code -eq 2) "services with no verb is a usage error"
    Check ((Horde $empty @("services", "restart")).code -eq 2) "and so is a verb it does not have"
    $wrong = Horde $empty @("services", "tend", "-Json")
    Check ($wrong.code -eq 1 -and $wrong.out -like "*-Json does not belong to services tend*") "a flag meant for another verb is refused, never ignored"
    Check ((Horde $empty @("services", "schedule", "now")).out -like "*takes nothing, or status, after it*") "schedule takes nothing, or status"
    Check ((Horde $empty @("services", "unschedule", "-Disabled")).out -like "*-Disabled does not belong to services unschedule*") "-Disabled belongs to schedule"
    $noName = Horde $empty @("services", "stop")
    Check ($noName.code -eq 1 -and $noName.out -like "*services stop needs the name of a service*") "stop needs the name of a service"
    $noSuch = Horde $empty @("services", "start", "nope")
    Check ($noSuch.code -eq 1 -and $noSuch.out -like "*no service named 'nope' is defined*") "start of a service that is not defined fails, naming it"

    Write-Host ""
    Write-Host "--- a home with nothing defined ---" -ForegroundColor Cyan
    $st = Horde $empty @("services", "status")
    Check ($st.code -eq 0 -and $st.out -like "*supervisor: the supervisor has never run in this home*" -and $st.out -like "*definitions: no service is defined*") "status says the supervisor has never run here, and that nothing is defined"
    $t = Horde $empty @("services", "tend")
    Check ($t.code -eq 0 -and $t.out -like "*no service is defined*nothing to tend*") "tend runs, with nothing to tend"
    $st = Horde $empty @("services", "status")
    Check ($st.out -like "*supervisor: the supervisor's last pass was * s ago*") "and after it, status says the supervisor's pass has come round"
    $j = Horde $empty @("services", "status", "-Json")
    $parsed = $null; try { $parsed = ($j.out.Trim() -split "`n")[0] | ConvertFrom-Json } catch { $parsed = $null }
    Check ($j.code -eq 0 -and $null -ne $parsed -and $parsed.supervisor.state -ceq "running" -and $parsed.definitions.state -ceq "none" -and @($parsed.services).Count -eq 0 -and $parsed.home -ceq $empty) "status -Json is one line of data saying the same"
    $ro = Horde $empty @("rollout")
    Check ($ro.code -eq 0 -and $ro.out -like "*no service is defined; nothing was rolled out*") "rollout with nothing defined has nothing to do, and says so"
    $no = Horde $empty @("rollout", "nope")
    Check ($no.code -eq 1 -and $no.out -like "*no service named 'nope' is defined*") "rollout of a service that is not defined fails, naming it"

    Write-Host ""
    Write-Host "--- a refused definitions file supervises nothing, loudly ---" -ForegroundColor Cyan
    $bad = New-Home "bad" '"svc": { "start": { "kind": "horde", "words": ["relay"] }, "stop": { "kind": "kill" }, "password": "x" }'
    $t = Horde $bad @("services", "tend")
    Check ($t.code -eq 1 -and $t.out -like "*service-definitions.json' is refused*" -and $t.out -like "*has the member 'password'*") "tend fails with every finding, and tends nothing"
    $st = Horde $bad @("services", "status")
    Check ($st.code -eq 0 -and $st.out -like "*NO SERVICE IS SUPERVISED until that file is mended*") "status says nothing is supervised until the file is mended"
    Check ((Horde $bad @("rollout")).code -eq 1) "and rollout fails the same way"

    Write-Host ""
    Write-Host "--- the installed CLI follows main through the real command (cli/ServicesBin.ps1) ---" -ForegroundColor Cyan
    # ONLY THROWAWAY REPOSITORIES UNDER THIS SUITE'S TEMP FOLDER ARE REACHED: the home names its clone with
    # installedCliFolder, and a home with none set is refused by the follower before any path is read.
    $gitEnv = @{ GIT_AUTHOR_NAME = "t"; GIT_AUTHOR_EMAIL = "t@example.invalid"; GIT_COMMITTER_NAME = "t"; GIT_COMMITTER_EMAIL = "t@example.invalid" }
    function G {
        param([string]$Dir, [string[]]$A)
        $r = Invoke-HordeServiceProgram -Program (Get-HordeServiceGitProgram) -Arguments (@("-C", $Dir) + $A) -Environment $gitEnv -TimeoutSeconds 60
        if ($r.code -ne 0) { throw ("git " + ($A -join " ") + " failed: " + $r.err) }
        return $r.out.Trim()
    }
    $okScript = 'if ($args[0] -ne "version") { exit 9 }; exit 0'
    $origin = Join-Path $work "cli-origin"; $seed = Join-Path $work "cli-seed"; $binClone = Join-Path $work "cli-bin"
    foreach ($d in @($origin, $seed)) { [void][System.IO.Directory]::CreateDirectory($d) }
    $null = G $origin @("init", "--bare", "--quiet"); $null = G $origin @("symbolic-ref", "HEAD", "refs/heads/main")
    $null = G $seed @("init", "--quiet"); $null = G $seed @("symbolic-ref", "HEAD", "refs/heads/main"); $null = G $seed @("remote", "add", "origin", $origin)
    foreach ($n in 1, 2) {
        [System.IO.File]::WriteAllText((Join-Path $seed "horde.ps1"), ($okScript + "`r`n")); [System.IO.File]::WriteAllText((Join-Path $seed "n.txt"), ("" + $n))
        $null = G $seed @("add", "-A"); $null = G $seed @("commit", "--quiet", "-m", ("c" + $n))
        if ($n -eq 1) { $null = G $seed @("push", "--quiet", "origin", "main"); $c = Invoke-HordeServiceProgram -Program (Get-HordeServiceGitProgram) -Arguments @("clone", "--quiet", $origin, $binClone) -Environment $gitEnv -TimeoutSeconds 60; if ($c.code -ne 0) { throw $c.err } }
    }
    $null = G $seed @("push", "--quiet", "origin", "main")
    $wantedTip = G $seed @("rev-parse", "HEAD")
    $cliHome = New-Home "cli-follow"
    [System.IO.File]::WriteAllText((Join-Path $cliHome "settings\services.json"), ('{ "schemaVersion": 1, "settings": { "tellWarchief": false, "installedCliFolder": "' + (Esc $binClone) + '" } }'))
    Check ((G $binClone @("rev-parse", "HEAD")) -cne $wantedTip) "the throwaway clone starts one commit behind"
    $st = Horde $cliHome @("services", "status")
    Check ($st.code -eq 0 -and $st.out -like "*installed CLI: *" + $binClone + "*") "status, through the real command, names the installed CLI it follows"
    $t = Horde $cliHome @("services", "tend")
    Check ($t.code -eq 0 -and $t.out -like "*installed CLI: moved * -> " + $wantedTip.Substring(0, 9) + " and it loads*") ("the real tend moves the clone to origin/main and says so (" + $t.out.Trim() + ")")
    Check ((G $binClone @("rev-parse", "HEAD")) -ceq $wantedTip) "and the clone is on origin/main"
    $st = Horde $cliHome @("services", "status", "-Json")
    $rec = $null
    try { $rec = $st.out | ConvertFrom-Json } catch { $rec = $null }
    Check ((Get-HordeTestMember $rec "installedCli.state") -ceq "current" -and (Get-HordeTestMember $rec "installedCli.sha") -ceq $wantedTip -and (Get-HordeTestMember $rec "installedCli.isBehind") -eq $false) "status -Json then says current, with the sha, and not behind"
    $t = Horde $empty @("services", "tend")
    Check ($t.code -eq 0 -and $t.out -notlike "*installed CLI*") "a temp home with no installedCliFolder prints no installed-CLI line: the default clone is never reached"

    Write-Host ""
    Write-Host "--- a service the supervisor starts, sees alive, and notices dying ---" -ForegroundColor Cyan
    $stubCo = Join-Path $work "stub checkout"
    [void][System.IO.Directory]::CreateDirectory($stubCo)
    [void][System.IO.Directory]::CreateDirectory($stubHome)
    # THE STUB (header). It is named horde.ps1 because that is what a horde service's checkout holds.
    $stubText = @'
$hh = $env:HORDE_HOME
$stop = Join-Path $hh "stop"
if ($args[0] -eq "stop") { [System.IO.File]::WriteAllText($stop, "x"); exit 0 }
$me = [System.Diagnostics.Process]::GetCurrentProcess()
$born = $me.StartTime.ToUniversalTime().ToString("o")
$end = (Get-Date).AddSeconds(90); $n = 0
while ((Get-Date) -lt $end -and -not (Test-Path -LiteralPath $stop)) {
    $n++
    $text = '{"at":"' + [datetime]::UtcNow.ToString("o") + '","pid":' + $PID + ',"startedAt":"' + $born + '","tickSeconds":10,"pass":' + $n + '}'
    try { [System.IO.File]::WriteAllText((Join-Path $hh "beat.json"), $text) } catch { }
    Write-Host ("stub beat " + $n + " for " + ($args -join " "))
    Start-Sleep -Milliseconds 500
}
exit 0
'@
    [System.IO.File]::WriteAllText((Join-Path $stubCo "horde.ps1"), $stubText)
    $sup = New-Home "sup" ('"stub": { "checkout": "' + (Esc $stubCo) + '", "hordeHome": "' + (Esc $stubHome) + '", "start": { "kind": "horde", "words": ["relay", "run"], "named": { "Relay": "none" } }, "stop": { "kind": "horde", "words": ["stop"], "waitSeconds": 10 }, "alive": { "heartbeat": "beat.json", "tickSeconds": 10 }, "confirmSeconds": 60 }')
    $st = Horde $sup @("services", "status")
    Check ($st.out -like "*stub: NOT RUNNING*" -and $st.out -like "*a pass would now: start (start)*") "before any pass, status says it is not running and that a pass would start it"
    $t = Horde $sup @("services", "tend")
    Check ($t.code -eq 0 -and $t.out -like "*stub: start (start) done - started as process *") ("tend starts it (" + $t.out.Trim() + ")")
    $deadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Path -LiteralPath (Join-Path $stubHome "beat.json")) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    $beat = Read-HordeHeartbeat -Path (Join-Path $stubHome "beat.json")
    $kept = Read-HordeServiceState -Name "stub" -HordeHome $sup
    Check ($beat.state -ceq "known" -and $kept.state -ceq "known" -and $beat.value.pid -eq $kept.value.started.pid -and (Test-HordeHeartbeatSameStart -One $beat.value.startedAt -Other $kept.value.started.startedAt)) "the process the supervisor recorded is the one that writes the heartbeat: same pid, same start"
    $st = Horde $sup @("services", "status")
    Check ($st.out -like "*stub: alive - its process * is running, heartbeat * s ago*" -and $st.out -like "*last action: * start (start) done*" -and $st.out -like "*failures in a row: 0; escalation outstanding: no*") "status says it is alive, with its heartbeat's age, its last action and no failures"
    $t = Horde $sup @("services", "tend")
    Check ($t.code -eq 0 -and $t.out -like "*stub: nothing - its process * is running*" -and $t.out -notlike "*start (start)*") "the next pass finds it running and starts nothing"
    $log = Get-HordeServiceLogPath -Name "stub" -HordeHome $sup
    $logText = ""; if (Test-Path -LiteralPath $log) { $logText = Read-HordeSharedText -Path $log }
    Check ($logText -match '(?m)^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d stub beat 1 for relay run -Relay none') "what the service says is kept in its log under the supervisor's home, with the time, and it was started with its words and named value"
    $journal = @(Read-HordeServiceJournalTail -Count 20 -HordeHome $sup | ForEach-Object { $_ | ConvertFrom-Json })
    Check (@($journal | Where-Object { $_.service -ceq "stub" -and $_.step -ceq "start" -and $_.outcome -ceq "done" }).Count -eq 1) "the journal has the one start"
    # STOP AND START, AS A PERSON WOULD: nobody edits a definitions file to stop a service.
    $firstPid = $kept.value.started.pid
    $sp = Horde $sup @("services", "stop", "stub")
    Check ($sp.code -eq 0 -and $sp.out -like "*stub: held - it was asked to stop, and stopped*horde services start stub*" -and (Get-HordeServiceProcessEntry -ProcessId $firstPid).state -ceq "absent") ("horde services stop asks it to stop with its own command, and it stops (" + $sp.out.Trim() + ")")
    $t = Horde $sup @("services", "tend")
    Check ($t.code -eq 0 -and $t.out -like "*stub: nothing - held, and left as it is (a person stopped it with horde services stop)*" -and $t.out -notlike "*start (start)*") "a pass leaves it stopped: held is not 'not running, so start it'"
    $st = Horde $sup @("services", "status")
    Check ($st.out -like "*stub: NOT RUNNING*" -and $st.out -like "*HELD - a person stopped it with horde services stop*") "status says it is held, and why"
    # The stub ends when it sees its stop file; a person letting it go wants it to run again.
    [System.IO.File]::Delete($stopFile)
    [System.IO.File]::Delete((Join-Path $stubHome "beat.json"))
    $go = Horde $sup @("services", "start", "stub")
    Check ($go.code -eq 0 -and $go.out -like "*stub: no longer held*" -and $go.out -like "*stub: start (start) done - started as process *") ("horde services start lets it go and starts it at once (" + $go.out.Trim() + ")")
    $deadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Path -LiteralPath (Join-Path $stubHome "beat.json")) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    $kept = Read-HordeServiceState -Name "stub" -HordeHome $sup
    Check ($kept.state -ceq "known" -and -not $kept.value.held -and $null -ne $kept.value.started -and $kept.value.started.pid -ne $firstPid -and (Read-HordeHeartbeat -Path (Join-Path $stubHome "beat.json")).state -ceq "known") "it runs again, as a new process, and beats"
    # The service is asked to stop the way its definition says, by the supervisor's own hands.
    $def = @((Get-HordeServiceDefinitions -HordeHome $sup).services)[0]
    $asked = Request-HordeServiceStop -Definition $def -Process $kept.value.started
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-HordeServiceProcessEntry -ProcessId $kept.value.started.pid).state -ceq "known" -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    Check ($asked.ok -and (Test-Path -LiteralPath $stopFile) -and (Get-HordeServiceProcessEntry -ProcessId $kept.value.started.pid).state -ceq "absent") "asked to stop with its own horde command, it stops"
    $t = Horde $sup @("services", "tend")
    Check ($t.code -eq 0 -and ($t.out -like "*stub: wait - *backing off after 1 start(s) in a row that did not last*" -or $t.out -like "*stub: start (start)*")) ("a pass after it has gone notices, and counts a start that did not last (" + $t.out.Trim() + ")")
    $st = Horde $sup @("services", "status", "-Json")
    $row = $null; try { $row = (($st.out.Trim() -split "`n")[0] | ConvertFrom-Json).services[0] } catch { $row = $null }
    Check ($null -ne $row -and $row.name -ceq "stub" -and $row.alive -ceq "no" -and $row.failures -ge 1 -and $row.escalationOutstanding -eq $false) "status -Json shows it not running, and the failure counted"

    Write-Host ""
    Write-Host "--- the schedule: Horde's own two jobs, in the test folder, disabled ---" -ForegroundColor Cyan
    foreach ($s in (Get-HordeSchedulerFiles)) { . $s }
    $real = Get-HordeScheduler
    if ($real.state -ne "known") {
        Write-Host ("  [SKIP] " + $real.reason)
    } else {
        Assert-TestName $testName
        $bootName = $testName + " at start-up"
        $mine = { $svcL = New-Object -ComObject Schedule.Service; try { $svcL.Connect(); try { return @($svcL.GetFolder("\HordeTest").GetTasks(1) | Where-Object { $_.Name -like ($testName + "*") } | ForEach-Object { $_.Name }) } catch { return @() } } finally { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($svcL) } }
        # ONLY AN ADMINISTRATOR, ELEVATED, MAY REGISTER A JOB THAT RUNS AT START-UP (measured
        # 2026-10-14, core/schedule/WindowsTaskScheduler.ps1). This suite checks whichever case it is
        # run in: elevated, the jobs are installed; not, the command fails and says what to do.
        $elevated = (New-Object System.Security.Principal.WindowsPrincipal ([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
        try {
            # SHOULD 3 of the review of PR 249: an INTERACTIVE Horde job already under the start-up
            # job's name - a disabled test task - is replaced in place by the S4U one.
            $savedHomeCli = $env:HORDE_HOME; $env:HORDE_HOME = $empty
            try { & $real.value.install (New-HordeScheduledJob -Name $bootName -Folder "HordeTest" -Script (Join-Path $root "horde.ps1") -Arguments @("services", "tend") -Environment @{ HORDE_HOME = $empty } -HordeHome $empty -EveryMinutes 1 -TimeLimitMinutes 5 -MayOutlastInterval -WithPerson -Disabled) } finally { $env:HORDE_HOME = $savedHomeCli }
            Check ((& $real.value.status $bootName "HordeTest").value.logonType -eq "Interactive") "CONTROL: an interactive job stands under the start-up job's name"
            $in = Horde $empty @("services", "schedule", "-TaskName", $testName, "-TaskFolder", "HordeTest", "-Disabled")
            if (-not $elevated) {
                Check ($in.code -ne 0 -and $in.out -like "*run this again from an elevated prompt*" -and (& $real.value.status $bootName "HordeTest").value.logonType -eq "Interactive" -and (& $real.value.status $testName "HordeTest").state -eq "absent") ("not elevated, schedule fails, says to run it elevated, and registers nothing in another form (" + $in.out.Trim() + ")")
                throw "SKIP-ELEVATED"
            }
            Check ($in.code -eq 0 -and $in.out -like "*installed '$bootName'*at start-up and every minute, whether or not anyone is signed in*DISABLED, so it never runs*installed '$testName'*at sign-in and every minute, in the person's own session*DISABLED, so it never runs*") ("schedule installs both jobs (" + $in.out.Trim() + ")")
            $ss = & $real.value.status $bootName "HordeTest"
            Check ($ss.state -eq "known" -and $ss.value.marked -and $ss.value.enabled -eq $false -and $ss.value.everyMinutes -eq 1 -and $ss.value.atStartup -eq $true -and $ss.value.logonType -eq "S4U" -and $ss.value.home -eq $empty -and $ss.value.program -ceq (Join-Path ([System.Environment]::SystemDirectory) "WindowsPowerShell\v1.0\powershell.exe")) "the start-up job replaced the interactive one under its name through -Force: at start-up and every minute, logon S4U - whether or not anyone is signed in - run by PowerShell itself, for this home, and disabled"
            $ps = & $real.value.status $testName "HordeTest"
            Check ($ps.state -eq "known" -and $ps.value.marked -and $ps.value.enabled -eq $false -and $ps.value.everyMinutes -eq 1 -and $ps.value.atLogon -eq $true -and $ps.value.logonType -eq "Interactive" -and $ps.value.runsAs -ne "") "the person's job: at sign-in and every minute, in their own session, and it names the account it runs as"
            $again = Horde $empty @("services", "schedule", "-TaskName", $testName, "-TaskFolder", "HordeTest", "-Disabled")
            Check ($again.code -eq 0 -and @(& $mine).Count -eq 2) "scheduling again replaces both: two jobs, never more"
            $sst = Horde $empty @("services", "schedule", "status", "-TaskName", $testName, "-TaskFolder", "HordeTest")
            Check ($sst.code -eq 0 -and $sst.out -like "*DISABLED*at start-up and every 1 minute(s), logon S4U*Horde's*DISABLED*at sign-in and every 1 minute(s), logon Interactive*Horde's*") "schedule status shows both"
            $un = Horde $empty @("services", "unschedule", "-TaskName", $testName, "-TaskFolder", "HordeTest")
            Check ($un.code -eq 0 -and $un.out -like "*removed*removed*Nothing that is running was stopped*" -and (& $real.value.status $testName "HordeTest").state -eq "absent" -and (& $real.value.status $bootName "HordeTest").state -eq "absent") "unschedule removes both"
            Check ((Horde $empty @("services", "schedule", "status", "-TaskName", $testName, "-TaskFolder", "HordeTest")).out -like "*neither job is installed: no service is being supervised*") "and then schedule status says nothing is supervised"
        } catch {
            if ($_.Exception.Message -cne "SKIP-ELEVATED") { throw }
            Write-Host "  [SKIP] the installed jobs' properties: this suite is not elevated, and a job that runs at start-up is registered only elevated"
        } finally {
            foreach ($n in @($bootName, $testName)) { try { $null = & $real.value.remove $n "HordeTest" } catch { } }
        }
        Check (@(& $mine).Count -eq 0) "nothing of this suite's is left in the scheduler"
    }
} finally {
    # The stub ends when its stop file appears; written whatever happened, so none outlives the suite.
    try { [void][System.IO.Directory]::CreateDirectory($stubHome); [System.IO.File]::WriteAllText($stopFile, "x") } catch { }
    if ($null -ne $sup) {
        $last = Read-HordeServiceState -Name "stub" -HordeHome $sup
        if ($last.state -ceq "known" -and $null -ne $last.value.started) { try { $null = Stop-HordeServiceProcess -Process $last.value.started } catch { } }
    }
    Start-Sleep -Milliseconds 800
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-HordeSuite -Success "horde services starts a defined service, sees it alive by its own heartbeat, notices it dying, and schedules itself only as Horde's own job"
