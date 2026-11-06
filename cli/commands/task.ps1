$HordeCommand = @{
    name    = "task"
    group   = "data"
    usage   = "task list [-Orc <letter or lane folder>] [-Json]"
    summary = "the fleet's open tasks, read from fleet.db, one numbered list per Orc (top tasks by priority, then position, then age; subtasks under their parent: 3, 3.1, 3.1.2). Every live task is printed: a task whose parent is closed stands at the top of its owner's list, and a task with no Orc to name comes out in a list called 'no Orc'. -Orc shows one Orc's list and also the tasks it owns inside another Orc's list, marked owner=; a task in a list that is not its owner's is marked the same way. Done tasks wait for verification and take no number; the last line counts them. -Json is one line of data. It only reads: it never makes or migrates fleet.db (run horde db init). The task ledger stays the source of tasks and reaches fleet.db by the sync every 5 minutes, so a task opened this minute can be missing here. The exit is 1 for any failure, and the message names the finer code from fleet-db\task-cli.mjs (2 no home, 3 'fleet.db busy', 4 no fleet.db yet). HORDE_HOME or a home pointer (horde home set) must name the home. Needs Node.js 24 or later"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("list")][string]$Verb,
            [string]$Orc,
            [switch]$Json
        )
        $root = Get-HordeRoot
        . (Join-Path $root "core\Home.ps1")
        $resolved = Resolve-HordeHome
        if ($resolved.source -eq "default") { throw "horde task needs HORDE_HOME set to the Horde home (or a home pointer: horde home set -Path <folder>): fleet.db is the fleet's one database and is never made in a default folder" }
        $hordeHome = $resolved.path

        $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $node) { throw "fleet.db needs Node.js 24 or later, and node is not installed or not on this machine's PATH" }
        $major = 0
        $ver = "" + (& $node.Source --version)
        if ($ver -match '^v(\d+)\.') { $major = [int]$Matches[1] }
        if ($major -lt 24) { throw ("fleet.db needs Node.js 24 or later, and this machine has " + $ver.Trim()) }

        $script = Join-Path $root "fleet-db\task-cli.mjs"
        $nodeArgs = @($Verb)
        if ($PSBoundParameters.ContainsKey("Orc")) { $nodeArgs += @("--orc", $Orc) }
        if ($Json) { $nodeArgs += "--json" }
        $before = $env:HORDE_HOME
        $env:HORDE_HOME = $hordeHome
        try { & $node.Source $script @nodeArgs } finally { $env:HORDE_HOME = $before }
        if ($LASTEXITCODE -ne 0) { throw ("horde task " + $Verb + " stopped with exit code " + $LASTEXITCODE) }
    }
}
