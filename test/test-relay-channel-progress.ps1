# DOES THE FOUNDER'S PHONE GET THE FLEET'S PROGRESS LOG - EVERY WHOLE, WELL-FORMED ENTRY ONCE, IN THE
# ORDER IT WAS WRITTEN, SEALED TO HIS TRUSTED PHONE KEYS ONLY - AND NOTHING GUESSED, NOTHING SENT TWICE,
# AND NOTHING STARTED OVER BEHIND HIS BACK?
#
# The progress channel (channels/progress; the founder asked for it, 2026-10-12), over relays/local in
# this process, with a phone held in memory (test/lib/RelayPhone.ps1) and a changelog of the suite's own,
# written in the shape the fleet's is. It attacks:
#   - a missing file is "nothing yet"; the first look sends only the newest entries, then only what is new;
#   - the file's order is kept though a later line carries an earlier time;
#   - a last line not yet finished is left until it is whole; a line that does not hold together (not
#     JSON, a member repeated or missing, a wrong version, a title or text too long, a time with no zone,
#     bytes that are not UTF-8, a secret, a line of 70,000 bytes) is left out and named by its number,
#     and the phone is told how many; a kind off the list is a note; an unknown member is ignored;
#   - an id an earlier line carried is left out; 500 entries go in pages, each within its size, each once;
#   - an entry no page of this relay can hold is left out, never cut;
#   - the place in the file survives a restart; an envelope recorded and not put is put again, the same;
#   - a phone key trusted later gets the newest entries alone; a revoked one gets nothing more, and an
#     envelope recorded for it before the revocation is never put;
#   - a file cut short, replaced, rewritten, gone, or another by the setting stops the channel, said once
#     here and to the phone, with nothing sent again; put back, it goes on; the state file deleted, it
#     starts over from the new file;
#   - nothing comes in on the channel; a damaged state or refused settings stop it in words.
# The end to end, with the phone app and the real horde command, is surfaces/pwa/test/test-pwa-phone-e2e.ps1.
#
# NO REAL FLEET IS TOUCHED. The fleet root is pointed at an empty folder of the suite's own before any
# channel loads (test/lib/FleetPin.ps1); every home and every changelog is the suite's own under %TEMP%.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "test\lib\FleetPin.ps1")
$fleetPin = Enter-HordeTestEmptyFleet
. (Join-Path $root "core\ModuleSettings.ps1")
. (Join-Path $root "channels\Port.ps1")
foreach ($f in @(Get-HordeRelayFiles)) { . $f }
foreach ($f in @(Get-HordeRelayChannelFiles)) { . $f }
. (Join-Path $root "cli\RelayRun.ps1")
. (Join-Path $root "test\lib\RelayPhone.ps1")
Set-StrictMode -Version Latest
Write-Host ("  runtime: PowerShell " + $PSVersionTable.PSVersion + " (" + $PSVersionTable.PSEdition + ")") -ForegroundColor DarkGray

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:homes = New-Object System.Collections.ArrayList
$script:worlds = New-Object System.Collections.ArrayList
$realHome = $env:HORDE_HOME

if ((Get-HordeRelayKeyStore).state -cne "known") {
    Check ($true) "CONTROL: the suite reached its skip honestly"
    Complete-HordeSuite -Success "no key store here: no machine identity can be made, so nothing was run" -PassCode 3
}

function ConvertTo-TestJson {
    # A JSON string in printable ASCII, as the changelog's writer escapes it.
    param([AllowEmptyString()][string]$Text)
    return ('"' + [regex]::Replace($Text, '[^\x20\x21\x23-\x5B\x5D-\x7E]', { param($m) '\u' + ([int][char]$m.Value).ToString("x4") }) + '"')
}
function New-Line {
    # One entry's line, in the changelog's shape. -Extra: raw JSON members to add; -Without: members to leave out.
    param([string]$Id, [string]$Title = "A title", [string]$Text = "Happened: a thing.", [string]$Ts = "2026-10-12T18:15:00Z", [string]$Kind = "progress", [string]$Area = "Form fill", [string]$Extra = "", [string[]]$Without = @(), [int]$V = 1)
    $parts = New-Object System.Collections.ArrayList
    if ($Without -cnotcontains "v") { [void]$parts.Add('"v":' + $V) }
    if ($Without -cnotcontains "id") { [void]$parts.Add('"id":' + (ConvertTo-TestJson $Id)) }
    if ($Without -cnotcontains "ts") { [void]$parts.Add('"ts":' + (ConvertTo-TestJson $Ts)) }
    if ($Without -cnotcontains "kind") { [void]$parts.Add('"kind":' + (ConvertTo-TestJson $Kind)) }
    if ($Without -cnotcontains "area") { [void]$parts.Add('"area":' + (ConvertTo-TestJson $Area)) }
    if ($Without -cnotcontains "title") { [void]$parts.Add('"title":' + (ConvertTo-TestJson $Title)) }
    if ($Without -cnotcontains "text") { [void]$parts.Add('"text":' + (ConvertTo-TestJson $Text)) }
    if ($Extra -cne "") { [void]$parts.Add($Extra) }
    return ("{" + ($parts -join ",") + "}")
}
function Add-Bytes {
    # Bytes appended to a world's changelog, as its writer appends them.
    param($World, [byte[]]$Bytes)
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $World.file))
    $fs = New-Object System.IO.FileStream -ArgumentList $World.file, ([System.IO.FileMode]::Append), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::ReadWrite)
    try { $fs.Write($Bytes, 0, $Bytes.Length) } finally { $fs.Dispose() }
}
function Add-Lines { param($World, [string[]]$Lines) Add-Bytes $World ($utf8.GetBytes((($Lines | ForEach-Object { $_ + "`n" }) -join ""))) }
function New-TestHome {
    param([string]$Settings)
    $h = Join-Path $env:TEMP ("horde-relay-progress-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $h "settings") -Force | Out-Null
    [void]$script:homes.Add($h)
    [System.IO.File]::WriteAllText((Join-Path $h "settings\relay.json"), '{"schemaVersion": 1, "settings": {"horde": "work"}}', $utf8)
    return $h
}
function Set-ProgressSettings {
    param($World, [string]$Settings)
    $t = $Settings.Replace("@FILE@", $World.file.Replace("\", "\\"))
    [System.IO.File]::WriteAllText((Join-Path $World.home "settings\relay-progress.json"), ('{"schemaVersion": 1, "settings": ' + $t + '}'), $utf8)
}
function Set-ProgressSettingsText { param($World, [string]$Json) [System.IO.File]::WriteAllText((Join-Path $World.home "settings\relay-progress.json"), ('{"schemaVersion": 1, "settings": ' + $Json + '}'), $utf8) }
function Add-PhoneKey {
    param([string]$HordeHome, $Phone)
    $v = New-HordeTestPhoneVouch -Phone $Phone -Horde "work"
    $k = Add-HordeRelayPhoneKey -HordeHome $HordeHome -AgreePublic $Phone.agreePublic -By $Phone.keyId -AuthenticatorData $v.authenticatorData -ClientDataJson $v.clientDataJson -Signature $v.signature
    if ($k.state -cne "known") { throw ("no phone key: " + $k.reason) }
}
function New-World {
    # A machine with its identity, a phone paired, confirmed and its key trusted, a local relay, a run
    # context, and a changelog path of its own (not yet a file). -DefaultFile: no progressFile setting, so
    # the changelog is the one under the home.
    param([switch]$NoPhoneKey, [switch]$DefaultFile, [string]$Settings = '{"sendIntervalMs": 0, "backfillEntries": 3, "progressFile": "@FILE@"}')
    $h = New-TestHome
    $env:HORDE_HOME = $h
    $id = New-HordeRelayMachineIdentity -HordeHome $h -Provider "software"
    if ($id.state -cne "known") { throw ("no identity: " + $id.reason) }
    $phone = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $h -Phone $phone)
    if (-not $NoPhoneKey) { Add-PhoneKey -HordeHome $h -Phone $phone }
    $c = Connect-HordeRelay -Name "local" -Options @{ root = (Join-Path $h "relay-mailboxes") }
    if ($c.state -cne "known") { throw ("no relay: " + $c.reason) }
    $ctx = New-HordeRelayRunContext -HordeHome $h -Connection $c.value
    if ($ctx.state -cne "known") { throw ("no context: " + $ctx.reason) }
    $file = $(if ($DefaultFile) { Join-Path $h "progress\changelog.jsonl" } else { Join-Path $h "analyst\progress\changelog.jsonl" })
    $w = [pscustomobject]@{ home = $h; id = $id.value; phone = $phone; conn = $c.value; ctx = $ctx.value; agree = @(, ([byte[]]$id.value.agree.public)); seen = 0; file = $file; state = (Join-Path $h "relay\progress\state.json") }
    if ($DefaultFile) { [System.IO.File]::WriteAllText((Join-Path $h "settings\relay-progress.json"), '{"schemaVersion": 1, "settings": {"sendIntervalMs": 0, "backfillEntries": 3}}', $utf8) }
    else { Set-ProgressSettings $w $Settings }
    [void]$script:worlds.Add($w)
    return $w
}
function Invoke-Tick { param($World) $env:HORDE_HOME = $World.home; return (Invoke-HordeProgressChannelTick -Context $World.ctx) }
function Restart-World {
    param($World)
    Close-HordeRelayRunContext -Context $World.ctx
    $World.ctx = (New-HordeRelayRunContext -HordeHome $World.home -Connection $World.conn).value
}
function Get-PhoneItems {
    param($World)
    $r = Receive-HordeRelayItems -Connection $World.conn -Mailbox "work/phone" -Since 0
    if ($r.state -cne "known") { return @() }
    return @($r.value.items)
}
function Get-NewMail {
    # What the phone opens of the items after the last look, as { header; body; to; length }. -Phone opens
    # as another phone; -All looks at every item. Items it cannot open have no body.
    param($World, $Phone = $null, [switch]$All)
    if ($null -eq $Phone) { $Phone = $World.phone }
    $items = @(Get-PhoneItems $World | Where-Object { $All -or $_.seq -gt $World.seen })
    if (-not $All -and $items.Count -gt 0) { $World.seen = ($items | ForEach-Object { [long]$_.seq } | Measure-Object -Maximum).Maximum }
    $out = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
        $r = Read-HordeRelayEnvelope -Text $it.text
        $hdr = $r.value.header
        $machine = New-HordeRelaySender -Public $World.id.sign.public -Proof "es256"
        $verdict = New-HordeKnown -Value ([pscustomobject]@{ key = (Get-HordeRelayReplayKey -Header $hdr); fresh = $true })
        $o = Unprotect-HordeRelayEnvelope -Envelope $r.value -Senders @{ ($machine.keyId) = $machine } -RecipientKeys @{ (Get-HordeRelayKeyId -Public $Phone.agreePublic) = $Phone.agree } -Replay $verdict -Channel $hdr.channel -Kind $hdr.kind
        if ($o.ok) { $raw = [System.Text.Encoding]::ASCII.GetString($o.value); [void]$out.Add([pscustomobject]@{ header = $hdr; body = ($raw | ConvertFrom-Json); raw = $raw; to = @($hdr.to); length = $o.value.Length }) }
        else { [void]$out.Add([pscustomobject]@{ header = $hdr; body = $null; raw = ""; to = @($hdr.to); length = 0 }) }
    }
    return @($out.ToArray())
}
function Get-Entries { param($Mail) return @($Mail | Where-Object { $null -ne $_.body -and $_.header.channel -ceq "progress" -and $_.body.kind -ceq "progress-entries" } | ForEach-Object { @($_.body.entries) }) }
function Get-Ids { param($Mail) return (@(Get-Entries $Mail | ForEach-Object { $_.id }) -join ",") }
function Get-Notices { param($Mail) return @($Mail | Where-Object { $null -ne $_.body -and $_.header.channel -ceq "progress" -and $_.body.kind -ceq "progress-notice" } | ForEach-Object { $_.body }) }
function Said { param($Tick) return (@($Tick.lines) -join " | ") }
function Get-FileMark { param([string]$Path) return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash + "/" + (Get-Item -LiteralPath $Path).LastWriteTimeUtc.Ticks) }

try {
    Write-Host ""
    Write-Host "--- 1. a missing file is nothing yet ---" -ForegroundColor Cyan
    $A = New-World -DefaultFile
    $t = Invoke-Tick $A
    $t2 = Invoke-Tick $A
    Check (@(Get-PhoneItems $A).Count -eq 0 -and -not $t.failed -and (Said $t) -like "*no progress yet*" -and @($t2.lines).Count -eq 0) ("with no changelog there is nothing to send: said once, not a failure, the relay not blamed (" + (Said $t) + ")")
    Check ((Said $t).Contains((Join-Path $A.home "progress\changelog.jsonl"))) "with no progressFile set, the file followed is progress\changelog.jsonl under Horde's own home - never a path of anyone's machine"
    Check (-not (Test-Path -LiteralPath $A.file) -and -not (Test-Path -LiteralPath (Split-Path -Parent $A.file))) "and the channel makes neither the file nor its folder: it only reads"

    Write-Host ""
    Write-Host "--- 2. the first look: the newest entries only, in the file's order, sealed to the trusted phone key ---" -ForegroundColor Cyan
    $four = "Asked: fix the ""ruled"" line \ box.`nHappened: PR 1605 merged " + [char]0x05E9 + [char]0x05DC + [char]0x05D5 + [char]0x05DD + ".`nMeans: text no longer touches ink.`nNext: the box path."
    Add-Lines $A @(
        (New-Line -Id "20261012T090000Z-01" -Title "one" -Ts "2026-10-12T09:00:00Z"),
        (New-Line -Id "20261012T100000Z-01" -Title "two" -Ts "2026-10-12T10:00:00Z" -Kind "started"),
        (New-Line -Id "20261012T110000Z-01" -Title "three" -Ts "2026-10-12T11:00:00Z" -Kind "decision" -Area "Whole fleet"),
        (New-Line -Id "20261012T181500Z-01" -Title "Ruled-line fix merged" -Text $four -Ts "2026-10-12T21:15:00+03:00" -Kind "merged" -Extra '"lane":"F","task":"T-0096"'),
        # Written last, about something that happened first: the file's order stands.
        (New-Line -Id "20261012T080000Z-01" -Title "five, which happened first" -Ts "2026-10-12T08:00:00Z" -Kind "result" -Without @("area"))
    )
    $fileMark = Get-FileMark $A.file
    $t = Invoke-Tick $A
    $mail = @(Get-NewMail $A)
    Check ($mail.Count -eq 1 -and $null -ne $mail[0].body -and $mail[0].header.channel -ceq "progress" -and $mail[0].header.kind -ceq "entries") ("one envelope of entries is put in the phone mailbox, on channel progress, and the phone opens it (" + (Said $t) + ")")
    Check ((Get-Ids $mail) -ceq "20261012T110000Z-01,20261012T181500Z-01,20261012T080000Z-01") ("from the end: the newest three of five, in the order they were written - the one that happened first still last (" + (Get-Ids $mail) + ")")
    $e = @(Get-Entries $mail)
    Check ($e.Count -eq 3 -and (@($e | ForEach-Object { $_.n }) -join ",") -ceq "3,4,5") "each carries its line number, which is the order the phone keeps"
    Check ($mail.Count -eq 1 -and $mail[0].body.backfill -eq $true -and $mail[0].body.machine -ceq $A.id.sign.keyId -and $mail[0].body.horde -ceq "work" -and $mail[0].body.v -eq 1) "the body is a backfill, naming this machine and the horde"
    Check ($mail.Count -eq 1 -and @($mail[0].to).Count -eq 1 -and $mail[0].to[0] -ceq (Get-HordeRelayKeyId -Public $A.phone.agreePublic)) "sealed to the one trusted phone key, and to nothing else"
    $m4 = @($e | Where-Object { $_.n -eq 4 })[0]
    Check ($m4.title -ceq "Ruled-line fix merged" -and $m4.text -ceq $four -and $m4.kind -ceq "merged" -and $m4.area -ceq "Form fill" -and $m4.lane -ceq "F" -and $m4.task -ceq "T-0096") "an entry arrives whole: its title, its four labelled lines with their line ends and non-ASCII words exact, its kind, area, lane and task"
    Check ($m4.ts -ceq "2026-10-12T18:15:00.000Z") ("its time is the same moment, written in one spelling (" + $m4.ts + ")")
    $m5 = @($e | Where-Object { $_.n -eq 5 })[0]
    Check ($null -eq $m5.PSObject.Properties["area"] -and $null -eq $m5.PSObject.Properties["lane"] -and $null -eq $m5.PSObject.Properties["corrects"]) "a label an entry does not carry is not sent as an empty one"
    Check ($mail[0].raw -cmatch '\A[\x20-\x7E]+\z') "the body is printable ASCII: every other character is an escape, so a byte is a character"

    Write-Host ""
    Write-Host "--- 3. then only what is new; nothing when nothing changed ---" -ForegroundColor Cyan
    $t = Invoke-Tick $A
    Check (@(Get-NewMail $A).Count -eq 0 -and @($t.lines).Count -eq 0) "no new line: nothing is sent, and nothing is said"
    Add-Lines $A @((New-Line -Id "n6" -Title "six" -Kind "waiting"), (New-Line -Id "n7" -Title "seven" -Kind "done"))
    $t = Invoke-Tick $A
    $mail = @(Get-NewMail $A)
    Check ((Get-Ids $mail) -ceq "n6,n7" -and $mail.Count -eq 1 -and $mail[0].body.backfill -eq $false -and (Said $t) -like "*2 progress entries in 1 envelope(s) sent*") ("two lines appended: exactly those two, not a backfill (" + (Said $t) + ")")

    # THE WRITER HOLDS THE FILE OPEN while the channel reads it: the channel shares it, and still reads.
    $writer = New-Object System.IO.FileStream -ArgumentList $A.file, ([System.IO.FileMode]::Append), ([System.IO.FileAccess]::Write), ([System.IO.FileShare]::ReadWrite)
    try {
        $wb = $utf8.GetBytes((New-Line -Id "n7b" -Title "written while held open") + "`n")
        $writer.Write($wb, 0, $wb.Length); $writer.Flush()
        $t = Invoke-Tick $A
    } finally { $writer.Dispose() }
    Check ((Get-Ids @(Get-NewMail $A)) -ceq "n7b") ("a line is read while its writer still holds the file open for writing (" + (Said $t) + ")")
    # THE RATE: lines written within the interval after a send wait, and go together.
    Set-ProgressSettingsText $A '{"sendIntervalMs": 600000, "backfillEntries": 3}'
    Add-Lines $A @((New-Line -Id "r1" -Title "rate one"), (New-Line -Id "r2" -Title "rate two"))
    $null = Invoke-Tick $A
    Check (@(Get-NewMail $A).Count -eq 0) "within the interval after a send, nothing is sent"
    Set-ProgressSettingsText $A '{"sendIntervalMs": 0, "backfillEntries": 3}'
    $null = Invoke-Tick $A
    $mail = @(Get-NewMail $A)
    Check ($mail.Count -eq 1 -and (Get-Ids $mail) -ceq "r1,r2") "past it, the lines written meanwhile go in one envelope"

    Write-Host ""
    Write-Host "--- 4. a last line not yet finished is left until it is whole ---" -ForegroundColor Cyan
    $whole = New-Line -Id "n8" -Title "eight, written in two goes" -Text "Happened: the writer was caught mid-line."
    $cutAt = [int]($whole.Length / 2)
    Add-Bytes $A ($utf8.GetBytes($whole.Substring(0, $cutAt)))
    $stateBefore = [System.IO.File]::ReadAllText($A.state)
    $t = Invoke-Tick $A
    $t2 = Invoke-Tick $A
    Check (@(Get-NewMail $A).Count -eq 0 -and @($t.lines).Count -eq 0 -and @($t2.lines).Count -eq 0 -and [System.IO.File]::ReadAllText($A.state) -ceq $stateBefore) "half a line with no line end: nothing is sent, nothing is said, and the place in the file does not move"
    Add-Bytes $A ($utf8.GetBytes($whole.Substring($cutAt) + "`n"))
    $t = Invoke-Tick $A
    $mail = @(Get-NewMail $A)
    $e = @(Get-Entries $mail)
    Check ($e.Count -eq 1 -and $e[0].id -ceq "n8" -and $e[0].n -eq 11 -and $e[0].title -ceq "eight, written in two goes" -and $e[0].text -ceq "Happened: the writer was caught mid-line.") "once its end is written, the line is sent whole, once"

    Write-Host ""
    Write-Host "--- 5. a line that does not hold together is left out and named by its number; the rest goes ---" -ForegroundColor Cyan
    $secretWord = "q8Wv3Lm9Zr4Xy7Kp2"
    # name = the line, and what the run must say of it.
    $badLines = [ordered]@{
        "not JSON" = @('{"v":1,"id":"b1","ts":"2026-10-12T18:15:00Z","title":"cut off', "it is not JSON")
        "a member twice" = @('{"v":1,"id":"b2","id":"b2-again","ts":"2026-10-12T18:15:00Z","title":"t","text":"x"}', "it has a member more than once")
        "no title" = @((New-Line -Id "b3" -Without @("title")), "it has no title")
        "no text" = @((New-Line -Id "b3b" -Without @("text")), "it has no text")
        "version 2" = @((New-Line -Id "b4" -V 2), "it is not version 1")
        "a title of 101 characters" = @((New-Line -Id "b5" -Title ("t" * 101)), "its title is 101 characters; a title holds 100")
        "a text of 2001 characters" = @((New-Line -Id "b6" -Text ("x" * 2001)), "its text is 2001 characters; a text holds 2000")
        "a time with no zone" = @((New-Line -Id "b7" -Ts "2026-10-12T18:15:00"), "its ts is not a time with a zone")
        "a time that is not one" = @((New-Line -Id "b7b" -Ts "yesterday"), "its ts is not a time with a zone")
        "a time in another spelling" = @((New-Line -Id "b7c" -Ts "2026-10-12 18:15:00Z"), "its ts is not a time with a zone")
        "a secret" = @((New-Line -Id "b8" -Text ("Happened: set token=" + $secretWord)), "it holds what looks like")
        "an id with a space" = @((New-Line -Id "b 9"), "its id is not")
        "ID in capitals" = @('{"v":1,"ID":"b10","ts":"2026-10-12T18:15:00Z","title":"t","text":"x"}', "it has no id")
        "an array" = @('[1,2,3]', "it is not a JSON object")
        "a title that is a number" = @('{"v":1,"id":"b11","ts":"2026-10-12T18:15:00Z","title":5,"text":"x"}', "its title is not words")
        "an area that is a list" = @((New-Line -Id "b12" -Without @("area") -Extra '"area":["a"]'), "its area is not")
        "a corrects that is not an id" = @((New-Line -Id "b13" -Extra '"corrects":"has space"'), "its corrects is not an entry's id")
        "a title with a line break" = @((New-Line -Id "b14" -Title "two`nlines"), "its title holds a control character")
        "a text with a bell in it" = @((New-Line -Id "b14b" -Text ("ring" + [char]7)), "its text holds a control character")
        "a title of spaces" = @((New-Line -Id "b14c" -Title "   "), "its title is not words")
    }
    $firstBad = 12
    Add-Lines $A @((New-Line -Id "g1" -Title "good before"))
    Add-Lines $A @($badLines.Values | ForEach-Object { $_[0] })
    # Bytes that are not UTF-8, a blank line, a line of 70,000 bytes, and a good one after them all.
    $notUtf8 = $utf8.GetBytes((New-Line -Id "b15" -Title "PLACE"))
    $at = [System.Text.Encoding]::ASCII.GetString($notUtf8).IndexOf("PLACE")
    $notUtf8[$at] = 0xFF
    Add-Bytes $A ([byte[]]($notUtf8 + [byte]10))
    Add-Bytes $A ([byte[]](10))
    Add-Lines $A @((New-Line -Id "b16" -Extra ('"pad":"' + ("p" * 70000) + '"')))
    Add-Lines $A @((New-Line -Id "g2" -Title "good after" -Kind "celebration" -Extra '"owner":"someone","pr":1605'), (New-Line -Id "g3" -Title "no kind at all" -Without @("kind")), ((New-Line -Id "g4" -Title "crlf ends") + "`r"), (New-Line -Id "g5" -Title "crlf inside" -Text "Asked: a`r`nNext: b"))
    $t = Invoke-Tick $A
    $mail = @(Get-NewMail $A)
    $said = Said $t
    Check ((Get-Ids $mail) -ceq "g1,g2,g3,g4,g5") ("the good lines around them are sent, and none of the others (" + (Get-Ids $mail) + ")")
    $n = $firstBad
    foreach ($name in @($badLines.Keys)) {
        $n++
        Check ($said.Contains("left out of the progress sent: line " + $n + ": " + $badLines[$name][1])) ("a line with " + $name + " is left out, named by its number, " + $n + ", and why: " + $badLines[$name][1])
    }
    $utfLine = $firstBad + $badLines.Count + 1
    Check ($said -cmatch ("line " + $utfLine + ": it is not UTF-8")) "so is a line whose bytes are not UTF-8"
    Check ($said -cmatch ("line " + ($utfLine + 2) + " is longer than 65536 bytes")) "and a line of 70,000 bytes; the blank line before it is passed over without a word, and still counted"
    Check (-not $said.Contains($secretWord) -and $said -like "*looks like*stays at the machine*") "the line with a secret is said by its number and what kind of thing it looks like - never the secret"
    Check (@($mail | Where-Object { $_.raw.Contains($secretWord) }).Count -eq 0) "and no envelope holds it"
    $g = @(Get-Entries $mail)
    Check ($g.Count -eq 5 -and $g[1].kind -ceq "note" -and $g[2].kind -ceq "note" -and $g[0].kind -ceq "progress") "a kind off the list, and no kind at all, are a note: the entry is never left out for its kind"
    Check ($g.Count -eq 5 -and $null -eq $g[1].PSObject.Properties["owner"] -and $null -eq $g[1].PSObject.Properties["pr"] -and $g[1].n -eq ($utfLine + 3)) "a member this code does not know is ignored, not sent on, and the entry still goes, under its own line number"
    Check ($g.Count -eq 5 -and $g[3].title -ceq "crlf ends" -and $g[3].text -ceq "Happened: a thing." -and $g[4].text -ceq "Asked: a`nNext: b") "a line ended CR LF is read as the line it is, and a CR LF inside a text is its line end"
    $notes = @(Get-Notices $mail)
    Check ($notes.Count -eq 1 -and $notes[0].code -ceq "lines-skipped" -and $notes[0].count -eq ($badLines.Count + 2) -and $notes[0].machine -ceq $A.id.sign.keyId) ("the phone is told how many lines were left out, so a gap is never silence (" + $(if ($notes.Count) { "" + $notes[0].count } else { "none" }) + " of " + ($badLines.Count + 2) + ")")
    $nineKinds = @("decision", "result", "merged", "blocked", "waiting", "started", "progress", "done", "note")
    Add-Lines $A @($nineKinds | ForEach-Object { New-Line -Id ("k-" + $_) -Kind $_ })
    Add-Lines $A @((New-Line -Id "fix-1" -Title "Correction" -Extra '"corrects":"k-merged"'))
    $t = Invoke-Tick $A
    $k = @(Get-Entries @(Get-NewMail $A))
    Check ($k.Count -eq 10 -and (@($k | Select-Object -First 9 | ForEach-Object { $_.kind }) -join ",") -ceq ($nineKinds -join ",")) "each of the nine kinds goes through as itself"
    Check ($k.Count -eq 10 -and $k[9].corrects -ceq "k-merged" -and $k[9].id -ceq "fix-1") "a correction carries the id of the entry it corrects"

    Write-Host ""
    Write-Host "--- 6. one id, one entry: a later line with an id already sent is left out ---" -ForegroundColor Cyan
    Add-Lines $A @((New-Line -Id "n6" -Title "six again, changed"), (New-Line -Id "fresh-1" -Title "new"), (New-Line -Id "fresh-1" -Title "new, twice in one read"), (New-Line -Id "20261012T110000Z-01" -Title "three again: an id the first look sent"))
    $t = Invoke-Tick $A
    $mail = @(Get-NewMail $A)
    Check ((Get-Ids $mail) -ceq "fresh-1" -and @(Get-Entries $mail)[0].title -ceq "new") ("of four lines, three repeating an id, only the first new one is sent (" + (Get-Ids $mail) + ")")
    Check ((Said $t) -cmatch 'repeats the id of line 6; the first stands' -and (Said $t) -cmatch 'repeats the id of line 3; the first stands' -and ([regex]::Matches((Said $t), "repeats the id")).Count -eq 3) ("each repeat is named with its line and the line that stands (" + (Said $t) + ")")

    Write-Host ""
    Write-Host "--- 7. the place in the file survives a restart; the state holds no word of the log ---" -ForegroundColor Cyan
    Restart-World $A
    $t = Invoke-Tick $A
    Check (@(Get-NewMail $A).Count -eq 0 -and @($t.lines).Count -eq 0) "a new run on the same home sends nothing again"
    Add-Lines $A @((New-Line -Id "after-restart" -Title "after the restart"))
    $t = Invoke-Tick $A
    Check ((Get-Ids @(Get-NewMail $A)) -ceq "after-restart") "and the next line is sent alone"
    $state = [System.IO.File]::ReadAllText($A.state)
    Check (-not $state.Contains("after the restart") -and -not $state.Contains("Ruled-line") -and -not $state.Contains("after-restart") -and $state.Contains('"pending":[]') -and $state -cmatch '"offset":[1-9][0-9]*,') "the state on disk holds the place, marks and keys - no title, no text, not even an id in the clear - and nothing waiting"
    Check ((Get-FileMark $A.file) -cne $fileMark -and $state.Contains('"offset":' + (Get-Item -LiteralPath $A.file).Length + ',')) "its offset is the file's length in bytes: everything whole was read"

    Write-Host ""
    Write-Host "--- 8. recorded and not put: the same envelope is put after a restart ---" -ForegroundColor Cyan
    $box = Join-Path $A.home "relay-mailboxes\work\phone"
    $moved = $box + ".away"
    [System.IO.Directory]::Move($box, $moved)
    [System.IO.File]::WriteAllText($box, "a file where the mailbox folder was")
    Add-Lines $A @((New-Line -Id "kept" -Title "kept for later"))
    $t = Invoke-Tick $A
    Check ($t.failed -eq $true -and (Said $t) -like "*not delivered yet*") ("the relay will not take it: the tick says so and counts as failed (" + (Said $t) + ")")
    $pendingKey = [regex]::Match([System.IO.File]::ReadAllText($A.state), '"pending":\["([^"]+)"\]').Groups[1].Value
    Check ($pendingKey -like ($A.id.sign.keyId + "/progress/*")) ("the recorded envelope's key waits in the state (" + $pendingKey + ")")
    [System.IO.File]::Delete($box)
    [System.IO.Directory]::Move($moved, $box)
    Restart-World $A
    $t = Invoke-Tick $A
    $mail = @(Get-NewMail $A)
    Check ($mail.Count -eq 1 -and (Get-Ids $mail) -ceq "kept" -and (Get-HordeRelayReplayKey -Header $mail[0].header) -ceq $pendingKey) ("after a restart, that very envelope is put, once (" + (Said $t) + ")")
    $null = Invoke-Tick $A
    Check (@(Get-NewMail $A).Count -eq 0) "and not again"
    $before = Get-FileMark $A.file
    $null = Invoke-Tick $A
    Check ((Get-FileMark $A.file) -ceq $before) "through all of it the channel never wrote to the changelog: its bytes and its time are its writer's"

    Write-Host ""
    Write-Host "--- 9. nothing comes in on the channel ---" -ForegroundColor Cyan
    $in = New-HordeTestPhoneEnvelope -Phone $A.phone -Kind "entries" -Channel "progress" -Body ($utf8.GetBytes('{"v":1,"kind":"progress-entries","entries":[]}')) -To $A.agree
    [void](Send-HordeRelayItem -Connection $A.conn -Mailbox $A.ctx.mailbox -Text $in.text -Key $in.key)
    $got = Receive-HordeRelayInbox -Context $A.ctx -TimeoutMs 0
    Check ($got.state -ceq "known" -and (@($got.value.refused) -join " ") -like "*the channel progress takes nothing in*" -and @($got.value.taken).Count -eq 0) ("an envelope sent to the channel by the founder's own trusted passkey is refused before the journal sees it (" + $(if ($got.state -ceq "known") { @($got.value.refused) -join "; " } else { $got.reason }) + ")")
    Check (-not (Test-Path -LiteralPath (Join-Path $A.home ("relay\journal\in\s-" + $A.phone.keyId + "\c-progress")))) "and nothing of it is journaled"
    $direct = Invoke-HordeProgressChannelAccept -Context $A.ctx -Item ([pscustomobject]@{ from = $A.phone.keyId; channel = "progress"; kind = "entries"; seq = 1; key = "k"; evidence = ""; ts = 1; body = [byte[]]@() })
    Check ($direct.outcome -ceq "refused") "should a record of this channel ever be handed over, it is refused for good"
    $ch = Get-HordeRelayChannel -Name "progress"
    Check ($null -ne $ch -and @($ch.kinds).Count -eq 0 -and $null -ne $ch.tick) "the channel registers no kind to take in, and a Tick to send out"

    Write-Host ""
    Write-Host "--- 10. 500 entries: pages, each within its size, every entry once and in order ---" -ForegroundColor Cyan
    $B = New-World -Settings '{"sendIntervalMs": 0, "backfillEntries": 5000, "pageBytes": 16384, "readBytes": 131072, "progressFile": "@FILE@"}'
    $body500 = "Happened: " + ("word " * 30)
    Add-Lines $B @(1..500 | ForEach-Object { New-Line -Id ("e" + $_) -Title ("entry " + $_) -Text $body500 })
    $t = Invoke-Tick $B
    $mail = @(Get-NewMail $B)
    $all = @(Get-Entries $mail)
    Check ($mail.Count -ge 5 -and @($mail | Where-Object { $_.length -gt 16384 }).Count -eq 0) ("500 entries go in " + $mail.Count + " envelopes, each body within the page of 16,384 bytes (largest " + (($mail | ForEach-Object { $_.length } | Measure-Object -Maximum).Maximum) + ")")
    Check ($all.Count -eq 500 -and (@($all | ForEach-Object { $_.id }) -join ",") -ceq (@(1..500 | ForEach-Object { "e" + $_ }) -join ",") -and (@($all | ForEach-Object { $_.n }) -join ",") -ceq ((1..500) -join ",")) ("every one of the 500 arrives once, in the file's order (" + $all.Count + ")")
    # 500 more, read 131,072 bytes a look: several turns, and still each once.
    Add-Lines $B @(501..1000 | ForEach-Object { New-Line -Id ("e" + $_) -Title ("entry " + $_) -Text $body500 })
    $turns = 0
    $more = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 12; $i++) { $t = Invoke-Tick $B; $got = @(Get-Entries @(Get-NewMail $B)); if ($got.Count -eq 0) { break }; $turns++; foreach ($x in $got) { [void]$more.Add($x) } }
    Check ($turns -ge 2 -and $more.Count -eq 500 -and (@($more | ForEach-Object { $_.n }) -join ",") -ceq ((501..1000) -join ",")) ("500 more, read at most 131,072 bytes a look, take " + $turns + " looks and arrive each once, in order (" + $more.Count + ")")

    # A line of 200,000 bytes, longer than one look reads: passed over across looks, named once its end is
    # found, and the line after it read as a line.
    Add-Lines $B @((New-Line -Id "huge" -Extra ('"pad":"' + ("p" * 200000) + '"')), (New-Line -Id "after-huge" -Title "after the huge line"))
    $saidAll = ""
    $afterHuge = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 6; $i++) { $t = Invoke-Tick $B; $saidAll += (Said $t) + " | "; foreach ($x in @(Get-Entries @(Get-NewMail $B))) { [void]$afterHuge.Add($x) } }
    Check ($afterHuge.Count -eq 1 -and $afterHuge[0].id -ceq "after-huge" -and $afterHuge[0].n -eq 1002 -and ([regex]::Matches($saidAll, "line 1001 is longer than 65536 bytes")).Count -eq 1) ("a line longer than one look reads is passed over, named once by its number, and the line after it arrives under its own number (" + $afterHuge.Count + ")")

    Write-Host ""
    Write-Host "--- 11. an entry no page of this relay can hold is left out, never cut ---" -ForegroundColor Cyan
    $realLimit = $B.conn.relay.limits.maxTextChars
    $B.conn.relay.limits.maxTextChars = 4000
    try {
        Add-Lines $B @((New-Line -Id "small-1" -Title "fits"), (New-Line -Id "big-1" -Title "too large for this relay" -Text ("Happened: " + ("y" * 1900))), (New-Line -Id "small-2" -Title "fits too"))
        $t = Invoke-Tick $B
        $mail = @(Get-NewMail $B)
    } finally { $B.conn.relay.limits.maxTextChars = $realLimit }
    Check ((Get-Ids $mail) -ceq "small-1,small-2" -and @($mail | Where-Object { $_.raw.Contains("yyyyyyyy") }).Count -eq 0) ("on a relay that holds 4,000 characters, the entry too large for a page is left out whole, and the ones beside it go (" + (Get-Ids $mail) + ")")
    Check ((Said $t) -cmatch 'line 1004 is [0-9]+ bytes as it is sent; a page holds [0-9]+, so it stays at the machine' -and @(Get-Notices $mail | Where-Object { $_.code -ceq "lines-skipped" -and $_.count -eq 1 }).Count -eq 1) ("it is named by its number, and the phone is told one was left out (" + (Said $t) + ")")

    Write-Host ""
    Write-Host "--- 12. a phone trusted later gets the newest entries alone; a revoked one, nothing more ---" -ForegroundColor Cyan
    $C = New-World
    Add-Lines $C @(1..5 | ForEach-Object { New-Line -Id ("c" + $_) -Title ("c " + $_) })
    $null = Invoke-Tick $C
    $null = Get-NewMail $C
    $p2 = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $C.home -Phone $p2)
    Add-PhoneKey -HordeHome $C.home -Phone $p2
    # A line written since the last look: it is new for both, and no part of the new phone's backfill.
    Add-Lines $C @((New-Line -Id "c5b" -Title "written since"))
    $t = Invoke-Tick $C
    $seenBefore = $C.seen
    $as2 = @(Get-NewMail $C -Phone $p2)
    Check ($as2.Count -eq 2 -and $as2[0].body.backfill -eq $true -and (Get-Ids @($as2[0])) -ceq "c3,c4,c5" -and @($as2[0].to).Count -eq 1 -and $as2[0].to[0] -ceq (Get-HordeRelayKeyId -Public $p2.agreePublic)) ("the new phone gets the newest three of what was already read, sealed to it alone (" + (Get-Ids $as2) + ")")
    Check ($as2.Count -eq 2 -and $as2[1].body.backfill -eq $false -and (Get-Ids @($as2[1])) -ceq "c5b" -and @($as2[1].to).Count -eq 2) "and the line written since goes to both, once, as new"
    $C.seen = $seenBefore
    $as1 = @(Get-NewMail $C)
    Check ($as1.Count -eq 2 -and $null -eq $as1[0].body -and (Get-Ids @($as1[1])) -ceq "c5b") "the first phone cannot open the second's backfill"
    Add-Lines $C @((New-Line -Id "c6" -Title "to both"))
    $null = Invoke-Tick $C
    $both = @(Get-NewMail $C)
    Check ($both.Count -eq 1 -and @($both[0].to).Count -eq 2 -and (Get-Ids $both) -ceq "c6") "a new entry goes to both keys"
    [void](Revoke-HordeRelayTrust -HordeHome $C.home -Subject "device" -Id $p2.deviceId -Reason "phone lost")
    Add-Lines $C @((New-Line -Id "c7" -Title "to one again"))
    $null = Invoke-Tick $C
    $one = @(Get-NewMail $C)
    Check ($one.Count -eq 1 -and @($one[0].to).Count -eq 1 -and $one[0].to[0] -ceq (Get-HordeRelayKeyId -Public $C.phone.agreePublic) -and (Get-Ids $one) -ceq "c7") "its passkey revoked, the second phone's key gets nothing more"

    Write-Host ""
    Write-Host "--- 13. an envelope recorded before a key was revoked is never put to it ---" -ForegroundColor Cyan
    $p3 = New-HordeTestPhone
    [void](Add-HordeTestPhonePairing -HordeHome $C.home -Phone $p3); Add-PhoneKey -HordeHome $C.home -Phone $p3
    $null = Invoke-Tick $C; $null = Get-NewMail $C
    $boxC = Join-Path $C.home "relay-mailboxes\work\phone"; $movedC = $boxC + ".away"
    [System.IO.Directory]::Move($boxC, $movedC); [System.IO.File]::WriteAllText($boxC, "x")
    Add-Lines $C @((New-Line -Id "c8" -Title "written before the revocation"))
    $t = Invoke-Tick $C
    Check ($t.failed -and [System.IO.File]::ReadAllText($C.state) -cmatch '"rewind":\{') "CONTROL: an envelope for both keys is recorded and waits, with the place before it kept"
    [void](Revoke-HordeRelayTrust -HordeHome $C.home -Subject "device" -Id $p3.deviceId -Reason "phone stolen")
    [System.IO.File]::Delete($boxC); [System.IO.Directory]::Move($movedC, $boxC)
    $null = Invoke-Tick $C
    $null = Invoke-Tick $C
    $stolen = @(Get-NewMail $C -Phone $p3 -All | Where-Object { $null -ne $_.body -and (Get-Ids @($_)) -like "*c8*" })
    $kept = @(Get-NewMail $C | Where-Object { $null -ne $_.body -and (Get-Ids @($_)) -like "*c8*" })
    Check ($stolen.Count -eq 0) ("the revoked key gets nothing put after its revocation, though it was recorded for it before (" + $stolen.Count + ")")
    Check ($kept.Count -eq 1 -and @($kept[0].to).Count -eq 1 -and @(Get-Entries $kept)[0].n -eq 9) "the line is read again and sealed to the keys trusted now: the first phone gets it, once, under the same line number"

    Write-Host ""
    Write-Host "--- 14. a file cut short stops the channel: said once, the phone told, nothing sent again ---" -ForegroundColor Cyan
    $D = New-World
    $original = @(1..6 | ForEach-Object { New-Line -Id ("d" + $_) -Title ("d " + $_) }) + @((New-Line -Id "d5" -Title "d 5 again, in the file before the first look"))
    Add-Lines $D $original
    $t = Invoke-Tick $D
    $mail = @(Get-NewMail $D)
    Check ((Get-Ids $mail) -ceq "d4,d5,d6" -and @(Get-Entries $mail)[1].title -ceq "d 5" -and (Said $t) -cmatch 'line 7 repeats the id of line 5; the first stands') ("the first look, too, sends an id once: the newest three are three entries, the repeat left out and named (" + (Get-Ids $mail) + ")")
    $fullBytes = [System.IO.File]::ReadAllBytes($D.file)
    $short = New-Object byte[] ([int]($fullBytes.Length / 2))
    [System.Array]::Copy($fullBytes, 0, $short, 0, $short.Length)
    [System.IO.File]::WriteAllBytes($D.file, $short)
    $t = Invoke-Tick $D
    $mail = @(Get-NewMail $D)
    Check ((Said $t) -like "*progress is stopped*was cut short*" -and -not $t.failed -and (Said $t).Contains($D.state)) ("a changelog shorter than what was read stops the channel, in words that name the state file to delete (" + (Said $t).Substring(0, [Math]::Min(170, (Said $t).Length)) + "...)")
    $notes = @(Get-Notices $mail)
    Check (@(Get-Entries $mail).Count -eq 0 -and $notes.Count -eq 1 -and $notes[0].code -ceq "file-replaced") "the phone is told, by a code, and no entry is sent again"
    Add-Lines $D @((New-Line -Id "d-after-cut" -Title "appended to the cut file"))
    $t2 = Invoke-Tick $D
    $t3 = Invoke-Tick $D
    Check (@(Get-NewMail $D).Count -eq 0 -and @($t2.lines).Count -eq 0 -and @($t3.lines).Count -eq 0) "while it is stopped nothing is read or sent - not what is appended to the cut file either - and it is said once, not every turn"
    Restart-World $D
    $t = Invoke-Tick $D
    Check (@(Get-NewMail $D).Count -eq 0 -and (Said $t) -like "*progress is stopped*") "a new run is still stopped, and says so once: the stop is in the state, not in a run's memory"
    # Put back as it was, with two lines more: it goes on from where it stopped.
    [System.IO.File]::WriteAllBytes($D.file, $fullBytes)
    Add-Lines $D @((New-Line -Id "d7" -Title "d 7"), (New-Line -Id "d8" -Title "d 8"))
    $t = Invoke-Tick $D
    $mail = @(Get-NewMail $D)
    Check ((Get-Ids $mail) -ceq "d7,d8" -and (Said $t) -like "*is as it was again*") ("put back as it was, the channel goes on by itself from where it stopped: only the two new lines (" + (Get-Ids $mail) + ")")
    Check (@(Get-Notices $mail | Where-Object { $_.code -ceq "following" }).Count -eq 1) "and the phone is told it is following again"

    Write-Host ""
    Write-Host "--- 15. replaced, rewritten, gone, another file by the setting: each stops it; the state deleted, it starts over ---" -ForegroundColor Cyan
    # (Forty lines more, so the file is longer than the 4,096 bytes its start is known by.)
    Add-Lines $D @(1..40 | ForEach-Object { New-Line -Id ("pad" + $_) -Title ("padding " + $_) })
    $null = Invoke-Tick $D; $null = Get-NewMail $D
    $goodBytes = [System.IO.File]::ReadAllBytes($D.file)
    # Rewritten: the same length, the same start, one byte of the last line already read changed.
    $rewritten = [byte[]]$goodBytes.Clone()
    $rewritten[$rewritten.Length - 12] = [byte]([int]$rewritten[$rewritten.Length - 12] -bxor 1)
    [System.IO.File]::WriteAllBytes($D.file, $rewritten)
    $t = Invoke-Tick $D
    Check ($goodBytes.Length -gt 4096 -and (Said $t) -like "*progress is stopped*was rewritten*" -and @(Get-Entries @(Get-NewMail $D)).Count -eq 0) ("a changelog of the same length and the same start whose last read line was changed is noticed (" + (Said $t).Substring(0, [Math]::Min(120, (Said $t).Length)) + "...)")
    [System.IO.File]::WriteAllBytes($D.file, $goodBytes)
    $null = Invoke-Tick $D; $null = Get-NewMail $D
    # Replaced: another, longer file under the same name.
    $other = $utf8.GetBytes(((@(1..80 | ForEach-Object { New-Line -Id ("x" + $_) -Title ("another log " + $_) }) | ForEach-Object { $_ + "`n" }) -join ""))
    [System.IO.File]::WriteAllBytes($D.file, $other)
    $t = Invoke-Tick $D
    $mail = @(Get-NewMail $D)
    Check ((Said $t) -like "*progress is stopped*was replaced*" -and @(Get-Entries $mail).Count -eq 0 -and $other.Length -gt $goodBytes.Length) ("a longer file put in its place is noticed by its start, and none of it is sent (" + (Said $t).Substring(0, [Math]::Min(120, (Said $t).Length)) + "...)")
    # The state deleted by a person: the new file is followed from its start.
    Remove-Item -LiteralPath $D.state -Force
    Restart-World $D
    $t = Invoke-Tick $D
    $mail = @(Get-NewMail $D)
    Check ((Get-Ids $mail) -ceq "x78,x79,x80" -and @($mail | Where-Object { $null -ne $_.body -and $_.body.kind -ceq "progress-entries" })[0].body.backfill -eq $true) ("with the state file deleted, the new file is followed as a first look: its newest three (" + (Get-Ids $mail) + ")")
    # Gone.
    Remove-Item -LiteralPath $D.file -Force
    $t = Invoke-Tick $D
    Check ((Said $t) -like "*progress is stopped*is gone*" -and @(Get-Notices @(Get-NewMail $D) | Where-Object { $_.code -ceq "file-replaced" }).Count -eq 1) "a changelog that is gone after it was read is a stop, not nothing yet"
    [System.IO.File]::WriteAllBytes($D.file, $other)
    $null = Invoke-Tick $D; $null = Get-NewMail $D
    # Another file by the setting.
    $elsewhere = Join-Path $D.home "elsewhere\changelog.jsonl"
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $elsewhere))
    [System.IO.File]::WriteAllBytes($elsewhere, $other)
    [System.IO.File]::WriteAllText((Join-Path $D.home "settings\relay-progress.json"), ('{"schemaVersion": 1, "settings": {"sendIntervalMs": 0, "backfillEntries": 3, "progressFile": "' + $elsewhere.Replace("\", "\\") + '"}}'), $utf8)
    $t = Invoke-Tick $D
    Check ((Said $t) -like "*progress is stopped*the setting progressFile names another*" -and @(Get-Entries @(Get-NewMail $D)).Count -eq 0) "the setting changed to another file - even one with the same bytes - is a stop too: nothing is started over by itself"

    Write-Host ""
    Write-Host "--- 16. no phone key; a damaged state; refused settings ---" -ForegroundColor Cyan
    $N = New-World -NoPhoneKey
    Add-Lines $N @((New-Line -Id "n1"))
    $t = Invoke-Tick $N
    $t2 = Invoke-Tick $N
    Check (@(Get-PhoneItems $N).Count -eq 0 -and (Said $t) -like "*no phone identity key*" -and @($t2.lines).Count -eq 0 -and -not $t.failed -and -not (Test-Path -LiteralPath $N.state)) "no trusted phone key: nothing is read or sent, said once and not again"
    Add-PhoneKey -HordeHome $N.home -Phone $N.phone
    New-Item -ItemType Directory -Path (Split-Path -Parent $N.state) -Force | Out-Null
    [System.IO.File]::WriteAllText($N.state, "{ not the state")
    Restart-World $N
    $t = Invoke-Tick $N
    Check ($t.failed -and (Said $t) -like "*progress is stopped*" -and @(Get-PhoneItems $N).Count -eq 0) ("a damaged state file stops the channel, in words; it is never quietly started over (" + (Said $t) + ")")
    [System.IO.File]::WriteAllText($N.state, '{"v":1,"started":true,"path":"","offset":-5,"line":0,"skip":false,"head":"","tail":"","phones":[],"pending":[],"sent":[],"rewind":null,"stopped":""}')
    Restart-World $N
    $t = Invoke-Tick $N
    Check ($t.failed -and (Said $t) -like "*offset and line are not whole numbers*") "so does a state whose offset is not a place in a file"
    $goodState = '{"v":1,"started":true,"path":"","offset":10,"line":1,"skip":false,"head":"","tail":"","phones":[],"pending":[],"sent":[],"rewind":null,"stopped":""}'
    [System.IO.File]::WriteAllText($N.state, $goodState)
    Check ((Read-HordeProgressChannelState -HordeHome $N.home).state -ceq "known") "CONTROL: a state that holds together is read"
    $damaged = [ordered]@{
        "a member missing" = @($goodState.Replace(',"stopped":""', ''), "its members are")
        "a member added" = @($goodState.Replace('"v":1,', '"v":1,"extra":1,'), "its members are")
        "a member twice" = @($goodState.Replace('"line":1,', '"line":1,"line":2,'), "a member is repeated")
        "another version" = @($goodState.Replace('"v":1,', '"v":2,'), "it is not version 1")
        "started that is not true or false" = @($goodState.Replace('"started":true', '"started":"yes"'), "started and skip are not true or false")
        "a path that is a number" = @($goodState.Replace('"path":""', '"path":5'), "its path is not a path")
        "a mark that is not a hash" = @($goodState.Replace('"head":""', '"head":"zz"'), "its marks are not hashes")
        "a phone that is not a key id" = @($goodState.Replace('"phones":[]', '"phones":["x"]'), "a phone key is not a key id")
        "a pending envelope that is a number" = @($goodState.Replace('"pending":[]', '"pending":[5]'), "a pending envelope is not a replay key")
        "a sent entry that is not a mark" = @($goodState.Replace('"sent":[]', '"sent":["abc:0"]'), "a sent entry is not an id mark and a line")
        "a stop this code does not know" = @($goodState.Replace('"stopped":""', '"stopped":"on-holiday"'), "its stopped is not a reason this code knows")
        "a rewind that is not a place" = @($goodState.Replace('"rewind":null', '"rewind":{"offset":1}'), "its rewind is not a place in the file")
        "a rewind whose offset is text" = @($goodState.Replace('"rewind":null', '"rewind":{"started":true,"offset":"1","line":0,"skip":false,"head":"","tail":"","phones":[]}'), "its rewind is not a place in the file")
        "a list where the state should be" = @('[1]', "it is not an object")
        "a byte that is not ASCII" = @($goodState.Replace('"path":""', ('"path":"' + [char]0xE9 + '"')), "cannot be read")
    }
    foreach ($name in @($damaged.Keys)) {
        [System.IO.File]::WriteAllText($N.state, $damaged[$name][0], $utf8)
        $rs = Read-HordeProgressChannelState -HordeHome $N.home
        Check ($rs.state -ceq "unknown" -and $rs.reason.Contains($damaged[$name][1])) ("a state with " + $name + " is not read, and says why (" + $(if ($rs.state -ceq "unknown") { $rs.reason.Substring($rs.reason.LastIndexOf(":") + 1).Trim() } else { $rs.state }) + ")")
    }
    Remove-Item -LiteralPath $N.state -Force
    [System.IO.File]::WriteAllText((Join-Path $N.home "settings\relay-progress.json"), '{"schemaVersion": 1, "settings": {"progressFile": "relative\\changelog.jsonl"}}', $utf8)
    Restart-World $N
    $t = Invoke-Tick $N
    Check ($t.failed -and (Said $t) -like "*progress is stopped*" -and (Said $t) -like "*progressFile*" -and @(Get-PhoneItems $N).Count -eq 0) ("a progressFile that is not an absolute path refuses the settings, and nothing is read (" + (Said $t) + ")")
    $decl = Get-HordeProgressChannelSettingsDeclaration
    $defaults = Get-HordeModuleSettings -Declaration $decl -HordeHome (New-TestHome)
    Check ($defaults.state -ceq "defaults" -and $defaults.values.progressFile -ceq "" -and $defaults.values.backfillEntries -eq 200) "by default the backfill is 200 entries, and no file of anyone's machine is named"
} finally {
    $env:HORDE_HOME = $realHome
    Exit-HordeTestEmptyFleet -Pin $fleetPin
    foreach ($w in $script:worlds) { Close-HordeRelayRunContext -Context $w.ctx }
    $keys = New-Object System.Collections.ArrayList
    foreach ($h in $script:homes) {
        $dir = Join-Path $h "relay\identity"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter "machine-*.json")) {
            $mm = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), '"scope":"([a-z]+)","signName":"([a-z0-9-]+)".*"agreeName":"([a-z0-9-]+)"')
            if ($mm.Success) { [void]$keys.Add(@{ n = $mm.Groups[2].Value; s = $mm.Groups[1].Value }); [void]$keys.Add(@{ n = $mm.Groups[3].Value; s = $mm.Groups[1].Value }) }
        }
    }
    foreach ($k in $keys) { try { [void](Remove-HordeRelayKey -Name $k.n -Scope $k.s) } catch { } }
    $left = @($keys | Where-Object { (Find-HordeRelayCngKey -Name $_.n -Scope $_.s) -cne "" })
    Check ($keys.Count -ge 2 -and $left.Count -eq 0) ("every key the suite made is gone (" + $keys.Count + ")")
    foreach ($h in $script:homes) { if ((Split-Path -Leaf $h) -match '^horde-relay-progress-[0-9a-f]{32}$') { Remove-Item -LiteralPath $h -Recurse -Force -ErrorAction SilentlyContinue } }
    Check (@($script:homes | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0 -and -not (Test-Path -LiteralPath $fleetPin.path)) "every folder the suite made is gone"
}

Complete-HordeSuite -Success "the phone gets the progress log's whole, well-formed entries once each, in the order they were written, sealed to trusted keys, durably and in pages; what does not hold together is left out and said; and a file that is not the one that was followed stops the channel instead of being sent again"
