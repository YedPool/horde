# DOES THE LINK'S WIRE CARRY EXACTLY A FRAME, AND REFUSE EVERYTHING ELSE WITH A REASON?
#
# Plan step R2 (planning/execution-plan-remote.md): remote/Protocol.ps1 turns frames into bytes and
# bytes into frames. What it must do, each proved below:
#   - every non-ASCII character leaves as \uXXXX and comes back as itself (A);
#   - a raw byte above 0x7F, a NUL, a stray CR, UTF-16, text that is not one JSON object, a frame not
#     in the link's one spelling, and a frame of another version are each refused, with a reason (B);
#   - every cap in schema/link-frame.v1's x-horde-limits holds, just under and just over (C);
#   - a stream is read line by line, CRLF and LF alike, a BOM only at its start, and the first line
#     that is not a frame closes it (D);
#   - PowerShell 5.1 as it really writes a pipe - BOM and CRLF - is read correctly, measured live (E);
#   - a hello with no common protocol version ends in bye (F);
#   - thousands of damaged frames, made by a seeded generator, never throw and never pass as
#     something they are not (G).

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "remote\Protocol.ps1")

$fx = Join-Path $here "fixtures\link"
$contract = Get-HordeLinkContract
$ascii = [System.Text.Encoding]::ASCII

# A FIXTURE IS DATA, NOT A SCHEMA: read as UTF-8 JSON. Read-HordeSchemaFile checks that what it reads
# is a schema (review of PR #27), so a frame read through it is refused for its member v.
function Read-Data { param([string]$Path) return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json) }
function Read-Fx { param([string]$Name) return (Read-Data (Join-Path $fx $Name)) }
function Copy-Json { param($Value) return (($Value | ConvertTo-Json -Depth 40) | ConvertFrom-Json) }
function Says { param($Text, [string]$Part) return ("$Text".Contains($Part)) }
function Bytes { param([string]$Text) return ,([byte[]]$ascii.GetBytes($Text)) }
function Join-Bytes {
    param([byte[][]]$Parts)
    $ms = New-Object System.IO.MemoryStream
    foreach ($p in $Parts) { $ms.Write($p, 0, $p.Length) }
    return ,([byte[]]$ms.ToArray())
}
function Decode {
    # One line (no LF) through the receiver, as bytes.
    param([byte[]]$Line, [switch]$StreamStart, $FrameBytes = $null, $Contract = $contract)
    return (ConvertFrom-HordeFrameBytes -Bytes $Line -Contract $Contract -FrameBytes $FrameBytes -StreamStart:$StreamStart)
}
function Line {
    # A frame's canonical line, without its LF.
    param($Frame)
    $t = ConvertTo-HordeWireText $Frame
    return ,(Bytes $t)
}
function Refused {
    param($Result, [string]$Code, [string]$Part, [string]$What)
    Check ((-not $Result.ok) -and $Result.code -ceq $Code -and (Says $Result.reason $Part)) $What
    if ($Result.ok -or $Result.code -cne $Code -or -not (Says $Result.reason $Part)) { Write-Host ("         got: ok=" + $Result.ok + " code=" + $Result.code + " reason=" + $Result.reason) -ForegroundColor DarkYellow }
}

$goldenNames = @(Get-ChildItem -LiteralPath (Join-Path $fx "frames") -Filter "*.json" | Sort-Object Name | ForEach-Object { $_.Name })
$golden = @{}
foreach ($n in $goldenNames) { $golden[$n] = Read-Fx ("frames\" + $n) }

Write-Host ""
Write-Host "--- A. every character outside printable ASCII is escaped, and comes back as itself ---" -ForegroundColor Cyan

Check ((ConvertTo-HordeWireString "abc") -ceq '"abc"') "plain ASCII is written as it is"
Check ((ConvertTo-HordeWireString 'a"b\c') -ceq '"a\"b\\c"') "a quote and a backslash are escaped with a backslash"
Check ((ConvertTo-HordeWireString ("caf" + [char]0xE9)) -ceq '"caf\u00e9"') "e-acute is \u00e9, lower-case hex"
Check ((ConvertTo-HordeWireString ([string][char]0x7F)) -ceq '"\u007f"') "DEL (0x7F), the first byte past printable ASCII, is escaped"
Check ((ConvertTo-HordeWireString "~ ") -ceq '"~ "') "tilde (0x7E) and space (0x20), the ends of printable ASCII, are not"
Check ((ConvertTo-HordeWireString ("a" + [char]9 + [char]10 + [char]13 + [char]1)) -ceq '"a\u0009\u000a\u000d\u0001"') "tab, LF, CR and other control characters are escaped, so a raw LF can only end a frame"
# NOT TEXT, REFUSED AT THE SENDER (review of PR #45): a NUL, and half a surrogate pair, each of which the
# first encoder wrote as an escape for the receiver to accept or choke on.
Check (Throws { ConvertTo-HordeWireString ("a" + [char]0 + "b") } "a NUL at character 1") "a NUL is refused at the sender"
Check (Throws { ConvertTo-HordeWireString ("a" + [char]0xD800 + "x") } "half a surrogate pair at character 1") "a lone high surrogate is refused at the sender"
Check (Throws { ConvertTo-HordeWireString ("a" + [char]0xD800) } "half a surrogate pair") "a high surrogate at the very end is refused"
Check (Throws { ConvertTo-HordeWireString ([string][char]0xDE00 + "x") } "half a surrogate pair at character 0") "a lone low surrogate is refused at the sender"
Check (Throws { ConvertTo-HordeWireString ([string][char]0xDE00 + [char]0xD83D) } "half a surrogate pair") "a pair in the wrong order is refused"
$nulReq = Copy-Json $golden["req-session-spawn.json"]; $nulReq.args.prompt.text = "go" + [char]0 + "now"
$nulSent = ConvertTo-HordeFrameBytes -Frame $nulReq -Contract $contract
Check ($null -ne $nulSent -and -not $nulSent.ok -and $nulSent.code -ceq "bad-frame" -and $null -eq $nulSent.bytes -and (Says $nulSent.reason "a NUL")) "a spawn whose prompt holds a NUL is refused at the sender as bad-frame, naming the NUL, with no bytes and no error"
$halfReq = Copy-Json $golden["req-session-spawn.json"]; $halfReq.args.prompt.text = "go " + [char]0xD83D
$halfSent = ConvertTo-HordeFrameBytes -Frame $halfReq -Contract $contract
Check ($null -ne $halfSent -and -not $halfSent.ok -and $halfSent.code -ceq "bad-frame" -and (Says $halfSent.reason "half a surrogate pair")) "a spawn whose prompt ends in half a surrogate pair is refused at the sender the same way"
$spLine = $ascii.GetString((Line $golden["req-session-spawn.json"]))
$U = [string][char]92 + "u"
Refused (Decode (Bytes ($spLine.Replace('"text":"', '"text":"' + $U + '0000 ')))) "bad-frame" "a NUL" "a received prompt holding an escaped NUL is refused"
Refused (Decode (Bytes ($spLine.Replace('"text":"', '"text":"' + $U + 'd800 ')))) "bad-frame" "one spelling" "a received prompt holding a lone escaped surrogate is refused (ConvertFrom-Json replaces the half, so the frame is not written again the same)"
Check ((Decode (Bytes ($spLine.Replace('"text":"', '"text":"' + $U + 'd83d' + $U + 'de00 ')))).ok) "CONTROL: a received prompt holding a whole escaped pair is accepted"
Check ((ConvertTo-HordeWireString ([char]::ConvertFromUtf32(0x1F600))) -ceq '"\ud83d\ude00"') "a character outside the BMP is its two UTF-16 escapes"
Check ((ConvertTo-HordeWireString ([string][char]0x2028)) -ceq '"\u2028"') "a line separator (U+2028) is escaped"
Check ((ConvertTo-HordeWireString "<a href='x'>&</a>") -ceq ('"' + "<a href='x'>&</a>" + '"')) "< > & and ' are written as they are, unlike ConvertTo-Json"
Check ((Measure-HordeWireString ("caf" + [char]0xE9)) -eq 9) "a string is measured as it is on the wire: cafe-acute is 9 bytes"

$samples = @("", "plain", 'q"uo\te', ("tab" + [char]9 + "nl" + [char]10), ("caf" + [char]0xE9 + " na" + [char]0xEF + "ve"),
             ([char]::ConvertFromUtf32(0x1F600) + [char]::ConvertFromUtf32(0x4E2D)), ([string][char]0x2028 + [char]0xFEFF + [char]0x7F), "<>&'/")
$rng = New-Object System.Random 20260930
for ($i = 0; $i -lt 40; $i++) {
    $sb = New-Object System.Text.StringBuilder
    $len = $rng.Next(1, 40)
    for ($j = 0; $j -lt $len; $j++) {
        $pick = $rng.Next(0, 4)
        if ($pick -eq 0) { [void]$sb.Append([char]$rng.Next(1, 0x80)) }
        elseif ($pick -eq 1) { [void]$sb.Append([char]$rng.Next(0x80, 0xD800)) }
        elseif ($pick -eq 2) { [void]$sb.Append([char]::ConvertFromUtf32($rng.Next(0x10000, 0x10FFFF))) }
        else { [void]$sb.Append([char]$rng.Next(0xE000, 0x10000)) }
    }
    $samples += $sb.ToString()
}
$roundTrips = 0; $asciiOnly = 0
foreach ($s in $samples) {
    $w = ConvertTo-HordeWireString $s
    if ([regex]::IsMatch($w, '\A[\x20-\x7E]*\z')) { $asciiOnly++ }
    $back = ConvertFrom-Json -InputObject ('{"s":' + $w + '}')
    if ([string]::Equals("$($back.s)", $s, [System.StringComparison]::Ordinal)) { $roundTrips++ }
}
Check ($asciiOnly -eq $samples.Count) ("every one of " + $samples.Count + " strings, 40 of them random across all of Unicode, is written in printable ASCII")
Check ($roundTrips -eq $samples.Count) ("and every one reads back through ConvertFrom-Json as exactly itself (" + $roundTrips + "/" + $samples.Count + ")")

# A WHOLE FRAME round-trips too: a handoff whose document holds non-ASCII text.
$hf = Copy-Json $golden["res-handoff-known.json"]
$hf.result.value.document = "Caf" + [char]0xE9 + " " + [char]0x2713 + " " + [char]::ConvertFromUtf32(0x1F600) + " kept on the node."
$enc = ConvertTo-HordeFrameBytes -Frame $hf -Contract $contract
Check ($enc.ok) "a handoff frame holding non-ASCII text encodes"
$printable = @($enc.bytes[0..($enc.bytes.Length - 2)] | Where-Object { $_ -lt 0x20 -or $_ -gt 0x7E }).Count
Check ($printable -eq 0 -and $enc.bytes[$enc.bytes.Length - 1] -eq 10) "its bytes are printable ASCII ending in one LF"
$dec = Decode ([byte[]]$enc.bytes[0..($enc.bytes.Length - 2)])
Check ($dec.ok -and [string]::Equals($dec.frame.result.value.document, $hf.result.value.document, [System.StringComparison]::Ordinal)) "and it decodes to the same document, character for character"

$allCanonical = $true
foreach ($n in $goldenNames) {
    $e = ConvertTo-HordeFrameBytes -Frame $golden[$n] -Contract $contract
    $d = $null
    if ($e.ok) { $d = Decode ([byte[]]$e.bytes[0..($e.bytes.Length - 2)]) }
    $again = $null
    if ($null -ne $d -and $d.ok) { $again = ConvertTo-HordeWireText $d.frame }
    if (-not ($e.ok -and $d.ok -and $again -ceq $ascii.GetString($e.bytes, 0, $e.bytes.Length - 1))) { $allCanonical = $false; Write-Host ("         " + $n + ": " + $e.reason + " " + $d.reason) -ForegroundColor DarkYellow }
}
Check $allCanonical ("all " + $goldenNames.Count + " golden frames encode, decode, and encode again to the same bytes")

Check (Throws { ConvertTo-HordeWireText (Get-Date) } "does not cross the link") "a [datetime] is refused: times cross as ISO text"
Check (Throws { ConvertTo-HordeWireText ([double]::NaN) } "whole number") "NaN is refused: a number on the link is a whole number"
Check (Throws { ConvertTo-HordeWireText ([decimal]"1.0") } "whole number") "a decimal 1.0 is refused at the sender: 1.0 would be a second spelling of 1"
Check (Throws { ConvertTo-HordeWireText ([double]1) } "whole number") "a double, even a whole one, is refused: only an integer type is written as a number"
Check (Throws { ConvertTo-HordeWireText @{ 1 = "x" } } "key must be a string") "an object key that is not a string is refused"
$deep = "x"; for ($i = 0; $i -lt 70; $i++) { $deep = @{ d = $deep } }
Check (Throws { ConvertTo-HordeWireText $deep } "nested more than") "a value nested past 64 is refused, never truncated as ConvertTo-Json does"
Check ((ConvertTo-HordeWireText ([ordered]@{ z = 1; a = @(); m = [ordered]@{ y = 2; b = 3 }; n = $null; t = $true; B = 4 })) -ceq '{"B":4,"a":[],"m":{"b":3,"y":2},"n":null,"t":true,"z":1}') "keys are written in ordinal order at every depth (B before a), and each kind of value has one spelling"
Check ((ConvertTo-HordeWireText ([pscustomobject][ordered]@{ seq = 1; id = "x" })) -ceq (ConvertTo-HordeWireText ([pscustomobject][ordered]@{ id = "x"; seq = 1 }))) "the same object built in two key orders is written the same"
Check ((ConvertTo-HordeWireText -Value @(1)) -ceq '[1]') "a one-element list stays a list"

Write-Host ""
Write-Host "--- B. the receiver refuses what is not a frame, each with its reason ---" -ForegroundColor Cyan

$ping = Line $golden["ping.json"]
$pingText = $ascii.GetString($ping)
Check ((Decode $ping).ok) "CONTROL: the canonical ping line decodes"
Refused (Decode (Join-Bytes @((Bytes $pingText.Substring(0, 20)), [byte[]](0xC3, 0xA9), (Bytes $pingText.Substring(20))))) "bad-frame" "raw byte 0xC3 above 0x7F at offset 20" "a raw UTF-8 byte above 0x7F is refused, naming the byte and where"
Refused (Decode (Join-Bytes @((Bytes $pingText.Substring(0, 5)), [byte[]](0), (Bytes $pingText.Substring(5))))) "bad-frame" "NUL byte" "a NUL is refused as a sign of UTF-16"
Refused (Decode (Join-Bytes @((Bytes $pingText.Substring(0, 5)), [byte[]](13), (Bytes $pingText.Substring(5))))) "bad-frame" "a CR that does not end the line" "a CR inside the line is refused"
Refused (Decode (Join-Bytes @((Bytes $pingText.Substring(0, 5)), [byte[]](9), (Bytes $pingText.Substring(5))))) "bad-frame" "byte 0x09" "a raw tab is refused"
Check ((Decode (Join-Bytes @($ping, [byte[]](13)))).ok) "a line ending CRLF decodes: one CR before the LF is stripped"
Refused (Decode (Join-Bytes @($ping, [byte[]](13, 13)))) "bad-frame" "a CR that does not end the line" "two CRs before the LF are refused"
$bomLine = Join-Bytes @([byte[]](0xEF, 0xBB, 0xBF), $ping)
$d = Decode $bomLine -StreamStart
Check ($d.ok -and $d.bom) "a UTF-8 BOM at the start of the stream is stripped, and reported"
Refused (Decode $bomLine) "bad-frame" "byte order mark in the middle of the stream" "a UTF-8 BOM anywhere else is refused"
Refused (Decode (Join-Bytes @([byte[]](0xFF, 0xFE), [System.Text.Encoding]::Unicode.GetBytes($pingText))) -StreamStart) "bad-frame" "UTF-16" "UTF-16 with its BOM is refused, and named"
Refused (Decode ([System.Text.Encoding]::Unicode.GetBytes($pingText))) "bad-frame" "NUL byte (is the stream UTF-16?)" "UTF-16 without a BOM is refused at its first NUL"
Refused (Decode (New-Object byte[] 0)) "bad-frame" "an empty line" "an empty line is refused"
Refused (Decode (Bytes "Windows PowerShell")) "bad-frame" "not JSON" "a banner line is refused"
Refused (Decode (Bytes "[1,2]")) "bad-frame" "not one object" "a JSON array is refused"
Refused (Decode (Bytes '"frame"')) "bad-frame" "not one object" "a JSON string is refused"
Refused (Decode (Bytes ($pingText + $pingText))) "bad-frame" "" "two frames on one line are refused"
Refused (Decode (Bytes ($pingText + " x"))) "bad-frame" "" "a frame followed by other text is refused"
Refused (Decode (Bytes ($pingText -replace '":', '": '))) "bad-frame" "one spelling" "a frame with spaces after its colons is refused: one spelling"
Refused (Decode (Bytes ($pingText -replace '"seq":10', '"seq":1e1'))) "bad-frame" "whole number" "a whole number written with an exponent is refused: it parses as a double, which the link does not write"
Refused (Decode (Bytes ($pingText -replace '"kind":"ping"', '"kind":"\u0070ing"'))) "bad-frame" "one spelling" "a character escaped that need not be is refused"
Refused (Decode (Bytes ($pingText -replace '\{"id":', '{id:'))) "bad-frame" "" "unquoted keys are refused"
Refused (Decode (Bytes ($pingText -replace '"seq":10', '"seq":10,"seq":11'))) "bad-frame" "" "a duplicated key is refused"
Refused (Decode (Bytes ($pingText -replace '"seq":10', '"seq":10,"SEQ":11'))) "bad-frame" "" "a key repeated in another case is refused"
Refused (Decode (Bytes ('{"v":1,"deep":' + ("[" * 200) + ("]" * 200) + '}'))) "bad-frame" "" "JSON nested 200 deep is refused without an unexpected error"
Refused (Decode (Bytes ($pingText -replace '"v":1', '"v":2'))) "unknown-version" "version '2'" "a frame of version 2 is refused as unknown-version"
Refused (Decode (Bytes '{"v":2,"kind":"stream","payload":{"chunks":[1,2]}}')) "unknown-version" "version 1 only" "a version 2 frame of a shape v1 does not know is still named unknown-version, not malformed"
Refused (Decode (Bytes ($pingText -replace '"v":1', '"v":"1"'))) "unknown-version" "" "a version written as text is refused"
Refused (Decode (Bytes ($pingText -replace ',"v":1', ''))) "bad-frame" "no version" "a frame with no version is refused"

# CANONICAL MEANS ONE SPELLING, NOT ONE PARSE (review of PR #45): each of these parses to the frame the
# canonical line does, and each was accepted while keys were re-encoded in arrival order and a decimal
# kept its scale.
Check ($pingText.StartsWith('{"id":') -and $pingText.EndsWith(',"v":1}')) "CONTROL: the canonical ping's keys are in ordinal order, id first and v last"
$swapped = [regex]::Replace($pingText, '\A\{("id":"[^"]*"),("kind":"ping")', '{$2,$1')
Check ($swapped -cne $pingText) "CONTROL: the swap changed the line"
Refused (Decode (Bytes $swapped)) "bad-frame" "one spelling" "a frame with two top-level keys swapped is refused"
$spText = $ascii.GetString((Line $golden["req-session-spawn.json"]))
$spSwapped = [regex]::Replace($spText, '"base":("[^"]*"),"branch":("[^"]*")', '"branch":$2,"base":$1')
Check ($spSwapped -cne $spText) "CONTROL: the nested swap changed the line"
Refused (Decode (Bytes $spSwapped)) "bad-frame" "one spelling" "a frame with two nested keys swapped is refused"
Refused (Decode (Bytes ($pingText -replace '"seq":10', '"seq":10.0'))) "bad-frame" "whole number" "seq 10.0 is refused: a second spelling of 10"
Refused (Decode (Bytes ($pingText -replace '"seq":10', '"seq":10.00'))) "bad-frame" "whole number" "seq 10.00 is refused"
$close = [pscustomobject][ordered]@{ v = 1; kind = "req"; id = "0a000000-0000-4000-8000-0000000000c1"; seq = 3; ts = "2026-09-30T12:00:00Z"; verb = "session.close"; requestId = "0b000000-0000-4000-8000-0000000000c1"; issuedAt = "2026-09-30T12:00:00.000Z"; args = [pscustomobject][ordered]@{ sessionId = "11111111-2222-4333-8444-555555555555"; expect = [pscustomobject][ordered]@{ ns = [pscustomobject][ordered]@{ device = "0f8fad5b-d9cb-469f-a165-70867728950e"; space = "windows" }; pid = 1234; procStart = "133420000000000000" }; reason = "the run is done" } }
$closeText = $ascii.GetString((Line $close))
Check ((Decode (Bytes $closeText)).ok) "CONTROL: a canonical session.close request with pid 1234 decodes"
Refused (Decode (Bytes ($closeText -replace '"pid":1234', '"pid":1234.0'))) "bad-frame" "whole number" "the same request with pid 1234.0 is refused"
Refused (Decode (Line ((Copy-Json $golden["req-node-info.json"]) | ForEach-Object { $_.verb = "exec"; $_ }))) "bad-frame" "unsupported-verb" "a frame naming a verb the table lacks is refused with the contract's reason"
$sp = Copy-Json $golden["req-session-spawn.json"]
$sp.args | Add-Member -NotePropertyName argv -NotePropertyValue @("cmd.exe")
Refused (Decode (Line $sp)) "bad-frame" "has 'argv'" "a frame smuggling an argv is refused on receipt"
$bad = ConvertTo-HordeFrameBytes -Frame $sp -Contract $contract
Check ((-not $bad.ok) -and $bad.code -ceq "bad-frame" -and $null -eq $bad.bytes) "and it is refused at the sender, which produces no bytes"

Write-Host ""
Write-Host "--- C. every cap holds: just under passes, just over is refused ---" -ForegroundColor Cyan

function Limit-Case {
    # A frame built by Build with a string or list of Size, through the sender and the receiver.
    param([scriptblock]$Build, [int]$Size, $Contract = $contract)
    $f = & $Build $Size
    $s = ConvertTo-HordeFrameBytes -Frame $f -Contract $Contract
    $r = Decode (Line $f) -Contract $Contract
    return [pscustomobject]@{ sent = $s; got = $r }
}
function Cap-Pair {
    param([string]$Name, [scriptblock]$Build, [int]$Cap, [string]$Part, $Contract = $contract)
    $under = Limit-Case $Build $Cap $Contract
    $over = Limit-Case $Build ($Cap + 1) $Contract
    Check ($under.sent.ok -and $under.got.ok) ($Name + ": at the cap (" + $Cap + ") the frame is sent and received")
    if (-not ($under.sent.ok -and $under.got.ok)) { Write-Host ("         " + $under.sent.reason + " / " + $under.got.reason) -ForegroundColor DarkYellow }
    Check ((-not $over.sent.ok) -and $over.sent.code -ceq "oversized" -and (Says $over.sent.reason $Part)) ($Name + ": one over, the sender refuses it as oversized, naming " + $Part)
    Check ((-not $over.got.ok) -and $over.got.code -ceq "oversized" -and (Says $over.got.reason $Part)) ($Name + ": one over, the receiver refuses it as oversized")
    if ($over.sent.ok -or $over.got.ok) { Write-Host ("         " + $over.sent.reason + " / " + $over.got.reason) -ForegroundColor DarkYellow }
}
$L = $contract.limits
Cap-Pair "summaryBytes (a handoff document)" { param($n) $x = Copy-Json $golden["res-handoff-known.json"]; $x.result.value.document = "d" * $n; $x } $L["summaryBytes"] '$.result.value.document'
Cap-Pair "summaryBytes counted on the wire (e-acute is 6 bytes)" { param($n) $x = Copy-Json $golden["res-handoff-known.json"]; $x.result.value.document = ("d" * ($n % 6)) + ([string][char]0xE9 * [Math]::Floor($n / 6)); $x } $L["summaryBytes"] '$.result.value.document'
$e1 = Limit-Case { param($n) $x = Copy-Json $golden["res-handoff-known.json"]; $x.result.value.document = [string][char]0xE9 * $n; $x } 10923
Check ((-not $e1.got.ok) -and (Says $e1.got.reason "65538 bytes on the wire")) "10923 e-acutes - fewer characters than the cap - are 65538 bytes on the wire and refused"
Cap-Pair "textBytes (a spawn prompt)" { param($n) $x = Copy-Json $golden["req-session-spawn.json"]; $x.args.prompt.text = "p" * $n; $x } $L["textBytes"] '$.args.prompt.text'
Cap-Pair "reasonBytes (an error's reason)" { param($n) $x = Copy-Json $golden["res-error-unsupported.json"]; $x.error.reason = "r" * $n; $x } $L["reasonBytes"] '$.error.reason'
Cap-Pair "reasonBytes (a nested answer's reason)" { param($n) $x = Copy-Json $golden["res-clone-status.json"]; $x.result.value.ahead.reason = "r" * $n; $x } $L["reasonBytes"] '$.result.value.ahead.reason'
Cap-Pair "listItems (an unowned report)" { param($n) $x = [pscustomobject][ordered]@{ v = 1; kind = "req"; id = "0a000000-0000-4000-8000-0000000000f1"; seq = 1; ts = "2026-09-30T12:00:00Z"; verb = "unowned.report"; requestId = "0b000000-0000-4000-8000-0000000000f1"; issuedAt = "2026-09-30T12:00:00.000Z"; args = [pscustomobject][ordered]@{ sessions = @(1..$n | ForEach-Object { [pscustomobject]@{ sessionId = ("s" + $_) } }); observedAt = "2026-09-30T12:00:00Z" } }; $x } $L["listItems"] '$.args.sessions'
# nameBytes bounds strings whose patterns already bound them below it, so it is proved on a copy of
# the contract with the cap lowered: the check is the same code whatever the number.
$small = [pscustomobject]@{ frame = $contract.frame; verbs = $contract.verbs; rows = $contract.rows; limits = @{} }
foreach ($k in $contract.limits.Keys) { $small.limits[$k] = $contract.limits[$k] }
$small.limits["nameBytes"] = 40
Cap-Pair "nameBytes (a hello name, cap lowered to 40, above every id and time in the frame)" { param($n) $x = Copy-Json $golden["hello-node.json"]; $x.hello.name = "n" * $n; $x } 40 '$.hello.name' $small
$tl = Test-HordeProtocolLimits -Frame $golden["res-node-info-known.json"] -Contract $contract
Check (@($tl).Count -eq 0) "CONTROL: a golden frame is within every cap"

# THE FRAME CAP. No valid frame reaches 1 MiB (the largest field is 64 KiB), so it is proved two ways:
# with a cap set to a golden frame's exact length, and with raw lines around the default cap.
$sp0 = $golden["req-session-spawn.json"]
$len = (Line $sp0).Length
Check ((ConvertTo-HordeFrameBytes -Frame $sp0 -Contract $contract -FrameBytes $len).ok) ("a frame exactly at a " + $len + "-byte cap is sent")
$o = ConvertTo-HordeFrameBytes -Frame $sp0 -Contract $contract -FrameBytes ($len - 1)
Check ((-not $o.ok) -and $o.code -ceq "oversized" -and (Says $o.reason ("over the frame cap of " + ($len - 1)))) "the same frame against a cap one byte smaller is refused at the sender"
Check ((Decode (Line $sp0) -FrameBytes $len).ok) "and received at its exact length"
Refused (Decode (Line $sp0) -FrameBytes ($len - 1)) "oversized" ("over the frame cap of " + ($len - 1)) "and refused on receipt one byte over"
$cap = $L["frameBytes"]
$atCap = Bytes ("a" * $cap)
Refused (Decode $atCap) "bad-frame" "not JSON" "a 1 MiB line of text is within the frame cap: it is parsed, and refused as not JSON"
$overCap = Bytes ("a" * ($cap + 1))
Refused (Decode $overCap) "oversized" ("over the frame cap of " + $cap) "one byte more is refused as oversized before it is parsed"
Check (Throws { Get-HordeFrameCap -Contract $contract -FrameBytes 8388608 } "above the ceiling") "a frame cap above the 4 MiB ceiling is refused"
Check (Throws { Get-HordeFrameCap -Contract $contract -FrameBytes 0 } "positive whole number") "a frame cap of 0 is refused"

Write-Host ""
Write-Host "--- D. a stream: line by line, LF or CRLF, a BOM only first, and the first non-frame closes it ---" -ForegroundColor Cyan

function Read-All {
    # Every frame a stream yields, and how it ended.
    param([byte[]]$Bytes, $FrameBytes = $null)
    $ms = New-Object System.IO.MemoryStream (, $Bytes)
    $r = New-HordeFrameReader -Stream $ms -Contract $contract -FrameBytes $FrameBytes
    $frames = New-Object System.Collections.ArrayList
    $last = $null
    for ($i = 0; $i -lt 100; $i++) {
        $last = Receive-HordeFrame -Reader $r
        if ($last.state -cne "frame") { break }
        [void]$frames.Add($last.frame)
    }
    $again = Receive-HordeFrame -Reader $r
    return [pscustomobject]@{ frames = @($frames); end = $last; again = $again; reader = $r }
}
$three = @("hello-node.json", "req-node-info.json", "ping.json")
$lf = Join-Bytes @($three | ForEach-Object { Join-Bytes @((Line $golden[$_]), [byte[]](10)) })
$crlf = Join-Bytes @($three | ForEach-Object { Join-Bytes @((Line $golden[$_]), [byte[]](13, 10)) })
$a = Read-All $lf
Check ($a.frames.Count -eq 3 -and $a.end.state -ceq "end") "three LF lines give three frames, then a clean end"
$a = Read-All $crlf
Check ($a.frames.Count -eq 3 -and $a.end.state -ceq "end") "three CRLF lines give the same three frames"
$a = Read-All (Join-Bytes @([byte[]](0xEF, 0xBB, 0xBF), $lf))
Check ($a.frames.Count -eq 3 -and $a.end.state -ceq "end") "a BOM before the first line is stripped"
$mid = Join-Bytes @((Line $golden["ping.json"]), [byte[]](10, 0xEF, 0xBB, 0xBF), (Line $golden["ping.json"]), [byte[]](10))
$a = Read-All $mid
Check ($a.frames.Count -eq 1 -and $a.end.state -ceq "closed" -and (Says $a.end.reason "line 2") -and (Says $a.end.reason "middle of the stream")) "a BOM before the second line closes the stream at line 2"
$banner = Join-Bytes @((Line $golden["hello-node.json"]), [byte[]](10), (Bytes "Windows PowerShell"), [byte[]](13, 10), (Line $golden["ping.json"]), [byte[]](10))
$a = Read-All $banner
Check ($a.frames.Count -eq 1 -and $a.end.state -ceq "closed" -and $a.end.code -ceq "bad-frame" -and (Says $a.end.reason "line 2")) "a line that is not a frame closes the link, naming the line"
Check ($a.again.state -ceq "closed" -and $a.again.reason -ceq $a.end.reason) "and nothing after it is read: the next call gives the same closure, never the third line's frame"
$a = Read-All (Join-Bytes @((Line $golden["ping.json"]), [byte[]](10), (Bytes '{"v":1,"kind"')))
Check ($a.frames.Count -eq 1 -and $a.end.state -ceq "closed" -and (Says $a.end.reason "ended inside a frame")) "a stream that ends inside a frame is closed as such, not as a clean end"
$a = Read-All (New-Object byte[] 0)
Check ($a.frames.Count -eq 0 -and $a.end.state -ceq "end") "an empty stream is a clean end"
$flood = Bytes ("a" * (3 * 65536 + 100))
$a = Read-All $flood -FrameBytes 1000
Check ($a.end.state -ceq "closed" -and $a.end.code -ceq "oversized" -and (Says $a.end.reason "with no end of line")) "a line with no end past the cap closes the link as oversized"
Check ($a.reader.pending.Length -le 1004 + 65536) ("and the reader held at most one read past the cap (" + $a.reader.pending.Length + " bytes), never the whole flood")
# THE COMMITTED STREAM, AS THE CHECKOUT WROTE IT. With core.autocrlf on, git turns this fixture's LFs
# into CRLFs; without it they stay LF. Either way it must read the same.
$raw = [System.IO.File]::ReadAllBytes((Join-Path $fx "wire\stream.ndjson"))
$crs = @($raw | Where-Object { $_ -eq 13 }).Count
$a = Read-All $raw
Check ($a.frames.Count -eq 7 -and $a.end.state -ceq "end") ("the committed stream fixture gives its 7 frames (this checkout has " + $crs + " CRs in it)")
Check ((@($a.frames)[3].result.value.document).Contains([char]::ConvertFromUtf32(0x1F600))) "its escaped emoji arrives as the character"

Write-Host ""
Write-Host "--- E. PowerShell 5.1 as it really writes a pipe, measured live ---" -ForegroundColor Cyan

# A child powershell.exe writes frames the way a shim or a hub would, and the raw bytes are read back.
# Measured 2026-09-30 (remote/Protocol.ps1's header): Write-Output ends lines CRLF, and a pipe into a
# native program under a UTF-8 $OutputEncoding starts with a BOM. Each case asserts what it measured,
# so the day 5.1 behaves differently this suite says so, and each is then read by the frame reader.
$lines = @($three | ForEach-Object { $ascii.GetString((Line $golden[$_])) })
$tmp = Join-Path $env:TEMP ("horde-protocol-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $linesFile = Join-Path $tmp "lines.txt"
    [System.IO.File]::WriteAllLines($linesFile, [string[]]$lines, (New-Object System.Text.UTF8Encoding $false))
    $writer = Join-Path $tmp "writer.ps1"
    [System.IO.File]::WriteAllText($writer, ('Get-Content -LiteralPath "' + $linesFile + '" | ForEach-Object { Write-Output $_ }'), $ascii)
    $hex = Join-Path $tmp "rawin.ps1"
    [System.IO.File]::WriteAllText($hex, '$s = [Console]::OpenStandardInput(); $ms = New-Object System.IO.MemoryStream; $s.CopyTo($ms); [Console]::Out.Write([Convert]::ToBase64String($ms.ToArray()))', $ascii)
    function Get-ChildStdout {
        param([string]$Script)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -File `"" + $Script + "`""
        $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true; $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close()
        $errTask = $p.StandardError.ReadToEndAsync()
        $ms = New-Object System.IO.MemoryStream
        $p.StandardOutput.BaseStream.CopyTo($ms)
        $p.WaitForExit()
        $null = $errTask.Result
        $p.Dispose()
        return [byte[]]$ms.ToArray()
    }
    $out = Get-ChildStdout $writer
    $crlfCount = 0; for ($i = 1; $i -lt $out.Length; $i++) { if ($out[$i] -eq 10 -and $out[$i - 1] -eq 13) { $crlfCount++ } }
    Check ($crlfCount -eq 3 -and -not ($out.Length -ge 3 -and $out[0] -eq 0xEF)) ("MEASURED: Write-Output to a redirected stdout ends each of 3 lines CRLF, with no BOM (" + $crlfCount + " CRLFs)")
    $a = Read-All $out
    Check ($a.frames.Count -eq 3 -and $a.end.state -ceq "end") "and the reader takes all 3 frames from it"

    $piper = Join-Path $tmp "piper.ps1"
    [System.IO.File]::WriteAllText($piper, ('$OutputEncoding = [System.Text.Encoding]::UTF8; Get-Content -LiteralPath "' + $linesFile + '" | powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $hex + '"'), $ascii)
    $b64 = $ascii.GetString((Get-ChildStdout $piper)).Trim()
    $piped = [Convert]::FromBase64String($b64)
    Check ($piped.Length -ge 3 -and $piped[0] -eq 0xEF -and $piped[1] -eq 0xBB -and $piped[2] -eq 0xBF) "MEASURED: PowerShell piping into a native program under a UTF-8 `$OutputEncoding starts the pipe with a BOM"
    $bomsAfter = 0; for ($i = 3; $i -lt $piped.Length - 2; $i++) { if ($piped[$i] -eq 0xEF -and $piped[$i + 1] -eq 0xBB) { $bomsAfter++ } }
    Check ($bomsAfter -eq 0) "and only at its start"
    $a = Read-All $piped
    Check ($a.frames.Count -eq 3 -and $a.end.state -ceq "end") "the reader strips that BOM and takes all 3 frames"
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Check (-not (Test-Path -LiteralPath $tmp)) "the measurement's temp folder is gone"

Write-Host ""
Write-Host "--- F. version negotiation: the highest common version, or bye ---" -ForegroundColor Cyan

Check ((Select-HordeLinkProtocol -Ours @(1) -Theirs @(1)) -eq 1) "both speak 1: 1"
Check ((Select-HordeLinkProtocol -Ours @(1, 2) -Theirs @(2, 3)) -eq 2) "1,2 and 2,3: 2, the highest common"
Check ((Select-HordeLinkProtocol -Ours @(1, 2, 3) -Theirs @(3, 1)) -eq 3) "order does not matter"
Check ((Select-HordeLinkProtocol -Ours @(1) -Theirs @(2)) -eq 0) "1 and 2: none"
Check ((Select-HordeLinkProtocol -Ours @(1) -Theirs @("1")) -eq 0) "a version written as text is not a version"
$h = Resolve-HordeLinkHello -Hello $golden["hello-node.json"]
Check ($h.protocol -eq 1 -and $null -eq $h.bye) "a hello listing 1 is answered with protocol 1"
$h2 = Copy-Json $golden["hello-node.json"]; $h2.hello.protocols = @(2, 3)
$r = Resolve-HordeLinkHello -Hello $h2 -Seq 2
Check ($r.protocol -eq 0 -and $null -ne $r.bye -and $r.bye.kind -ceq "bye" -and $r.bye.bye.code -ceq "no-common-protocol") "a hello with no common version ends in bye, no-common-protocol"
Check ((Says $r.bye.bye.reason "this end speaks 1") -and (Says $r.bye.bye.reason "the other speaks 2, 3")) "the bye names both lists"
$e = ConvertTo-HordeFrameBytes -Frame $r.bye -Contract $contract
Check ($e.ok) "and the bye is a valid frame that encodes"
if (-not $e.ok) { Write-Host ("         " + $e.reason) -ForegroundColor DarkYellow }

# HOSTILE OFFERS (review of PR #45): a version of 2^40 threw at an [int] cast, and 256 offered versions
# made a bye reason of 1231 bytes, over its 1024 cap, so the bye could not be sent.
$huge = [long]1099511627776
Check ((Select-HordeLinkProtocol -Ours @(1) -Theirs @($huge)) -eq 0) "a version of 1099511627776 is compared, not cast: no common version, and no error"
Check ((Select-HordeLinkProtocol -Ours @(1) -Theirs @($huge, 1)) -eq 1) "and it does not hide a common version beside it"
$h3 = Copy-Json $golden["hello-node.json"]; $h3.hello.protocols = @($huge)
$r3 = Resolve-HordeLinkHello -Hello $h3 -Seq 3
Check ($r3.protocol -eq 0 -and $null -ne $r3.bye -and (ConvertTo-HordeFrameBytes -Frame $r3.bye -Contract $contract).ok) "a hello offering only 1099511627776 ends in a bye that is sent"
$h4 = Copy-Json $golden["hello-node.json"]; $h4.hello.protocols = @(2..257)
$r4 = Resolve-HordeLinkHello -Hello $h4 -Seq 4
$e4 = ConvertTo-HordeFrameBytes -Frame $r4.bye -Contract $contract
Check ($r4.protocol -eq 0 -and $e4.ok) "a hello offering 256 versions ends in a bye that is sent"
if (-not $e4.ok) { Write-Host ("         " + $e4.reason) -ForegroundColor DarkYellow }
Check ((Measure-HordeWireString $r4.bye.bye.reason) -le $L["reasonBytes"] -and (Says $r4.bye.bye.reason "and 240 more")) ("and its reason names 16 of them and counts the rest, within the reason cap (" + (Measure-HordeWireString $r4.bye.bye.reason) + " bytes)")
$long = "x" * 1000 + [char]::ConvertFromUtf32(0x1F600) * 300
$b5 = New-HordeLinkBye -Code "shutdown" -Reason $long -Seq 5
$e5 = ConvertTo-HordeFrameBytes -Frame $b5 -Contract $contract
Check ($e5.ok -and (Measure-HordeWireString $b5.bye.reason) -le $L["reasonBytes"] -and $b5.bye.reason.EndsWith(" ...")) "a bye whose reason is far over the cap, cut inside a run of surrogate pairs, is cut to fit and still sent"
if (-not $e5.ok) { Write-Host ("         " + $e5.reason) -ForegroundColor DarkYellow }
$b6 = New-HordeLinkBye -Code "shutdown" -Reason "short" -Seq 6
Check ($b6.bye.reason -ceq "short") "CONTROL: a reason within the cap is left as it is"

# THE RECEIVER BOUNDS A HELLO'S LISTS before negotiation reads them: versionItems entries, versionMax each.
$V = $L["versionItems"]; $M = $L["versionMax"]
Check ($V -eq 16 -and $M -eq 65535) "the contract bounds a hello at 16 versions of at most 65535"
$hOk = Copy-Json $golden["hello-node.json"]; $hOk.hello.protocols = @(1..$V)
Check ((Decode (Line $hOk)).ok) "a hello offering exactly versionItems versions is received"
$hOver = Copy-Json $golden["hello-node.json"]; $hOver.hello.protocols = @(1..($V + 1))
Refused (Decode (Line $hOver)) "oversized" "over the versionItems cap" "a hello offering one more is refused as oversized"
$hVer = Copy-Json $golden["hello-node.json"]; $hVer.hello.verbsVersions = @(1..($V + 1))
Refused (Decode (Line $hVer)) "oversized" "verbsVersions has" "and so is one listing one verbs version too many"
$hMax = Copy-Json $golden["hello-node.json"]; $hMax.hello.protocols = @(1, $M)
Check ((Decode (Line $hMax)).ok) "a hello offering version versionMax is received"
$hBig = Copy-Json $golden["hello-node.json"]; $hBig.hello.protocols = @(1, ($M + 1))
Refused (Decode (Line $hBig)) "oversized" "over the versionMax cap" "a hello offering versionMax + 1 is refused as oversized"
$hHuge = Copy-Json $golden["hello-node.json"]; $hHuge.hello.protocols = @($huge)
Refused (Decode (Line $hHuge)) "oversized" "1099511627776" "and so is one offering 1099511627776"
$sent = ConvertTo-HordeFrameBytes -Frame $hOver -Contract $contract
Check ((-not $sent.ok) -and $sent.code -ceq "oversized") "the sender refuses to send a hello over versionItems too"

Write-Host ""
Write-Host "--- G. damaged frames, generated: nothing throws, nothing passes as what it is not ---" -ForegroundColor Cyan

# Seeded, so a failure is reproducible: the seed and the case number are printed.
$seed = 20260930
$rng = New-Object System.Random $seed
$codes = @("bad-frame", "unknown-version", "oversized")
$cases = 0; $accepted = 0; $refused = 0; $bad = 0
foreach ($n in $goldenNames) {
    $base = Line $golden[$n]
    for ($k = 0; $k -lt 40; $k++) {
        $cases++
        $bytes = New-Object System.Collections.Generic.List[byte]
        $bytes.AddRange([byte[]]$base)
        $op = $rng.Next(0, 6)
        $at = $rng.Next(0, $bytes.Count)
        switch ($op) {
            0 { $bytes[$at] = [byte]$rng.Next(0, 256) }
            1 { $bytes.RemoveAt($at) }
            2 { $bytes.Insert($at, [byte]$rng.Next(0, 256)) }
            3 { $bytes.RemoveRange($at, $bytes.Count - $at) }
            4 { $bytes[$at] = [byte]$rng.Next(0x20, 0x7F) }
            5 { $cut = $rng.Next($at, $bytes.Count); $bytes.InsertRange($at, $bytes.GetRange($at, $cut - $at).ToArray()) }
        }
        $line = $bytes.ToArray()
        $res = $null
        try { $res = Decode $line -StreamStart:($rng.Next(0, 2) -eq 1) }
        catch { $bad++; Write-Host ("         seed " + $seed + " case " + $cases + " (" + $n + ", op " + $op + "): threw " + $_.Exception.Message) -ForegroundColor Red; continue }
        if ($res.ok) {
            $accepted++
            # Accepted means: the contract passes it, and it is exactly the bytes Horde would write.
            $again = ConvertTo-HordeWireText $res.frame
            $s0 = 0; $e0 = $line.Length
            if ($e0 -ge 3 -and $line[0] -eq 0xEF -and $line[1] -eq 0xBB -and $line[2] -eq 0xBF) { $s0 = 3 }
            if ($e0 -gt $s0 -and $line[$e0 - 1] -eq 13) { $e0-- }
            $core = $ascii.GetString($line, $s0, $e0 - $s0)
            $ok2 = (@(Test-HordeLinkFrame -Frame $res.frame -Contract $contract).Count -eq 0)
            if (-not $ok2 -or $core -cne $again) { $bad++; Write-Host ("         case " + $cases + " accepted something that is not a valid canonical frame") -ForegroundColor Red }
        } else {
            $refused++
            if ($codes -cnotcontains $res.code -or "$($res.reason)".Trim() -eq "") { $bad++; Write-Host ("         case " + $cases + " refused without a known code and a reason: " + $res.code) -ForegroundColor Red }
        }
    }
}
for ($k = 0; $k -lt 100; $k++) {
    $cases++
    $junk = New-Object byte[] ($rng.Next(0, 300))
    $rng.NextBytes($junk)
    try { $res = Decode $junk; if ($res.ok -or $codes -cnotcontains $res.code) { $bad++ } else { $refused++ } } catch { $bad++ }
}
Write-Host ("         " + $cases + " cases: " + $accepted + " still valid frames, " + $refused + " refused, " + $bad + " wrong") -ForegroundColor DarkGray
Check ($bad -eq 0) ("every one of " + $cases + " damaged or random lines is either a valid canonical frame or refused with a code and a reason, and none throws")
Check ($refused -gt $cases / 2) "and the generator really damages frames: most are refused"

Complete-HordeSuite -Success "the wire carries exactly a frame in printable ASCII, within every cap, and refuses everything else with a reason"
