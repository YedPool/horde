$HordeCommand = @{
    name    = "decisions"
    group   = "decisions"
    usage   = "decisions add -File <question.json> [-Id <32 hex>] [-Json] | decisions update <number> -File <changes.json> [-Id <32 hex>] [-Json] | decisions close <number> (-Outcome <one line> or -OutcomeFile <path>) [-Id <32 hex>] [-Json] | decisions reopen <number> -Reason <one line> [-Id <32 hex>] [-Json] | decisions list [-State <open, closed or all>] [-Json] | decisions show <number> [-Json] | decisions kinds [-Json] | decisions answer <number> (-Text <one line> or -File <path>) [-Wording <number>] [-Id <32 hex>] [-Json] | decisions reply <number> (-Text <one line> or -File <path>) [-Wording <number>] [-Id <32 hex>] [-Json] | decisions inbox [-Peek] [-Id <32 hex>] [-Json]"
    summary = "the standing list of questions waiting for a person. add: a new question from a JSON file, and print its permanent number; update: change the fields a JSON file names; close: record what was done; reopen: open it again under the same number; list and show: read the list or one question; kinds: what each kind of question means; answer: write down, in his exact words, what the founder said in chat under a question; reply: say something under a question; inbox: print what the founder has said that was not yet read, then mark it read up to the last message printed (-Peek marks nothing; with -Json the one line says whether and up to where it marked). A number is given once and never reused. Long text always comes from a file; -Json prints one line of data"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("add", "update", "close", "reopen", "list", "show", "kinds", "answer", "reply", "inbox")][string]$Verb,
            [Parameter(Position = 1)][string]$Number,
            [string]$File,
            [string]$Id,
            [string]$OutcomeFile,
            [string]$Outcome,
            [string]$Reason,
            [string]$State,
            [string]$Text,
            [string]$Wording,
            [switch]$Peek,
            [switch]$Json
        )
        # The usage above and the ValidateSet are decisions/Console.ps1's verbs table written out, because
        # this file's constants are read without running it; test/test-decisions-cli.ps1 holds them to it.
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why). This block only
        # hands the arguments on: what a verb takes, and everything about the list, is decided in
        # decisions/, so this caller cannot come to differ from the next one.
        . (Join-Path (Get-HordeRoot) "decisions\Console.ps1")
        $result = Invoke-HordeDecisionCommand -Verb $Verb -Given $PSBoundParameters
        Write-HordeDecisionLines -Lines $result.lines
        # Printed first, then failed: the lines say what was refused and why, and the throw gives a
        # script its non-zero exit (horde.ps1: a command fails by throwing).
        if ($result.failure -ne "") { throw $result.failure }
        # What a verb does once its lines are out (inbox marks as read what it has just printed).
        $then = Complete-HordeDecisionCommand -After $result.after
        Write-HordeDecisionLines -Lines $then.lines
        if ($then.failure -ne "") { throw $then.failure }
    }
}
