$HordeCommand = @{
    name    = "merge"
    group   = "work"
    sustained = $true
    usage   = "merge OWNER/REPO#N -Task T-NNNN -State done|waiting|progress -By <lane> [-On <who>] [-Reason <text>] [-Guards later|now]  |  merge -RunOwed [-Repo OWNER/REPO] [-Json]"
    summary = "merge one pull request the fleet's way, every step in one command (cli/Merge.ps1). Refused, with nothing merged, when the task is not in the ledger, the PR is not open, is a draft, is not mergeable or misses a review its repository requires. DAYTIME MODE, the default (-Guards later): merges do not wait for test runs - the guards are NOT run; the merge is queued in <HORDE_HOME>\merge\guards-owed.jsonl and the warchief, the analyst and the progress line say the guards are owed. One run at night or at idle (merge -RunOwed) runs every guard listed in test\guards.txt (and reports one the list dropped since the day began), each in Windows PowerShell 5.1 and in PowerShell 7, on the tip of each branch merges went into, finds which queued merge turned a guard red (walking the queue in merge order), writes <HORDE_HOME>\merge\nightly\<UTC date>-<owner>-<repo>.txt and prints it; that merge's owner fixes it first thing. THE QUEUE IS PER MACHINE: only merges made on this machine are in its queue, so every machine that merges needs its own run, and the report names the machine. A damaged queue line or a merge missing from its branch is reported in every run and the rest is still checked; the run ends 2 for them only when nothing could be checked. -RunOwed does not schedule itself and does not check idle; -Repo limits it to one repository; -Json adds a one-line JSON summary as the last line (its exit field is 0 all green, 1 any red, 2 could not run; the horde process ends 0, or 1 for anything else). -Guards now is the old way: the tree that will exist after the merge - the PR head merged with its base, in a scratch checkout of its own, never yours - must pass every guard first, or nothing is merged and the failing lines are printed; if the base moves while they run, the new combination is checked first. Then gh pr merge --merge (never squash), the ledger's merged event for -Task with -State (waiting needs -On: founder, M, lane:X, device or service; progress needs -Reason), a message to the warchief (M) and a mail to the analyst, and a one-line progress draft. Anything that fails after the merge is said loudly with what to run by hand, and the command exits 1. Settings: <HORDE_HOME>\settings\merge.json (ledgerScript: the task ledger's script, required for a merge)"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Position = 0)][string]$Pr,
            [string]$Task,
            [string]$State,
            [string]$By,
            [string]$On,
            [string]$Reason,
            [string]$Guards = "later",
            [switch]$RunOwed,
            [string]$Repo,
            [switch]$Json
        )
        # What must be given is asked for here, not declared mandatory: a missing mandatory parameter is
        # PROMPTED for, and a horde started with its input open would wait there (cli/commands/wake.ps1).
        if ($RunOwed) {
            foreach ($no in @("Pr", "Task", "State", "By", "On", "Reason", "Guards")) {
                if ($PSBoundParameters.ContainsKey($no)) { throw (New-HordeUsageError ("merge -RunOwed takes only -Repo and -Json, not " + $(if ($no -ceq "Pr") { "a pull request" } else { "-" + $no }))) }
            }
        } elseif ($PSBoundParameters.ContainsKey("Repo") -or $Json) { throw (New-HordeUsageError "-Repo and -Json belong to merge -RunOwed") }
        foreach ($need in $(if ($RunOwed) { @() } else { @("Pr", "Task", "State", "By") })) {
            if (-not $PSBoundParameters.ContainsKey($need) -or ("" + $PSBoundParameters[$need]).Trim() -eq "") {
                throw (New-HordeUsageError ("merge needs " + $(if ($need -ceq "Pr") { "the pull request, OWNER/REPO#N" } else { "-" + $need })))
            }
        }
        $root = Get-HordeRoot
        . (Join-Path $root "cli\Merge.ps1")
        $request = $null
        if (-not $RunOwed) {
            $request = Test-HordeMergeRequest -Pr $Pr -Task $Task -State $State -By $By -On ("" + $On) -Reason ("" + $Reason) -Guards $Guards
            if (-not $request.ok) { throw (New-HordeUsageError $request.why) }
        }

        . (Join-Path $root "core\Home.ps1")
        $mergeHome = Get-HordeHome
        $settings = Get-HordeModuleSettings -Declaration $script:HordeMergeSettings -HordeHome $mergeHome
        if ($settings.state -ceq "refused") { throw ($settings.findings -join [Environment]::NewLine) }
        $mergeValues = $settings.values
        # NO LEDGER, NO MERGE (cli/Merge.ps1, settings): refused before GitHub is asked anything. The nightly
        # run records nothing in the ledger, so it does not need one.
        if (-not $RunOwed -and "" + $mergeValues.ledgerScript -eq "") { throw ("the merge settings name no ledgerScript, the task ledger's script, so the merge could not be recorded; nothing was merged. Set it in " + $settings.path) }
        if (-not $RunOwed -and -not [System.IO.File]::Exists("" + $mergeValues.ledgerScript)) { throw ("the ledger script " + $mergeValues.ledgerScript + " is not there; nothing was merged") }
        foreach ($prog in $(if ($RunOwed) { @("gh", "git") } else { @("gh", "git", "ledgerProgram") })) {
            if (Test-HordeMergeShellScript -Program ("" + $mergeValues.$prog)) { throw ("the merge setting " + $prog + " names a .cmd or .bat, which cmd would run and re-read; name the program itself. Nothing was merged") }
        }
        $workFolder = Get-HordeMergeWorkFolder -Values $mergeValues

        # THE TELLS, loaded here in the command's own scope, so the blocks a messenger registers keep their
        # helpers (cli/commands/analyst.ps1 does the same). The warchief through the messenger port; the analyst through
        # its mail folder, exactly as `horde analyst mail` leaves one.
        $tell = { param([string]$Body) return [pscustomobject]@{ ok = $false; detail = "the nightly run tells nobody" } }
        $mail = $tell
        if (-not $RunOwed) {
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
        }
        # THE OWED QUEUE lives in <HORDE_HOME>\merge (cli/Merge.ps1, header): the daytime merge appends to it,
        # the nightly run reads it and writes its reports beside it.
        $owedFolder = Join-Path $mergeHome "merge"
        $tools = New-HordeMergeTools -Values $mergeValues -Tell $tell -Mail $mail -OwedFolder $owedFolder

        [void][System.IO.Directory]::CreateDirectory($workFolder)
        $lock = Get-HordeMergeLock -WorkFolder $workFolder
        $held = $false
        # THE LOCK GUARDS THE WORK FOLDER (the cache and the scratch checkouts). A daytime merge (-Guards later) only
        # reads GitHub and appends one line to the queue, so it takes none and never waits for a long nightly run
        # (S3, review of PR 375); -Guards now and -RunOwed use the work folder and take turns.
        $needLock = ($RunOwed -or $request.guards -ceq "now")
        try {
            if ($needLock) { try { $held = $lock.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $held = $true } }
            if ($needLock -and -not $held) {
                Write-Output "another horde merge is running on this machine; waiting for it to end"
                try { $held = $lock.WaitOne([System.TimeSpan]::FromMinutes(30)) } catch [System.Threading.AbandonedMutexException] { $held = $true }
                if (-not $held) { throw "another horde merge held this machine's merge lock for 30 minutes; nothing was merged" }
            }
            if ($RunOwed) { $owedRun = Invoke-HordeMergeRunOwed -Tools $tools -WorkFolder $workFolder -Folder $owedFolder -Repo ("" + $Repo) }
            else { $done = Invoke-HordeMerge -Request $request -Tools $tools -WorkFolder $workFolder }
        } finally {
            if ($held) { $lock.ReleaseMutex() }
            $lock.Dispose()
        }
        if ($RunOwed) {
            if ($Json) { Write-Output $owedRun.json }
            if ($owedRun.exit -ne 0) { throw ("the guards run found " + $(if ($owedRun.exit -eq 1) { "a red guard" } else { "that it could not run everything" }) + " (exit " + $owedRun.exit + ")") }
            return
        }
        switch -CaseSensitive ($done.outcome) {
            "merged" { Write-Output ("done: " + $request.pr + " merged as " + $done.mergeSha + ", recorded, told" + $(if ($request.guards -ceq "later") { "; guards NOT run, owed to the nightly run" } else { "" })) }
            "refused" { throw ("refused, nothing merged: " + $done.why) }
            default { throw ("MERGED, NOT FINISHED: " + $done.why) }
        }
    }
}
