$HordeCommand = @{
    name    = "work"
    group   = "data"
    usage   = "work start -Kind <agent or warg> -ParentSession <uuid> (-AgentId <id> [-AgentType <type>] or -Session <uuid>) -WorkType <build, review, verify, research, mechanical, monitor or other> [-Task T-NNNN] [-Domain <lane>] [-Model <model>] [-At <ms or ISO time>] | work end (-ParentSession <uuid> -AgentId <id> or -Session <uuid>) -Outcome <done, failed, stopped or abandoned> [-At <ms or ISO time>] | work list [-Orc <letter or lane folder>] [-Running] [-Json]"
    summary = "the record of delegated work in fleet.db: an AGENT is an Agent-tool subagent inside a session (no window of its own, named by the harness's subagent id), a WARG is its own agent session in its own pane; both have a parent, the session that spawned them. start: record a unit as running (a repeat prints 'already started' and changes nothing; -AgentId is stored exactly as given, never trimmed or re-cased; no -Task records it as no_task; a task fleet.db does not know yet is recorded as no_task with a warning naming it, since the ledger may be ahead of the last import; a parent or warg session fleet.db has not seen gets a stub session row); end: record how it ended (a repeat with the same outcome prints 'already ended'; a different outcome is refused, an ended unit is final); list: the units newest first, -Orc for one Orc, -Running for those not ended, -Json for one line of data. One short transaction per call and ASCII output, for hooks: exit 0 is done (repeats included), nonzero is a refusal with a one-line reason, and a locked database gives 'fleet.db busy' after a few seconds, never a hang. HORDE_HOME or a home pointer (horde home set) must name the home. Needs Node.js 24 or later"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("start", "end", "list")][string]$Verb,
            [string]$Kind,
            [string]$ParentSession,
            [string]$AgentId,
            [string]$AgentType,
            [string]$Session,
            [string]$WorkType,
            [string]$Task,
            [string]$Domain,
            [string]$Model,
            [string]$At,
            [string]$Outcome,
            [string]$Orc,
            [switch]$Running,
            [switch]$Json
        )
        # A flag meant for another verb is refused, never silently ignored (cli/commands/db.ps1).
        $own = @{
            start = @("Kind", "ParentSession", "AgentId", "AgentType", "Session", "WorkType", "Task", "Domain", "Model", "At")
            end   = @("ParentSession", "AgentId", "Session", "Outcome", "At")
            list  = @("Orc", "Running", "Json")
        }
        foreach ($flag in @($PSBoundParameters.Keys)) {
            if ($flag -ne "Verb" -and $own[$Verb] -notcontains $flag) { throw ("-" + $flag + " does not belong to work " + $Verb) }
        }
        $root = Get-HordeRoot
        . (Join-Path $root "core\Home.ps1")
        $resolved = Resolve-HordeHome
        if ($resolved.source -eq "default") { throw "horde work needs HORDE_HOME set to the Horde home (or a home pointer: horde home set -Path <folder>): fleet.db is the fleet's one database and is never made in a default folder" }
        $hordeHome = $resolved.path

        $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $node) { throw "fleet.db needs Node.js 24 or later, and node is not installed or not on this machine's PATH" }
        $major = 0
        $ver = "" + (& $node.Source --version)
        if ($ver -match '^v(\d+)\.') { $major = [int]$Matches[1] }
        if ($major -lt 24) { throw ("fleet.db needs Node.js 24 or later, and this machine has " + $ver.Trim()) }

        $script = Join-Path $root "fleet-db\work-cli.mjs"
        $flags = [ordered]@{
            "--kind" = "Kind"; "--parent-session" = "ParentSession"; "--agent-id" = "AgentId"; "--agent-type" = "AgentType"
            "--session" = "Session"; "--work-type" = "WorkType"; "--task" = "Task"; "--domain" = "Domain"; "--model" = "Model"
            "--at" = "At"; "--outcome" = "Outcome"; "--orc" = "Orc"
        }
        $nodeArgs = @($Verb)
        foreach ($f in $flags.Keys) {
            if ($PSBoundParameters.ContainsKey($flags[$f])) { $nodeArgs += @($f, [string]$PSBoundParameters[$flags[$f]]) }
        }
        if ($Running) { $nodeArgs += "--running" }
        if ($Json) { $nodeArgs += "--json" }
        $before = $env:HORDE_HOME
        $env:HORDE_HOME = $hordeHome
        try { & $node.Source $script @nodeArgs } finally { $env:HORDE_HOME = $before }
        if ($LASTEXITCODE -ne 0) { throw ("horde work " + $Verb + " stopped with exit code " + $LASTEXITCODE) }
    }
}
