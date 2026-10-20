$HordeCommand = @{
    name    = "decisions"
    group   = "decisions"
    usage   = "decisions add -File <question.json> [-Importance <high, normal or low>] [-Blocks <all, part or none>] [-FollowsUp <question>] [-NeedsPasskey] [-Id <32 hex>] [-Json] | decisions update <number> -File <changes.json> [-Id <32 hex>] [-Json] | decisions close <number> (-Outcome <one line> or -OutcomeFile <path>) [-Id <32 hex>] [-Json] [-HordeHome <path>] | decisions reopen <number> -Reason <one line> [-Id <32 hex>] [-Json] | decisions rank <number> [-Importance <high, normal or low>] [-Blocks <all, part or none>] [-Id <32 hex>] [-Json] | decisions list [-State <open, closed or all>] [-Json] | decisions show <number> [-Json] [-HordeHome <path>] | decisions kinds [-Json] | decisions answer <number> (-Text <one line> or -File <path>) [-Part <letter>] [-Wording <number>] [-Id <32 hex>] [-Json] | decisions reply <number> (-Text <one line> or -File <path>) [-Note] [-Wording <number>] [-Id <32 hex>] [-Json] | decisions inbox [-Peek] [-Id <32 hex>] [-Json] | decisions mark-read -UpTo <record> [-Id <32 hex>] [-Json] | decisions ack <number> -Answer <record> [-Id <32 hex>] [-Json] [-HordeHome <path>] | decisions change-reply <number> -Answer <record> -Reply <not-acted, undoing or cannot-undo> [-Why <one line>] [-Id <32 hex>] [-Json] [-HordeHome <path>] | decisions route | decisions notify [-Once] | decisions open [-Hidden] [-OffScreen] [-Report <file.json>] [-Picture <file.png>] [-Unfold <numbers>] [-Orc <letter>] [-Probe <file.json>]"
    summary = "the standing list of questions waiting for a person. add: a new question from a JSON file, and print its permanent number - SAY HOW MUCH IT MATTERS when you add it: -Importance is how important the task it belongs to is overall (high, normal or low), -Blocks is how much of that task's work stands still until he answers (all, part or none); left out they read as normal and part, and he can order his list by either; -FollowsUp <question> makes it a follow-up to an earlier question, which he sees folded under the new one with what he answered; -NeedsPasskey marks a question that the founder must answer with a fresh passkey on the phone (production deploys, anything that changes something important); update: change the fields a JSON file names; close: record what was done; reopen: NO LONGER DONE - a question he has answered, or one that is closed, is never put back in front of him; it is refused and says how to ask a follow-up (add -FollowsUp); rank: correct the importance or the blocking of an open question; list and show: read the list or one question; kinds: what each kind of question means; answer: write down, in his exact words, what the founder said in chat under a question (-Part <letter>: his words answer that one part of a question of parts); reply: say something under a question that is still on his list (-Note: it tells him something and asks him nothing, so the turn stays yours; once he has answered, only a note is taken - words that ask are refused, because they would put the question back in front of him: ask a follow-up instead); inbox: print what the founder has said that was not yet read, then mark it read up to the last message printed (-Peek marks nothing; -Json never marks: its one line says so and names the last record it showed); mark-read: record that everything said up to a record has been read, which is how a caller of inbox -Json marks; ack: run by the Orc that asked, from inside its own session - acknowledge the founder's answer that Horde routed to you, which closes the question with you as the closer (-Answer <record>, required: the answer the notice named; only an open, answered question closes, and a closed one is never opened again); change-reply: run by the Orc that asked, from inside its own session, when the routed notice says the founder CHANGED his answer - say what became of your work with -Reply not-acted (you had not acted: using the new answer), undoing (you had acted and are undoing it) or cannot-undo (you had acted and cannot undo it: -Why <one line> says why); -Answer is the record of the changed answer the notice names; the page tells him your reply in plain words; route: one pass of the router, which sends each new answer of the founder's to the Orc that asked (or to the warchief when askedBy names no Orc it can find), mirrors one line to the analyst, reminds the asker once of a question answered over an hour ago and still open, and records each send in the list so it is sent once; open: show the list in a window of its own, beside the terminal window of the session that keeps it, redrawn as the list changes, where the founder types his answers - the command returns when the window is closed, and a second open asks the first to come forward; notify: tell the warchief's session, through a messenger, when the founder has answered - question numbers only, never his words (-Once: one pass; open runs it beside the window). A number is given once and never reused. Long text always comes from a file; -Json prints one line of data"
    run     = {
        [CmdletBinding()] param(
            [Parameter(Mandatory = $true, Position = 0)][ValidateSet("add", "update", "close", "reopen", "rank", "list", "show", "kinds", "answer", "reply", "inbox", "mark-read", "ack", "change-reply", "route", "notify", "open")][string]$Verb,
            [Parameter(Position = 1)][string]$Number,
            [string]$File,
            [string]$Id,
            [string]$OutcomeFile,
            [string]$Outcome,
            [string]$Reason,
            [string]$Importance,
            [string]$Blocks,
            [string]$FollowsUp,
            [switch]$NeedsPasskey,
            [string]$Part,
            [string]$State,
            [string]$Text,
            [string]$Wording,
            [switch]$Peek,
            [switch]$Once,
            [switch]$Note,
            [string]$UpTo,
            [string]$Answer,
            [string]$Reply,
            [string]$Why,
            [switch]$Json,
            [switch]$Hidden,
            [switch]$OffScreen,
            [string]$Report,
            [string]$Picture,
            [string]$Unfold,
            [string]$Orc,
            [string]$Probe,
            [Alias("Home")][string]$HordeHome
        )
        # The usage above and the ValidateSet are decisions/Console.ps1's verbs table written out, because
        # this file's constants are read without running it; test/test-decisions-cli.ps1 holds them to it.
        # Loaded here, in the command's own scope (cli/commands/metrics.ps1 says why). This block only
        # hands the arguments on: what a verb takes, and everything about the list, is decided in
        # decisions/, so this caller cannot come to differ from the next one.
        # -HordeHome (alias -Home; the parameter cannot be named Home, which PowerShell owns) points this
        # one call at another home's list, where the question lives (decisions/Route.ps1 puts it in the
        # commands it sends: the founder's list is not an Orc's own HORDE_HOME). It overrides HORDE_HOME for
        # this call only and is put back after it, whichever way the call ends.
        $keptHordeHome = $env:HORDE_HOME
        if ($PSBoundParameters.ContainsKey("HordeHome")) {
            if ("$HordeHome".Trim() -eq "") { throw "-HordeHome needs a folder: the home whose list this call reads (an absolute path)" }
            $env:HORDE_HOME = "$HordeHome".Trim()
        }
        try {
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
        # THE ROUTER IS ANOTHER CALLER (decisions/Route.ps1), loaded only now: one pass, its lines as it says
        # them. Another router holding this home's mutex (the relay runner's) is said, and is no failure.
        if ($result.routes) {
            . (Join-Path (Get-HordeRoot) "decisions\Route.ps1")
            $turn = Invoke-HordeDecisionRouteTurn -Memory @{} -Force
            if ($turn.outcome -ceq "elsewhere") { Write-Output "not run: another router of this home is in a pass now, and it routes what waits"; return }
            if (@($turn.lines).Count -eq 0) { Write-Output "nothing to route: every answer under an open question is routed, and no question waits for its one reminder"; return }
            foreach ($line in @($turn.lines)) { Write-Output $line }
            if ($turn.outcome -ceq "refused") { throw ("" + @($turn.lines)[0]) }
            return
        }
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
        finally { if ($PSBoundParameters.ContainsKey("HordeHome")) { $env:HORDE_HOME = $keptHordeHome } }
    }
}
