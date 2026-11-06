$HordeCommand = @{
    name    = "job"
    group   = "data"
    usage   = "job upsert -Id <id> -Owner <who> (-Job <text> | -File <path>) -By <who> [-Session <uuid>] [-Started <ms or ISO time with a zone>] [-Due <ms or ISO time with a zone>] | job done -Id <id> (-Proof <text> | -File <path>) -By <who> [-At <ms or ISO time with a zone>] | job list [-Open] [-Owner <who>] [-Overdue] [-Json]"
    summary = "the overseer's jobs in fleet.db (a piece of promised work somebody is on), so the overseer and the analyst detect a stall once, from one place; the jobs have no file behind them, fleet.db is their only home. Every verb is idempotent, is one short transaction and prints one line; long text goes in -File (ASCII or UTF-8, no shell quoting). upsert: make the job, or change the owner, text, session or due time of an OPEN one (a field left out stays as it was); the first started time stands and is never moved; the same call again prints 'kept' and changes nothing; a job that is done is refused ('a new piece of work takes a new id'). done: close it with its proof (required); the same proof again prints 'kept' and keeps the first time; another proof is refused, a done job is final; -By is checked and not stored (a job keeps who made it). list: one plain line per job, open ones first and soonest due first; -Open leaves out the done ones, -Overdue is open with a due time before now, -Json is one line of data. Times are UTC milliseconds or an ISO time WITH a zone (2026-11-06T09:00:00Z or -05:00): a local time with no zone is refused, because it means two instants at a clock change. ASCII only; a value may not be empty or hold a double quote (use -File). The commands never make or migrate fleet.db (run horde db init); the exit is 1 for any failure, and the message names the finer code from fleet-db\jobs-cli.mjs (2 no home, 3 'fleet.db busy', 4 no fleet.db yet). HORDE_HOME or a home pointer (horde home set) must name the home. Needs Node.js 24 or later"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("upsert", "done", "list")][string]$Verb,
            [string]$Id,
            [string]$Owner,
            [string]$Job,
            [string]$File,
            [string]$Session,
            [string]$Started,
            [string]$Due,
            [string]$By,
            [string]$Proof,
            [string]$At,
            [switch]$Open,
            [switch]$Overdue,
            [switch]$Json
        )
        # A flag meant for another verb is refused, never silently ignored (cli/commands/work.ps1).
        $own = @{
            upsert = @("Id", "Owner", "Job", "File", "Session", "Started", "Due", "By")
            done   = @("Id", "Proof", "File", "By", "At")
            list   = @("Owner", "Open", "Overdue", "Json")
        }
        foreach ($flag in @($PSBoundParameters.Keys)) {
            if ($flag -ne "Verb" -and $own[$Verb] -notcontains $flag) { throw ("-" + $flag + " does not belong to job " + $Verb) }
        }
        $root = Get-HordeRoot
        . (Join-Path $root "fleet-db\Jobs.ps1")
        $flags = [ordered]@{
            "--id" = "Id"; "--owner" = "Owner"; "--job" = "Job"; "--proof" = "Proof"; "--file" = "File"; "--session" = "Session"
            "--started" = "Started"; "--due" = "Due"; "--by" = "By"; "--at" = "At"
        }
        $values = [ordered]@{}
        foreach ($f in $flags.Keys) {
            if ($PSBoundParameters.ContainsKey($flags[$f])) { $values[$f] = $PSBoundParameters[$flags[$f]] }
        }
        $bare = @()
        if ($Open) { $bare += "--open" }
        if ($Overdue) { $bare += "--overdue" }
        if ($Json) { $bare += "--json" }
        Invoke-HordeJobsCli -Root $root -Noun "job" -Verb $Verb -Values $values -Switches $bare
    }
}
