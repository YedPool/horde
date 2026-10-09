$HordeCommand = @{
    name    = "decisions"
    group   = "decisions"
    usage   = "decisions add -File <question.json> [-Id <32 hex>] [-Json] | decisions update <number> -File <changes.json> [-Id <32 hex>] [-Json] | decisions close <number> (-Outcome <one line> or -OutcomeFile <path>) [-Id <32 hex>] [-Json] | decisions reopen <number> -Reason <one line> [-Id <32 hex>] [-Json] | decisions list [-State <open, closed or all>] [-Json] | decisions show <number> [-Json] | decisions kinds [-Json] | decisions answer <number> (-Text <one line> or -File <path>) [-Wording <number>] [-Id <32 hex>] [-Json] | decisions reply <number> (-Text <one line> or -File <path>) [-Note] [-Wording <number>] [-Id <32 hex>] [-Json] | decisions inbox [-Peek] [-Id <32 hex>] [-Json] | decisions mark-read -UpTo <record> [-Id <32 hex>] [-Json] | decisions notify [-Once] | decisions open [-Hidden] [-OffScreen] [-Report <file.json>] [-Picture <file.png>] [-Unfold <numbers>] [-Orc <letter>] [-Probe <file.json>]"
    summary = "the standing list of questions waiting for a person. add: a new question from a JSON file, and print its permanent number; update: change the fields a JSON file names; close: record what was done; reopen: open it again under the same number; list and show: read the list or one question; kinds: what each kind of question means; answer: write down, in his exact words, what the founder said in chat under a question; reply: say something under a question (-Note: it tells him something and asks him nothing, so the turn stays yours); inbox: print what the founder has said that was not yet read, then mark it read up to the last message printed (-Peek marks nothing; -Json never marks: its one line says so and names the last record it showed); mark-read: record that everything said up to a record has been read, which is how a caller of inbox -Json marks; open: show the list in a window of its own, beside the terminal window of the session that keeps it, redrawn as the list changes, where the founder types his answers - the command returns when the window is closed, and a second open asks the first to come forward; notify: tell the warchief's session, through a messenger, when the founder has answered - question numbers only, never his words (-Once: one pass; open runs it beside the window). A number is given once and never reused. Long text always comes from a file; -Json prints one line of data"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("add", "update", "close", "reopen", "list", "show", "kinds", "answer", "reply", "inbox", "mark-read", "notify", "open")][string]$Verb,
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
            [switch]$Once,
            [switch]$Note,
            [string]$UpTo,
            [switch]$Json,
            [switch]$Hidden,
            [switch]$OffScreen,
            [string]$Report,
            [string]$Picture,
            [string]$Unfold,
            [string]$Orc,
            [string]$Probe
        )
        # The usage above and the ValidateSet are decisions/Console.ps1's verbs table written out, because
        # this file's constants are read without running it; test/test-decisions-cli.ps1 holds them to it.
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why). This block only
        # hands the arguments on: what a verb takes, and everything about the list, is decided in
        # decisions/, so this caller cannot come to differ from the next one.
        . (Join-Path (Get-HordeRoot) "decisions\Console.ps1")
        $result = Invoke-HordeDecisionCommand -Verb $Verb -Given $PSBoundParameters
        # THE WINDOW IS ANOTHER CALLER of the same operations, not a way the command line shows them:
        # the console's side has checked the command line and done nothing, and the window's own file
        # is loaded only now, so no other verb pays for it.
        if ($result.opens) {
            . (Join-Path (Get-HordeRoot) "decisions\Window.ps1")
            Open-HordeDecisionWindow -Hidden:$Hidden -OffScreen:$OffScreen -Report "$Report" -Picture "$Picture" -Unfold "$Unfold" -Orc "$Orc" -Probe "$Probe"
            return
        }
        # NOTIFY IS ANOTHER CALLER too (decisions/Notify.ps1), loaded only now. Its lines go out as it says
        # them; a told record that cannot be read ends it with a throw, so horde exits 1.
        if ($result.notifies) {
            . (Join-Path (Get-HordeRoot) "decisions\Notify.ps1")
            Invoke-HordeDecisionNotifyLoop -Once:$Once
            return
        }
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
