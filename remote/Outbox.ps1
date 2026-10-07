# remote/Outbox.ps1 - the node's outbox: mail an orc on this node wrote to an orc elsewhere.
#
# WHY (plan step R21, slice 4). The reverse path of messaging is a pull: the message waits here, the hub
# takes it with mail.next and says how its delivery went with mail.receipt. Slice 5's `horde tell` puts a
# message here; remote/NodeServe.ps1 reads the outbox and asks its caller to mark it.
#
# NOTHING IS REWRITTEN. A message is one file, <messageId>.json, created with CreateNew, so two writers of
# one id give one message and a second write is refused, never an overwrite. Every change after that is
# another file created the same way - a MARKER, <messageId>.<marker>.json: "handed" when mail.next has
# returned it, and one per receipt stage the hub reports. remote/ may not move or replace a file
# (tools/ExecScan.ps1), and an append-only record needs neither: a torn write leaves at most one torn
# marker, never a torn message.
#
# THE STAGE IS THE RULES', NOT THIS FILE'S. Which stage a record holds is decided from its markers by
# remote/Messaging.ps1's Select-HordeMailRecordedStage - the receipt rule replayed - so a late or racing
# marker can never move a message backwards or off a final stage. Which message comes next is
# Select-HordeMailNext's. This file only reads and writes.
#
# WHAT IS REFUSED AT THE DOOR: a message the link could not carry (checked against link-verbs v1's
# outbound-mail, the ttl ceiling and the summaryBytes cap), so a bad message can never sit at the head
# of the queue failing every mail.next. The root is a parameter (<HordeHome>\node\outbox in production);
# a folder that was never made an outbox is unknown, never an empty outbox (as remote/Journal.ps1).
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

. (Join-Path $PSScriptRoot "Journal.ps1")
. (Join-Path $PSScriptRoot "Protocol.ps1")
. (Join-Path $PSScriptRoot "Messaging.ps1")

$script:HordeOutboxMarkerFile = "outbox.json"
$script:HordeOutboxHanded = "handed"
$script:HordeOutboxContract = $null

function Get-HordeOutboxContract {
    # Read once per process: Get-HordeLinkContract parses both link schemas (about 1.4 s, NodeServe.ps1).
    if ($null -eq $script:HordeOutboxContract) { $script:HordeOutboxContract = Get-HordeLinkContract }
    return $script:HordeOutboxContract
}

function Get-HordeOutboxMarkers {
    # The marker names a record may carry: handed, and every receipt stage (remote/Messaging.ps1's).
    return @(@($script:HordeOutboxHanded) + @(Get-HordeMailReceiptStages))
}

function Test-HordeOutboxRoot {
    param([string]$Root)
    if ("$Root".Trim() -eq "") { return "no outbox root was given" }
    $m = Read-HordeJournalFile -Path (Join-Path $Root $script:HordeOutboxMarkerFile)
    if ($m.kind -ne "ok" -or "$(Get-HordeJournalProp $m.data 'kind')" -cne "outbox") { return ("'" + $Root + "' is not an outbox (no " + $script:HordeOutboxMarkerFile + "); that is unknown, not an empty outbox") }
    return ""
}

function Initialize-HordeOutbox {
    # Make -Root an outbox: its folder, and its marker once. Again is harmless.
    param([Parameter(Mandatory = $true)][string]$Root)
    $null = Resolve-HordeJournalPath -Root $Root -Name $script:HordeOutboxMarkerFile
    [void][System.IO.Directory]::CreateDirectory($Root)
    $null = New-HordeJournalFile -Root $Root -Name $script:HordeOutboxMarkerFile -Text '{"v":1,"kind":"outbox"}'
    return $Root
}

function New-HordeOutboxMail {
    # Put one outbound message in the outbox. A tristate answer: known with the record, or unknown with
    # the reason it was refused (the link could not carry it, its id is taken, the root is not an outbox).
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)]$Mail)
    $bad = Test-HordeOutboxRoot -Root $Root
    if ($bad -ne "") { return (New-HordeUnknown -Reason $bad) }
    $id = "$(Get-HordeLinkProp $Mail 'messageId')"
    if ($id -cnotmatch $script:HordeJournalIdPattern) { return (New-HordeUnknown -Reason ("'" + $id + "' is not a message id: an id is one lowercase UUID")) }
    $m = ($Mail | ConvertTo-Json -Depth 20) | ConvertFrom-Json
    $contract = Get-HordeOutboxContract
    $walk = Get-HordeLinkWalkTarget -Contract $contract -Target "#/definitions/outbound-mail" -Path '$.mail'
    $found = @(Test-HordeLinkValue -Value $m -Walk $walk -Path '$.mail')
    if ($found.Count -eq 0) { $found = @(Test-HordeLinkTtlCeiling -Value $m -Path '$.mail') }
    if ($found.Count -eq 0 -and (Measure-HordeWireString "$($m.body)") -gt $contract.limits.summaryBytes) { $found = @("the body is over the " + $contract.limits.summaryBytes + "-byte cap a result string may hold") }
    if ($found.Count -gt 0) { return (New-HordeUnknown -Reason ("not put in the outbox, because the link could not carry it: " + ($found -join "; "))) }
    $text = ([ordered]@{ v = 1; mail = $m } | ConvertTo-Json -Depth 20 -Compress)
    $made = New-HordeJournalFile -Root $Root -Name ($id + ".json") -Text $text
    if ($made -eq "exists") { return (New-HordeUnknown -Reason ("message " + $id + " is already in the outbox; a message is written once")) }
    return (New-HordeKnown -Value $m -ObservedAt ([datetime]::UtcNow))
}

function Add-HordeOutboxMarker {
    # Record one marker on a message: handed, or a receipt stage. Written once; a marker already there is
    # left as it is and answered known. Which stage the record then holds is the rules' (see the header).
    param([Parameter(Mandatory = $true)][string]$Root, [string]$MessageId, [string]$Marker, [Parameter(Mandatory = $true)][string]$At)
    $bad = Test-HordeOutboxRoot -Root $Root
    if ($bad -ne "") { return (New-HordeUnknown -Reason $bad) }
    if ($MessageId -cnotmatch $script:HordeJournalIdPattern) { return (New-HordeUnknown -Reason ("'" + $MessageId + "' is not a message id")) }
    if ((Get-HordeOutboxMarkers) -cnotcontains $Marker) { return (New-HordeUnknown -Reason ("'" + $Marker + "' is not a marker an outbox record carries")) }
    $rec = Read-HordeJournalFile -Path (Resolve-HordeJournalPath -Root $Root -Name ($MessageId + ".json"))
    if ($rec.kind -ne "ok") { return (New-HordeUnknown -Reason ("the outbox holds no message " + $MessageId)) }
    $text = ([ordered]@{ v = 1; marker = $Marker; at = $At } | ConvertTo-Json -Compress)
    $null = New-HordeJournalFile -Root $Root -Name ($MessageId + "." + $Marker + ".json") -Text $text
    return (New-HordeKnown -Value $Marker -ObservedAt ([datetime]::UtcNow))
}

function Get-HordeOutbox {
    # Every message in the outbox: { messageId; mail; createdAt; handedOut; stage; recordedAt }, the stage
    # and when it was recorded decided by Select-HordeMailRecordedStage from the record's markers. A
    # tristate answer; a message whose file cannot be read is left out and named in the note.
    param([Parameter(Mandatory = $true)][string]$Root)
    $bad = Test-HordeOutboxRoot -Root $Root
    if ($bad -ne "") { return (New-HordeUnknown -Reason $bad) }
    $markerNames = @(Get-HordeOutboxMarkers)
    $records = @{}
    $marks = @{}
    $unread = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $Root -File -Filter "*.json")) {
        $name = "$($f.Name)"
        if ($name -ceq $script:HordeOutboxMarkerFile) { continue }
        $parts = $name.Split(".")
        if ($parts.Count -lt 2 -or $parts[0] -cnotmatch $script:HordeJournalIdPattern) { continue }
        $id = $parts[0]
        $got = Read-HordeJournalFile -Path $f.FullName
        if ($parts.Count -eq 2) {
            if ($got.kind -ne "ok") { [void]$unread.Add($id + " (" + $got.kind + ")"); continue }
            $records[$id] = Get-HordeJournalProp $got.data "mail"
            continue
        }
        if ($parts.Count -ne 3 -or $markerNames -cnotcontains $parts[1] -or $got.kind -ne "ok") { continue }
        if (-not $marks.ContainsKey($id)) { $marks[$id] = New-Object System.Collections.ArrayList }
        [void]$marks[$id].Add([pscustomobject]@{ marker = $parts[1]; at = "$(Get-HordeJournalProp $got.data 'at')" })
    }
    $out = New-Object System.Collections.ArrayList
    foreach ($id in @($records.Keys)) {
        $mine = @()
        if ($marks.ContainsKey($id)) { $mine = @($marks[$id]) }
        $handed = @($mine | Where-Object { $_.marker -ceq $script:HordeOutboxHanded }).Count -gt 0
        $stages = @($mine | Where-Object { $_.marker -cne $script:HordeOutboxHanded } | ForEach-Object { [pscustomobject]@{ stage = $_.marker; at = $_.at } })
        $held = Select-HordeMailRecordedStage -Markers $stages
        $mail = $records[$id]
        [void]$out.Add([pscustomobject]@{ messageId = $id; mail = $mail; createdAt = "$(Get-HordeLinkProp $mail 'createdAt')"; handedOut = $handed; stage = $held.stage; recordedAt = $held.at })
    }
    $note = ""
    if ($unread.Count -gt 0) { $note = "left out, unreadable: " + ($unread.ToArray() -join ", ") }
    $answer = New-HordeKnown -Value $out.ToArray() -ObservedAt ([datetime]::UtcNow)
    $answer | Add-Member -NotePropertyName unreadable -NotePropertyValue $note -Force
    return $answer
}
