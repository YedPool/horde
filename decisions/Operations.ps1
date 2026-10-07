# decisions/Operations.ps1 - the one list of things that can be done to the decisions list.
#
# THIS IS THE ONLY THING A CALLER USES. The command line calls it today (cli/commands/decisions.ps1); a
# window and a link between machines are meant to call it later, unchanged. So:
#   - PLAIN DATA IN, PLAIN DATA OUT. A request is an object that could be written as JSON, checked
#     against its definition in schema/decision-request.v1 before anything is read or written. What
#     comes back is a core/Tristate.ps1 answer whose value is checked against
#     schema/decision-result.v1 before it is returned.
#   - NOTHING HERE ASSUMES A CONSOLE, a file a person wrote, or a person at all. It prints nothing,
#     prompts for nothing, and reads no file but the store's own records.
#   - ONE ENTRY POINT, Invoke-HordeDecision, AND ONE TABLE of operations. A new operation is an entry
#     in $HordeDecisionOperations, its function below, and its definition in the request schema.
#
# WHAT THE ANSWER'S THREE STATES MEAN HERE (schema/decision-result.v1 says it in full):
#   known    the value says what happened: outcome done, replayed (the same id and request were
#            recorded before; nothing was written) or refused (nothing was written; findings says why).
#   absent   the store was read and there is no question of that number.
#   unknown  the store, or the one record asked about, could not be read or written; the reason says.
#            Also: a record was given its place but could not be confirmed on disk. That is never
#            "done" - a caller is told its words are saved only when everything that makes them
#            durable returned success (decisions/Store.ps1) - and the reason says the record is there.
# A refusal is KNOWN on purpose: "I will not" is a fact with reasons, and a caller must never retry it
# as if the store had been unreachable.
#
# HOW A WRITE STAYS CORRECT WITH SEVERAL WRITERS. A write reads every record, works out the list,
# checks the request against that list, and then tries to create the record numbered one past the last
# it read. decisions/Store.ps1 lets exactly one writer create a given number. A writer that loses reads
# the list again - now holding the winner's record - and checks its request AGAIN before trying the
# next number. So every record was checked against the list exactly as it stood before it, and two
# requests that cannot both hold (two closes of one question) cannot both be written. No lock is
# held and none can be left behind by a process that dies.
#
# IDEMPOTENCY. Every write carries an id its caller chose. The id is looked up in the list before the
# request is judged: the same id with the same request is answered from the record already there and
# writes nothing, however often it is sent and whatever has happened to the question since; the same
# id with a different request is refused. A writer that loses the race to another process sending the
# same id finds that record on its next read and replays it, so two deliveries of one request make
# one record. What is compared is a hash of the request as the rules normalised it, not its spelling.
#
# SECRETS ARE LOOKED FOR FIRST, over every text of the request, before the schema check, so that no
# later finding - "the actor is 'x', not one of ..." - can repeat one.
#
# No Set-StrictMode here (see core/Tristate.ps1): this file is dot-sourced. It runs under -Version Latest.

. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Tristate.ps1")
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Home.ps1")
. (Join-Path $PSScriptRoot "Settings.ps1")
. (Join-Path $PSScriptRoot "Store.ps1")
. (Join-Path $PSScriptRoot "Rules.ps1")
. (Join-Path $PSScriptRoot "Definitions.ps1")

# THE OPERATIONS. Each is named for its definition in schema/decision-request.v1. A write names the
# kind of record it makes and the function that turns a checked request into that record's content; a
# read names the function that answers from the list.
$script:HordeDecisionOperations = [ordered]@{
    add    = @{ writes = $true;  kind = "question-added";    content = "Get-HordeDecisionAddContent" }
    update = @{ writes = $true;  kind = "question-updated";  content = "Get-HordeDecisionUpdateContent" }
    close  = @{ writes = $true;  kind = "question-closed";   content = "Get-HordeDecisionCloseContent" }
    reopen = @{ writes = $true;  kind = "question-reopened"; content = "Get-HordeDecisionReopenContent" }
    list   = @{ writes = $false; read = "Get-HordeDecisionListAnswer" }
    show   = @{ writes = $false; read = "Get-HordeDecisionShowAnswer" }
    # Answered from the definitions alone: no store is read, so it answers where a list could not.
    kinds  = @{ writes = $false; read = "Get-HordeDecisionKindsAnswer"; noStore = $true }
}
# HOW LONG A WRITE KEEPS TRYING is two settings (decisions/Settings.ps1 and its table), written nowhere
# here:
#   decisions.write.raceTries  how many times a write tries for a sequence number before it says it
#     cannot. Each failed try means another writer's record was written, so the default of 200 is 200
#     other writes landing first; a write that still has not won is reported, never spun for ever.
#   decisions.write.heldReads  how many reads in a row may find a record held open by another process
#     before a write gives up. The store has already waited its own 2 s for that record on each read
#     (decisions/Store.ps1), so the default of 5 is about ten seconds - far longer than any writer
#     holds a record, and short enough to wait for at a command line. It has a limit of its own
#     because the tries above were sized for losing a race, which costs milliseconds: measured
#     2026-10-06, counted against them, a write with record 1 held open was still waiting after 40 s
#     and could have waited 400.

function Get-HordeDecisionOperations {
    # The operations, as { name; writes }, for a caller that offers them (a bridge, a help text).
    return @($script:HordeDecisionOperations.Keys | ForEach-Object { [pscustomobject]@{ name = $_; writes = [bool]$script:HordeDecisionOperations[$_].writes } })
}

function Get-HordeDecisionStoreRoot {
    # Where the store is: <HordeHome>\store\decisions. Worked out, never created here: a read must not
    # make folders (core/Home.ps1).
    return (Join-Path (Join-Path (Get-HordeHome) "store") "decisions")
}

function New-HordeDecisionResult {
    # The value of a known answer, schema/decision-result.v1. -State is the list the answer was worked
    # out from, or $null when the request was refused before the store was read; its unreadable and
    # ignored records, and the store's stray files, go into every result, so no caller can show a list
    # without them.
    param([string]$Operation, [string]$Outcome, [string]$Reason = "", $Findings = @(), $State = $null, $More = $null)
    $value = [ordered]@{ schemaVersion = 1; operation = $Operation; outcome = $Outcome; reason = $Reason; findings = [string[]]@($Findings) }
    if ($null -ne $More) { foreach ($k in @($More.Keys)) { $value[$k] = $More[$k] } }
    $unreadable = @(); $ignored = @(); $strays = @(); $later = @()
    if ($null -ne $State) {
        # Records of a kind this version does not know, once for each kind (decisions/Rules.ps1, THE
        # COMPATIBILITY CONTRACT): reported, never hidden, and never called unreadable.
        $later = @($State.notUnderstood.Values | ForEach-Object { [pscustomobject]@{ kind = "$($_.kind)"; count = [int]$_.count; first = [long]$_.first; last = [long]$_.last
            reason = ("its kind '" + $_.kind + "' is not one this version of Horde knows. A later version wrote it: it is kept, it changes nothing this version shows, and it costs no question number") } })
        $strays = @($State.strays | ForEach-Object { [pscustomobject]@{ file = "$($_.file)"; reason = "$($_.reason)" } })
        $unreadable = @($State.unreadable | ForEach-Object { [pscustomobject]@{ sequence = $_.sequence; file = $_.file; reason = $_.reason } })
        $ignored = @($State.ignored | ForEach-Object { [pscustomobject]@{ sequence = $_.sequence; file = $_.file; reason = $_.reason } })
    }
    $value["unreadable"] = $unreadable
    $value["ignored"] = $ignored
    $value["strays"] = $strays
    $value["notUnderstood"] = $later
    return [pscustomobject]$value
}

function Complete-HordeDecisionAnswer {
    # The last step of every operation: the value is checked against schema/decision-result.v1, and
    # only then wrapped as known. A value that does not match is a defect in this module, and is
    # answered as unknown with the findings - never handed on as if it were a result. -Written says
    # what, if anything, is already on disk, so that the unknown does not hide a record that exists.
    param($Value, $Definitions, [datetime]$Now, [string]$Written = "")
    $off = @(Test-HordeSchema -Value $Value -Schema $Definitions.resultSchema)
    if ($off.Count -gt 0) {
        $why = "the result of '" + $Value.operation + "' does not match decision-result.v1 (" + (@($off | Select-Object -First 3) -join "; ") + "), so it is not handed on"
        if ($Written -ne "") { $why = $why + ". " + $Written }
        return (New-HordeUnknown -Reason $why)
    }
    return (New-HordeKnown -Value $Value -ObservedAt $Now)
}

function Get-HordeDecisionAddContent {
    # A checked add request as { body; findings }: body is what the record's data holds besides the
    # number, which only the list can give.
    param($Request, $Definitions)
    $bad = @(Test-HordeSchema -Value $Request.question -Schema $Definitions.questionSchema -Path "question")
    if ($bad.Count -gt 0) { return [pscustomobject]@{ body = $null; findings = $bad } }
    $fields = ConvertTo-HordeDecisionFields -Source $Request.question
    return [pscustomobject]@{ body = [ordered]@{ question = $fields }; findings = @(Test-HordeDecisionQuestion -Question $fields -Kinds $Definitions.kinds) }
}

function Get-HordeDecisionUpdateContent {
    param($Request, $Definitions)
    $wrong = @(Test-HordeSchema -Value $Request.changes -Schema $Definitions.questionSchema -Path "changes")
    if ($wrong.Count -gt 0) { return [pscustomobject]@{ body = $null; findings = $wrong } }
    $fields = ConvertTo-HordeDecisionFields -Source $Request.changes -Partial
    $found = @()
    if ($fields.Count -eq 0) { $found = @("the change names no field, so there is nothing to change; the fields are: " + ((Get-HordeDecisionFieldNames) -join ", ")) }
    # The changed question as a whole is judged after the change is applied to the list, in
    # Invoke-HordeDecisionWrite: a change of kind to "choice" is right or wrong only together with the
    # options the question already has.
    return [pscustomobject]@{ body = [ordered]@{ changes = $fields }; findings = $found }
}

function Get-HordeDecisionCloseContent {
    param($Request, $Definitions)
    return [pscustomobject]@{ body = [ordered]@{ outcome = [string]$Request.outcome }; findings = @(Test-HordeDecisionNote -Text ([string]$Request.outcome) -Name "outcome") }
}

function Get-HordeDecisionReopenContent {
    param($Request, $Definitions)
    return [pscustomobject]@{ body = [ordered]@{ reason = [string]$Request.reason }; findings = @(Test-HordeDecisionNote -Text ([string]$Request.reason) -Name "reason" -OneLine) }
}

function Get-HordeDecisionNumberAnswer {
    # For an operation about one question: $null when the list has it, else the answer to give -
    # absent when the number was never given, unknown when its record cannot be read.
    param($State, [long]$Number, [string]$Operation)
    $status = "absent"
    if ($Number -le [int]::MaxValue) { $status = Get-HordeDecisionNumberStatus -State $State -Number ([int]$Number) }
    if ($status -eq "present") { return $null }
    if ($status -eq "unreadable") {
        $which = @($State.unreadable | ForEach-Object { "record " + $_.sequence + " (" + $_.file + "): " + $_.reason }) -join "; "
        return (New-HordeUnknown -Reason ("question " + $Number + " cannot be read, so '" + $Operation + "' did nothing: its number was given, or may have been, to a record that cannot be read. " + $which))
    }
    return (New-HordeAbsent -Note ("there is no question " + $Number + "; the highest number given is " + $State.lastNumber))
}

function Get-HordeDecisionListAnswer {
    param($Request, $State, $Definitions, [datetime]$Now)
    $want = "open"
    # The listed words in any case: a person types this one, and "ALL" means all. Nothing else is
    # taken; what is refused is named back only when it is letters and hyphens, so that a refusal
    # never repeats text of another kind.
    if (Test-HordeDecisionMember -Object $Request -Name "state") { $want = ([string]$Request.state).ToLowerInvariant() }
    $states = @(Get-HordeDecisionStates)
    if ($want -cne "all" -and $states -cnotcontains $want) {
        $named = "that"
        if ($want -cmatch '\A[a-z][a-z-]{0,31}\z') { $named = "'" + $want + "'" }
        $why = $named + " is not a state a question can be in; give one of: " + ($states -join ", ") + ", or all"
        return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation "list" -Outcome "refused" -Reason $why -Findings @($why) -State $State) -Definitions $Definitions -Now $Now)
    }
    $counts = [ordered]@{}
    foreach ($s in $states) { $counts[$s] = 0 }
    $views = New-Object System.Collections.ArrayList
    foreach ($question in $State.questions.Values) {
        if ($counts.Contains("$($question.state)")) { $counts["$($question.state)"] = [int]$counts["$($question.state)"] + 1 }
        if ($want -ceq "all" -or "$($question.state)" -ceq $want) { [void]$views.Add((ConvertTo-HordeDecisionView -Question $question)) }
    }
    $value = New-HordeDecisionResult -Operation "list" -Outcome "done" -State $State -More ([ordered]@{ questions = @($views); counts = [pscustomobject]$counts })
    return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now)
}

function Get-HordeDecisionShowAnswer {
    param($Request, $State, $Definitions, [datetime]$Now)
    $number = [long]$Request.number
    $missing = Get-HordeDecisionNumberAnswer -State $State -Number $number -Operation "show"
    if ($null -ne $missing) { return $missing }
    $view = ConvertTo-HordeDecisionView -Question $State.questions[[int]$number]
    $value = New-HordeDecisionResult -Operation "show" -Outcome "done" -State $State -More ([ordered]@{ number = [int]$number; question = $view })
    return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now)
}

function Get-HordeDecisionKindsAnswer {
    # The table of question kinds (decisions/question-kinds.json, read by decisions/Definitions.ps1), as
    # an answer. It is an operation so that every caller gets the one table from the one API: a caller
    # across a link cannot open this checkout's file, and one that could would be a second reader of it.
    param($Request, $State, $Definitions, [datetime]$Now)
    $value = New-HordeDecisionResult -Operation "kinds" -Outcome "done" -More ([ordered]@{ kinds = $Definitions.kinds })
    return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now)
}

function Read-HordeDecisionState {
    # The store's records and the list worked out from them, as { state; reason; busy; list }. state
    # is the store's own (ok, absent or unknown); busy is the first record another process still holds
    # open, or $null.
    #
    # KNOWN COST, LEFT AS IT IS ON PURPOSE. Every operation reads and checks every record again.
    # Measured 2026-10-06 on a throttled machine, 81 records: reading and parsing the files 130 ms,
    # checking each against its schemas 1128 ms, checking the list result of 81 questions 1292 ms;
    # 3.4 s for one list, about 40 ms a record, nearly all of it schema checking and almost none of
    # it the disk. Nothing is cached on disk, because a cache is a second copy of the truth, and the
    # store is the only one. A caller that stays alive (a window) can keep the list it has in memory
    # and fold in only the records it has not seen: the records never change, and their order is
    # their names.
    param([string]$Root, $Definitions)
    $loaded = Get-HordeDecisionRecords -Root $Root
    if ($loaded.state -ceq "unknown") { return [pscustomobject]@{ state = "unknown"; reason = $loaded.reason; busy = $null; list = $null } }
    $busy = @($loaded.records | Where-Object { $_.kind -ceq "busy" }) | Select-Object -First 1
    $list = ConvertTo-HordeDecisionState -Records $loaded.records -Definitions $Definitions
    foreach ($stray in @($loaded.strays)) { [void]$list.strays.Add($stray) }
    return [pscustomobject]@{ state = $loaded.state; reason = $loaded.reason; busy = $busy; list = $list }
}

function Invoke-HordeDecisionWrite {
    # One write: see "HOW A WRITE STAYS CORRECT" in the header. -Request has passed its schema and the
    # secret check.
    param([string]$Operation, $Request, [string]$Root, $Definitions, [datetime]$Now)
    $entry = $script:HordeDecisionOperations[$Operation]
    $refuse = { param($why, $found, $list) return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation $Operation -Outcome "refused" -Reason $why -Findings $found -State $list) -Definitions $Definitions -Now $Now) }

    $actor = [string]$Request.actor
    $actors = @(Get-HordeDecisionActors)
    if ($actors -cnotcontains $actor) {
        $why = "'" + $actor + "' is not a role that may change the list; the roles that may are: " + ($actors -join ", ")
        return (& $refuse $why @($why) $null)
    }
    $content = & $entry.content $Request $Definitions
    $hasNumber = Test-HordeDecisionMember -Object $Request -Name "number"
    $number = [long]0
    if ($hasNumber) { $number = [long]$Request.number }
    $requestHash = ""
    if ($null -ne $content.body) {
        $hashed = [ordered]@{ operation = $Operation; actor = $actor; number = $number; body = $content.body }
        $requestHash = Get-HordeDecisionHash -Value $hashed
    }
    $id = [string]$Request.id

    $raceTries = Get-HordeDecisionSetting -Name "decisions.write.raceTries"
    $heldReads = Get-HordeDecisionSetting -Name "decisions.write.heldReads"
    $busyReads = 0
    for ($attempt = 1; $attempt -le $raceTries; $attempt++) {
        $read = Read-HordeDecisionState -Root $Root -Definitions $Definitions
        if ($read.state -ceq "unknown") { return (New-HordeUnknown -Reason ("nothing was written: " + $read.reason)) }
        if ($null -ne $read.busy) {
            # A record is still open in another process after the store's own wait. Its content decides
            # whether this request may be written, so this request waits for it rather than guess -
            # for about ten seconds, and then says which record, and that nothing was written.
            $busyReads++
            if ($busyReads -ge $heldReads) {
                return (New-HordeUnknown -Reason ("nothing was written: another process holds record " + $read.busy.sequence + " open, and still did after " + $busyReads + " reads that each waited for it. Try again when it has let go"))
            }
            continue
        }
        $list = $read.list

        # A REPOST IS ANSWERED BEFORE THE REQUEST IS JUDGED: what was recorded stands.
        if ($list.ids.ContainsKey($id)) {
            $prior = $list.ids[$id]
            if ($requestHash -ne "" -and $prior.requestHash -ceq $requestHash) {
                # "REPLAYED" SAYS "THIS WAS RECORDED", so the record is flushed to disk before it is said.
                # A save that answered "unconfirmed" left its record in place, and nothing records which
                # saves those were; so every repost confirms, by the same flush the move makes. If that
                # flush fails the answer is unknown again - never "replayed" on the strength of it.
                $sure = "unconfirmed"
                try { $sure = Confirm-HordeDecisionRecord -Root $Root -Sequence ([long]$prior.sequence) } catch { $sure = "unconfirmed" }
                if ($sure -cne "confirmed") {
                    return (New-HordeUnknown -Reason ("record " + $prior.sequence + " holds this request, but it could not be confirmed written through to the disk (" + $sure + "), so it is NOT reported as saved. Send the same request again, with the same id"))
                }
                $more = [ordered]@{ sequence = $prior.sequence; number = [int]$prior.number }
                if ($list.questions.ContainsKey([int]$prior.number)) { $more["question"] = ConvertTo-HordeDecisionView -Question $list.questions[[int]$prior.number] }
                return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation $Operation -Outcome "replayed" -State $list -More $more) -Definitions $Definitions -Now $Now)
            }
            $why = "the id " + $id + " was already used for a different request (record " + $prior.sequence + ", " + $prior.kind + "); nothing was written. A new request needs a new id"
            return (& $refuse $why @($why) $list)
        }
        if (@($content.findings).Count -gt 0) {
            return (& $refuse ("the request breaks " + @($content.findings).Count + " rule(s); nothing was written") @($content.findings) $list)
        }
        if ($hasNumber) {
            $not = Get-HordeDecisionNumberAnswer -State $list -Number $number -Operation $Operation
            if ($null -ne $not) { return $not }
        }

        # THE RECORD, built as text and read back, so that what is checked and applied below is exactly
        # what a later reader will parse - not the objects it was built from.
        $data = [ordered]@{}
        if ($hasNumber) { $data["number"] = [int]$number } else { $data["number"] = Get-HordeDecisionNextNumber -State $list }
        foreach ($k in @($content.body.Keys)) { $data[$k] = $content.body[$k] }
        $sequence = [long]$list.lastSequence + 1
        $envelope = [ordered]@{
            schemaVersion = 1; sequence = $sequence; id = $id; kind = $entry.kind
            at = $Now.ToUniversalTime().ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
            actor = $actor; requestHash = $requestHash; data = $data
        }
        $text = ConvertTo-Json -InputObject $envelope -Compress -Depth 12
        $record = [pscustomobject]@{ sequence = $sequence; file = (Get-HordeDecisionRecordName -Sequence $sequence); kind = "ok"; data = ($text | ConvertFrom-Json); reason = "" }
        # The list's problems as they stood, kept for a refusal: applying the record below adds the
        # unwritten record itself to them when it does not apply.
        $before = [pscustomobject]@{ unreadable = @($list.unreadable); ignored = @($list.ignored); strays = @($list.strays); notUnderstood = $list.notUnderstood }
        $why = Add-HordeDecisionRecordToState -State $list -Record $record -Definitions $Definitions
        if ($why -ne "") { return (& $refuse ("nothing was written: " + $why) @($why) $before) }
        $question = $list.questions[[int]$data["number"]]
        if ($Operation -ceq "update") {
            $found = @(Test-HordeDecisionQuestion -Question $question -Kinds $Definitions.kinds)
            if ($found.Count -gt 0) { return (& $refuse ("the question as changed would break " + $found.Count + " rule(s); nothing was written") $found $before) }
        }

        $made = ""
        try { $made = Add-HordeDecisionRecord -Root $Root -Sequence $sequence -Text $text }
        catch { return (New-HordeUnknown -Reason ("record " + $sequence + " could not be written, so nothing changed") -ErrorRecord $_) }
        # THE RECORD HAS ITS PLACE, AND NOTHING SAYS IT IS ON DISK (decisions/Store.ps1, "unconfirmed").
        # Not "done": the caller would be told its words are saved on the strength of a flush that
        # failed. Not "nothing was written": the record is there, and every reader sees it. And not
        # another turn of this loop, which would find the record by its id and answer "replayed" -
        # the same claim in other words.
        if ($made -ceq "unconfirmed") {
            return (New-HordeUnknown -Reason ("record " + $sequence + " has its place in the store, but it could not be confirmed written through to the disk, so it is NOT reported as saved. Send the same request again, with the same id: it is answered from the record if the record is still there"))
        }
        if ($made -cne "created") { continue }
        $more = [ordered]@{ sequence = $sequence; attempts = $attempt; number = [int]$data["number"]; question = (ConvertTo-HordeDecisionView -Question $question) }
        $value = New-HordeDecisionResult -Operation $Operation -Outcome "done" -State $list -More $more
        return (Complete-HordeDecisionAnswer -Value $value -Definitions $Definitions -Now $Now -Written ("Record " + $sequence + " WAS written"))
    }
    return (New-HordeUnknown -Reason ("nothing was written: " + $raceTries + " tries each found another writer had taken the next sequence number first"))
}

function Invoke-HordeDecision {
    # Do one operation. -Operation is a name from Get-HordeDecisionOperations; -Request is plain data
    # matching that operation's definition in schema/decision-request.v1 (a hashtable, or an object
    # read from JSON). Returns a core/Tristate.ps1 answer; see the header for what its states mean.
    #
    # -Root is the store folder, for a caller that names the one it made (a test); without it the
    # store is Horde's own, under HORDE_HOME. -Now is the writer's clock, for the same caller.
    param([Parameter(Mandatory = $true)][string]$Operation, $Request = $null, [string]$Root = "", [datetime]$Now = [datetime]::UtcNow)
    $definitions = Get-HordeDecisionDefinitions
    $refuse = { param($name, $why, $found) return (Complete-HordeDecisionAnswer -Value (New-HordeDecisionResult -Operation $name -Outcome "refused" -Reason $why -Findings $found) -Definitions $definitions -Now $Now) }

    $entry = $null
    if ($Operation -cmatch '\A[a-z][a-z-]{0,31}\z') { $entry = $script:HordeDecisionOperations[$Operation] }
    if ($null -eq $entry) {
        $why = "that is not an operation on the decisions list; the operations are: " + (@($script:HordeDecisionOperations.Keys) -join ", ")
        return (& $refuse "unknown" $why @($why))
    }
    # PLAIN DATA, PROVEN: the request is written as JSON and read back, which is exactly what crossing
    # a link would do to it. Whatever the caller built it from - a hashtable, typed objects - the
    # checks below see only what would arrive.
    # Named $plain, not $request: variable names ignore case, so that would be the parameter itself.
    $plain = $null
    try {
        if ($null -ne $Request) { $plain = (ConvertTo-Json -InputObject $Request -Compress -Depth 12) | ConvertFrom-Json }
    } catch {
        $why = "the request is not plain data that can be written as JSON: " + $_.Exception.Message
        return (& $refuse $Operation $why @($why))
    }
    if ($null -eq $plain) { $plain = [pscustomobject]@{} }
    $secrets = @(Find-HordeDecisionSecrets -Value $plain)
    if ($secrets.Count -gt 0) { return (& $refuse $Operation ("the request holds what looks like a secret in " + $secrets.Count + " place(s); nothing was written") $secrets) }
    $shapeSchema = Get-HordeDecisionMember -Object $definitions.requestSchema.definitions -Name $Operation
    $shape = @(Test-HordeSchema -Value $plain -Schema $shapeSchema -Path "request" -Root $definitions.requestSchema)
    if ($shape.Count -gt 0) { return (& $refuse $Operation ("the request is not what '" + $Operation + "' takes; nothing was done") $shape) }
    # A NUMBER NO QUESTION CAN HAVE IS ANSWERED HERE, BEFORE ANYTHING CASTS IT. 1e30 passes the schema's
    # "type": "integer", and the cast to a 64-bit number below it threw instead of answering (measured
    # 2026-10-06: show and close). No store need be read to know there is no such question.
    if ((Test-HordeDecisionMember -Object $plain -Name "number") -and -not (Test-HordeDecisionCount -Value $plain.number -Most (Get-HordeDecisionMaxNumber))) {
        return (New-HordeAbsent -Note ("there is no question " + $plain.number + ": no question has a number above " + (Get-HordeDecisionMaxNumber)))
    }

    if ($entry.ContainsKey("noStore")) { return (& $entry.read $plain $null $definitions $Now) }
    if ($Root -eq "") {
        try { $Root = Get-HordeDecisionStoreRoot }
        catch { return (New-HordeUnknown -Reason "the decisions store could not be found" -ErrorRecord $_) }
    }
    # THE SETTINGS, BEFORE THE STORE IS TOUCHED. An override file that failed its checks refuses every
    # setting (decisions/Settings.ps1), and an operation that went ahead would be running on defaults a
    # person had tried to replace - or would answer at all only because its path happened to need no
    # setting. So every operation on the store answers unknown, in the settings' own sentence: the file
    # and every problem in it. Asked AFTER the store is found, so that a home that cannot be worked out
    # is still said as that, by the lines above; with -Root given and no home, the settings cannot be
    # found either, and core/Home's own words are the reason.
    $unfit = ""
    try { $unfit = Get-HordeDecisionSettingsProblem } catch { $unfit = "$($_.Exception.Message)" }
    if ($unfit -ne "") { return (New-HordeUnknown -Reason $unfit) }
    if ($entry.writes) { return (Invoke-HordeDecisionWrite -Operation $Operation -Request $plain -Root $Root -Definitions $definitions -Now $Now) }
    $read = Read-HordeDecisionState -Root $Root -Definitions $definitions
    if ($read.state -ceq "unknown") { return (New-HordeUnknown -Reason $read.reason) }
    return (& $entry.read $plain $read.list $definitions $Now)
}
