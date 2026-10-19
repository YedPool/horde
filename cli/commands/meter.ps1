$HordeCommand = @{
    name    = "meter"
    group   = "metrics"
    usage   = "meter collect [-SinceDays <n>] [-MaxMs <n>] [-Projects <folder>] [-Registry <folder>] [-Journal <folder>] | meter live [-Session <id>] [-Projects <folder>] [-Registry <folder>] | meter latency | meter watch-limits [-DryRun] [-Projects <folder>] [-Registry <folder>] | meter status | meter tell -File <text file>"
    summary = "the fleet meter (token use, turns, subagent calls and usage-limit stops of every session, kept in HORDE_HOME\metrics\fleet.sqlite): collect: read every transcript touched in the last -SinceDays days (14) from where it stopped last time, for at most -MaxMs milliseconds (240000; it then says partial and the next run continues), also read the hops of phone messages from the relay journal (read-only), and print a summary line and a mail line; live: refresh the per-session view (tokens_usage: tokens, context fill against the model window, running or done) of -Session, or of every session whose transcript changed in the last 10 minutes, reading only the bytes written since the last pass; latency: p50 and p95 of the time between each pair of adjacent hops of a phone message, flagging pairs measured across two clocks; watch-limits: look at the last 64 KB of transcripts changed in the last 6 hours and, once per stop, tell the warchief's session through the fleet's mail that a session has sat at a usage limit for over 5 minutes (it never types into a pane; -DryRun prints what it would send); status: the database, rows per table and the age of the data; tell: the one message the watch sends, text read from -File. Needs Node.js 24 or later"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("collect", "live", "latency", "watch-limits", "status", "tell")][string]$Verb,
            [switch]$DryRun,
            [string]$Projects,
            [string]$Registry,
            [string]$File,
            [string]$Session,
            [string]$Journal,
            [int]$SinceDays,
            [int]$MaxMs
        )
        $verbFlags = @{ collect = @("Projects", "Registry", "SinceDays", "MaxMs", "Journal"); live = @("Session", "Projects", "Registry"); latency = @(); "watch-limits" = @("DryRun", "Projects", "Registry"); status = @(); tell = @("File") }
        # A flag meant for another verb is refused, never silently ignored (cli/commands/metrics.ps1).
        foreach ($flag in @("DryRun", "Projects", "Registry", "File", "SinceDays", "MaxMs", "Session", "Journal")) {
            if ($PSBoundParameters.ContainsKey($flag) -and ($verbFlags[$Verb] -cnotcontains $flag)) { throw ("-" + $flag + " does not apply to meter " + $Verb) }
        }
        $root = Get-HordeRoot
        . (Join-Path $root "core\Home.ps1")
        $hordeHome = Get-HordeHome

        if ($Verb -eq "tell") {
            if (-not $PSBoundParameters.ContainsKey("File") -or $File -eq "") { throw "meter tell needs -File, a text file holding the message" }
            if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { throw ("no such file: " + $File) }
            foreach ($f in @("Tristate", "SessionSeat", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
            . (Join-Path $root "messengers\Port.ps1")
            foreach ($m in @(Get-HordeMessengerFiles)) { . $m }
            . (Join-Path $root "cli\MeterTell.ps1")
            $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $File).Path)
            $r = Send-HordeMeterTell -Body $text -HordeHome $hordeHome
            if (-not $r.ok) { throw $r.detail }
            Write-Output $r.detail
            return
        }

        # NODE IS CHECKED FIRST, in one sentence, so a machine without it fails at once and plainly: a
        # scheduled task has a thin PATH and "not recognised" from a child is no help to whoever reads
        # the task's history.
        $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $node) { throw "the fleet meter needs Node.js 24 or later, and node is not installed or not on this machine's PATH" }
        $major = 0
        $ver = "" + (& $node.Source --version)
        if ($ver -match '^v(\d+)\.') { $major = [int]$Matches[1] }
        if ($major -lt 24) { throw ("the fleet meter needs Node.js 24 or later, and this machine has " + $ver.Trim()) }

        $script = Join-Path $root "fleet-metrics\cli.mjs"
        $nodeArgs = @($script, $Verb)
        if ($DryRun) { $nodeArgs += "--dry-run" }
        if ($Projects -ne "") { $nodeArgs += @("--projects", $Projects) }
        if ($Registry -ne "") { $nodeArgs += @("--registry", $Registry) }
        if ($Session -ne "") { $nodeArgs += @("--session", $Session) }
        if ($Journal -ne "") { $nodeArgs += @("--journal", $Journal) }
        if ($PSBoundParameters.ContainsKey("SinceDays")) { $nodeArgs += @("--since-days", [string]$SinceDays) }
        if ($PSBoundParameters.ContainsKey("MaxMs")) { $nodeArgs += @("--max-ms", [string]$MaxMs) }
        if ($Verb -eq "watch-limits") { $nodeArgs += @("--horde-script", (Join-Path $root "horde.ps1")) }
        # The home is handed down explicitly: the node side has no default of its own (fleet-metrics/home.mjs).
        $before = $env:HORDE_HOME
        $env:HORDE_HOME = $hordeHome
        try { & $node.Source @nodeArgs } finally { $env:HORDE_HOME = $before }
        if ($LASTEXITCODE -ne 0) { throw ("the fleet meter stopped with exit code " + $LASTEXITCODE) }
    }
}
