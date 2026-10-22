$HordeCommand = @{
    name    = "status"
    group   = "status"
    usage   = "status set -Doing <text> -Finished <text> -Blocked <no|sentence> [-WaitingOn <text>] [-Lane <text>] [-Orc <letter>] [-Folder <lane folder>] [-DryRun]"
    summary = "the one way an Orc's status card (the status.txt the founder's phone shows) is written. set: build the whole record from -Doing, -Finished and -Blocked (all three, every time: no, or one sentence saying what stops all the Orc's work), plus -WaitingOn when something is awaited (left out, the card has no waiting-on line); -Orc and -Lane are taken from the card already in the folder when it reads clean, and must be given when it does not. -Folder is the lane folder, the current folder when left out. The record is checked by the panel's own reader before anything is written: a card it would refuse (a value over 120 characters, a bare pull-request or issue number, a path, a character outside ASCII) is refused with every problem listed, in the reader's words, and nothing is written. A clean card is written whole, read back, and kept as .status.last-good.txt, which the status guard hook restores from. The first card an Orc writes also gives it its row in fleet.db (found by lane folder or letter and kept when there; a new Orc had none until a hand import, and horde decisions publish refused without one): 'fleet.db: row made for Orc X' is printed when a row was made and nothing when it was there, and when the row cannot be made (no Horde home, no fleet.db yet, a busy or newer database, node missing or older than 24) the card stays written, the command still succeeds, and one line says 'card written; fleet.db row not made: <reason>'. -DryRun never touches fleet.db -DryRun prints the record and the verdict and writes nothing"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Position = 0)][string]$Verb = "",
            [string]$Doing,
            [string]$Finished,
            [string]$Blocked,
            [string]$WaitingOn,
            [string]$Lane,
            [string]$Orc,
            [string]$Folder,
            [switch]$DryRun
        )
        # NOTHING IS DECLARED MANDATORY: a missing mandatory parameter is prompted for, and a horde started
        # with its input open waits there for ever (cli/Commands.ps1, New-HordeUsageError). So what must
        # be given is checked here, first, and refused as a usage error. A value given EMPTY is not a
        # missing one: it is the reader's to refuse, in its words.
        if ($Verb -cne "set") { throw (New-HordeUsageError -Message ("status needs a verb: set, not '" + $Verb + "'")) }
        $left = @(foreach ($n in @("Doing", "Finished", "Blocked")) { if (-not $PSBoundParameters.ContainsKey($n)) { "-" + $n } })
        if ($left.Count -gt 0) { throw (New-HordeUsageError -Message ("status set writes the whole card, so it needs " + ($left -join ", ") + " as well")) }
        $dir = $Folder
        if (-not $PSBoundParameters.ContainsKey("Folder") -or "$Folder" -eq "") { $dir = (Get-Location).ProviderPath }
        if (-not [System.IO.Directory]::Exists($dir)) { throw (New-HordeUsageError -Message ("the folder '" + $dir + "' does not exist")) }
        $dir = [System.IO.Path]::GetFullPath($dir)
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why).
        . (Join-Path (Get-HordeRoot) "fleet\StatusWrite.ps1")
        $waiting = $null
        if ($PSBoundParameters.ContainsKey("WaitingOn")) { $waiting = "" + $WaitingOn }
        $r = Invoke-HordeStatusSet -Folder $dir -Doing "$Doing" -Finished "$Finished" -Blocked "$Blocked" -WaitingOn $waiting -Lane "$Lane" -Orc "$Orc" -DryRun:$DryRun
        if ($r.ok) {
            if ($DryRun) { foreach ($l in @($r.lines)) { Write-Output ("  " + $l) } }
            Write-Output $r.message
            # A WRITTEN card (not a dry run, which touches nothing else) gets its fleet.db row if it has none; the card
            # is already safe, so every trouble here is one warning line (Invoke-HordeStatusOrcRow).
            if ($r.written) {
                $row = Invoke-HordeStatusOrcRow -Folder $dir -Orc $r.orc -Lane $r.lane
                if ($row.state -ceq "added") { Write-Output ("fleet.db: row made for Orc " + $r.orc) }
                elseif ($row.state -ceq "skipped") { Write-Output ("card written; fleet.db row not made: " + $row.reason) }
            }
            return
        }
        # A missing Orc or Lane is the command line being short, not the card being wrong.
        if ($r.usage) { throw (New-HordeUsageError -Message "$($r.problems[0])") }
        $out = @("status NOT written: the card would not be read, for " + @($r.problems).Count + " reason(s)")
        if ($r.PSObject.Properties["undone"] -and $r.undone) { $out = @("status write undone: the card was written and did not read back clean, for " + @($r.problems).Count + " reason(s)") }
        foreach ($p in @($r.problems)) { $out += ("  - " + $p) }
        if ($DryRun) { foreach ($l in @($r.lines)) { Write-Output ("  " + $l) } }
        throw ($out -join "`n")
    }
}
