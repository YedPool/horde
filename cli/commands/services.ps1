$HordeCommand = @{
    name    = "services"
    group   = "services"
    usage   = "services tend | services status [-Json] | services schedule [status] [-TaskName <name>] [-TaskFolder Horde|HordeTest] [-Disabled] | services unschedule [-TaskName <name>] [-TaskFolder Horde|HordeTest]"
    summary = "the long-lived pieces of Horde on this machine, kept running and kept current. Each service is defined as data in <HORDE_HOME>\settings\service-definitions.json: how it is started and asked to stop, how to tell it is alive (a heartbeat file, and the process), and which revision it follows. tend: one pass over every service - start what is not running, restart what is hung, take a verified update when it may be restarted, roll a failed update back - journaled, and telling the warchief once when something needs a person; schedule: run tend every minute in the person's own session (schedule status shows the job; -Disabled installs it without letting it run); unschedule: remove that job, stopping nothing; status: each service - alive or not and why, heartbeat age, running against wanted revision, last action, failures in a row, whether an escalation is outstanding - and, first, whether tend itself is still coming round; -Json prints one line of data. horde rollout does an update now"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("tend", "status", "schedule", "unschedule")][string]$Verb,
            [Parameter(Position = 1)][string]$Target = "",
            [switch]$Json,
            [string]$TaskName = "Horde services tend",
            [ValidateSet("Horde", "HordeTest")][string]$TaskFolder = "Horde",
            [switch]$Disabled
        )
        # A flag meant for another verb is refused, never silently ignored (cli/Commands.ps1, run blocks).
        $verbFlags = @{ tend = @(); status = @("Json"); schedule = @("Target", "TaskName", "TaskFolder", "Disabled"); unschedule = @("TaskName", "TaskFolder") }
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
        $done = Invoke-HordeServiceSupervisor -Tools $tools
        foreach ($l in @($done.lines)) { Write-Output $l }
        # A refused file is a failure a person running the pass, and its journal, must see.
        if ($done.problem -ne "") { throw $done.problem }
    }
}
