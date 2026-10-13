$HordeCommand = @{
    name    = "rollout"
    group   = "services"
    # It waits for services to stop, start and prove themselves: minutes of light work.
    sustained = $true
    usage   = "rollout [<service>] [-Now] [-WaitSeconds <n>]"
    summary = "bring one defined service, or all of them, to the revision each follows, now: ask the remote, check the new revision in a scratch copy, stop the service, move its checkout forward, start it, and wait for it to prove itself - with every safety of the scheduled pass (fast-forward only, never over local changes, rolled back and pinned when the new revision does not come up; horde services says what a service is). A service whose definition restarts it only when the person is idle is left waiting unless -Now is given: that one rule, and no other, is what -Now sets aside. -WaitSeconds is how long to wait for the services to settle (600). Fails, naming each, when a chosen service did not end on its wanted revision"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Position = 0)][string]$Service = "",
            [switch]$Now,
            [ValidateRange(1, 3600)][int]$WaitSeconds = 600
        )
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Home", "ModuleSettings", "Heartbeat", "Services", "ServicesFiles", "ServiceHostPort")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        foreach ($f in @("ServicesAct", "ServicesTend", "ServicesTell")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }
        foreach ($f in @(Get-HordeServiceHostFiles)) { . $f }
        $only = @()
        if ($Service -ne "") { $only = @($Service) }
        $tools = New-HordeServiceTools
        # The teller, loaded inside its one block (cli/commands/services.ps1 says why).
        $tools["TellAll"] = {
            param($Notices, $HordeHome, $Policy)
            foreach ($f in @("SessionSeat", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
            . (Join-Path $root "messengers\Port.ps1")
            foreach ($f in @(Get-HordeMessengerFiles)) { . $f }
            return (Send-HordeServiceNotices -Notices $Notices -HordeHome $HordeHome -Policy $Policy)
        }
        # The scheduled pass holds the lock for under a minute; a person's roll-out waits it out.
        $done = Invoke-HordeServiceSupervisor -Tools $tools -Only $only -IgnoreIdle:$Now -ForceFetch -LockWaitSeconds 90 -SettleSeconds $WaitSeconds -BudgetSeconds $WaitSeconds
        foreach ($l in @($done.lines)) { Write-Output $l }
        if ($done.problem -ne "") { throw $done.problem }
        if (-not $done.ran) { throw "the roll-out did not run" }
        $defined = Get-HordeServiceDefinitions
        $chosen = @($defined.services | Where-Object { $only.Count -eq 0 -or $only -ccontains $_.name })
        $short = @(Get-HordeServiceRolloutVerdict -Definitions $chosen -Services $done.services)
        if ($short.Count -gt 0) { throw ("the roll-out is not complete: " + (@($short | ForEach-Object { $_.name + " (" + $_.reason + ")" }) -join "; ")) }
        Write-Output $(if ($chosen.Count -eq 0) { "no service is defined; nothing was rolled out" } else { "rolled out: " + (@($chosen | ForEach-Object { $_.name }) -join ", ") })
    }
}
