$HordeCommand = @{
    name    = "install"
    group   = "setup"
    usage   = "install [-BinDir <folder>] [-DryRun] [-Force] [-AllowWorktree]"
    summary = "write horde.cmd into a bin folder (default %USERPROFILE%\bin), launching this checkout"
    run     = {
        [CmdletBinding()] param([string]$BinDir, [switch]$DryRun, [switch]$Force, [switch]$AllowWorktree)
        # Loaded here, when the command runs, never when the file is listed: a command file only
        # declares (cli\Commands.ps1).
        . (Join-Path (Get-HordeRoot) "cli\Install.ps1")
        $root = Get-HordeRoot
        if ("$BinDir".Trim() -eq "") {
            $BinDir = Get-HordeDefaultBinDir
            if ($BinDir -eq "") { throw "USERPROFILE is not set, so there is no default bin folder; pass -BinDir <folder>" }
        }
        # Resolved against PowerShell's current location, not the process's: [IO.Path]::GetFullPath
        # would resolve a relative -BinDir against a directory the caller never chose.
        $BinDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BinDir)

        $plan = Get-HordeInstallPlan -Root $root -BinDir $BinDir -Force:$Force -AllowWorktree:$AllowWorktree
        Write-Output ("shim     " + $plan.shim)
        Write-Output ("launches " + $plan.target)
        if ($plan.action -eq "refuse") { throw $plan.problem }
        if ($plan.checkout -eq "worktree") { Write-Output "note     this is a linked worktree, allowed because -AllowWorktree was given" }
        if ($plan.previous -and "$($plan.previous)" -ine $plan.target) { Write-Output ("replaces a shim that launched " + $plan.previous) }

        if ($plan.action -eq "unchanged") { Write-Output "unchanged: the shim is already current" }
        elseif ($DryRun) { Write-Output ("would " + $plan.action + " " + $plan.shim + " (dry run: nothing was written)") }
        else {
            Write-HordeShim -Plan $plan
            Write-Output ($(if ($plan.action -eq "create") { "created " } else { "updated " }) + $plan.shim)
        }
        if (-not (Test-HordeOnPath -Dir $BinDir)) {
            Write-Output ("warning: " + $BinDir + " is not on PATH, so typing horde will not find it; add that folder to PATH and open a new shell")
        }
    }
}
