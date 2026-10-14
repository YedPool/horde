# remote/NodeServe - what a node answers on the link, one frame at a time.
#
# WHY (remote plan step R12a). `horde node serve` (cli/NodeServe.ps1) holds the listener and the loop;
# this file holds the protocol: given one received line and what the node knows, the frame to send
# back. It is pure and starts nothing, so it lives in remote/ under tools/ExecScan.ps1's proof, and
# every answer can be tested without a pipe.
#
# WHAT IT ANSWERS. The hub's hello, once, with the node's own (protocol negotiation, R2); a ping, with a
# pong carrying the node's clock (R6); the read verbs of R12a: node.info, sessions.list, session.get
# and request.status; on a node that serves acts, the two act verbs of R19's first version (the act
# path's A3, 2026-10-05): session.spawn and session.close; and messaging, R21 slice 4: session.deliver,
# delivery.status, mail.next and mail.receipt. Every other verb of link-verbs v1 is refused as
# unsupported - observe.since and binding.get belong to R12b.
#
# AN ACT HAPPENS ONCE PER REQUEST ID, AND NOT HERE. This file starts nothing. On the first sight of an
# act request it records it in the request journal (remote/Journal.ps1, before anything acts) and
# answers NeedAct: its caller (cli/NodeServe.ps1, through cli/NodeAct.ps1) acts through the host and
# agent layers and calls again with the outcome, which is recorded and answered as the journal entry.
# A resend replays what was recorded and acts nothing; the same id with other arguments is refused; a
# node with no journal, or that serves no acts, acts on nothing. Anything before the hello but the
# hello, a second hello, and a hello that is not a hub's end the link; a line that is not a frame ends
# it too.
#
# MESSAGING DECIDES NOTHING HERE (review of PR #97). Which session a deliver reaches and whether it may,
# which outbound message is next, and what a receipt does to a record are remote/Messaging.ps1's rules -
# Resolve-HordeDeliverTarget, Select-HordeMailNext and Resolve-HordeMailReceipt - called below and never
# re-decided; test/test-node-serve-messaging.ps1 checks the call sites. And this file still acts on
# nothing: a deliver that passes the gate comes back as NeedDeliver, a status as NeedStatus, the outbox
# as NeedOutbox, the node's opt-in list as NeedDeliverTo (read again for every deliver, so an edit to
# engine-live.json holds from the next one), and an outbox mark as a write the caller (cli/NodeServe.ps1)
# performs before it sends the reply. A message is journaled (remote/Journal.ps1, kind message, keyed by
# messageId) only once the messenger has answered; a resend before then asks the messenger again, which
# is safe because a node's messenger must be idempotent by messageId (the messenger port's
# idempotent.post).
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
. (Join-Path $PSScriptRoot "Messaging.ps1")

# The verbs this node answers in R12a, and those that need the session projection.
$script:HordeNodeServedVerbs = @("node.info", "sessions.list", "session.get", "request.status", "session.deliver", "delivery.status", "mail.next", "mail.receipt")
# The act verbs of R19's first version, answered only by a node that serves acts (Data.acts).
$script:HordeNodeActVerbs = @("session.spawn", "session.close")
# The link's time spelling (Get-HordeLinkTime), for a request's issuedAt.
$script:HordeNodeIssuedFormat = "yyyy-MM-dd'T'HH:mm:ss.fff'Z'"
$script:HordeNodeViewVerbs = @("sessions.list", "session.get", "session.deliver")
$script:HordeNodeOutboxVerbs = @("mail.next", "mail.receipt")
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
    return [pscustomobject]@{ helloDone = $false; protocol = 0; seq = 0; peerId = ""; nodeId = $NodeId; nodeName = $NodeName; hordeVersion = $HordeVersion; closed = $false; contract = $Contract }
}

function Get-HordeNodeNextSeq {
    param([Parameter(Mandatory = $true)]$State)
    $State.seq = $State.seq + 1
    return $State.seq
}

function New-HordeNodeReply {
    # What Invoke-HordeNodeFrame decided: the frame to send (or none); what the caller must fetch or do
    # first and then ask again with - the projection (needView), an act (needAct: act), a delivery by the
    # messenger (needDeliver: { target; message }), the messenger's word on one message (needStatus: its
    # messageId), the outbox (needOutbox), the node's opt-in list read from its layers now (needDeliverTo);
    # a mark the caller must write to the outbox BEFORE sending the reply (write: { messageId; marker; at });
    # and whether the link ends after the reply.
    param($Reply = $null, [bool]$NeedView = $false, [bool]$Close = $false, [bool]$NeedAct = $false, $Act = $null,
        $NeedDeliver = $null, [string]$NeedStatus = "", [bool]$NeedOutbox = $false, [bool]$NeedDeliverTo = $false, $Write = $null)
    return [pscustomobject]@{ reply = $Reply; needView = $NeedView; close = $Close; needAct = $NeedAct; act = $Act; needDeliver = $NeedDeliver; needStatus = $NeedStatus; needOutbox = $NeedOutbox; needDeliverTo = $NeedDeliverTo; write = $Write }
}

function Get-HordeNodeLiveSessions {
    # The node's live sessions as the messaging rules take them: { sessionId; label; pid; procStart; ns },
    # from the session view, every process placed in this node's namespace (R11). A field the view does not
    # know is "", which the rules read as proving nothing.
    param($View, [Parameter(Mandatory = $true)]$Namespace)
    $out = New-Object System.Collections.ArrayList
    foreach ($s in @(Get-HordeLinkProp $View "sessions")) {
        if ($null -eq $s) { continue }
        $f = Get-HordeLinkProp $s "fields"
        $vals = @{}
        foreach ($n in @("label", "pid", "procStart")) {
            $a = Get-HordeLinkProp $f $n
            $vals[$n] = ""
            if ("$(Get-HordeLinkProp $a 'state')" -ceq "known") { $vals[$n] = "$(Get-HordeLinkProp $a 'value')" }
        }
        [void]$out.Add([pscustomobject]@{ sessionId = "$(Get-HordeLinkProp $s 'sessionId')"; label = $vals["label"]; pid = $vals["pid"]; procStart = $vals["procStart"]
            ns = [pscustomobject]@{ device = "$($Namespace.device)"; space = "$($Namespace.space)" } })
    }
    return $out.ToArray()
}

function ConvertTo-HordeNodeAnswer {
    # A tristate answer held by this node (the journal's, the messenger's) as a link answer: known with its
    # value and a time, otherwise unknown with a reason cut to its cap.
    param($Answer, [string]$Unknown = "")
    $now = Get-HordeLinkTime
    if ("$(Get-HordeLinkProp $Answer 'state')" -ceq "known") { return [ordered]@{ state = "known"; value = (Get-HordeLinkProp $Answer "value"); reason = ""; observedAt = $now } }
    $why = "$(Get-HordeLinkProp $Answer 'reason')"
    if ($why.Trim() -eq "") { $why = "no reason was given" }
    if ($Unknown -ne "") { $why = $Unknown + ": " + $why }
    return [ordered]@{ state = "unknown"; reason = (Limit-HordeNodeReason $why) }
}

function New-HordeNodeDelivery {
    # The link's delivery value for one message, from a stage the messenger reported. A stage the link does
    # not know is $null, and the caller answers unknown rather than send it.
    param([Parameter(Mandatory = $true)][string]$MessageId, [Parameter(Mandatory = $true)][string]$SessionId, $Reported, [Parameter(Mandatory = $true)]$Contract)
    $stage = "$(Get-HordeLinkProp $Reported 'stage')"
    if (@($Contract.verbs.definitions.delivery.properties.stage.enum) -cnotcontains $stage) { return $null }
    # The port gives at as a time; a messenger's own text is taken only in the link's spelling.
    $atRaw = Get-HordeLinkProp $Reported "at"
    $at = "$atRaw"
    if ($atRaw -is [datetime]) { $at = Get-HordeLinkTime -At $atRaw }
    if ($at -cnotmatch $script:HordeNodeTimePattern) { $at = Get-HordeLinkTime }
    $d = [ordered]@{ messageId = $MessageId; sessionId = $SessionId; stage = $stage; at = $at }
    $why = "$(Get-HordeLinkProp $Reported 'reason')"
    if ($why.Trim() -ne "") { $d["reason"] = Limit-HordeNodeReason $why }
    return $d
}

function Test-HordeNodeDataGiven {
    # Was a member of Data given at all? An empty list is given; a missing or null member is not yet
    # fetched. Asked of the property itself, because a list read through a function comes back unrolled,
    # and an empty one as $null.
    param($Data, [string]$Name)
    if ($null -eq $Data) { return $false }
    $p = $Data.PSObject.Properties[$Name]
    return ($null -ne $p -and $null -ne $p.Value)
}

function Get-HordeNodeDataList {
    # The non-null items of a list member of Data, written to the pipeline one by one (none when it is
    # missing), so a caller collects them with @() and never receives one nested array.
    param($Data, [string]$Name)
    if (-not (Test-HordeNodeDataGiven $Data $Name)) { return }
    foreach ($x in @($Data.PSObject.Properties[$Name].Value)) { if ($null -ne $x) { $x } }
}

function Find-HordeNodeOutboxRecord {
    param($Outbox, [string]$MessageId)
    foreach ($r in @($Outbox)) { if ($null -ne $r -and [string]::Equals("$($r.messageId)", $MessageId, [System.StringComparison]::Ordinal)) { return $r } }
    return $null
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
            "act" { return (New-HordeNodeReply -NeedAct $true -Act ([pscustomobject]@{ verb = $verb; args = $Frame.args; requestId = "$($Frame.requestId)"; hubId = "$($State.peerId)" })) }
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

function Invoke-HordeNodeDeliver {
    # session.deliver (R21 slice 4). In order: the message journal (a message already delivered is answered
    # from it, a reused messageId refused, before anything else is asked); the messenger present; the target
    # and its gate, by Resolve-HordeDeliverTarget over the live sessions, the hub-spawned records and the
    # node's own remote.deliverTo; then NeedDeliver, and with the messenger's answer, the journal and the
    # reply. Data.hubSpawned is the sessions this hub spawned here, which step 3.8's record writer
    # provides; until it ships, the caller passes none, and only opted-in labels can be reached.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)]$Data)
    $f = $Request
    $a = $f.args
    $id = "$($a.messageId)"
    $jr = "$(Get-HordeLinkProp $Data 'messageJournalRoot')"
    if ($jr -eq "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason "this node keeps no message journal, so it could not tell a resend from a first sight; nothing is delivered")) }
    $issued = ConvertFrom-HordeNodeIssuedAt -Text "$($f.issuedAt)"
    if ($null -eq $issued) { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason "the request's issuedAt is not a time this node can record")) }
    $prior = Get-HordeJournalEntry -Root $jr -Id $id
    if ($prior.state -ceq "unknown") { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = "the node's message journal could not say whether this message was delivered; its own reason is kept on the node" }))) }
    if ($prior.state -ceq "known") {
        $e = $prior.value
        if ("$($e.argsHash)" -cne (Get-HordeJournalArgsHash -Verb "session.deliver" -Arguments $a -IssuedAt $issued)) {
            return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason ("message " + $id + " was reused: it was recorded with other arguments or another issue time")))
        }
        if ($null -eq $e.result) { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = ("message " + $id + " is being recorded at this moment; it is not delivered twice") }))) }
        return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer (ConvertTo-HordeNodeAnswer -Answer $e.result)))
    }
    # A NODE LAYER THAT FAILS ITS CHECKS REFUSES EVERY DELIVER, to a hub-spawned session as to an opted-in
    # one, exactly as it refuses every spawn: the node cannot say what its owner allows.
    if (-not (Test-HordeNodeDataGiven $Data "deliverTo") -and "$(Get-HordeLinkProp $Data 'deliverToError')" -eq "") { return (New-HordeNodeReply -NeedDeliverTo $true) }
    $layerWhy = "$(Get-HordeLinkProp $Data 'deliverToError')"
    if ($layerWhy -ne "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason ("this node's own configuration is refused, so it delivers nothing: " + $layerWhy))) }
    if ("$(Get-HordeLinkProp $Data 'messenger')" -eq "") {
        $why = "$(Get-HordeLinkProp $Data 'messengerError')"
        $said = "this node has no messenger, so nothing is delivered"
        if ($why -ne "") { $said = $said + ": " + $why }
        return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason $said))
    }
    $label = ""
    $lp = $a.PSObject.Properties["label"]
    if ($null -ne $lp) { $label = "$($lp.Value)" }
    $target = Resolve-HordeDeliverTarget -SessionId "$($a.sessionId)" -Label $label -Live @(Get-HordeNodeLiveSessions -View $Data.view -Namespace $Data.namespace) -HubSpawned @(Get-HordeNodeDataList $Data "hubSpawned") -DeliverTo @(Get-HordeNodeDataList $Data "deliverTo" | ForEach-Object { "$_" })
    if ($target.refused -ne "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason $target.refused)) }
    $said = Get-HordeLinkProp $Data "deliverResult"
    if ($null -eq $said) { return (New-HordeNodeReply -NeedDeliver ([pscustomobject]@{ target = $target; message = $a })) }
    if ("$(Get-HordeLinkProp $said 'state')" -cne "known") {
        return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer (ConvertTo-HordeNodeAnswer -Answer $said -Unknown "the messenger did not say whether it took the message")))
    }
    $d = New-HordeNodeDelivery -MessageId $id -SessionId $target.sessionId -Reported (Get-HordeLinkProp $said "value") -Contract $State.contract
    if ($null -eq $d) { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = "the messenger reported a stage the link does not know" }))) }
    $answer = New-HordeKnown -Value ([pscustomobject]$d) -ObservedAt ([datetime]::UtcNow)
    $open = Open-HordeJournalEntry -Root $jr -Id $id -Verb "session.deliver" -Arguments $a -IssuedAt $issued
    if ($open.decision -ceq "act") { $null = Complete-HordeJournalEntry -Root $jr -Id $id -State "done" -Result $answer }
    elseif ($open.decision -ceq "replay") { $answer = $open.result }
    elseif ($open.decision -ceq "refuse") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason $open.reason)) }
    return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer (ConvertTo-HordeNodeAnswer -Answer $answer)))
}

function Invoke-HordeNodeDeliveryStatus {
    # delivery.status: the message journal says whether, and to which session, this node delivered the
    # message; the messenger says where it is now (NeedStatus). A messenger that cannot say is unknown,
    # naming the last stage the journal recorded.
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Request, [Parameter(Mandatory = $true)]$Data)
    $f = $Request
    $id = "$($f.args.messageId)"
    $now = Get-HordeLinkTime
    $jr = "$(Get-HordeLinkProp $Data 'messageJournalRoot')"
    if ($jr -eq "") { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = "this node keeps no message journal" }))) }
    $prior = Get-HordeJournalEntry -Root $jr -Id $id
    if ($prior.state -ceq "absent") { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "absent"; reason = "this node never accepted that message"; observedAt = $now }))) }
    if ($prior.state -cne "known" -or $null -eq $prior.value.result -or "$($prior.value.result.state)" -cne "known") {
        return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = "the node's message journal could not say; its own reason is kept on the node" })))
    }
    $recorded = $prior.value.result.value
    $said = Get-HordeLinkProp $Data "deliveryStatus"
    if ($null -eq $said) { return (New-HordeNodeReply -NeedStatus $id) }
    if ("$(Get-HordeLinkProp $said 'state')" -ceq "known") {
        $d = New-HordeNodeDelivery -MessageId $id -SessionId "$($recorded.sessionId)" -Reported (Get-HordeLinkProp $said "value") -Contract $State.contract
        if ($null -ne $d) { return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "known"; value = $d; reason = ""; observedAt = $now }))) }
    }
    $why = "$(Get-HordeLinkProp $said 'reason')"
    if ($why.Trim() -eq "") { $why = "the messenger gave no stage the link knows" }
    return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "unknown"; reason = (Limit-HordeNodeReason ("the messenger could not say where the message is (" + $why + "); last stage recorded: " + $recorded.stage)) })))
}

function Get-HordeNodeReadOnlyRefusal {
    # The refusal a read-only node gives -Verb, or $null when the node is not read-only or the verb is a
    # read. The effect class comes from remote/Contract.ps1's pinned table, so a verb added later is
    # judged by it too; a verb the table does not class is not a read (review of #112, B1).
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Frame, [Parameter(Mandatory = $true)]$Data, [Parameter(Mandatory = $true)][string]$Verb)
    if ((Get-HordeLinkProp $Data "readOnly") -eq $true) {
        $effect = "unclassed"
        if ($script:HordeLinkVerbAllow.ContainsKey($Verb)) { $effect = "$($script:HordeLinkVerbAllow[$Verb].effect)" }
        if ($effect -cne "read") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $Frame -Code "refused" -Reason ("this node serves read verbs only (horde node serve -ReadOnly); " + $Verb + " is a " + $effect + " verb"))) }
    }
    return $null
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
        # The hub this link serves, handed with every act: a session is closed only by the hub that
        # asked for it (review of #104, F8).
        $State.peerId = "$($f.hello.id)"
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
    if ($script:HordeNodeActVerbs -ccontains $verb -and (Get-HordeLinkProp $Data "acts") -eq $true) {
        # READ-ONLY DECIDES BEFORE ANY ACT (R17c, 2026-10-07): handed both an act and -ReadOnly, the node
        # acted - the check below came after this dispatch. horde node serve drops the act under -ReadOnly,
        # but a dialled link is the always-on box's production path, and the flag, not what was passed,
        # must decide (as it does for messaging).
        $roAct = Get-HordeNodeReadOnlyRefusal -State $State -Frame $f -Data $Data -Verb $verb
        if ($null -ne $roAct) { return $roAct }
        return (Invoke-HordeNodeAct -State $State -Frame $f -Data $Data)
    }
    if ($script:HordeNodeServedVerbs -cnotcontains $verb) { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "unsupported-verb" -Reason ("this node answers " + ($script:HordeNodeServedVerbs -join ", ") + "; '" + $verb + "' is not one of them"))) }
    # A READ-ONLY NODE ANSWERS READS AND NOTHING ELSE (review of #112, B1). The verb's effect class is read
    # from remote/Contract.ps1's pinned table, not from a list of names here, so a write, drive, spawn or
    # kill verb added later is refused too; a verb the table does not class is not a read.
    $ro = Get-HordeNodeReadOnlyRefusal -State $State -Frame $f -Data $Data -Verb $verb
    if ($null -ne $ro) { return $ro }
    if ($script:HordeNodeViewVerbs -ccontains $verb) {
        if ("$($Data.viewError)" -ne "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "internal" -Reason ("the node could not build its view of its sessions: " + $Data.viewError))) }
        if ($null -eq $Data.view) { return (New-HordeNodeReply -NeedView $true) }
    }
    if ($script:HordeNodeOutboxVerbs -ccontains $verb) {
        $why = "$(Get-HordeLinkProp $Data 'outboxError')"
        if ($why -ne "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "internal" -Reason ("the node could not read its outbox: " + $why))) }
        if (-not (Test-HordeNodeDataGiven $Data "outbox")) { return (New-HordeNodeReply -NeedOutbox $true) }
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
            # A session the node left out because its end is proven (core/Projection.ps1,
            # ConvertTo-HordeNodeViewDocument) is absent with that proof: its control file is still on
            # disk, so "no store holds it" would be false (review of PR #240).
            foreach ($e in @(Get-HordeLinkProp $Data.view "endedSessions")) {
                # Matched as the sessions above are: the id exactly, and the agent when one is named.
                if ($null -eq $e -or "$(Get-HordeLinkProp $e 'sessionId')" -cne $want) { continue }
                if ($wantAgent -ne "" -and "$(Get-HordeLinkProp $e 'agent')" -cne $wantAgent) { continue }
                return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "absent"; reason = (Limit-HordeNodeReason ("session " + $want + " has ended, proven by its process: " + (Get-HordeLinkProp $e "reason"))); observedAt = $at })))
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
        "session.deliver" { return (Invoke-HordeNodeDeliver -State $State -Request $f -Data $Data) }
        "delivery.status" { return (Invoke-HordeNodeDeliveryStatus -State $State -Request $f -Data $Data) }
        "mail.next" {
            $pick = Select-HordeMailNext -Outbox @(Get-HordeNodeDataList $Data "outbox")
            $value = [ordered]@{ pending = $pick.pending }
            $write = $null
            if ($null -ne $pick.next) {
                $value["mail"] = $pick.next.mail
                # HANDED OUT BEFORE IT IS SENT: a receipt for this message is accepted only once the
                # record says mail.next returned it, so the caller writes that first.
                if (-not $pick.next.handedOut) { $write = [pscustomobject]@{ messageId = "$($pick.next.messageId)"; marker = "handed"; at = $now } }
            }
            return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "known"; value = $value; reason = ""; observedAt = $now })) -Write $write)
        }
        "mail.receipt" {
            $id = "$($f.args.messageId)"
            $rec = Find-HordeNodeOutboxRecord -Outbox @(Get-HordeNodeDataList $Data "outbox") -MessageId $id
            $recorded = ""
            if ($null -ne $rec -and $rec.handedOut) { $recorded = "$($rec.stage)" }
            $r = Resolve-HordeMailReceipt -Recorded $recorded -Asked "$($f.args.stage)"
            if ($r.refused -ne "") { return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "refused" -Reason ("message " + $id + ": " + $r.refused))) }
            $write = $null
            $at = "$($rec.recordedAt)"
            if ($r.changed) { $at = $now; $write = [pscustomobject]@{ messageId = $id; marker = $r.stage; at = $now } }
            if ($at -cnotmatch $script:HordeNodeTimePattern) { $at = $now }
            $ack = [ordered]@{ messageId = $id; stage = $r.stage; recordedAt = $at }
            return (New-HordeNodeReply -Reply (New-HordeNodeResult -State $State -Request $f -Answer ([ordered]@{ state = "known"; value = $ack; reason = ""; observedAt = $now })) -Write $write)
        }
    }
    return (New-HordeNodeReply -Reply (New-HordeNodeError -State $State -Request $f -Code "internal" -Reason ("no answer was built for '" + $verb + "'")))
}
