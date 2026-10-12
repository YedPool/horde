# DOES AN ANSWER FROM THE FOUNDER'S PHONE ENTER THE DECISIONS LIST AS HIS OWN WORDS, BY ITS OWN ROUTE,
# CARRYING THE HASH OF THE PROOF THAT IT CAME FROM HIM - AND NOTHING ELSE MAY CLAIM THAT ROUTE?
#
# decisions/Rules.ps1's route "phone" and its evidence, through decisions/Operations.ps1's one entry
# point, against stores this suite makes (relay design 2026-10-09, PR plan item 5; the founder's
# decision of the same day: phone answers enter decisions as a new route, phone, and the passkey
# signature is kept in relay's own journal, with only its hash in the decision record). It attacks:
#   - THE ROUTE'S CLOSED LIST: only the founder speaks by it, only the founder's own caller records it,
#     and it always states the wording on screen - like the window, and unlike words written down
#     from chat;
#   - THE EVIDENCE: required by the phone route, refused on every other, and only ever 64 lower-case
#     hex digits - a SHA-256, never the proof itself;
#   - SECRETS ARE STILL REFUSED FIRST, before the evidence's own shape, and never repeated;
#   - IDEMPOTENCY: the same answer delivered again under the same id, carrying another delivery's proof,
#     is the first record answered again - the first answer wins - and other words under that id are
#     refused;
#   - A STORED RECORD IS A FACT: its evidence reads back verbatim, a damaged one is unreadable, and the
#     view shows it.
#   - WHO SIGNED (signedBy, 2026-10-12): the key id of the passkey the relay channel verified the answer
#     against is kept once, in the record, on the route phone only - refused on every other route and in
#     every other spelling - and Get-HordeDecisionSigner, the one reader of it for a claim, names a
#     passkey only for a phone record with its evidence and a key id: never for a record written before
#     the member, and never for a record by another route that holds it anyway.
#
# EVERY STORE IS A FOLDER THIS SUITE MADE under %TEMP% and removes (CONTRIBUTING 9), named in each call
# with -Root. The real store under the user profile is listed before and after, and must not have changed.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "decisions\Operations.ps1")

$defs = Get-HordeDecisionDefinitions
$script:work = Join-Path $env:TEMP ("horde-decisions-phone-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $script:work | Out-Null
$script:n = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-RealStoreListing {
    $real = Join-Path (Join-Path (Join-Path "$env:USERPROFILE" ".horde") "store") "decisions"
    if (-not (Test-Path -LiteralPath $real)) { return "(no store)" }
    return (@(Get-ChildItem -LiteralPath $real -Force | Sort-Object Name | ForEach-Object { $_.Name + "|" + $_.Length + "|" + $_.LastWriteTimeUtc.Ticks }) -join ";")
}
$realBefore = Get-RealStoreListing

function New-TestStore { $script:n++; return (Join-Path $script:work ("home-" + $script:n + "\store\decisions")) }
function New-Id { return [guid]::NewGuid().ToString("N") }
function New-Evidence {
    # A SHA-256 in lower-case hex, as the relay channel computes it over a journal record.
    param([string]$Of = (New-Id))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $d = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Of)) } finally { $sha.Dispose() }
    return (($d | ForEach-Object { $_.ToString("x2") }) -join "")
}
function Invoke-Op {
    # One operation against a store of this suite. A throw becomes an unknown answer saying so, and
    # every known value is held to schema/decision-result.v1 here.
    param([string]$Store, [string]$Operation, $Request)
    $answer = $null
    try { $answer = Invoke-HordeDecision -Operation $Operation -Request $Request -Root $Store }
    catch { return (New-HordeUnknown -Reason ("THREW: " + $_.Exception.Message)) }
    if (-not (Test-HordeAnswer $answer)) { return (New-HordeUnknown -Reason "NOT AN ANSWER") }
    if ($answer.state -ceq "known") {
        $off = @(Test-HordeSchema -Value $answer.value -Schema $defs.resultSchema)
        if ($off.Count -gt 0) { return (New-HordeUnknown -Reason ("OFF SCHEMA: " + ($off -join "; "))) }
    }
    return $answer
}
function Add-Q { param([string]$Store) return (Invoke-Op $Store "add" @{ id = (New-Id); actor = "warchief"; question = @{ title = "Should the closing sound play when the assistant closes?"; kind = "yes-no"; whatItIs = "The app has no closing sound today."; group = "voice"; askedBy = "orc-b" } }) }
function Phone {
    # The founder's answer from his phone, as the relay channel sends it, unless the parameters say
    # otherwise. -Evidence "-" leaves the evidence out; -Wording 0 leaves the wording out.
    # -SignedBy names the passkey that signed; without it the request names none, as before 2026-10-12.
    param([string]$Store, [string]$Text = "Yes, play it.", [string]$Evidence = "", [int]$Wording = 1, [string]$Speaker = "founder", [string]$Actor = "founder", [string]$Route = "phone", [string]$Id = "", [int]$Number = 1, [string]$SignedBy = "")
    if ($Id -eq "") { $Id = New-Id }
    if ($Evidence -eq "") { $Evidence = New-Evidence }
    $request = @{ id = $Id; actor = $Actor; number = $Number; speaker = $Speaker; route = $Route; text = $Text }
    if ($Evidence -ne "-") { $request["evidence"] = $Evidence }
    if ($Wording -gt 0) { $request["wordingVersion"] = $Wording }
    if ($SignedBy -ne "") { $request["signedBy"] = $SignedBy }
    return (Invoke-Op $Store "say" $request)
}
function Get-Outcome { param($Answer) if ($Answer.state -cne "known") { return ($Answer.state + ": " + $Answer.reason) }; return "$($Answer.value.outcome)" }
function Test-Refused { param($Answer, [string]$Text) return ($Answer.state -ceq "known" -and $Answer.value.outcome -ceq "refused" -and @($Answer.value.findings | Where-Object { "$_".Contains($Text) }).Count -gt 0) }
function Get-Count { param([string]$Store) if (-not (Test-Path -LiteralPath $Store)) { return 0 }; return @(Get-ChildItem -LiteralPath $Store -File).Count }
function Read-Record {
    # A record of the store as parsed JSON; one with no members when it is not there, so the checks that
    # read it fail by name instead of raising an error.
    param([string]$Store, [long]$Sequence)
    $p = Join-Path $Store ($Sequence.ToString("D10") + ".json")
    if (-not (Test-Path -LiteralPath $p)) { return [pscustomobject]@{ kind = "(missing)"; actor = ""; data = [pscustomobject]@{} } }
    return ([System.IO.File]::ReadAllText($p, $utf8) | ConvertFrom-Json)
}
function Get-Member { param($Object, [string]$Name) if ($null -eq $Object -or $null -eq $Object.PSObject.Properties[$Name]) { return "(no " + $Name + ")" }; return $Object.$Name }
function Get-Said {
    # The message a say answered with, or a stand-in that fails every check that reads it.
    param($Answer)
    if ($Answer.state -ceq "known" -and $null -ne $Answer.value.PSObject.Properties["message"]) { return $Answer.value.message }
    return [pscustomobject]@{ sequence = -1; text = "(no message)"; route = ""; routeShown = ""; recordedBy = ""; speaker = ""; wordingStated = $false; wordingVersion = -1; evidence = "(no message)" }
}
function Get-Thread {
    param([string]$Store, [int]$Number = 1)
    $a = Invoke-Op $Store "show" @{ number = $Number }
    if ($a.state -cne "known" -or $a.value.outcome -cne "done") { return [pscustomobject]@{ count = -1; turn = (Get-Outcome $a); messages = @() } }
    return $a.value.question.thread
}

try {
    Write-Host ""
    Write-Host "--- the route phone: the founder's own words, recorded by his own caller, with the wording on screen ---" -ForegroundColor Cyan
    Check ((@(Get-HordeDecisionRoutes) -ccontains "phone")) ("phone is one of the routes words arrive by (" + (@(Get-HordeDecisionRoutes) -join ", ") + ")")
    $s = New-TestStore
    $null = Add-Q $s
    $proof = New-Evidence -Of "journal record one"
    $a = Phone $s -Evidence $proof
    $m = Get-Said $a
    Check ((Get-Outcome $a) -ceq "done" -and $m.text -ceq "Yes, play it." -and $m.speaker -ceq "founder" -and $m.route -ceq "phone" -and $m.recordedBy -ceq "founder") ("an answer from the phone is recorded as the founder's words, by the route phone, by his own caller (" + (Get-Outcome $a) + ")")
    Check ($m.routeShown -ceq "answered on the founder's phone" -and $m.routeShown -cne "typed in the window" -and $m.routeShown -cne "recorded by the warchief from chat") ("it is shown in words of its own, never as the window or as chat (" + $m.routeShown + ")")
    Check ($m.wordingStated -eq $true -and $m.wordingVersion -eq 1) "and it says which wording was on the phone's screen"
    Check ((Get-Member $m "evidence") -ceq $proof) "the answer hands the evidence back, exactly as given"
    $rec = Read-Record $s 2
    Check ($rec.kind -ceq "message-said" -and $rec.actor -ceq "founder" -and $rec.data.route -ceq "phone" -and (Get-Member $rec.data "evidence") -ceq $proof) "the record holds the route and the evidence: the hash of the relay journal record that proved the answer"
    Check ((@($rec.data.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "evidence,number,route,speaker,text,wordingVersion") "and no more than that: the proof itself is relay's, never the decision record's"
    $t = Get-Thread $s
    Check ($t.count -eq 1 -and $t.turn -ceq "warchief") "his answer passes the turn to the warchief, as his words always do"
    Check ((Get-Member (@($t.messages) | Select-Object -First 1) "evidence") -ceq $proof) "and show hands the evidence back with the message"

    Write-Host ""
    Write-Host "--- nobody else answers by phone, and no phone answer goes without its wording or its proof ---" -ForegroundColor Cyan
    $s = New-TestStore
    $null = Add-Q $s
    Check (Test-Refused (Phone $s -Speaker "warchief") "only these speak: founder") "the warchief's words never arrive by phone"
    Check (Test-Refused (Phone $s -Actor "warchief") "recorded only by: founder") "and the warchief cannot record words as answered on the phone"
    Check (Test-Refused (Phone $s -Wording 0) "('wordingVersion')") "a phone answer that does not say which wording it saw is refused"
    Check (Test-Refused (Phone $s -Evidence "-") "'evidence'") "a phone answer without its evidence is refused"
    Check ((Get-Count $s) -eq 1) "and none of the four was written"
    $w = Invoke-Op $s "say" @{ id = (New-Id); actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "typed"; wordingVersion = 1; evidence = (New-Evidence) }
    Check (Test-Refused $w "'evidence'") "evidence on words typed in the window is refused: no route but phone carries it"
    $c = Invoke-Op $s "say" @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = "heard"; evidence = (New-Evidence) }
    Check (Test-Refused $c "'evidence'") "and so is evidence on words written down from chat"
    $ok = Invoke-Op $s "say" @{ id = (New-Id); actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "typed"; wordingVersion = 1 }
    Check ((Get-Outcome $ok) -ceq "done" -and (Get-Member (Get-Said $ok) "evidence") -ceq "") "CONTROL: the same window words without it are written, and carry no evidence"
    foreach ($bad in @(("A" * 64), ("a" * 63), ("a" * 65), ("g" * 64), "")) {
        $b = Phone $s -Evidence $(if ($bad -eq "") { " " } else { $bad })
        Check ((Get-Outcome $b) -ceq "refused") ("evidence '" + $bad + "' is not a SHA-256 in lower-case hex, and is refused (" + (Get-Outcome $b) + ")")
    }
    Check ((Get-Count $s) -eq 2) "nothing of those was written: the question and the one window message"

    Write-Host ""
    Write-Host "--- a secret is refused first, and never repeated ---" -ForegroundColor Cyan
    $s = New-TestStore
    $null = Add-Q $s
    $token = "ghp_" + ("Ab3" * 10)
    $x = Phone $s -Text ("the token is " + $token)
    Check ((Test-Refused $x "looks like an access token") -and -not ((ConvertTo-Json -InputObject $x.value -Depth 8 -Compress).Contains($token))) "a secret in a phone answer is refused, and the refusal does not repeat it"
    $y = Phone $s -Evidence $token
    $yText = ConvertTo-Json -InputObject $y.value -Depth 8 -Compress
    Check ((Test-Refused $y "'evidence' holds what looks like an access token") -and -not $yText.Contains($token)) "a secret where the evidence goes is refused AS A SECRET, before its shape is judged, and not repeated"
    Check (@($y.value.findings).Count -eq 1) ("and the secret is the only finding: the schema's, which would quote the pattern, never ran (" + (@($y.value.findings) -join " | ") + ")")
    Check ((Get-Count $s) -eq 1) "nothing was written"

    Write-Host ""
    Write-Host "--- the same answer delivered twice is one record: the first answer wins ---" -ForegroundColor Cyan
    $s = New-TestStore
    $null = Add-Q $s
    $id = New-Id
    $first = New-Evidence -Of "first delivery"
    $second = New-Evidence -Of "second delivery"
    $a1 = Phone $s -Id $id -Evidence $first
    $a2 = Phone $s -Id $id -Evidence $second
    Check ((Get-Outcome $a1) -ceq "done" -and (Get-Outcome $a2) -ceq "replayed" -and $a2.value.sequence -eq $a1.value.sequence) ("the same words under the same id, carrying another delivery's proof, are the first record answered again (" + (Get-Outcome $a2) + ")")
    Check ((Get-Count $s) -eq 2 -and (Get-Member (Read-Record $s 2).data "evidence") -ceq $first -and (Get-Member (Get-Said $a2) "evidence") -ceq $first) "one record, holding the first delivery's evidence: the proof of the answer that won"
    $a3 = Phone $s -Id $id -Text "No, keep it silent."
    Check ((Test-Refused $a3 "already used for a different request") -and (Get-Count $s) -eq 2) "other words under that id are refused, and the first answer stands"
    $a4 = Phone $s -Text "No, keep it silent."
    Check ((Get-Outcome $a4) -ceq "done" -and (Get-Count $s) -eq 3) "CONTROL: the same other words under a new id are a second answer, kept after the first"

    Write-Host ""
    Write-Host "--- a stored record is a fact: its evidence reads back, and a damaged one is unreadable ---" -ForegroundColor Cyan
    $s = New-TestStore
    $null = Add-Q $s
    $null = Phone $s -Evidence (New-Evidence -Of "kept")
    $path = Join-Path $s "0000000002.json"
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    $list = Invoke-Op $s "show" @{ number = 1 }
    Check ((Get-Outcome $list) -ceq "done" -and @($list.value.unreadable).Count -eq 0 -and $list.value.question.thread.count -eq 1) "CONTROL: the record reads, whole"
    $m = [regex]::Match($text, '"evidence":"([0-9a-f]{64})"')
    Check ($m.Success) "CONTROL: the record spells its evidence where this suite will damage it"
    [System.IO.File]::WriteAllText($path, $text.Replace($m.Groups[1].Value, $m.Groups[1].Value.ToUpperInvariant()), $utf8)
    $list = Invoke-Op $s "show" @{ number = 1 }
    Check ((Get-Outcome $list) -ceq "done" -and @($list.value.unreadable).Count -eq 1 -and $list.value.question.thread.count -eq 0) "a record whose evidence is not a lower-case SHA-256 is unreadable, and its words are not shown as proven"
    $s2 = New-TestStore
    $null = Add-Q $s2
    $null = Phone $s2
    $p2 = Join-Path $s2 "0000000002.json"
    $t2 = [System.IO.File]::ReadAllText($p2, $utf8)
    [System.IO.File]::WriteAllText($p2, [regex]::Replace($t2, ',"evidence":"[0-9a-f]{64}"', ''), $utf8)
    $l2 = Invoke-Op $s2 "show" @{ number = 1 }
    Check ((Get-Outcome $l2) -ceq "done" -and @($l2.value.unreadable).Count -eq 0 -and $l2.value.question.thread.count -eq 1 -and (Get-Member (@($l2.value.question.thread.messages) | Select-Object -First 1) "evidence") -ceq "") "a stored phone record without evidence is still read - stored records are facts - and shows no evidence rather than inventing one"
    Write-Host ""
    Write-Host "--- who signed: the passkey's key id, kept once in the record, on the route phone only ---" -ForegroundColor Cyan
    $s = New-TestStore
    $null = Add-Q $s
    $key = "0123456789abcdef0123456789abcdef"
    $proof = New-Evidence -Of "signed delivery"
    $a = Phone $s -Evidence $proof -SignedBy $key
    $m = Get-Said $a
    Check ((Get-Outcome $a) -ceq "done" -and (Get-Member $m "signedBy") -ceq $key) ("a phone answer that names the passkey that signed it is written, and hands the key id back (" + (Get-Outcome $a) + ")")
    $rec = Read-Record $s 2
    Check ((Get-Member $rec.data "signedBy") -ceq $key -and (@($rec.data.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object) -join ",") -ceq "evidence,number,route,signedBy,speaker,text,wordingVersion") "the record holds it, once, beside the evidence, and nothing else is new"
    Check ((Get-Member (@((Get-Thread $s).messages) | Select-Object -First 1) "signedBy") -ceq $key) "and show hands it back with the message"
    $plainPhone = Phone $s
    Check ((Get-Outcome $plainPhone) -ceq "done" -and (Get-Member (Get-Said $plainPhone) "signedBy") -ceq "" -and (Get-Member (Read-Record $s 3).data "signedBy") -ceq "(no signedBy)") "CONTROL: a phone answer that names no passkey is still written - a caller from before the member - and its record holds none"
    $before = Get-Count $s
    $w = Invoke-Op $s "say" @{ id = (New-Id); actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "typed"; wordingVersion = 1; signedBy = $key }
    Check (Test-Refused $w "carry no 'signedBy'") "signedBy on words typed in the window is refused: no passkey signed them"
    $c = Invoke-Op $s "say" @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "founder"; route = "chat-recorded"; text = "heard"; signedBy = $key }
    Check (Test-Refused $c "carry no 'signedBy'") "and so is signedBy on words written down from chat"
    $k = Invoke-Op $s "say" @{ id = (New-Id); actor = "warchief"; number = 1; speaker = "warchief"; route = "command"; text = "said"; signedBy = $key }
    Check (Test-Refused $k "carry no 'signedBy'") "and on the warchief's own words by command"
    foreach ($bad in @(("A" * 32), ("a" * 31), ("a" * 33), ("g" * 32), ("a" * 64), " ")) {
        $b = Phone $s -SignedBy $bad
        Check ((Get-Outcome $b) -ceq "refused") ("signedBy '" + $bad + "' is not a key id, and is refused (" + (Get-Outcome $b) + ")")
    }
    Check ((Get-Count $s) -eq $before) "nothing of those was written"
    # The rule's own words, when a caller reaches it without the schema.
    Check (@(Test-HordeDecisionSaying -Speaker "founder" -Route "phone" -Actor "founder" -Text "x" -EvidenceStated $true -Evidence $proof -SignedByStated $true -SignedBy ("A" * 32) | Where-Object { "$_".Contains("'signedBy' is not a key id") }).Count -eq 1) "the rules refuse a signedBy that is not 32 lower-case hex in their own words"
    Check (@(Test-HordeDecisionSaying -Speaker "founder" -Route "phone" -Actor "founder" -Text "x" -EvidenceStated $true -Evidence $proof -SignedByStated $true -SignedBy $key).Count -eq 0) "CONTROL: and take one that is"
    # It is not part of what makes a request the same: the first answer wins, with what it named.
    $s = New-TestStore
    $null = Add-Q $s
    $id = New-Id
    $old = Phone $s -Id $id
    $again = Phone $s -Id $id -SignedBy $key
    Check ((Get-Outcome $old) -ceq "done" -and (Get-Outcome $again) -ceq "replayed" -and $again.value.sequence -eq $old.value.sequence -and (Get-Member (Get-Said $again) "signedBy") -ceq "" -and (Get-Count $s) -eq 2) ("an answer recorded naming no passkey, handed over again naming one, is the first record answered again - and still names none (" + (Get-Outcome $again) + ")")
    # A stored record is a fact: one written before the member reads as it always did.
    $s = New-TestStore
    $null = Add-Q $s
    $null = Phone $s -SignedBy $key
    $path = Join-Path $s "0000000002.json"
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    Check ($text.Contains(',"signedBy":"' + $key + '"')) "CONTROL: the record spells its signedBy where this suite will change it"
    [System.IO.File]::WriteAllText($path, $text.Replace(',"signedBy":"' + $key + '"', ''), $utf8)
    $l = Invoke-Op $s "show" @{ number = 1 }
    Check ((Get-Outcome $l) -ceq "done" -and @($l.value.unreadable).Count -eq 0 -and $l.value.question.thread.count -eq 1 -and (Get-Member (@($l.value.question.thread.messages) | Select-Object -First 1) "signedBy") -ceq "") "a phone record written before records named the passkey is read as it always was, and names none"
    [System.IO.File]::WriteAllText($path, $text.Replace($key, $key.ToUpperInvariant()), $utf8)
    $l = Invoke-Op $s "show" @{ number = 1 }
    Check ((Get-Outcome $l) -ceq "done" -and @($l.value.unreadable).Count -eq 1 -and $l.value.question.thread.count -eq 0) "a record whose signedBy is not a key id is unreadable: its words are not shown, signed or not"
    # A record by another route that holds the member anyway - written by hand, or by a later version:
    # it is read, a fact, and shows what it holds; but it NAMES NOBODY (Get-HordeDecisionSigner).
    $s = New-TestStore
    $null = Add-Q $s
    $null = Invoke-Op $s "say" @{ id = (New-Id); actor = "founder"; number = 1; speaker = "founder"; route = "window"; text = "typed"; wordingVersion = 1 }
    $path = Join-Path $s "0000000002.json"
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    $forged = $text.Replace('"route":"window"', '"route":"window","signedBy":"' + $key + '"')
    Check ($forged -cne $text) "CONTROL: the window record spells its route where this suite forges beside it"
    [System.IO.File]::WriteAllText($path, $forged, $utf8)
    $l = Invoke-Op $s "show" @{ number = 1 }
    $fm = $(if ((Get-Outcome $l) -ceq "done" -and $l.value.question.thread.count -eq 1) { @($l.value.question.thread.messages)[0] } else { [pscustomobject]@{ route = "(unread)"; evidence = "(unread)"; signedBy = "(unread)" } })
    Check ($fm.route -ceq "window" -and $fm.signedBy -ceq $key) "a window record forged to hold a signedBy is read as the fact it is"
    $who = Get-HordeDecisionSigner -Route $fm.route -Evidence $fm.evidence -SignedBy $fm.signedBy
    Check ($who.keyId -ceq "" -and $who.why.Contains("typed in the window")) ("but it names no passkey: no passkey signs words by that route (" + $who.why + ")")
    Write-Host ""
    Write-Host "--- Get-HordeDecisionSigner: a passkey is named only for a phone record with its evidence and a key id ---" -ForegroundColor Cyan
    $ok = Get-HordeDecisionSigner -Route "phone" -Evidence $proof -SignedBy $key
    Check ($ok.keyId -ceq $key -and $ok.why -ceq "") "the route phone, its evidence and a key id: that passkey is named"
    foreach ($route in @("window", "chat-recorded", "command", "no-such-route", "")) {
        $nobody = Get-HordeDecisionSigner -Route $route -Evidence $proof -SignedBy $key
        Check ($nobody.keyId -ceq "" -and $nobody.why -cne "") ("by the route '" + $route + "' nobody is named, whatever the record holds (" + $nobody.why + ")")
    }
    $nobody = Get-HordeDecisionSigner -Route "phone" -Evidence "" -SignedBy $key
    Check ($nobody.keyId -ceq "" -and $nobody.why.Contains("no evidence")) "a phone record with no evidence names nobody"
    $nobody = Get-HordeDecisionSigner -Route "phone" -Evidence ("A" * 64) -SignedBy $key
    Check ($nobody.keyId -ceq "" -and $nobody.why.Contains("no evidence")) "nor one whose evidence is not spelled as evidence"
    $nobody = Get-HordeDecisionSigner -Route "phone" -Evidence $proof -SignedBy ""
    Check ($nobody.keyId -ceq "" -and $nobody.why.Contains("written before")) "a phone record written before the member names nobody, and says that is why"
    foreach ($bad in @(("A" * 32), ("a" * 31), ("a" * 33), ("a" * 32 + "`n"), ("g" * 32), "founder", $proof)) {
        $nobody = Get-HordeDecisionSigner -Route "phone" -Evidence $proof -SignedBy $bad
        Check ($nobody.keyId -ceq "" -and $nobody.why.Contains("not a key id")) ("a signedBy that is not a key id names nobody ('" + $bad.Trim() + "', " + $bad.Length + " characters)")
    }

    Write-Host ""
    Write-Host "--- list with messages: the window's view, for a reader that is not the window ---" -ForegroundColor Cyan
    # The relay's snapshot (channels/decisions) reads the open questions with their conversation through
    # this one option, not a parallel reader (review of relay PR 6, item 9).
    $s = New-TestStore
    $null = Add-Q $s
    $null = Phone $s -Text "With a chime."
    $plain = Invoke-Op $s "list" @{ state = "open" }
    $full = Invoke-Op $s "list" @{ state = "open"; messages = $true }
    Check ((Get-Outcome $plain) -ceq "done" -and $null -eq @($plain.value.questions)[0].thread.PSObject.Properties["messages"]) "CONTROL: a plain list carries each thread's counts, not its messages"
    $fm = @()
    if ((Get-Outcome $full) -ceq "done" -and $null -ne @($full.value.questions)[0].thread.PSObject.Properties["messages"]) { $fm = @(@($full.value.questions)[0].thread.messages) }
    Check ($fm.Count -eq 1 -and $fm[0].text -ceq "With a chime." -and $fm[0].route -ceq "phone") ("list with messages carries each thread's messages, as show does (" + (Get-Outcome $full) + ")")
    Check (Test-Refused (Invoke-Op $s "list" @{ state = "open"; messages = "yes" }) "messages") "messages is true or false, nothing else"
} finally {
    if ((Split-Path -Leaf $script:work) -match '^horde-decisions-phone-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $script:work)) "every store this suite made is gone"
Check ((Get-RealStoreListing) -ceq $realBefore) "the real store was not touched"

Complete-HordeSuite -Success "a phone answer is the founder's own words by its own route, with its wording and the hash of its proof; nothing else claims the route, a secret is refused first, and the first answer wins"
