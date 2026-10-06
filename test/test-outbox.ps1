# IS THE NODE'S OUTBOX A STORE THAT LOSES NOTHING, WRITES EACH THING ONCE, AND NEVER MOVES A MESSAGE BACKWARDS?
#
# Remote plan step R21, slice 4. remote/Outbox.ps1 keeps the mail orcs on this node write to orcs
# elsewhere (slice 5's `horde tell` puts it there; mail.next and mail.receipt read and mark it). Each
# message is one file created with CreateNew, and every change to it is another file created the same
# way - a marker - so nothing is ever rewritten in place and two writers cannot tear a record. The stage a
# record holds is decided from its markers by remote/Messaging.ps1's rule, never here.
# Every file lives under a temp root that is removed at the end.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "remote\Outbox.ps1")

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-outbox-" + [guid]::NewGuid().ToString("N"))
$box = Join-Path $tmp "outbox"
$device = "0f8fad5b-d9cb-469f-a165-70867728950e"
function Mail {
    param([string]$Id, [string]$Body = "the box finished batch 7", [int]$Ttl = 86400)
    return [pscustomobject][ordered]@{ messageId = $Id; from = [pscustomobject][ordered]@{ deviceId = $device; sessionId = "cccccccc-0000-4000-8000-000000000001"; label = "A" }; to = [pscustomobject][ordered]@{ label = "M" }; body = $Body; createdAt = "2026-10-05T12:00:00.000Z"; ttlSeconds = $Ttl }
}
function Rec { param([string]$Id) $all = Get-HordeOutbox -Root $box; return @($all.value | Where-Object { "$($_.messageId)" -ceq $Id })[0] }
$id1 = "0e000000-0000-4000-8000-000000000201"

try {
Write-Host ""
Write-Host "--- a folder is an outbox only once it is made one ---" -ForegroundColor Cyan
$g = Get-HordeOutbox -Root $box
Check ($g.state -ceq "unknown" -and "$($g.reason)" -clike "*not an outbox*") "a folder that was never made an outbox is unknown, never an empty outbox"
$null = Initialize-HordeOutbox -Root $box
$null = Initialize-HordeOutbox -Root $box
$g = Get-HordeOutbox -Root $box
Check ($g.state -ceq "known" -and @($g.value).Count -eq 0) "once made one, and made again harmlessly, it is known and empty"

Write-Host ""
Write-Host "--- one message, once ---" -ForegroundColor Cyan
$n = New-HordeOutboxMail -Root $box -Mail (Mail $id1)
Check ($n.state -ceq "known") "a message is put in the outbox"
$r = Rec $id1
Check ($null -ne $r -and "$($r.stage)" -ceq "queued" -and $r.handedOut -eq $false -and "$($r.mail.body)" -ceq "the box finished batch 7") "it is read back queued, not handed out, with its body"
$n = New-HordeOutboxMail -Root $box -Mail (Mail $id1 -Body "a second body under the same id")
Check ($n.state -ceq "unknown" -and "$($n.reason)" -clike "*already*") "the same messageId again is refused, never overwritten"
Check ("$((Rec $id1).mail.body)" -ceq "the box finished batch 7") "and the first message stands"
$bad = Mail "0e000000-0000-4000-8000-000000000202"
$bad.to | Add-Member -NotePropertyName pane -NotePropertyValue 4
$n = New-HordeOutboxMail -Root $box -Mail $bad
Check ($n.state -ceq "unknown" -and "$($n.reason)" -clike "*pane*" -and $null -eq (Rec "0e000000-0000-4000-8000-000000000202")) "a message the link could not carry (addressed by pane) is refused, and nothing is written"
$n = New-HordeOutboxMail -Root $box -Mail (Mail "0e000000-0000-4000-8000-000000000203" -Ttl 604801)
Check ($n.state -ceq "unknown" -and "$($n.reason)" -clike "*604800-second ceiling*") "a message living longer than 7 days is refused"
$n = New-HordeOutboxMail -Root $box -Mail (Mail "..\..\escape")
Check ($n.state -ceq "unknown" -and @(Get-ChildItem -LiteralPath $tmp -Filter "escape*" -Recurse -ErrorAction SilentlyContinue).Count -eq 0) "a messageId that is not a uuid is refused, and no file leaves the outbox"

Write-Host ""
Write-Host "--- markers: written once each, and the stage decided by the receipt rule ---" -ForegroundColor Cyan
$m = Add-HordeOutboxMarker -Root $box -MessageId "0e000000-0000-4000-8000-0000000002ff" -Marker "handed" -At "2026-10-05T12:00:01.000Z"
Check ($m.state -ceq "unknown" -and "$($m.reason)" -clike "*no message*") "a marker for a message the outbox does not hold is refused"
$m = Add-HordeOutboxMarker -Root $box -MessageId $id1 -Marker "delivered" -At "2026-10-05T12:00:01.000Z"
Check ($m.state -ceq "unknown" -and "$($m.reason)" -clike "*not a marker*") "a marker that is no stage and not handed is refused"
$null = Add-HordeOutboxMarker -Root $box -MessageId $id1 -Marker "handed" -At "2026-10-05T12:00:01.000Z"
Check ((Rec $id1).handedOut -eq $true -and "$((Rec $id1).stage)" -ceq "queued") "the handed-out marker marks it handed out and leaves it queued"
$null = Add-HordeOutboxMarker -Root $box -MessageId $id1 -Marker "accepted" -At "2026-10-05T12:00:02.000Z"
$null = Add-HordeOutboxMarker -Root $box -MessageId $id1 -Marker "seen" -At "2026-10-05T12:00:03.000Z"
$r = Rec $id1
Check ("$($r.stage)" -ceq "seen" -and "$($r.recordedAt)" -ceq "2026-10-05T12:00:03.000Z") "accepted then seen: the record holds seen, recorded when seen was"
$m = Add-HordeOutboxMarker -Root $box -MessageId $id1 -Marker "accepted" -At "2026-10-05T12:00:04.000Z"
Check ($m.state -ceq "known" -and "$((Rec $id1).stage)" -ceq "seen") "a second marker of a stage already written changes nothing: seen stands"
$null = Add-HordeOutboxMarker -Root $box -MessageId $id1 -Marker "refused" -At "2026-10-05T12:00:05.000Z"
Check ("$((Rec $id1).stage)" -ceq "seen") "a late final marker from a race does not overwrite the first final stage"
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $tmp)) "the temp root is gone"

Complete-HordeSuite -Success "the outbox writes each message and each marker once, refuses what the link could not carry, and holds the stage the receipt rule decides"
