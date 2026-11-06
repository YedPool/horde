$HordeCommand = @{
    name    = "signal"
    group   = "data"
    usage   = "signal raise -Key <key> -Kind <kind> (-Text <text> | -File <path>) [-Owner <who>] [-At <ms or ISO time with a zone>] [-Urgent] [-Quiet] | signal woke -Key <key> [-At <ms or ISO time with a zone>] | signal close -Key <key> -By <who> | signal list [-Open] [-Owner <who>] [-Unwoken] [-MarkWoke [-At <ms or ISO time with a zone>]] [-Json] | signal prune -Days <n>"
    summary = "the overseer's signals in fleet.db (a problem it saw, one row per key), so the overseer and the analyst detect a stall once, from one place; the signals have no file behind them, fleet.db is their only home. Every verb is idempotent, is one short transaction and prints one line; long text goes in -File (ASCII or UTF-8, no shell quoting). raise: a new key is made with first and last time at -At (now when left out) and count 1; an open key moves its last time forward, adds 1 to the count and takes the new text; a CLOSED key raised again is REOPENED ('reopened': closed time and closer cleared, first time and count kept going), because a problem that came back is the same problem and must wake the overseer; on an OPEN signal a raise whose time is not after the last one is a retry or an older report and changes nothing ('kept'), so the same key with the same -At never counts twice, and -Urgent / -Quiet (the overseer skips its one-hour gap for urgent, wakes nobody for quiet; absent means off) are set by every raise that changes something and left alone by one that does not; a CLOSED signal raised with ANY time is reopened (last_at never moves back) and both wake times are cleared; a key of another kind is refused. Raising a still-true condition on every pass moves last_at and makes the signal unwoken again, so raise only a NEW key, or pass the condition's own time as -At. The owner may be a person or a path with spaces (one line of printable ASCII, up to 120 characters); the kind is the overseer's to map from its key prefix. close: close it (closing a closed one prints 'kept'; an unknown key is refused). list: one plain line per signal, newest first; -Open leaves out the closed ones, -Unwoken keeps the open, not quiet ones with no CONFIRMED wake since they last happened (a wake that was attempted and failed stays unwoken and is retried), -Json is one line of data. -MarkWoke (with -Open; it implies -Unwoken) records the wake ATTEMPT time woke_at (now, or -At) on exactly the signals that need a wake, in the same transaction, so two passes cannot wake the same signals twice and the overseer can back off from that time. woke: once the wake worked, record it (woke_ok_at, -At or now, never moved back; a repeat prints 'kept'; an unknown key is refused); until then the signal is still unwoken. prune: delete the CLOSED signals closed more than -Days days ago (required, 1 or more) and say how many; open signals are never pruned. Times are UTC milliseconds or an ISO time WITH a zone: a local time with no zone is refused, and so is a time more than a day ahead. ASCII only; a value may not be empty or hold a double quote (use -File). The commands never make or migrate fleet.db (run horde db init); the exit is 1 for any failure, and the message names the finer code from fleet-db\jobs-cli.mjs (2 no home, 3 'fleet.db busy', 4 no fleet.db yet). HORDE_HOME or a home pointer (horde home set) must name the home. Needs Node.js 24 or later"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("raise", "woke", "close", "list", "prune")][string]$Verb,
            [string]$Key,
            [string]$Kind,
            [string]$Owner,
            [string]$Text,
            [string]$File,
            [string]$At,
            [string]$By,
            [string]$Days,
            [switch]$Open,
            [switch]$Unwoken,
            [switch]$Urgent,
            [switch]$Quiet,
            [switch]$MarkWoke,
            [switch]$Json
        )
        # A flag meant for another verb is refused, never silently ignored (cli/commands/work.ps1).
        $own = @{
            raise = @("Key", "Kind", "Owner", "Text", "File", "At", "Urgent", "Quiet")
            woke  = @("Key", "At")
            close = @("Key", "By")
            list  = @("Owner", "At", "Open", "Unwoken", "MarkWoke", "Json")
            prune = @("Days")
        }
        foreach ($flag in @($PSBoundParameters.Keys)) {
            if ($flag -ne "Verb" -and $own[$Verb] -notcontains $flag) { throw ("-" + $flag + " does not belong to signal " + $Verb) }
        }
        $root = Get-HordeRoot
        . (Join-Path $root "fleet-db\Jobs.ps1")
        $flags = [ordered]@{
            "--key" = "Key"; "--kind" = "Kind"; "--owner" = "Owner"; "--text" = "Text"; "--file" = "File"
            "--at" = "At"; "--by" = "By"; "--days" = "Days"
        }
        $values = [ordered]@{}
        foreach ($f in $flags.Keys) {
            if ($PSBoundParameters.ContainsKey($flags[$f])) { $values[$f] = $PSBoundParameters[$flags[$f]] }
        }
        $bare = @()
        if ($Urgent) { $bare += "--urgent" }
        if ($Quiet) { $bare += "--quiet" }
        if ($Open) { $bare += "--open" }
        if ($Unwoken) { $bare += "--unwoken" }
        if ($MarkWoke) { $bare += "--mark-woke" }
        if ($Json) { $bare += "--json" }
        Invoke-HordeJobsCli -Root $root -Noun "signal" -Verb $Verb -Values $values -Switches $bare
    }
}
