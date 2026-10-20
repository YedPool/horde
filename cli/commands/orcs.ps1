$HordeCommand = @{
    name    = "orcs"
    group   = "orcs"
    usage   = "orcs list [-Json] | orcs order <id> <id> ... [-BackBurner <id,id,...>] [-Version <n>] [-Json] | orcs backburner <id> on|off [-Version <n>] [-Json] | orcs name <id> <name> [-Version <n>] [-Json] | orcs domain <id> <one line> [-Version <n>] [-Json] | orcs retire <id> [-Version <n>] [-Json] | orcs tier <id> 1|2 [-Version <n>] [-Json] | orcs seed -File <seed.json>"
    summary = "the one list of Orcs, in the founder's priority order, that his phone's Dash shows. list: every Orc with its letter, name, status and how long (working, idle 3 h, blocked 40 min), the questions waiting on the founder, the sessions it has open and its one-line domain, the main list then the back-burner, and the registry version; a lane seen in the lanes folder and not yet on the list is shown at the end and registered by the next change. order: the WHOLE list, first to last, every Orc exactly once, with -BackBurner naming the ones below the divider - refused when an Orc is missing, extra or named twice; backburner: move one Orc below the divider (on) or back to the end of the main list (off); name: the name shown (at most 40 characters); domain: its one-line domain (at most 80 plain characters, stored exactly) - for M and the founder, not for an Orc to write its own: an Orc proposes a change to M; retire: take an Orc off the list for good; tier: put an Orc in tier 1 or 2; seed: M's one step that sets every domain from a file {""v"":1,""domains"":{""<letter>"":""<domain>""}}. An id is the lane's folder name, or the Orc's letter when one Orc has it. -Version is the registry version the change was drawn from: when the registry has moved since, the change is refused as stale and nothing is written. Every change is a record kept for good, with who and when; -Json prints one line of data"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("list", "order", "backburner", "name", "domain", "retire", "tier", "seed")][string]$Verb,
            [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
            [string]$BackBurner,
            [string]$Version,
            [string]$File,
            [switch]$Json
        )
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why). This block only hands
        # the arguments on: what a verb takes, and everything about the list, is decided in orcs/.
        . (Join-Path (Get-HordeRoot) "orcs\Console.ps1")
        $result = Invoke-HordeOrcCommand -Verb $Verb -Rest @($Rest) -BackBurner "$BackBurner" -Version "$Version" -File "$File" -Json:$Json
        foreach ($l in @($result.lines)) { Write-Output $l }
        # Printed first, then failed: the throw gives a script its non-zero exit (horde.ps1).
        if ($result.failure -ne "") { throw $result.failure }
    }
}
