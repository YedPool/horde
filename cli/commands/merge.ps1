$HordeCommand = @{
    name    = "merge"
    group   = "work"
    sustained = $true
    usage   = "merge OWNER/REPO#N -Task T-NNNN -State done|waiting|progress -By <lane> [-On <who>] [-Reason <text>]"
    summary = "merge one pull request the fleet's way, every step in one command (cli/Merge.ps1). Refused, with nothing merged, when the task is not in the ledger, the PR is not open, is a draft, is not mergeable or misses a review its repository requires. The tree that will exist after the merge - the PR head merged with its base, in a scratch checkout of its own, never yours - must pass test\test-host-names.ps1 and test\test-mutation-specs.ps1, or nothing is merged and the failing lines are printed; if the base moves while they run, the new combination is checked first. Then gh pr merge --merge (never squash), the ledger's merged event for -Task with -State (waiting needs -On: founder, M, lane:X, device or service; progress needs -Reason), a message to M and a mail to the analyst, and a one-line progress draft. Anything that fails after the merge is said loudly with what to run by hand, and the command exits 1. Settings: <HORDE_HOME>\settings\merge.json (ledgerScript: the task ledger's script, required)"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Position = 0)][string]$Pr,
            [string]$Task,
            [string]$State,
            [string]$By,
            [string]$On,
            [string]$Reason
        )
        # What must be given is asked for here, not declared mandatory: a missing mandatory parameter is
        # PROMPTED for, and a horde started with its input open would wait there (cli/commands/wake.ps1).
        foreach ($need in @("Pr", "Task", "State", "By")) {
            if (-not $PSBoundParameters.ContainsKey($need) -or ("" + $PSBoundParameters[$need]).Trim() -eq "") {
                throw (New-HordeUsageError ("merge needs " + $(if ($need -ceq "Pr") { "the pull request, OWNER/REPO#N" } else { "-" + $need })))
            }
        }
        $root = Get-HordeRoot
        . (Join-Path $root "cli\Merge.ps1")
        $request = Test-HordeMergeRequest -Pr $Pr -Task $Task -State $State -By $By -On ("" + $On) -Reason ("" + $Reason)
        if (-not $request.ok) { throw (New-HordeUsageError $request.why) }

        . (Join-Path $root "core\Home.ps1")
        $mergeHome = Get-HordeHome
        $settings = Get-HordeModuleSettings -Declaration $script:HordeMergeSettings -HordeHome $mergeHome
        if ($settings.state -ceq "refused") { throw ($settings.findings -join [Environment]::NewLine) }
        $mergeValues = $settings.values
        # NO LEDGER, NO MERGE (cli/Merge.ps1, settings): refused before GitHub is asked anything.
        if ("" + $mergeValues.ledgerScript -eq "") { throw ("the merge settings name no ledgerScript, the task ledger's script, so the merge could not be recorded; nothing was merged. Set it in " + $settings.path) }
        if (-not [System.IO.File]::Exists("" + $mergeValues.ledgerScript)) { throw ("the ledger script " + $mergeValues.ledgerScript + " is not there; nothing was merged") }
        $workFolder = Get-HordeMergeWorkFolder -Values $mergeValues

        # THE TELLS, loaded here in the command's own scope, so the blocks a messenger registers keep their
        # helpers (cli/commands/analyst.ps1 does the same). M through the messenger port; the analyst through
        # its mail folder, exactly as `horde analyst mail` leaves one.
        foreach ($f in @("Tristate", "ModuleSettings", "Heartbeat", "AnalystRounds", "AnalystSession", "SessionSeat", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        . (Join-Path $root "cli\AnalystTend.ps1")
        . (Join-Path $root "messengers\Port.ps1")
        foreach ($f in @(Get-HordeMessengerFiles)) { . $f }
        $tell = { param([string]$Body) return (Send-HordeMergeTell -Body $Body -Label $request.by -HordeHome $mergeHome) }
        $mail = {
            param([string]$Text)
            try {
                $policy = Get-HordeAnalystPolicy -HordeHome $mergeHome
                if (-not $policy.ok) { return [pscustomobject]@{ ok = $false; detail = $policy.reason } }
                $folder = Get-HordeAnalystFolder -Values $policy.values -HordeHome $mergeHome
                return [pscustomobject]@{ ok = $true; detail = (Write-HordeAnalystMail -Folder $folder -Text $Text -Markers $policy.markers) }
            } catch { return [pscustomobject]@{ ok = $false; detail = $_.Exception.Message } }
        }
        $tools = New-HordeMergeTools -Values $mergeValues -Tell $tell -Mail $mail

        [void][System.IO.Directory]::CreateDirectory($workFolder)
        $lock = Get-HordeMergeLock -WorkFolder $workFolder
        $held = $false
        try {
            try { $held = $lock.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true }
            if (-not $held) {
                Write-Output "another horde merge is running on this machine; waiting for it to end"
                try { $held = $lock.WaitOne([System.TimeSpan]::FromMinutes(30)) } catch [System.Threading.AbandonedMutexException] { $held = $true }
                if (-not $held) { throw "another horde merge held this machine's merge lock for 30 minutes; nothing was merged" }
            }
            $done = Invoke-HordeMerge -Request $request -Tools $tools -WorkFolder $workFolder
        } finally {
            if ($held) { $lock.ReleaseMutex() }
            $lock.Dispose()
        }
        switch -CaseSensitive ($done.outcome) {
            "merged" { Write-Output ("done: " + $request.pr + " merged as " + $done.mergeSha + ", recorded, told") }
            "refused" { throw ("refused, nothing merged: " + $done.why) }
            default { throw ("MERGED, NOT FINISHED: " + $done.why) }
        }
    }
}
