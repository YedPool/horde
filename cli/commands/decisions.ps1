$HordeCommand = @{
    name    = "decisions"
    group   = "decisions"
    usage   = "decisions add -File <question.json> [-Id <32 hex>] [-Json] | decisions update <number> -File <changes.json> [-Id <32 hex>] [-Json] | decisions close <number> -OutcomeFile <path> | -Outcome <one line> [-Id <32 hex>] [-Json] | decisions reopen <number> -Reason <one line> [-Id <32 hex>] [-Json] | decisions list [-State open|closed|all] [-Json] | decisions show <number> [-Json] | decisions kinds [-Json]"
    summary = "the standing list of questions waiting for a person. add: a new question from a JSON file, and print its permanent number; update: change the fields a JSON file names; close: record what was done; reopen: open it again under the same number; list and show: read the list or one question; kinds: what each kind of question means. A number is given once and never reused. Long text always comes from a file; -Json prints one line of data"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("add", "update", "close", "reopen", "list", "show", "kinds")][string]$Verb,
            [Parameter(Position = 1)][string]$Number,
            [string]$File,
            [string]$Id,
            [string]$OutcomeFile,
            [string]$Outcome,
            [string]$Reason,
            [string]$State,
            [switch]$Json
        )
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why). This block only
        # hands the arguments on: what a verb takes, and everything about the list, is decided in
        # decisions/, so this caller cannot come to differ from the next one.
        . (Join-Path (Get-HordeRoot) "decisions\Console.ps1")
        $result = Invoke-HordeDecisionCommand -Verb $Verb -Given $PSBoundParameters
        Write-HordeDecisionLines -Lines $result.lines
        # Printed first, then failed: the lines say what was refused and why, and the throw gives a
        # script its non-zero exit (horde.ps1: a command fails by throwing).
        if ($result.failure -ne "") { throw $result.failure }
    }
}
