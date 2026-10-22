# core/GuardList - the repo-wide guards, as one file of the repository (test\guards.txt) and the few
# rules that read it. T-0247.
#
# WHY ONE FILE, ONE READER. The guards that read the whole repository (CONTRIBUTING 15 rule 9) were
# named in four places that drifted: `horde merge` ran two, the CI workflow ran four, and the PR bodies
# of the fleet said "seven" and then "eight" (2026-10-21: four merges skipped guards and one turned main
# red). Now test\guards.txt is the only list; `horde merge` (cli/Merge.ps1) and the CI runner
# (tools/CiGuards.ps1) both read it through this file, so adding a guard is one line there.
#
# THE FILE: one script per line, relative to the repository root, under test/ and ending .ps1. A # starts
# a comment, blank lines are ignored, either slash is taken. A line that is no guard refuses the WHOLE
# list: a skipped line is a guard that silently does not run.
#
# THE SHELLS: every guard runs in Windows PowerShell 5.1 AND in PowerShell 7, and is green only if it is
# green in both. test/test-guard-list.ps1 holds this file.
#
# No Set-StrictMode here: this file is dot-sourced, so a file-scope Set-StrictMode would set the
# caller's mode (see core/Tristate.ps1).

function Get-HordeGuardListPath {
    # The list, relative to the repository root.
    return "test\guards.txt"
}

function Get-HordeGuardShells {
    # The shells every guard runs in, in order. key is what a runner passes; label is what it says.
    return @(
        @{ key = "5.1"; label = "Windows PowerShell 5.1" },
        @{ key = "7"; label = "PowerShell 7" }
    )
}

function Read-HordeGuardList {
    # PURE. { ok; why; guards } from the text of test\guards.txt. Guards are spelled with backslashes.
    param([AllowEmptyString()][string]$Text)
    $path = Get-HordeGuardListPath
    $guards = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($raw in @(("" + $Text) -split "\r?\n")) {
        $n++
        $line = $raw.Trim()
        if ($n -eq 1 -and $line.Length -gt 0 -and [int][char]$line[0] -eq 0xFEFF) { $line = $line.Substring(1).Trim() }
        if ($line -eq "" -or $line.StartsWith("#")) { continue }
        if ($line -cnotmatch '\Atest[\\/][A-Za-z0-9][A-Za-z0-9._-]*\.ps1\z') {
            return [pscustomobject]@{ ok = $false; why = ("line " + $n + " of " + $path + " is not a guard script under test/ ending .ps1: '" + $line + "'"); guards = @() }
        }
        $guard = $line.Replace("/", "\")
        if ($guards -ccontains $guard) { return [pscustomobject]@{ ok = $false; why = ("line " + $n + " of " + $path + " lists " + $guard + " twice"); guards = @() } }
        [void]$guards.Add($guard)
    }
    if ($guards.Count -eq 0) { return [pscustomobject]@{ ok = $false; why = ($path + " lists no guard, so nothing could say the tree is green"); guards = @() } }
    return [pscustomobject]@{ ok = $true; why = ""; guards = @($guards) }
}

function Join-HordeGuardLists {
    # PURE. The guards to run: the base's list, then the checked tree's extras. A pull request may add a
    # guard; it may not remove or rename one out of the run, so a PR that edits the list to dodge a red
    # guard is still held to it. -Base is $null when the base has no list yet.
    param([string[]]$Tree = @(), [string[]]$Base = $null)
    $all = New-Object System.Collections.ArrayList
    foreach ($g in @($Base)) { if ($null -ne $g -and -not ($all -ccontains $g)) { [void]$all.Add($g) } }
    foreach ($g in @($Tree)) { if ($null -ne $g -and -not ($all -ccontains $g)) { [void]$all.Add($g) } }
    return @($all)
}

function Get-HordeGuardEnvironment {
    # PURE. The environment variables set for a guard's child in a shell, after the parent's PSModulePath
    # is dropped. Windows PowerShell 5.1 gets the MACHINE value of PSModulePath: started from Git Bash,
    # PowerShell 7 or a runner with theirs it could not load its own modules, and test-mutation-specs
    # needs Import-PowerShellDataFile (measured 2026-10-16). PowerShell 7 gets none: it builds its own,
    # and 5.1's value would put 5.1 modules ahead of its own.
    param([Parameter(Mandatory = $true)][string]$Shell, [AllowEmptyString()][string]$MachinePsModulePath = "")
    if ($Shell -ceq "5.1" -and "" + $MachinePsModulePath -ne "") { return @{ PSModulePath = ("" + $MachinePsModulePath) } }
    return @{}
}

function Get-HordeGuardPwsh7 {
    # The PowerShell 7 to use: the setting, else the MSI install under Program Files. Never whatever pwsh
    # the search path finds first: it may be the Microsoft Store copy (CONTRIBUTING 16).
    param([AllowEmptyString()][string]$Setting = "")
    if ("" + $Setting -ne "") { return ("" + $Setting) }
    $pf = [Environment]::GetEnvironmentVariable("ProgramW6432")
    if ("" + $pf -eq "") { $pf = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles) }
    return [System.IO.Path]::Combine($pf, "PowerShell", "7", "pwsh.exe")
}
