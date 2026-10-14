$HordeCommand = @{
    name    = "services"
    group   = "services"
    usage   = "services tend | services status [-Json] | services stop <name> | services start <name> | services schedule [status] [-TaskName <name>] [-TaskFolder Horde|HordeTest] [-Disabled] | services unschedule [-TaskName <name>] [-TaskFolder Horde|HordeTest]"
    summary = "the long-lived pieces of Horde on this machine, kept running and kept current. Each service is defined as data in <HORDE_HOME>\settings\service-definitions.json: how it is started and asked to stop, how to tell it is alive (a heartbeat file, and the process), and which revision it follows. tend: one pass over every service - start what is not running, restart what is hung, take a verified update when it may be restarted, roll a failed update back - journaled, and telling the warchief once when something needs a person; and keep the hosted phone page current, deploying it when only the page changed since the recorded deploy, checking it took, and otherwise telling the warchief why not (cli/RelayPublish.ps1); stop <name>: ask that service to stop, the way its definition says, and HOLD it - the supervisor then leaves it exactly as it is, not started, not updated, until start <name> lets it go and tends it at once; schedule: run tend in two jobs, each every minute - one from start-up, whether or not anyone is signed in, and one in the person's own session from sign-in, for the services that need their desktop - installing or updating both (it needs an elevated prompt, signed in as the account the jobs run as: only an administrator may register a job that runs at start-up; schedule status shows both; -Disabled installs them without letting them run); unschedule: remove both, stopping nothing; status: each service - alive or not and why, heartbeat age, running against wanted revision, last action, failures in a row, whether an escalation is outstanding - and, first, whether tend itself is still coming round; -Json prints one line of data. horde rollout does an update now"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("tend", "status", "stop", "start", "schedule", "unschedule")][string]$Verb,
            [Parameter(Position = 1)][string]$Target = "",
            [switch]$Json,
            [string]$TaskName = "Horde services tend",
            [ValidateSet("Horde", "HordeTest")][string]$TaskFolder = "Horde",
            [switch]$Disabled
        )
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        $verbFlags = @{ tend = @(); status = @("Json"); stop = @("Target"); start = @("Target"); schedule = @("Target", "TaskName", "TaskFolder", "Disabled"); unschedule = @("TaskName", "TaskFolder") }
        foreach ($flag in @($PSBoundParameters.Keys)) { if ($flag -ne "Verb" -and $verbFlags[$Verb] -notcontains $flag) { throw ("-" + $flag + " does not belong to services " + $Verb) } }
        # Loaded here, in the command's own scope, so the adapters' functions stay visible to the blocks
        # they register (core/ServiceHostPort.ps1, core/Schedule.ps1).
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort", "Schedule")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        foreach ($f in @("ServicesAct", "ServicesTend", "ServicesTell")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
        if ($Verb -eq "schedule" -or $Verb -eq "unschedule") {
            if ($Verb -eq "schedule" -and @("", "status") -cnotcontains $Target) { throw ("services schedule takes nothing, or status, after it, not '" + $Target + "'") }
            foreach ($s in (Get-HordeSchedulerFiles)) { . $s }
            $action = $(if ($Verb -eq "unschedule") { "remove" } elseif ($Target -ceq "status") { "status" } else { "install" })
            if ($action -cne "install" -and $Disabled) { throw "-Disabled belongs to services schedule, when it installs the job" }
            Invoke-HordeServiceSchedule -Action $action -TaskName $TaskName -Folder $TaskFolder -Disabled:$Disabled -HordeScript (Join-Path $root "horde.ps1") | ForEach-Object { Write-Output $_ }
            return
        }
        foreach ($f in @(Get-HordeServiceHostFiles)) { . $f }
        $tools = New-HordeServiceTools
        if ($Verb -eq "status") {
            $report = Get-HordeServiceStatusReport -Tools $tools
            if ($Json) { ConvertTo-Json -InputObject (ConvertTo-HordeServiceStatusRecord -Report $report) -Depth 8 -Compress; return }
            Format-HordeServiceStatus -Report $report | ForEach-Object { Write-Output $_ }
            return
        }
        # THE TELLER: the messenger port and what it needs are loaded INSIDE this one block, at the
        # moment something has to be told, so a quiet pass - nearly every pass - never pays for them,
        # and the blocks a messenger registers can see its helpers for as long as the block runs
        # (cli/ServicesTell.ps1). Called at most once a process.
        $tools["TellAll"] = {
            param($Notices, $HordeHome, $Policy)
            foreach ($f in @("SessionSeat", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
            . (Join-Path $root "messengers\Port.ps1")
            foreach ($f in @(Get-HordeMessengerFiles)) { . $f }
            return (Send-HordeServiceNotices -Notices $Notices -HordeHome $HordeHome -Policy $Policy)
        }
        if ($Verb -eq "stop" -or $Verb -eq "start") {
            if ($Target -eq "") { throw ("services " + $Verb + " needs the name of a service (horde services status lists them)") }
            $set = Set-HordeServiceHeld -Name $Target -Held:($Verb -eq "stop") -Tools $tools
            foreach ($l in @($set.lines)) { Write-Output $l }
            if ($set.problem -ne "") { throw $set.problem }
            if ($Verb -eq "stop") { return }
            # Let go: tended at once, by the ordinary pass, for that one service.
            $done = Invoke-HordeServiceSupervisor -Tools $tools -Only @($Target) -LockWaitSeconds 90
            foreach ($l in @($done.lines)) { Write-Output $l }
            if ($done.problem -ne "") { throw $done.problem }
            return
        }
        # THE HOSTED PHONE PAGE (cli/RelayPublish.ps1), looked at by the whole pass only: loaded INSIDE
        # this block, as the teller is, and refused for a test's home before any real tool is made.
        $tools["PagePublish"] = {
            param($HordeHome, $Policy, $Teller)
            if (Test-HordeServiceHomeIsATests -HordeHome $HordeHome) { return @("phone page: this Horde home is under the temp folder, so it is a test's: the hosted page is not looked at") }
            . (Join-Path $root "cli\RelayDeploy.ps1")
            . (Join-Path $root "cli\RelayPublish.ps1")
            return (Invoke-HordeRelayPublishStep -HordeHome $HordeHome -Tools (New-HordeRelayPublishTools) -Policy $Policy -Teller $Teller -Checkout $root)
        }
        $done = Invoke-HordeServiceSupervisor -Tools $tools
        foreach ($l in @($done.lines)) { Write-Output $l }
        # A refused file is a failure a person running the pass, and its journal, must see.
        if ($done.problem -ne "") { throw $done.problem }
    }
}
