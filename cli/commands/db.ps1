$HordeCommand = @{
    name    = "db"
    group   = "data"
    usage   = "db init | db status | db check | db import [-Ledger <tasks.jsonl>] [-PrCache <pr-cache.json>] [-Changelog <changelog.jsonl>] [-Cards <orcs folder>] [-ThrallCard <status.txt>] [-Registry <sessions folder>] [-Decisions <storedecisions folder>] [-Lots <hibernations folder>] [-DryRun]"
    summary = "fleet.db, the fleet's one database of work data, kept in HORDE_HOME\fleet.db: init: make it, or bring it to this version's schema (safe to run again); status: the file, its schema and the rows in every table, changing no data; check: SQLite's integrity and foreign-key checks and the rules one row cannot hold alone, one line per problem, exit 1 if any; import: read the old files you name (the task ledger, the PR cache, the changelog, the status cards, the Thrall card, the session registry, the decisions store, the parking lots; no path is ever defaulted) into fleet.db in one transaction, print the rows added and already there per table and every line that could not be linked, and run it twice to add nothing; -DryRun does it all and writes nothing. HORDE_HOME must be set: fleet.db is never made in a default folder. Needs Node.js 24 or later"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("init", "status", "check", "import")][string]$Verb,
            [ValidateNotNullOrEmpty()][string]$Ledger,
            [ValidateNotNullOrEmpty()][string]$PrCache,
            [ValidateNotNullOrEmpty()][string]$Changelog,
            [ValidateNotNullOrEmpty()][string]$Cards,
            [ValidateNotNullOrEmpty()][string]$ThrallCard,
            [ValidateNotNullOrEmpty()][string]$Registry,
            [ValidateNotNullOrEmpty()][string]$Decisions,
            [ValidateNotNullOrEmpty()][string]$Lots,
            [switch]$DryRun
        )
        # A flag meant for another verb is refused, never silently ignored (cli/commands/metrics.ps1).
        if ($Verb -ne "import") {
            foreach ($flag in @("Ledger", "PrCache", "Changelog", "Cards", "ThrallCard", "Registry", "Decisions", "Lots", "DryRun")) {
                if ($PSBoundParameters.ContainsKey($flag)) { throw ("-" + $flag + " belongs to db import, not db " + $Verb) }
            }
        }
        # THE HOME MUST BE NAMED, not defaulted (fleet-db/cli.mjs): one database for the whole fleet, and a
        # second one made under a default folder would be read by nothing. Checked before Node, so the
        # message is about the home and not about a child process.
        $root = Get-HordeRoot
        . (Join-Path $root "core\Home.ps1")
        $resolved = Resolve-HordeHome
        if ($resolved.source -eq "default") { throw "horde db needs HORDE_HOME set to the Horde home (or a home pointer: horde home set -Path <folder>): fleet.db is the fleet's one database and is never made in a default folder" }
        $hordeHome = $resolved.path

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
        $nodeArgs = @($Verb.ToLowerInvariant())
        if ($Verb -eq "import") {
            # Paths are made absolute here, against the folder the user is in, because node starts in
            # PowerShell's process folder, which is not always the same one.
            $flags = [ordered]@{ "--ledger" = $Ledger; "--pr-cache" = $PrCache; "--changelog" = $Changelog; "--cards" = $Cards; "--thrall-card" = $ThrallCard; "--registry" = $Registry; "--decisions" = $Decisions; "--lots" = $Lots }
            foreach ($f in $flags.Keys) {
                if ("" + $flags[$f] -ne "") { $nodeArgs += @($f, $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($flags[$f])) }
            }
            if ($DryRun) { $nodeArgs += "--dry-run" }
        }
        try { & $node.Source $script @nodeArgs } finally { $env:HORDE_HOME = $before }
        if ($LASTEXITCODE -ne 0) { throw ("horde db " + $Verb + " stopped with exit code " + $LASTEXITCODE) }
    }
}
