$HordeCommand = @{
    name    = "home"
    group   = "data"
    usage   = "home | home set -Path <absolute folder> | home clear"
    summary = "where Horde keeps its files, resolved the same way everywhere: HORDE_HOME if set, else the pointer file (.horde-home.json in the user profile folder), else (PowerShell only) the .horde folder in the user profile. home: print the home and which of the three gave it, warn when HORDE_HOME is set here and overrides the pointer, and list every Task Scheduler task under \Horde\ that names another home (read only; a refused query is said in one line); home set -Path: point the whole fleet at a folder in one atomic write, so running sessions, hooks and tasks that resolve the home follow at their next call (refused: a relative path, a folder that does not exist, a folder without fleet.db; prints the old and the new home, then the same check); home clear: remove the pointer and print what the home is now, then the same check. Long-lived services take the home when they start, and tasks registered before the pointer existed keep a home baked into their action: restart the services and re-register the tasks. A bad pointer file is refused by name, never skipped"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Position = 0)][ValidateSet("set", "clear")][string]$Verb,
            [ValidateNotNullOrEmpty()][string]$Path
        )
        $root = Get-HordeRoot
        . (Join-Path $root "core\HomeTasks.ps1")
        # A flag meant for another verb is refused, never silently ignored (cli/commands/db.ps1).
        if ($PSBoundParameters.ContainsKey("Path") -and $Verb -ne "set") { throw "-Path belongs to home set, not to home or home clear" }
        if ($Verb -eq "set") {
            if (-not $PSBoundParameters.ContainsKey("Path")) { throw "home set needs -Path, the absolute folder of the Horde home" }
            # A horde-kind service still running under the current home is a refusal, before anything is written.
            Assert-HordeNoServiceRunsOnOldHome -NewHome $Path
            $r = Set-HordeHomePointer -Path $Path
            Write-Output ("old home: " + $(if ($r.old -ne "") { $r.old } else { "(none could be resolved)" }))
            Write-Output ("new home: " + $r.new)
            Write-Output ("pointer:  " + $r.file)
            # The effective home after the write, which is not the new one when HORDE_HOME is set in this process.
            $now = Resolve-HordeHome
            Write-Output ("effective here: " + $now.path + " (" + $now.source + ")")
            foreach ($l in @(Get-HordeHomeCheckLines)) { Write-Output $l }
            return
        }
        if ($Verb -eq "clear") {
            $r = Clear-HordeHomePointer
            Write-Output $(if ($r.removed) { "pointer removed: " + $r.file } else { "no pointer to remove: " + $r.file })
            $now = Resolve-HordeHome
            Write-Output ("home now: " + $now.path + " (" + $now.source + ")")
            foreach ($l in @(Get-HordeHomeCheckLines)) { Write-Output $l }
            return
        }
        $now = Resolve-HordeHome
        Write-Output ("home:   " + $now.path)
        $why = switch ($now.source) {
            "HORDE_HOME" { "HORDE_HOME" }
            "pointer" { "pointer " + (Get-HordeHomePointerPath) }
            default { "default (the .horde folder in the user profile)" }
        }
        Write-Output ("source: " + $why)
        foreach ($l in @(Get-HordeHomeCheckLines)) { Write-Output $l }
    }
}
