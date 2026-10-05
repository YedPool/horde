# remote/NodeServe - what a node answers on the link, one frame at a time.
#
# WHY (remote plan step R12a). `horde node serve` (cli/NodeServe.ps1) holds the listener and the loop;
# this file holds the protocol: given one received line and what the node knows, the frame to send
# back. It is pure and starts nothing, so it lives in remote/ under tools/ExecScan.ps1's proof, and
# every answer can be tested without a pipe.
#
# WHAT IT ANSWERS. The hub's hello, once, with the node's own (protocol negotiation, R2); a ping, with a
# pong carrying the node's clock (R6); the read verbs of R12a: node.info, sessions.list, session.get
# and request.status; and, on a node that serves acts, the two act verbs of R19's first version
# (the act path's A3, 2026-10-05): session.spawn and session.close. Every other verb of link-verbs v1
# is refused as unsupported - session.deliver, a drive verb, among them, and observe.since and
# binding.get, which belong to R12b.
#
# AN ACT HAPPENS ONCE PER REQUEST ID, AND NOT HERE. This file starts nothing. On the first sight of an
# act request it records it in the request journal (remote/Journal.ps1, before anything acts) and
# answers NeedAct: its caller (cli/NodeServe.ps1, through cli/NodeAct.ps1) acts through the host and
# agent layers and calls again with the outcome, which is recorded and answered as the journal entry.
# A resend replays what was recorded and acts nothing; the same id with other arguments is refused; a
# node with no journal, or that serves no acts, acts on nothing. Anything before the hello but the hello, a second
# hello, and a hello that is not a hub's end the link; a line that is not a frame ends it too.
#
# WHAT CROSSES. sessions.list and session.get carry a fixed summary of each session (schema
# session-summary): identity and status fields, each a tristate answer, with the pid, procStart and
# project directory placed by device and space (R11). No transcript path, resume command or other raw
# worker context. complete is known true only when every store the projection read was readable.
#
# EVERY ANSWER FITS THE WIRE. A value the link cannot carry becomes an unknown with the reason; a reason
# is cut to the reasonBytes cap; a session whose id the link cannot carry, or past the list cap, is left
# out and complete says so. One bad record never takes the whole list down (review of this PR: a
# session id 'a..b' and a 1500-byte reason each made the frame unsendable).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Protocol.ps1")
. (Join-Path $PSScriptRoot "Journal.ps1")

# The verbs this node answers in R12a, and those that need the session projection.
$script:HordeNodeServedVerbs = @("node.info", "sessions.list", "session.get", "request.status")
# The act verbs of R19's first version, answered only by a node that serves acts (Data.acts).
$script:HordeNodeActVerbs = @("session.spawn", "session.close")
# The link's time spelling (Get-HordeLinkTime), for a request's issuedAt.
$script:HordeNodeIssuedFormat = "yyyy-MM-dd'T'HH:mm:ss.fff'Z'"
$script:HordeNodeViewVerbs = @("sessions.list", "session.get")
# The verbs versions this node speaks (link-verbs v1).
$script:HordeNodeVerbsVersions = @(1)
# The time pattern of the link (link-frame.v1 "time"), for values taken from the session view.
$script:HordeNodeTimePattern = '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z\z'
# answer-token's value pattern (link-verbs v1).
$script:HordeNodeTokenPattern = '\A[A-Za-z0-9][A-Za-z0-9._/-]{0,199}\z'
# answer-place's value pattern: printable ASCII, at most 255 characters; and its nameBytes cap on the wire.
$script:HordeNodePlacePattern = '\A[\x20-\x7E]{1,255}\z'
$script:HordeNodeNameBytes = 256
# The reasonBytes and listItems caps (link-frame.v1).
$script:HordeNodeReasonBytes = 1024
$script:HordeNodeListItems = 256

function New-HordeNodeServeState {
    # One link's state on the node side: whether hello is done, the protocol chosen, the next seq, and
    # the contract, read here once. Get-HordeLinkContract parses both link schemas on every call (about
    # 1.4 s, measured 2026-10-02); read per frame and per session id, sessions.list over 31 sessions
    # took 44 s and the hub's 60 s wait ran out. Every contract use below takes this one.
    param([Parameter(Mandatory = $true)][string]$NodeId, [Parameter(Mandatory = $true)][string]$NodeName, [Parameter(Mandatory = $true)][string]$HordeVersion, $Contract = $null)
    if ($null -eq $Contract) { $Contract = Get-HordeLinkContract }
    return [pscustomobject]@{ helloDone = $false; protocol = 0; seq = 0; nodeId = $NodeId; nodeName = $NodeName; hordeVersion = $HordeVersion; closed = $false; contract = $Contract }
}

function Get-HordeNodeNextSeq {
    param([Parameter(Mandatory = $true)]$State)
    $State.seq = $State.seq + 1
    return $State.seq
}

function New-HordeNodeReply {
    # What Invoke-HordeNodeFrame decided: the frame to send (or none), whether the projection is needed
    # first, and whether the link ends after the reply.
    param($Reply = $null, [bool]$NeedView = $false, [bool]$Close = $false, [bool]$NeedAct = $false, $Act = $null)
    return [pscustomobject]@{ reply = $Reply; needView = $NeedView; close = $Close; needAct = $NeedAct; act = $Act }
}

function Limit-HordeNodeReason {
    param([string]$Text)
    return (Limit-HordeWireString -Text $Text -Bytes $script:HordeNodeReasonBytes)
}

function Get-HordeNodeViewTime {
    # The view's observation time as link text, or now when it gives none the link can carry.
    param($View)
    $at = "$(Get-HordeLinkProp $View 'observedAt')"
    if ($at -cmatch $script:HordeNodeTimePattern) { return $at }
    return (Get-HordeLinkTime)
}

function ConvertTo-HordeNodeWireAnswer {
    # A link answer record from a known/absent/unknown answer as the session view writes it: state,
    # value, reason and observedAt, a missing value or time left out (link-frame.v1), and a known or
    # absent answer with no time of its own given the view's. The view's own extras (source,
    # provisional, shadow) are dropped; the reason is cut to its cap.
    param($Answer, [string]$ViewObservedAt)
    $state = "$(Get-HordeLinkProp $Answer 'state')"
    if (@("known", "absent", "unknown") -cnotcontains $state) { return [ordered]@{ state = "unknown"; reason = "the node's projection gave no answer the link knows" } }
    $out = [ordered]@{ state = $state }
    if ($state -ceq "known") { $out["value"] = Get-HordeLinkProp $Answer "value" }
    $reason = "$(Get-HordeLinkProp $Answer 'reason')"
    if ($state -ceq "unknown" -and $reason.Trim() -eq "") { $reason = "the node's projection gives no reason" }
    $out["reason"] = Limit-HordeNodeReason $reason
    if ($state -cne "unknown") {
        $at = "$(Get-HordeLinkProp $Answer 'observedAt')"
        if ($at -cnotmatch $script:HordeNodeTimePattern) { $at = $ViewObservedAt }
        $out["observedAt"] = $at
    }
    return $out
}

function Get-HordeNodeFieldAnswer {
    # One field of a view session as a link answer, its value held to -Kind's shape. A value the link
    # cannot carry in that shape is unknown with the reason, never cut or reshaped.
    param($Fields, [Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Kind, [string]$ViewObservedAt, $Namespace = $null)
    $a = Get-HordeLinkProp $Fields $Name
    $w = $null
    if ($null -eq $a) { $w = [ordered]@{ state = "unknown"; reason = ("the node's projection has no field " + $Name) } }
    else { $w = ConvertTo-HordeNodeWireAnswer -Answer $a -ViewObservedAt $ViewObservedAt }
    if ($w["state"] -ceq "known") {
        $v = $w["value"]
        $fits = $false
        switch ($Kind) {
            "token" { $fits = ($v -is [string] -and $v -cmatch $script:HordeNodeTokenPattern) }
            "time" { $fits = ($v -is [string] -and $v -cmatch $script:HordeNodeTimePattern) }
            "bool" { $fits = ($v -is [bool]) }
            "pid" { $fits = (($v -is [int] -or $v -is [long]) -and $v -ge 1) }
            "ticks" { $fits = (($v -is [int] -or $v -is [long]) -and $v -ge 0) }
            "place" { $fits = ($v -is [string] -and $v -cmatch $script:HordeNodePlacePattern -and (Measure-HordeWireString $v) -le $script:HordeNodeNameBytes) }
        }
        if (-not $fits) { $w = [ordered]@{ state = "unknown"; reason = ("the node's " + $Name + " is not a value the link can carry as a " + $Kind) } }
    }
    if ($null -ne $Namespace) { $w["ns"] = [ordered]@{ device = "$($Namespace.device)"; space = "$($Namespace.space)" } }
    return $w
}

function Test-HordeNodeSessionId {
    # Can the link carry this as a session id (link-verbs v1 session-id)? The pattern is read from the
    # contract, so the node checks exactly what the hub's decoder will; a line break is refused outright
    # because a final $ in .NET also matches before one.
    param([string]$Id, [Parameter(Mandatory = $true)]$Contract)
    if ($Id.Contains("`n") -or $Id.Contains("`r")) { return $false }
    $pattern = "$($Contract.verbs.definitions.'session-id'.pattern)"
    return ($Id -cmatch $pattern)
}

function ConvertTo-HordeNodeSessionSummary {
    # One session of the session view as the link's session-summary.
    param([Parameter(Mandatory = $true)]$Session, [Parameter(Mandatory = $true)][string]$ViewObservedAt, [Parameter(Mandatory = $true)]$Namespace)
    $f = Get-HordeLinkProp $Session "fields"
    return [ordered]@{
        sessionId = "$(Get-HordeLinkProp $Session 'sessionId')"
        agent = Get-HordeNodeFieldAnswer -Fields $f -Name "agent" -Kind "token" -ViewObservedAt $ViewObservedAt
        fleetSessionId = Get-HordeNodeFieldAnswer -Fields $f -Name "fleetSessionId" -Kind "token" -ViewObservedAt $ViewObservedAt
        role = Get-HordeNodeFieldAnswer -Fields $f -Name "role" -Kind "token" -ViewObservedAt $ViewObservedAt
        label = Get-HordeNodeFieldAnswer -Fields $f -Name "label" -Kind "token" -ViewObservedAt $ViewObservedAt
        parent = Get-HordeNodeFieldAnswer -Fields $f -Name "parent" -Kind "token" -ViewObservedAt $ViewObservedAt
        liveStatus = Get-HordeNodeFieldAnswer -Fields $f -Name "liveStatus" -Kind "token" -ViewObservedAt $ViewObservedAt
        workState = Get-HordeNodeFieldAnswer -Fields $f -Name "workState" -Kind "token" -ViewObservedAt $ViewObservedAt
        startedAt = Get-HordeNodeFieldAnswer -Fields $f -Name "startedAt" -Kind "time" -ViewObservedAt $ViewObservedAt
        lastActivity = Get-HordeNodeFieldAnswer -Fields $f -Name "lastActivity" -Kind "time" -ViewObservedAt $ViewObservedAt
        retired = Get-HordeNodeFieldAnswer -Fields $f -Name "retired" -Kind "bool" -ViewObservedAt $ViewObservedAt
        pid = Get-HordeNodeFieldAnswer -Fields $f -Name "pid" -Kind "pid" -ViewObservedAt $ViewObservedAt -Namespace $Namespace
        procStart = Get-HordeNodeFieldAnswer -Fields $f -Name "procStart" -Kind "ticks" -ViewObservedAt $ViewObservedAt -Namespace $Namespace
        projectCwd = Get-HordeNodeFieldAnswer -Fields $f -Name "projectCwd" -Kind "place" -ViewObservedAt $ViewObservedAt -Namespace $Namespace
    }
}

function Get-HordeNodeUnreadable {
    # The stores the projection could not read, each "<store> (<why>)"; empty when it read every one.
    # A view naming no store at all has read nothing, which is said as one entry.
    param($Complete)
    $bad = New-Object System.Collections.ArrayList
    $pairs = @(Get-HordeLinkPairs $Complete)
    if ($pairs.Count -eq 0) { [void]$bad.Add("the node's projection names no store it read"); return $bad.ToArray() }
    foreach ($p in $pairs) {
        $st = "$(Get-HordeLinkProp $p.Value 'state')"
        $v = Get-HordeLinkProp $p.Value "value"
        if (-not ($st -ceq "known" -and $v -is [bool] -and $v)) {
            $why = "$(Get-HordeLinkProp $p.Value 'reason')"
            if ($why.Trim() -eq "") { $why = "not read" }
            [void]$bad.Add($p.Name + " (" + $why + ")")
        }
    }
    return $bad.ToArray()
}

function New-HordeNodeComplete {
    # complete as a link answer: known true only with nothing missing; otherwise known false, the reason
    # naming what was missing, cut to its cap.
    param([string[]]$Missing, [Parameter(Mandatory = $true)][string]$ViewObservedAt)
    $m = @($Missing | Where-Object { "$_" -ne "" })
    if ($m.Count -eq 0) { return [ordered]@{ state = "known"; value = $true; reason = ""; observedAt = $ViewObservedAt } }
    return [ordered]@{ state = "known"; value = $false; reason = (Limit-HordeNodeReason ("not complete: " + ($m -join "; "))); observedAt = $ViewObservedAt }
}

function Get-HordeNodeSessionList {
    # sessions.list's result value from a session-view document. A session the link cannot carry, or
    # past the list cap, is left out, and complete names the omission.
    param([Parameter(Mandatory = $true)]$View, [Parameter(Mandatory = $true)]$Namespace, [Parameter(Mandatory = $true)]$Contract)
    $at = Get-HordeNodeViewTime $View
    $missing = New-Object System.Collections.ArrayList
    foreach ($u in @(Get-HordeNodeUnreadable (Get-HordeLinkProp $View "complete"))) { [void]$missing.Add("not every store was readable: " + $u) }
    $list = New-Object System.Collections.ArrayList
    $skipped = 0
    $over = 0
    foreach ($s in @(Get-HordeLinkProp $View "sessions")) {
        if ($null -eq $s) { continue }
        if (-not (Test-HordeNodeSessionId -Id "$(Get-HordeLinkProp $s 'sessionId')" -Contract $Contract)) { $skipped++; continue }
        if ($list.Count -ge $script:HordeNodeListItems) { $over++; continue }
        [void]$list.Add((ConvertTo-HordeNodeSessionSummary -Session $s -ViewObservedAt $at -Namespace $Namespace))
    }
    if ($skipped -gt 0) { [void]$missing.Add("" + $skipped + " session(s) left out: their ids are not ones the link can carry") }
    if ($over -gt 0) { [void]$missing.Add("" + $over + " session(s) left out past the list cap of " + $script:HordeNodeListItems) }
    return [ordered]@{ complete = (New-HordeNodeComplete -Missing $missing.ToArray() -ViewObservedAt $at); sessions = $list.ToArray(); observedAt = $at }
}

function ConvertTo-HordeNodeRequestEntry {
    # request.status's result value from a journal entry: the closed request-entry, times as link text.
    param([Parameter(Mandatory = $true)]$Entry)
    $out = [ordered]@{ requestId = "$($Entry.id)"; verb = "$($Entry.verb)" }
    if ("$($Entry.argsHash)" -cmatch '\A[0-9a-f]{64}\z') { $out["argsHash"] = "$($Entry.argsHash)" }
    $out["state"] = "$($Entry.state)"
    $out["receivedAt"] = Get-HordeLinkTime -At $Entry.receivedAt
    if ($null -ne $Entry.doneAt) { $out["doneAt"] = Get-HordeLinkTime -At $Entry.doneAt }
    # An act's outcome (R19): the session it concerns, the process a spawn started, and the reason.
    $res = $Entry.PSObject.Properties["result"]
    if ($null -ne $res -and $null -ne $res.Value -and "$($res.Value.state)" -ceq "known" -and $null -ne $res.Value.value) {
        $v = $res.Value.value
        $sidv = "$(Get-HordeLinkProp $v 'sessionId')"
        if ($sidv -ne "") { $out["sessionId"] = $sidv }
        $ex = Get-HordeLinkProp $v "expect"
        if ($null -ne $ex) {
            $exNs = Get-HordeLinkProp $ex "ns"
            $out["expect"] = [ordered]@{ ns = [ordered]@{ device = "$(Get-HordeLinkProp $exNs 'device')"; space = "$(Get-HordeLinkProp $exNs 'space')" }; pid = [long](Get-HordeLinkProp $ex "pid"); procStart = "$(Get-HordeLinkProp $ex 'procStart')" }
        }
        $why = "$(Get-HordeLinkProp $v 'reason')"
        if ($why -ne "") { $out["reason"] = Limit-HordeNodeReason $why }
    }
    return $out
}

function New-HordeNodeHello {
    param([Parameter(Mandatory = $true)]$State)
    $t = Get-HordeLinkTime
    $h = [ordered]@{ role = "node"; id = $State.nodeId; name = $State.nodeName; protocols = @($script:HordeLinkProtocols); verbsVersions = @($script:HordeNodeVerbsVersions); hordeVersion = $State.hordeVersion; t1 = $t }
    return [pscustomobject][ordered]@{ v = 1; kind = "hello"; id = (New-HordeLinkFrameId); seq = (Get-HordeNodeNextSeq $State); ts = $t; hello = [pscustomobject]$h }
}

function New-HordeNodeResult {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)]$Answer)
    # Built as ordered maps, sent as parsed JSON objects: the contract's checker and the wire writer
    # read objects, and a round trip through JSON is the one conversion both agree on.
    $result = ($Answer | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json
    return [pscustomobject][ordered]@{ v = 1; kind = "res"; id = (New-HordeLinkFrameId); seq = (Get-HordeNodeNextSeq $State); ts = (Get-HordeLinkTime); verb = "$($Request.verb)"; requestId = "$($Request.requestId)"; re = "$($Request.id)"; result = $result }
}

function New-HordeNodeError {
    # An error answer to one request. -Request needs only verb, requestId and id (the frame answered).
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)][string]$Code, [Parameter(Mandatory = $true)][string]$Reason)
    $said = Limit-HordeNodeReason $Reason
    return [pscustomobject][ordered]@{ v = 1; kind = "res"; id = (New-HordeLinkFrameId); seq = (Get-HordeNodeNextSeq $State); ts = (Get-HordeLinkTime); verb = "$($Request.verb)"; requestId = "$($Request.requestId)"; re = "$($Request.id)"; error = [pscustomobject][ordered]@{ code = $Code; reason = $said } }
}

function New-HordeNodeBye {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)][string]$Code, [Parameter(Mandatory = $true)][string]$Reason)
    return (New-HordeNodeReply -Reply (New-HordeLinkBye -Code $Code -Reason $Reason -Seq (Get-HordeNodeNextSeq $State) -Contract $State.contract) -Close $true)
}

function ConvertFrom-HordeNodeIssuedAt {
    # A request's issuedAt as a UTC time, or $null when it is not the link's spelling of one.
    param([string]$Text)
    $d = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParseExact($Text, $script:HordeNodeIssuedFormat, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$d)) { return $d }
    return $null
}

function Test-HordeNodeActArgs {
    # The rules of an act's arguments the schema cannot say: "" when they hold, or the refusal.
    param([Parameter(Mandatory = $true)][string]$Verb, $Arguments)
    if ($Verb -cne "session.spawn") { return "" }
    $p = Get-HordeLinkProp $Arguments "prompt"
    $hasText = ($null -ne (Get-HordeLinkProp $p "text"))
    $hasRef = ($null -ne (Get-HordeLinkProp $p "handoffRef"))
    if ($hasText -and $hasRef) { return "a spawn's prompt is text or a handoff reference, not both" }
    if (-not $hasText -and -not $hasRef) { return "a spawn's prompt is text or a handoff reference, and this one has neither" }
    if ($hasRef) { return "a prompt given as a handoff reference is not served yet (R14); send its text" }
    return ""
}

function Invoke-HordeNodeAct {
    # An act verb's frame, answered (see the header: AN ACT HAPPENS ONCE PER REQUEST ID, AND NOT HERE).
    # -Data.actOutcome is $null on the first call and { state; sessionId; expect; reason } on the second.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Frame, [Parameter(Mandatory = $true)]$Data)
    $verb = "$($Frame.verb)"
    $journal = "$($Data.journalRoot)"
    if ($journal -eq "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $Frame -Code "refused" -Reason "this node keeps no request journal, so it acts on nothing: an act it could not record could happen twice")) }
    $outcome = Get-HordeLinkProp $Data "actOutcome"
    if ($null -eq $outcome) {
        $bad = Test-HordeNodeActArgs -Verb $verb -Arguments $Frame.args
        if ($bad -ne "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $Frame -Code "refused" -Reason $bad)) }
        $issued = ConvertFrom-HordeNodeIssuedAt -Text "$($Frame.issuedAt)"
        if ($null -eq $issued) { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $Frame -Code "refused" -Reason "the request's issuedAt is not a time this node can record")) }
        $o = Open-HordeJournalEntry -Root $journal -Id "$($Frame.requestId)" -Verb $verb -Arguments $Frame.args -IssuedAt $issued
        switch ("$($o.decision)") {
            "act" { return (New-HordeNodeReply -NeedAct $true -Act ([pscustomobject]@{ verb = $verb; args = $Frame.args; requestId = "$($Frame.requestId)" })) }
            "refuse" { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $Frame -Code "refused" -Reason "$($o.reason)")) }
            "replay" {
                $e = Get-HordeJournalEntry -Root $journal -Id "$($Frame.requestId)"
                if ($e.state -ceq "known") { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $Frame -Answer ([ordered]@{ state = "known"; value = (ConvertTo-HordeNodeRequestEntry -Entry $e.value); reason = ""; observedAt = (Get-HordeLinkTime) }))) }
            }
        }
        # The journal cannot say what happened; its own reason can name its files and stays on the node.
        return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $Frame -Answer ([ordered]@{ state = "unknown"; reason = "the node's journal cannot say what happened to this request, so it is not acted on again; its own reason is kept on the node" })))
    }
    $st = "$(Get-HordeLinkProp $outcome 'state')"
    if (@("done", "failed", "refused") -cnotcontains $st) { $st = "failed" }
    $value = [ordered]@{ sessionId = "$(Get-HordeLinkProp $outcome 'sessionId')"; expect = (Get-HordeLinkProp $outcome "expect"); reason = (Limit-HordeNodeReason "$(Get-HordeLinkProp $outcome 'reason')") }
    $now = Get-HordeLinkTime
    $existing = Get-HordeJournalEntry -Root $journal -Id "$($Frame.requestId)"
    if ($existing.state -ceq "known" -and "$($existing.value.state)" -cne "accepted") {
        # Already recorded: the first outcome stands, and is what is answered.
        return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $Frame -Answer ([ordered]@{ state = "known"; value = (ConvertTo-HordeNodeRequestEntry -Entry $existing.value); reason = ""; observedAt = $now })))
    }
    $null = Complete-HordeJournalEntry -Root $journal -Id "$($Frame.requestId)" -State $st -Result (New-HordeKnown -Value $value)
    $e = Get-HordeJournalEntry -Root $journal -Id "$($Frame.requestId)"
    if ($e.state -ceq "known") { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $Frame -Answer ([ordered]@{ state = "known"; value = (ConvertTo-HordeNodeRequestEntry -Entry $e.value); reason = ""; observedAt = $now }))) }
    return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $Frame -Answer ([ordered]@{ state = "unknown"; reason = "the outcome was recorded and could not be read back; ask request.status" })))
}

function Invoke-HordeNodeFrame {
    # One received line, answered. -Data is what the node knows: manifest (node.info's value), view (the
    # session-view document, or $null until asked for), viewError (why the view could not be built, or
    # ""), journalRoot (the request journal, or ""), namespace (this node's { device; space }). When a
    # verb needs the view and neither a view nor its error is given, the answer is NeedView and nothing
    # is sent; the caller builds the view and asks again.
    param([Parameter(Mandatory = $true)]$State, $Line, [Parameter(Mandatory = $true)]$Data)
    $bytes = [System.Text.Encoding]::GetEncoding(28591).GetBytes("$Line")
    $got = ConvertFrom-HordeFrameBytes -Bytes $bytes -Contract $State.contract
    if (-not $got.ok) {
        # A line that is not a frame cannot be answered by id: the link is ended, saying why (R2).
        return (New-HordeNodeReply -Reply (New-HordeLinkBye -Code "$($got.code)" -Reason "$($got.reason)" -Seq (Get-HordeNodeNextSeq $State) -Contract $State.contract) -Close $true)
    }
    $f = $got.frame
    $kind = "$($f.kind)"
    if ($kind -ceq "hello") {
        if ($State.helloDone) { return (New-HordeNodeBye -State $State -Code "refused" -Reason "a second hello on one link: the protocol is chosen once") }
        if ("$($f.hello.role)" -cne "hub") { return (New-HordeNodeBye -State $State -Code "refused" -Reason ("a node answers a hub; this hello says its role is '" + $f.hello.role + "'")) }
        $r = Resolve-HordeLinkHello -Hello $f -Seq ($State.seq + 1) -Contract $State.contract
        if ($null -ne $r.bye) { $null = Get-HordeNodeNextSeq $State; return (New-HordeNodeReply -Reply $r.bye -Close $true) }
        $State.helloDone = $true
        $State.protocol = $r.protocol
        return (New-HordeNodeReply -Reply (New-HordeNodeHello -State $State))
    }
    if ($kind -ceq "bye") { return (New-HordeNodeReply -Close $true) }
    if (-not $State.helloDone) {
        if ($kind -ceq "req") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason "no request is answered before the hello")) }
        return (New-HordeNodeBye -State $State -Code "refused" -Reason ("a " + $kind + " frame before the hello"))
    }
    if ($kind -ceq "ping") {
        $t2 = Get-HordeLinkTime
        $pong = [pscustomobject][ordered]@{ v = 1; kind = "pong"; id = (New-HordeLinkFrameId); seq = (Get-HordeNodeNextSeq $State); ts = (Get-HordeLinkTime); re = "$($f.id)"; pong = [pscustomobject][ordered]@{ t1 = "$($f.ping.t1)"; t2 = $t2; t3 = (Get-HordeLinkTime) } }
        return (New-HordeNodeReply -Reply $pong)
    }
    if ($kind -cne "req") { return (New-HordeNodeReply) }
    $verb = "$($f.verb)"
    if ($script:HordeNodeActVerbs -ccontains $verb -and (Get-HordeLinkProp $Data "acts") -eq $true) { return (Invoke-HordeNodeAct -State $State -Frame $f -Data $Data) }
    if ($script:HordeNodeServedVerbs -cnotcontains $verb) { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "unsupported-verb" -Reason ("this node answers " + ($script:HordeNodeServedVerbs -join ", ") + "; '" + $verb + "' is not one of them"))) }
    if ($script:HordeNodeViewVerbs -ccontains $verb) {
        if ("$($Data.viewError)" -ne "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "internal" -Reason ("the node could not build its view of its sessions: " + $Data.viewError))) }
        if ($null -eq $Data.view) { return (New-HordeNodeReply -NeedView $true) }
    }
    $now = Get-HordeLinkTime
    switch ($verb) {
        "node.info" {
            return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "known"; value = $Data.manifest; reason = ""; observedAt = $now })))
        }
        "sessions.list" {
            $list = Get-HordeNodeSessionList -View $Data.view -Namespace $Data.namespace -Contract $State.contract
            return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "known"; value = $list; reason = ""; observedAt = $list["observedAt"] })))
        }
        "session.get" {
            $want = "$($f.args.sessionId)"
            $agentProp = $f.args.PSObject.Properties["agent"]
            $wantAgent = ""
            if ($null -ne $agentProp) { $wantAgent = "$($agentProp.Value)" }
            $at = Get-HordeNodeViewTime $Data.view
            $found = New-Object System.Collections.ArrayList
            foreach ($s in @(Get-HordeLinkProp $Data.view "sessions")) {
                if ($null -eq $s -or "$(Get-HordeLinkProp $s 'sessionId')" -cne $want) { continue }
                if ($wantAgent -ne "") {
                    $ag = Get-HordeLinkProp (Get-HordeLinkProp $s "fields") "agent"
                    if ("$(Get-HordeLinkProp $ag 'value')" -cne $wantAgent) { continue }
                }
                [void]$found.Add($s)
            }
            if ($found.Count -gt 1) { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = ("" + $found.Count + " sessions on this node have the id " + $want + "; name the agent to choose one") }))) }
            if ($found.Count -eq 1) {
                $summary = ConvertTo-HordeNodeSessionSummary -Session $found[0] -ViewObservedAt $at -Namespace $Data.namespace
                return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "known"; value = $summary; reason = ""; observedAt = $at })))
            }
            # Absent only when the projection read every store; otherwise the session may be in a store
            # it could not read, and the answer is unknown (design 7.1).
            $unread = @(Get-HordeNodeUnreadable (Get-HordeLinkProp $Data.view "complete"))
            if ($unread.Count -eq 0) { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "absent"; reason = ("the node's projection read every store and holds no session " + $want); observedAt = $at }))) }
            return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = (Limit-HordeNodeReason ("the node's projection holds no session " + $want + ", but not every store was readable: " + ($unread -join "; "))) })))
        }
        "request.status" {
            if ("$($Data.journalRoot)" -eq "") { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = "this node keeps no request journal yet" }))) }
            $e = Get-HordeJournalEntry -Root $Data.journalRoot -Id "$($f.args.requestId)"
            if ($e.state -ceq "known") { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "known"; value = (ConvertTo-HordeNodeRequestEntry -Entry $e.value); reason = ""; observedAt = $now }))) }
            if ($e.state -ceq "absent") { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "absent"; reason = "the node's journal holds no such request"; observedAt = $now }))) }
            # The journal's own reason can name its files; the hub is told only that it could not say.
            return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = "the node's journal could not say; its own reason is kept on the node" })))
        }
    }
    return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "internal" -Reason ("no answer was built for '" + $verb + "'")))
}
