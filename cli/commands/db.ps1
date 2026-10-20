$HordeCommand = @{
    name    = "db"
    group   = "data"
    usage   = "db init | db status | db check"
    summary = "fleet.db, the fleet's one database of work data, kept in HORDE_HOME\fleet.db: init: make it, or bring it to this version's schema (safe to run again); status: the file, its schema and the rows in every table, changing no data; check: SQLite's integrity and foreign-key checks and the rules one row cannot hold alone, one line per problem, exit 1 if any. HORDE_HOME must be set: fleet.db is never made in a default folder. Needs Node.js 24 or later"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("init", "status", "check")][string]$Verb
        )
        # THE HOME MUST BE NAMED, not defaulted (fleet-db/cli.mjs): one database for the whole fleet, and a
        # second one made under a default folder would be read by nothing. Checked before Node, so the
        # message is about the home and not about a child process.
        if ("$env:HORDE_HOME".Trim() -eq "") { throw "horde db needs HORDE_HOME set to the Horde home: fleet.db is the fleet's one database and is never made in a default folder" }
        $root = Get-HordeRoot
        . (Join-Path $root "core\Home.ps1")
        $hordeHome = Get-HordeHome

        # Node is checked first, in one sentence, as the fleet meter does (cli/commands/meter.ps1).
        $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $node) { throw "fleet.db needs Node.js 24 or later, and node is not installed or not on this machine's PATH" }
        $major = 0
        $ver = "" + (& $node.Source --version)
        if ($ver -match '^v(\d+)\.') { $major = [int]$Matches[1] }
        if ($major -lt 24) { throw ("fleet.db needs Node.js 24 or later, and this machine has " + $ver.Trim()) }

        $script = Join-Path $root "fleet-db\cli.mjs"
        $before = $env:HORDE_HOME
        $env:HORDE_HOME = $hordeHome
        # ValidateSet lets INIT through; the node side knows the verbs in lower case only.
        try { & $node.Source $script $Verb.ToLowerInvariant() } finally { $env:HORDE_HOME = $before }
        if ($LASTEXITCODE -ne 0) { throw ("horde db " + $Verb + " stopped with exit code " + $LASTEXITCODE) }
    }
}
