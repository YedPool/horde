# decisions/Console.ps1 - the command line's side of the decisions list: one caller, and one way of showing.
#
# THE ONE JOB of this file is to stand between a person at a terminal and decisions/Operations.ps1: it
# reads the files a command names, builds the plain request, calls the one entry point, and turns the
# answer into lines. It decides nothing about the list - no rule, no state, no record is known here -
# so the command line can never come to disagree with another caller about what is allowed.
# cli/commands/decisions.ps1 declares the command and hands its arguments to
# Invoke-HordeDecisionCommand; a command file may only declare (cli/Commands.ps1), so the work is here.
#
# LONG TEXT ALWAYS COMES FROM A FILE. The Windows command shell cuts a command at its first line
# break, and a message once arrived as its first line only (decisions design, 2026-10-06, section 3.1). So a question is a
# JSON file, a closing outcome of more than a line is a file, and only one-line texts are arguments.
#
# A FILE IS READ AS WHAT IT IS, OR REFUSED. UTF-8 with or without a byte-order mark, or UTF-16 with
# one (what Windows PowerShell 5.1's own > and Out-File write). Bytes that are neither are refused:
# read in the machine's code page, a question in another alphabet would be stored as different letters.
#
# -Json IS ONE LINE OF ASCII. Every character outside printable ASCII is written as a \u escape, which
# any JSON reader turns back into the same character. A console, a pipe and a log each re-encode
# output in a code page of their own, and escaped text passes through all of them unchanged: text in
# any alphabet comes back character for character.
#
# THE CONVERSATION UNDER A QUESTION is three verbs. `answer` and `reply` are both the operation say:
# which of them was typed decides who is recorded as speaking and by what route, and no flag can say
# otherwise - `answer` is the session that keeps the list writing down what the founder said in chat,
# stored as recorded from chat and never as typed by him. `inbox` is the operation inbox, asked twice:
# once to read what is unread, and - after the lines are out - once to mark exactly those messages as
# read (Complete-HordeDecisionCommand). The words of a message are printed line for line as they are.
#
# THE PLAIN-TEXT OUTPUT IS UTF-8 WHEN IT GOES TO A PIPE. Typed at a terminal it is written as it is, and
# how it looks is the terminal's doing. Redirected, Windows PowerShell 5.1 encodes it in the console's
# code page, and the session that keeps the list reads these commands through a pipe: measured
# 2026-10-06 from code page 437, a Hebrew title came out of `show` as "??? ????? ?? ??????", with
# nothing to say so. So for the length of the print, and only when the output is redirected, the
# console's output encoding is set to UTF-8 with no byte-order mark, and put back afterwards. This is
# the decisions command's own doing; no other horde command is changed by it.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\JsonText.ps1")
. (Join-Path $PSScriptRoot "Operations.ps1")

# THE ONE TABLE OF THE COMMAND'S VERBS. A verb is an operation of the same name
# (decisions/Operations.ps1), unless its entry names another (operation): "answer" and "reply" are
# both the operation say, with who speaks and by what route fixed here (says), because at this
# command line that is decided by which verb was typed and never by a flag. Here is what the command
# line adds to an operation: whether it is about one
# question (and so takes its number), which flags it takes, and how its usage reads. The dispatch
# below reads it, a wrong command line is answered with a verb's usage from it, and the whole usage
# line is built from it. Whether a verb writes is not said here: the operations say that.
# A flag given to a verb that does not take it is refused, never ignored (cli/commands/metrics.ps1
# does the same).
# THE COMMAND FILE HAS TO WRITE TWO THINGS OUT AGAIN: its usage and its ValidateSet are constants read
# from its syntax tree without running anything (cli/Commands.ps1), so neither can be worked out from
# this table when the file is loaded. test/test-decisions-cli.ps1 holds both to this table, word for
# word, so they cannot drift.
# IN A USAGE, a bar stands between two verbs and for nothing else: alternatives inside one verb are
# written in words.
$script:HordeDecisionCommandVerbs = [ordered]@{
    add    = @{ number = $false; flags = @("File", "Id", "Json");                   usage = "add -File <question.json> [-Id <32 hex>] [-Json]" }
    update = @{ number = $true;  flags = @("File", "Id", "Json");                   usage = "update <number> -File <changes.json> [-Id <32 hex>] [-Json]" }
    close  = @{ number = $true;  flags = @("OutcomeFile", "Outcome", "Id", "Json"); usage = "close <number> (-Outcome <one line> or -OutcomeFile <path>) [-Id <32 hex>] [-Json]" }
    reopen = @{ number = $true;  flags = @("Reason", "Id", "Json");                 usage = "reopen <number> -Reason <one line> [-Id <32 hex>] [-Json]" }
    list   = @{ number = $false; flags = @("State", "Json");                        usage = "list [-State <open, closed or all>] [-Json]" }
    show   = @{ number = $true;  flags = @("Json");                                 usage = "show <number> [-Json]" }
    kinds  = @{ number = $false; flags = @("Json");                                 usage = "kinds [-Json]" }
    # THE CONVERSATION UNDER A QUESTION. answer: the session that keeps the list writes down what the
    # founder said in chat, in his words - stored as recorded from chat, never as typed by him.
    # reply: that session speaks. inbox: what the founder has said that it has not read.
    answer = @{ number = $true;  flags = @("Text", "File", "Wording", "Id", "Json"); usage = "answer <number> (-Text <one line> or -File <path>) [-Wording <number>] [-Id <32 hex>] [-Json]"; operation = "say"; says = @{ speaker = "founder"; route = "chat-recorded" } }
    reply  = @{ number = $true;  flags = @("Text", "File", "Wording", "Id", "Json"); usage = "reply <number> (-Text <one line> or -File <path>) [-Wording <number>] [-Id <32 hex>] [-Json]"; operation = "say"; says = @{ speaker = "warchief"; route = "command" } }
    inbox  = @{ number = $false; flags = @("Peek", "Id", "Json");                   usage = "inbox [-Peek] [-Id <32 hex>] [-Json]" }
}
# The role this caller acts as. The command line is the warchief's tool: nobody else writes to the list
# today, and the operations refuse a role the rules' list of actors does not hold.
$script:HordeDecisionCommandActor = "warchief"

function Get-HordeDecisionCommandVerbs { return @($script:HordeDecisionCommandVerbs.Keys) }

function Get-HordeDecisionCommandVerb {
    # One verb's entry of the table, as { number; flags; usage }, or $null for a word that is no verb.
    param([Parameter(Mandatory = $true)][string]$Verb)
    $entry = $script:HordeDecisionCommandVerbs[$Verb]
    if ($null -eq $entry) { return $null }
    return [pscustomobject]@{ number = [bool]$entry.number; flags = @($entry.flags); usage = "$($entry.usage)" }
}

function Get-HordeDecisionCommandUsage {
    # The command's whole usage line, built from the table: each verb's usage, a bar between two.
    return (@($script:HordeDecisionCommandVerbs.Keys | ForEach-Object { "decisions " + $script:HordeDecisionCommandVerbs[$_].usage }) -join " | ")
}

function Read-HordeDecisionTextFile {
    # The whole text of a file a command named, exactly as written. -What names it in a refusal.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$What)
    # Resolved against PowerShell's current folder, not the process's: the two differ after a
    # Set-Location, and .NET alone would read a file of the same name somewhere else.
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not [System.IO.File]::Exists($full)) { throw ($What + " '" + $Path + "' was not found") }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    try {
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes, 3, $bytes.Length - 3)
        }
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return (New-Object System.Text.UnicodeEncoding($false, $false, $true)).GetString($bytes, 2, $bytes.Length - 2) }
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { return (New-Object System.Text.UnicodeEncoding($true, $false, $true)).GetString($bytes, 2, $bytes.Length - 2) }
        return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)
    } catch {
        throw ($What + " '" + $Path + "' is not UTF-8 text. Save it as UTF-8 and try again; it was not read in another encoding, which would change its letters")
    }
}

function Read-HordeDecisionJsonFile {
    # A JSON object from a file a command named. A key given twice in one object is refused:
    # ConvertFrom-Json keeps one of the two and says nothing (core/JsonText.ps1), so the file would
    # show its author one title and store another.
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$What)
    $text = Read-HordeDecisionTextFile -Path $Path -What $What
    $twice = @(Find-HordeJsonDuplicateKey -Text $text)
    # The key is not named: a name is text somebody typed, and what Find-HordeJsonDuplicateKey says
    # of it quotes it. A token pasted where a name goes was printed back here (measured 2026-10-06).
    if ($twice.Count -gt 0) { throw ($What + " '" + $Path + "' gives a key twice (" + $twice.Count + " key(s) are given more than once). One of each pair would be stored unseen, so nothing was read. The keys are not named here, because a name may hold what must not be printed") }
    $parsed = $null
    # THE PARSER'S OWN MESSAGE IS NOT REPEATED. Windows PowerShell 5.1's ConvertFrom-Json quotes what it
    # could not read: "Invalid JSON primitive: <the text>", and for a string left open the whole file.
    # Measured 2026-10-06: a question file one quote short of valid, holding a token, had the token
    # printed back by this refusal - before the secret check, which only sees a request, could run.
    try { $parsed = $text | ConvertFrom-Json } catch { throw ($What + " '" + $Path + "' is not JSON. Nothing of it is quoted here, because it may hold what must not be printed; ConvertFrom-Json on the file says where it stops being JSON") }
    if ($null -eq $parsed -or $parsed -isnot [System.Management.Automation.PSCustomObject]) { throw ($What + " '" + $Path + "' must hold one JSON object, written between { and }") }
    return $parsed
}

function ConvertTo-HordeDecisionJsonLine {
    # An answer as one line of ASCII JSON: { state; value; reason; observedAt }, core/Tristate.ps1's
    # stored form, so a script reads the three states the same way everywhere in Horde.
    param($Answer)
    $json = ConvertTo-Json -InputObject (ConvertTo-HordeAnswerRecord -Answer $Answer) -Compress -Depth 12
    # Outside a string, JSON has no character beyond ASCII, so every match is inside one, where a \u
    # escape is the same character. A character beyond U+FFFF is two UTF-16 units and becomes two
    # escapes, which is how JSON writes it.
    return [regex]::Replace($json, '[^\x20-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") })
}

function Format-HordeDecisionTime {
    # A stored time (ISO 8601, UTC) as "2026-10-06 19:34 UTC". Cut from the text, not parsed: parsing
    # would hand back local time, and a list read in two time zones must show one time.
    param([string]$At)
    if ($At -cnotmatch '\A([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2})') { return $At }
    return ($Matches[1] + " " + $Matches[2] + " UTC")
}

function Get-HordeDecisionKindLabel {
    param($Kinds, [string]$Kind)
    $entry = Get-HordeDecisionMember -Object $Kinds -Name $Kind
    if ($null -eq $entry) { return $Kind }
    return "$($entry.label)"
}

function Get-HordeDecisionFirstLine {
    # The first line of a text, cut at -Most characters with a mark that says it was cut.
    param([string]$Text, [int]$Most = 160)
    $line = @($Text -split "\r?\n" | Where-Object { $_.Trim() -ne "" }) | Select-Object -First 1
    $line = "$line".Trim()
    if ($line.Length -gt $Most) { return ($line.Substring(0, $Most) + " [...]") }
    if ($line -ne $Text.Trim()) { return ($line + " [...]") }
    return $line
}

function Format-HordeDecisionMessage {
    # One message as lines, for a thread and for an inbox alike: who said it and by what route, when,
    # in which record; what is to be known about it; and the words, every line, exactly.
    # THE WORDS ARE NEVER CUT, JOINED OR RE-WRAPPED: each of their lines is one printed line, indented.
    param($Message, [string]$Indent = "  ", [int]$NowWording = 0)
    $lines = New-Object System.Collections.ArrayList
    $wording = "wording not stated"
    if ($Message.wordingStated) { $wording = "said to wording " + $Message.wordingVersion }
    [void]$lines.Add($Indent + $Message.speakerShown + ", " + $Message.routeShown + ", " + (Format-HordeDecisionTime -At $Message.at) + " (record " + $Message.sequence + ", " + $wording + ")")
    if ($Message.arrivedAfterClosing) { [void]$lines.Add($Indent + "  NOTE: this arrived after the question was closed. It is kept, and it reopened nothing.") }
    if ($Message.saidToEarlierWording) {
        $now = ""
        if ($NowWording -gt 0) { $now = "; the question is now at wording " + $NowWording }
        [void]$lines.Add($Indent + "  NOTE: this was said to an earlier wording (wording " + $Message.wordingVersion + $now + "). Check that it still answers the question as it reads now.")
    }
    foreach ($l in @(([string]$Message.text) -split "\r?\n")) { [void]$lines.Add($Indent + "    " + $l) }
    return @($lines)
}

function Format-HordeDecisionThreadSummary {
    # A thread's counts as one phrase: "3 message(s); 1 not yet read by the warchief; turn: the warchief".
    param($Thread)
    $phrase = "" + $Thread.count + " message(s)"
    foreach ($u in @($Thread.unread)) { if ($u.count -gt 0) { $phrase = $phrase + "; " + $u.count + " not yet read by " + $u.readerShown } }
    return ($phrase + "; turn: " + $Thread.turnShown)
}

function Format-HordeDecisionInbox {
    # An inbox answer as lines: each unread message under its question's number and plain-words title.
    param($Value)
    $lines = New-Object System.Collections.ArrayList
    $items = @($Value.messages)
    if ($items.Count -eq 0) { [void]$lines.Add("Nothing unread: nothing has been said that was not already read."); return @($lines) }
    [void]$lines.Add("" + $items.Count + " message(s) not yet read, oldest first:")
    foreach ($item in $items) {
        [void]$lines.Add("")
        $heading = "Question " + $item.number + ": " + $item.title
        if ("$($item.state)" -cne "open") { $heading = $heading + " [" + $item.state + "]" }
        [void]$lines.Add($heading)
        foreach ($l in @(Format-HordeDecisionMessage -Message $item.message)) { [void]$lines.Add($l) }
    }
    return @($lines)
}

function Format-HordeDecisionProblems {
    # The lines that say which records could not be read, or did not apply. They follow every listing
    # and every result, so a damaged record is never out of sight.
    param($Value)
    $lines = New-Object System.Collections.ArrayList
    $bad = @($Value.unreadable)
    if ($bad.Count -gt 0) {
        [void]$lines.Add("")
        [void]$lines.Add("WARNING: " + $bad.Count + " record(s) in the store could not be read. Everything else is shown; nothing was skipped silently.")
        foreach ($b in $bad) { [void]$lines.Add("  record " + $b.sequence + " (" + $b.file + "): " + $b.reason) }
    }
    $off = @($Value.ignored)
    if ($off.Count -gt 0) {
        [void]$lines.Add("")
        [void]$lines.Add("NOTE: " + $off.Count + " record(s) were read and changed nothing:")
        foreach ($o in $off) { [void]$lines.Add("  record " + $o.sequence + " (" + $o.file + "): " + $o.reason) }
    }
    $later = @($Value.notUnderstood)
    if ($later.Count -gt 0) {
        $total = 0
        foreach ($k in $later) { $total += [int]$k.count }
        [void]$lines.Add("")
        [void]$lines.Add("NOTE: " + $total + " record(s) are of a kind this version of Horde does not understand. A later version wrote them; they are kept, and cost no question number:")
        foreach ($k in $later) {
            $where = "record " + $k.first
            if ([long]$k.last -ne [long]$k.first) { $where = "records " + $k.first + " to " + $k.last }
            [void]$lines.Add("  " + $k.kind + ": " + $k.count + " record(s), " + $where)
        }
    }
    $loose = @($Value.strays)
    if ($loose.Count -gt 0) {
        [void]$lines.Add("")
        [void]$lines.Add("NOTE: " + $loose.Count + " file(s) in the store folder are named like a record and are not part of the list:")
        foreach ($l in $loose) { [void]$lines.Add("  " + $l.file + ": " + $l.reason) }
    }
    return @($lines)
}

function Format-HordeDecisionList {
    # A list result as lines: a count, then the questions under their groups, in number order.
    param($Value, $Kinds, [string]$Showing)
    $lines = New-Object System.Collections.ArrayList
    $parts = @()
    foreach ($p in $Value.counts.PSObject.Properties) { $parts += ("" + $p.Value + " " + $p.Name) }
    [void]$lines.Add("Decisions: " + ($parts -join ", ") + ".")
    $questions = @($Value.questions)
    if ($questions.Count -eq 0) { [void]$lines.Add("No question to show (" + $Showing + ")."); return @($lines) }
    $width = ("" + ($questions | ForEach-Object { $_.number } | Measure-Object -Maximum).Maximum).Length
    # Groups in the order of the lowest-numbered question shown in each, so a list keeps its order as it grows.
    $groups = New-Object System.Collections.ArrayList
    foreach ($q in $questions) { if ($groups -cnotcontains $q.group) { [void]$groups.Add($q.group) } }
    foreach ($g in $groups) {
        [void]$lines.Add("")
        [void]$lines.Add($g)
        $mine = @($questions | Where-Object { $_.group -ceq $g })
        $note = @($mine | Where-Object { "$($_.groupNote)".Trim() -ne "" }) | Select-Object -First 1
        if ($null -ne $note) { [void]$lines.Add("  (" + (Get-HordeDecisionFirstLine -Text $note.groupNote) + ")") }
        foreach ($q in $mine) {
            $pad = " " * ($width + 4)
            [void]$lines.Add("  " + ("" + $q.number).PadLeft($width) + ". " + $q.title)
            $meta = (Get-HordeDecisionKindLabel -Kinds $Kinds -Kind $q.kind) + "; asked by " + $q.askedBy + "; "
            if (@($q.waiting).Count -gt 0) { $meta = $meta + "waiting: " + (@($q.waiting) -join ", ") } else { $meta = $meta + "nobody is waiting" }
            if ($q.needsSecret) { $meta = $meta + "; needs a secret" }
            [void]$lines.Add($pad + $meta)
            if ("$($q.recommendation)".Trim() -ne "") { [void]$lines.Add($pad + "recommended: " + (Get-HordeDecisionFirstLine -Text $q.recommendation)) }
            # A question nobody has spoken under says nothing here: it is the founder's turn, as for
            # every question just asked.
            if ($q.thread.count -gt 0) { [void]$lines.Add($pad + "conversation: " + (Format-HordeDecisionThreadSummary -Thread $q.thread)) }
            if ($q.state -cne "open") {
                $done = $q.state
                if ("$($q.closedAt)" -ne "") { $done = $done + " " + (Format-HordeDecisionTime -At $q.closedAt) }
                if ("$($q.outcome)".Trim() -ne "") { $done = $done + ": " + (Get-HordeDecisionFirstLine -Text $q.outcome) }
                [void]$lines.Add($pad + $done)
            }
        }
    }
    return @($lines)
}

function Add-HordeDecisionTextBlock {
    # A heading and a text under it, indented, every line kept.
    param($Lines, [string]$Heading, [string]$Text)
    [void]$Lines.Add($Heading)
    foreach ($l in @($Text -split "\r?\n")) { [void]$Lines.Add("  " + $l) }
}

function Format-HordeDecisionQuestion {
    # One question in full, as lines.
    param($Question, $Kinds)
    $q = $Question
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("Question " + $q.number + " - " + $q.state + " (wording " + $q.wordingVersion + ")")
    [void]$lines.Add($q.title)
    [void]$lines.Add("")
    $kindEntry = Get-HordeDecisionMember -Object $Kinds -Name $q.kind
    if ($null -ne $kindEntry) { [void]$lines.Add("Kind: " + $kindEntry.label + ". " + $kindEntry.means) } else { [void]$lines.Add("Kind: " + $q.kind) }
    foreach ($listName in @("options", "parts")) {
        $items = @($q.$listName)
        if ($items.Count -eq 0) { continue }
        [void]$lines.Add($listName.Substring(0, 1).ToUpperInvariant() + $listName.Substring(1) + ":")
        $i = 0
        foreach ($item in $items) { $i++; [void]$lines.Add("  " + $i + ". " + $item) }
    }
    if ("$($q.whatItIs)".Trim() -ne "") { Add-HordeDecisionTextBlock -Lines $lines -Heading "What it is:" -Text $q.whatItIs }
    if ("$($q.yesMeans)".Trim() -ne "") { Add-HordeDecisionTextBlock -Lines $lines -Heading "What yes means:" -Text $q.yesMeans }
    if ("$($q.recommendation)".Trim() -ne "") { Add-HordeDecisionTextBlock -Lines $lines -Heading "Recommendation:" -Text $q.recommendation }
    else { [void]$lines.Add("Recommendation: none given") }
    [void]$lines.Add("Group: " + $q.group)
    if ("$($q.groupNote)".Trim() -ne "") { Add-HordeDecisionTextBlock -Lines $lines -Heading "About this group:" -Text $q.groupNote }
    [void]$lines.Add("Asked by: " + $q.askedBy)
    if (@($q.waiting).Count -gt 0) { [void]$lines.Add("Waiting on this: " + (@($q.waiting) -join ", ")) } else { [void]$lines.Add("Waiting on this: nobody") }
    if (@($q.files).Count -gt 0) { [void]$lines.Add("Files:"); foreach ($f in @($q.files)) { [void]$lines.Add("  " + $f) } }
    if (@($q.references).Count -gt 0) { [void]$lines.Add("References: " + (@($q.references) -join ", ")) }
    if ($q.needsSecret) { [void]$lines.Add("Needs a secret: yes. Never write the secret into this list or into an answer; give it outside.") }
    if ("$($q.outcome)".Trim() -ne "") { Add-HordeDecisionTextBlock -Lines $lines -Heading ("Closed " + (Format-HordeDecisionTime -At $q.closedAt) + ", with this outcome:") -Text $q.outcome }
    if ("$($q.reopenReason)".Trim() -ne "") { [void]$lines.Add("Last reopened because: " + $q.reopenReason) }
    [void]$lines.Add("")
    [void]$lines.Add("History:")
    foreach ($h in @($q.history)) { [void]$lines.Add("  " + (Format-HordeDecisionTime -At $h.at) + "  " + $h.note + " (by " + $h.actor + ", record " + $h.sequence + ")") }
    [void]$lines.Add("")
    [void]$lines.Add("Conversation: " + (Format-HordeDecisionThreadSummary -Thread $q.thread))
    $said = @()
    if ($null -ne $q.thread.PSObject.Properties["messages"]) { $said = @($q.thread.messages) }
    foreach ($m in $said) {
        foreach ($l in @(Format-HordeDecisionMessage -Message $m -NowWording ([int]$q.wordingVersion))) { [void]$lines.Add($l) }
        foreach ($reader in @($m.unreadBy)) { $who = @($q.thread.unread | Where-Object { $_.reader -ceq $reader }) | Select-Object -First 1; if ($null -ne $who) { [void]$lines.Add("    (not yet read by " + $who.readerShown + ")") } }
    }
    return @($lines)
}

function Format-HordeDecisionAnswer {
    # Any operation's answer as lines a person can read without knowing how the list is kept.
    param([Parameter(Mandatory = $true)][string]$Verb, $Answer, $Kinds, [string]$Showing = "")
    $lines = New-Object System.Collections.ArrayList
    if ($Answer.state -ceq "unknown") { [void]$lines.Add("Could not tell: " + $Answer.reason); return @($lines) }
    if ($Answer.state -ceq "absent") { [void]$lines.Add("Nothing was done: " + $Answer.reason); return @($lines) }
    $value = $Answer.value
    if ($value.outcome -ceq "refused") {
        [void]$lines.Add("Refused: " + $value.reason)
        $i = 0
        foreach ($f in @($value.findings)) { $i++; [void]$lines.Add("  " + $i + ". " + $f) }
    }
    elseif ($Verb -ceq "list") { foreach ($l in @(Format-HordeDecisionList -Value $value -Kinds $Kinds -Showing $Showing)) { [void]$lines.Add($l) } }
    elseif ($Verb -ceq "show") { foreach ($l in @(Format-HordeDecisionQuestion -Question $value.question -Kinds $Kinds)) { [void]$lines.Add($l) } }
    elseif ($Verb -ceq "kinds") {
        [void]$lines.Add("The kinds of question:")
        foreach ($k in $value.kinds.PSObject.Properties) {
            $needs = ""
            if ("$($k.Value.list)" -ne "") { $needs = " It needs at least two " + $k.Value.list + "." }
            [void]$lines.Add("  " + $k.Name + ": " + $k.Value.label + ". " + $k.Value.means + $needs)
        }
    }
    elseif ($Verb -ceq "inbox") { foreach ($l in @(Format-HordeDecisionInbox -Value $value)) { [void]$lines.Add($l) } }
    elseif ($value.outcome -ceq "replayed") {
        [void]$lines.Add("Question " + $value.number + ": this request was already recorded (record " + $value.sequence + "), so nothing was written again.")
    }
    elseif ($Verb -ceq "answer" -or $Verb -ceq "reply") {
        $said = "Replied under question "
        if ($Verb -ceq "answer") { $said = "Kept " + $value.message.speakerShown + "'s words, " + $value.message.routeShown + ", under question " }
        [void]$lines.Add($said + $value.number + " (record " + $value.sequence + "): " + $value.question.title)
        if ($value.message.arrivedAfterClosing) { [void]$lines.Add("  NOTE: question " + $value.number + " is " + $value.question.state + ". The words are kept under it, and it stays " + $value.question.state + ": saying something reopens nothing.") }
        if ($value.message.saidToEarlierWording) { [void]$lines.Add("  NOTE: they were said to wording " + $value.message.wordingVersion + ", and the question is now at wording " + $value.question.wordingVersion + ". They are kept, and marked as said to an earlier wording.") }
    }
    else {
        $done = @{ add = "Added question "; update = "Changed question "; close = "Closed question "; reopen = "Reopened question " }
        [void]$lines.Add($done[$Verb] + $value.number + ": " + $value.question.title)
        if ($Verb -ceq "update") { $last = @($value.question.history) | Select-Object -Last 1; [void]$lines.Add("  " + $last.note) }
    }
    foreach ($l in @(Format-HordeDecisionProblems -Value $value)) { [void]$lines.Add($l) }
    return @($lines)
}

function Write-HordeDecisionLines {
    # Print a command's lines. To a terminal: as they are. To a pipe or a file: as UTF-8 with no
    # byte-order mark (see the header), the console's own encoding put back whatever happens.
    # The lines are still written to the pipeline, one by one, so a caller in the same process gets
    # them as it always did; each is on its way out before the encoding is put back.
    param($Lines)
    $piped = $false
    try { $piped = [Console]::IsOutputRedirected } catch { }
    if (-not $piped) { foreach ($line in @($Lines)) { Write-Output $line }; return }
    $was = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        foreach ($line in @($Lines)) { Write-Output $line }
    } finally { [Console]::OutputEncoding = $was }
}

function Complete-HordeDecisionCommand {
    # What a command does once its lines are out: -After is what Invoke-HordeDecisionCommand handed
    # back for it, or $null for nothing. Returns { lines; failure } like the command itself.
    # Today that is the second half of `inbox`: marking as read exactly the messages that were
    # printed, by naming the last of them (upTo). PRINTED FIRST, MARKED AFTER, so that a command
    # stopped between the two leaves messages unread that were seen - which shows them again - and
    # never messages marked read that nobody saw.
    param($After)
    if ($null -eq $After) { return [pscustomobject]@{ lines = @(); failure = "" } }
    $answer = Invoke-HordeDecision -Operation "$($After.operation)" -Request $After.request
    if ($answer.state -cne "known") { return [pscustomobject]@{ lines = @(); failure = ("the messages above were NOT marked as read, and will be shown again: " + $answer.reason) } }
    if ($answer.value.outcome -ceq "refused") { return [pscustomobject]@{ lines = @(); failure = ("the messages above were NOT marked as read, and will be shown again: " + $answer.value.reason) } }
    $lines = @()
    if (-not [bool]$After.quiet) { $lines = @("", ("Marked as read: " + $answer.value.marked + " message(s), up to record " + $answer.value.upTo + ".")) }
    # Another reader marked them between this command's printing and its marking: said as it is,
    # not as "0 message(s), up to record 0".
    if (-not [bool]$After.quiet -and [int]$answer.value.marked -eq 0) { $lines = @("", "Nothing was left to mark: the messages above were marked as read by another reader in the meantime.") }
    return [pscustomobject]@{ lines = $lines; failure = "" }
}

function Invoke-HordeDecisionCommand {
    # Run one `horde decisions <verb>`. -Given is the command's bound parameters, by name. Returns
    # { lines; failure; after }: the lines to print; when the command must fail, the message to fail
    # with; and what is to be done once the lines are out (Complete-HordeDecisionCommand), or $null.
    # It throws only for a command line it cannot act on: an unknown verb, a flag that belongs to
    # another verb, a missing number, a file it cannot read.
    param([Parameter(Mandatory = $true)][string]$Verb, [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Given)
    $spec = $script:HordeDecisionCommandVerbs[$Verb]
    # Copied into a plain table: the bound parameters of a script block and a table built by a test are
    # different dictionary types, and only a plain table answers ContainsKey for both.
    $have = @{}
    foreach ($k in @($Given.Keys)) { $have["$k"] = $Given[$k] }
    if ($null -eq $spec) { throw ("decisions takes " + (@($script:HordeDecisionCommandVerbs.Keys) -join ", ") + ", not '" + $Verb + "'") }
    # What a command line that cannot be acted on is answered with, after the reason: this verb's usage.
    $usageNote = ". Usage: horde decisions " + $spec.usage
    $operation = $Verb
    if ($spec.ContainsKey("operation")) { $operation = "$($spec.operation)" }
    $writes = [bool](@(Get-HordeDecisionOperations | Where-Object { $_.name -ceq $operation }) | Select-Object -First 1).writes
    # `inbox` reads first and writes afterwards, as two requests of its own (see below): the request
    # built here is the reading one, which takes no id.
    if ($Verb -ceq "inbox") { $writes = $false }
    foreach ($flag in @($have.Keys)) {
        if ($flag -eq "Verb" -or $flag -eq "Number") { continue }
        if ($spec.flags -notcontains $flag) { throw ("-" + $flag + " does not belong to decisions " + $Verb + $usageNote) }
    }
    $request = [ordered]@{}
    $numberText = ""
    if ($have.ContainsKey("Number")) { $numberText = "$($have['Number'])" }
    if ($spec.number) {
        if ($numberText -cnotmatch '\A[1-9][0-9]{0,8}\z') { throw ("decisions " + $Verb + " needs the question's number, as in: horde decisions " + $Verb + " 7" + $(if ($numberText -ne "") { " (got '" + $numberText + "')" } else { "" })) }
    }
    elseif ($numberText -ne "") { throw ("decisions " + $Verb + " takes no question number, and got '" + $numberText + "'" + $usageNote) }
    $id = [guid]::NewGuid().ToString("N")
    if ($have.ContainsKey("Id")) {
        $id = "$($have['Id'])"
        if ($id -cnotmatch '\A[0-9a-f]{32}\z') { throw "-Id is 32 lowercase hex digits (a GUID with no hyphens), chosen once and reused when the same command is sent again" }
    }
    if ($writes) {
        $request["id"] = $id
        $request["actor"] = $script:HordeDecisionCommandActor
    }
    if ($spec.number) { $request["number"] = [int]$numberText }
    $showing = "open"
    switch ($Verb) {
        "add" {
            if (-not $have.ContainsKey("File")) { throw ("decisions add needs -File <question.json>: the question as a JSON file. Long text is never taken from the command line" + $usageNote) }
            $request["question"] = Read-HordeDecisionJsonFile -Path "$($have['File'])" -What "the question file"
        }
        "update" {
            if (-not $have.ContainsKey("File")) { throw ("decisions update needs -File <changes.json>: a JSON file holding only the fields to change" + $usageNote) }
            $request["changes"] = Read-HordeDecisionJsonFile -Path "$($have['File'])" -What "the changes file"
        }
        "close" {
            if ($have.ContainsKey("Outcome") -eq $have.ContainsKey("OutcomeFile")) { throw ("decisions close needs the outcome exactly once: -Outcome <one line>, or -OutcomeFile <path> for more than a line" + $usageNote) }
            if ($have.ContainsKey("OutcomeFile")) { $request["outcome"] = Read-HordeDecisionTextFile -Path "$($have['OutcomeFile'])" -What "the outcome file" }
            else { $request["outcome"] = "$($have['Outcome'])" }
        }
        "reopen" {
            if (-not $have.ContainsKey("Reason")) { throw ("decisions reopen needs -Reason <one line>: why the question is open again" + $usageNote) }
            $request["reason"] = "$($have['Reason'])"
        }
        "list" { if ($have.ContainsKey("State")) { $showing = "$($have['State'])"; $request["state"] = $showing } }
        "inbox" { $request["actor"] = $script:HordeDecisionCommandActor }
    }
    if ($spec.ContainsKey("says")) {
        # THE WORDS: one line as an argument, or anything longer from a file, exactly as the file holds
        # them. Never both, never neither.
        if ($have.ContainsKey("Text") -eq $have.ContainsKey("File")) { throw ("decisions " + $Verb + " needs the words exactly once: -Text <one line>, or -File <path> for more than a line" + $usageNote) }
        $words = ""
        if ($have.ContainsKey("File")) { $words = Read-HordeDecisionTextFile -Path "$($have['File'])" -What "the file of words" }
        else {
            $words = "$($have['Text'])"
            # Nothing of the text is repeated: what was typed may be what must not be printed.
            if ($words -match "[\r\n]") { throw ("-Text is one line, and it has a line break: words of more than a line come from -File <path>, so that none is lost on the way in" + $usageNote) }
        }
        $request["speaker"] = "$($spec.says.speaker)"
        $request["route"] = "$($spec.says.route)"
        $request["text"] = $words
        if ($have.ContainsKey("Wording")) {
            $wording = "$($have['Wording'])"
            if ($wording -cnotmatch '\A[1-9][0-9]{0,8}\z') { throw ("-Wording is the number of the wording the speaker was looking at, as in: -Wording 2" + $usageNote) }
            $request["wordingVersion"] = [int]$wording
        }
    }
    $answer = Invoke-HordeDecision -Operation $operation -Request $request
    # `inbox` WITHOUT -Peek MARKS WHAT IT PRINTED, AFTER IT IS PRINTED. The second request names the
    # last message this answer holds (upTo), so a message that arrives between the two is beyond it
    # and stays unread. Nothing to mark - no message, or the reading failed - asks for nothing.
    $after = $null
    $peek = ($have.ContainsKey("Peek") -and [bool]$have["Peek"])
    $asJson = ($have.ContainsKey("Json") -and [bool]$have["Json"])
    if ($Verb -ceq "inbox" -and -not $peek -and $answer.state -ceq "known" -and $answer.value.outcome -ceq "done" -and @($answer.value.messages).Count -gt 0) {
        $after = [pscustomobject]@{ operation = "inbox"; quiet = $asJson
            request = [ordered]@{ actor = $script:HordeDecisionCommandActor; id = $id; mark = $true; upTo = [long]$answer.value.upTo } }
    }
    $lines = @()
    if ($have.ContainsKey("Json") -and [bool]$have["Json"]) { $lines = @(ConvertTo-HordeDecisionJsonLine -Answer $answer) }
    else {
        # The kinds table comes from the operations, like everything else this caller knows of the
        # list; if it cannot be had, a kind is shown by its name.
        $kinds = $null
        $table = Invoke-HordeDecision -Operation "kinds" -Request @{}
        if ($table.state -ceq "known" -and $table.value.outcome -ceq "done") { $kinds = $table.value.kinds }
        $lines = @(Format-HordeDecisionAnswer -Verb $Verb -Answer $answer -Kinds $kinds -Showing $showing)
        if ($Verb -ceq "inbox" -and $peek -and $answer.state -ceq "known" -and $answer.value.outcome -ceq "done" -and @($answer.value.messages).Count -gt 0) { $lines += @("", "Nothing was marked as read (-Peek).") }
    }
    $failure = ""
    if ($answer.state -cne "known") { $failure = "$($answer.reason)" }
    elseif ($answer.value.outcome -ceq "refused") { $failure = "$($answer.value.reason)" }
    return [pscustomobject]@{ lines = $lines; failure = $failure; after = $after }
}
