# IS A FINDING KEPT ONLY WHEN IT IS ONE - A BOUNDED CLAIM WITH ITS NUMBERS AND WHAT THEY WERE COUNTED
# FROM - AND REFUSED WHOLE WHEN IT HOLDS CONVERSATION, A CREDENTIAL OR CUSTOMER DATA?
#
# core/Finding.ps1 (the pure reading of a finding's text) and core/FindingStore.ps1 (the local writer).
# SEEDED WITH REAL FINDINGS: test/fixtures/finding/g01.json to g12.json are the twelve generalisable
# findings a fleet analyst prepared on 2026-10-07, adapted to schema/finding.v1 - its free-text metric
# became metric.what, ranges became two values, names over 31 characters were shortened, the window,
# machine shape and record kinds were taken from the analyst's own notes, and words about one person
# were made general. Every one must read. Then every refusal is ATTACKED, each with a control that the
# same field with ordinary text is kept: a rule that refuses everything passes every attack. The writer
# runs in a home this suite creates under TEMP and removes; nothing here reads or writes the real home.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "core\FindingStore.ps1")

function Section { param([string]$Title) Write-Host ""; Write-Host ("--- " + $Title + " ---") -ForegroundColor Cyan }

$fxDir = Join-Path $root "test\fixtures\finding"
$seedText = [System.IO.File]::ReadAllText((Join-Path $fxDir "g01.json"))

function New-FindingText {
    # g01 with one change: -Set is a script block given the parsed finding to change in place.
    param([scriptblock]$Set = {})
    $f = ConvertFrom-HordeJson -Text $seedText
    & $Set $f
    return ($f | ConvertTo-Json -Depth 20)
}

function Read-Finding { param([string]$Body) return (Read-HordeFindingText -Text $Body) }

function Test-Refused {
    # Refused, with no finding, and with a reason matching -Like.
    param($Answer, [string]$Like)
    return ($Answer.state -ceq "refused" -and $null -eq $Answer.finding -and @($Answer.findings | Where-Object { $_ -like $Like }).Count -ge 1)
}

function Show { param($Answer) return ("state=" + $Answer.state + "; " + (@($Answer.findings) -join " | ")) }

Section "the twelve seeded findings all read"
$fixtures = @(Get-ChildItem -LiteralPath $fxDir -Filter "g*.json" -File | Sort-Object Name)
Check ($fixtures.Count -eq 12) ("CONTROL: the twelve seeded findings are there (" + $fixtures.Count + ")")
foreach ($fx in $fixtures) {
    $a = Read-Finding ([System.IO.File]::ReadAllText($fx.FullName))
    Check ($a.state -ceq "read" -and @($a.findings).Count -eq 0 -and $null -ne $a.finding) ($fx.Name + " reads (" + (Show $a) + ")")
}
$g1 = Read-Finding $seedText
Check ($g1.finding.confidence -ceq "medium" -and @($g1.finding.metric.numbers).Count -eq 7 -and @($g1.finding.metric.numbers[6].values).Count -eq 8) "the finding read is the file's: its confidence, its 7 figures, the 8 values of its series"
$g5 = Read-Finding ([System.IO.File]::ReadAllText((Join-Path $fxDir "g05.json")))
Check ($g5.finding.metric.countedFrom.window.from -ceq $g5.finding.metric.countedFrom.window.to) "a single snapshot (g05) has a window that starts and ends at once, and reads"
Check ((New-FindingText) -ne "" -and (Read-Finding (New-FindingText)).state -ceq "read") "CONTROL: g01 parsed and written again, unchanged, still reads"

Section "free text over its bound"
$long = (Read-Finding (New-FindingText { param($f) $f.claim = ("a" * 401) }))
Check (Test-Refused $long '*$.claim does not match*') ("a claim of 401 characters is refused (" + (Show $long) + ")")
Check ((Read-Finding (New-FindingText { param($f) $f.claim = ("a" * 400) })).state -ceq "read") "CONTROL: a claim of 400 characters reads"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.claim = "one line`nand a second" })) '*$.claim does not match*') "a claim of two lines is refused: a claim is one line"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.claim = "" })) '*$.claim does not match*') "an empty claim is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.proposedChange = ("b" * 601) })) '*$.proposedChange does not match*') "a proposed change of 601 characters is refused"
Check ((Read-Finding (New-FindingText { param($f) $f.proposedChange = ("b" * 600) })).state -ceq "read") "CONTROL: a proposed change of 600 characters reads"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.whyItGeneralises = ("c" * 401) })) '*$.whyItGeneralises does not match*') "a reason it generalises of 401 characters is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.what = ("d" * 401) })) '*$.metric.what does not match*') "a metric description of 401 characters is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.limits = ("e" * 401) })) '*$.limits does not match*') "a limits text of 401 characters is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.machine = ("m" * 161) })) '*machine does not match*') "a machine shape of 161 characters is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.recordKinds = @(("k" * 81)) })) '*recordKinds*does not match*') "a record kind of 81 characters is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.versions = @(("v" * 81)) })) '*versions*does not match*') "a version of 81 characters is refused"
$huge = Read-Finding ($seedText + (" " * 16384))
Check (Test-Refused $huge '*longer than 16384 characters*') ("a whole text over 16384 characters is refused before it is parsed (" + (Show $huge) + ")")

Section "what a finding holds: shape, lists, window"
$noCounted = Read-Finding (New-FindingText { param($f) $f.metric.PSObject.Properties.Remove("countedFrom") })
Check (Test-Refused $noCounted "*has no 'countedFrom'*") ("a finding with no countedFrom is refused (" + (Show $noCounted) + ")")
foreach ($field in @("claim", "metric", "proposedChange", "confidence", "whyItGeneralises", "schemaVersion")) {
    $a = Read-Finding (New-FindingText { param($f) $f.PSObject.Properties.Remove($field) }.GetNewClosure())
    Check (Test-Refused $a ("*has no '" + $field + "'*")) ("a finding with no " + $field + " is refused")
}
foreach ($field in @("recordKinds", "window", "machine", "versions")) {
    $a = Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.PSObject.Properties.Remove($field) }.GetNewClosure())
    Check (Test-Refused $a ("*has no '" + $field + "'*")) ("countedFrom with no " + $field + " is refused")
}
Check ((Read-Finding (New-FindingText { param($f) $f.PSObject.Properties.Remove("limits") })).state -ceq "read") "CONTROL: limits is optional"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f | Add-Member -NotePropertyName "chatLog" -NotePropertyValue "kept" })) "*'chatLog', which the schema does not allow*") "a field the schema does not have is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.confidence = "certain" })) "*confidence*not one of*") "a confidence outside high, medium and low is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.confidence = 0.9 })) "*confidence should be string*") "a confidence given as a number is refused: the list is closed"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.schemaVersion = 2 })) "*schemaVersion*not one of*") "a schema version other than 1 is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.numbers = @() })) "*metric.numbers holds 0 item(s); it needs at least 1*") "a finding with no numbers is refused"
$many = Read-Finding (New-FindingText { param($f) $f.metric.numbers = @(1..25 | ForEach-Object { [pscustomobject]@{ name = ("n" + $_); values = @(1) } }) })
Check (Test-Refused $many "*metric.numbers holds 25 items; it may hold at most 24*") ("25 numbers are refused (" + (Show $many) + ")")
Check ((Read-Finding (New-FindingText { param($f) $f.metric.numbers = @(1..24 | ForEach-Object { [pscustomobject]@{ name = ("n" + $_); values = @(1) } }) })).state -ceq "read") "CONTROL: 24 numbers read"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.numbers[0].values = @() })) "*metric.numbers (item 1).values holds 0 item(s)*") "a figure with no value is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.numbers[0].values = @(1..17) })) "*metric.numbers (item 1).values holds 17 items*") "a figure with 17 values is refused"
Check ((Read-Finding (New-FindingText { param($f) $f.metric.numbers[0].values = @(1..16) })).state -ceq "read") "CONTROL: a figure with 16 values reads"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.numbers[0].values = @("579") })) "*values*should be number*") "a value written as text is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.numbers[0].name = ("n" + ("a" * 31)) })) "*name does not match*") "a figure's name of 32 characters is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.recordKinds = @() })) "*recordKinds holds 0 item(s)*") "no record kinds is refused: a number with no record behind it says nothing"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.versions = @(1..11 | ForEach-Object { "v" + $_ }) })) "*versions holds 11 items*") "11 versions are refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.recordKinds = @(1..11 | ForEach-Object { "kind " + $_ }) })) "*recordKinds holds 11 items*") "11 record kinds are refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.window.to = "2026-10-05T14:54Z" })) "*window ends before it starts*") "a window that ends before it starts is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.window.from = "2026-02-30T10:00Z" })) "*window.from is not a date and time that exists*") "a window starting on February 30th is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.window.to = "2026-10-07 18:23" })) "*window.to does not match*") "a window end that is not UTC in the schema's form is refused"
Check ((Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.window.to = "2026-10-07T18:23:59Z" })).state -ceq "read") "CONTROL: a window end with seconds reads"

Section "text that is not a finding's"
Check (Test-Refused (Read-Finding "") "*not a JSON object*") "an empty text is refused"
Check (Test-Refused (Read-Finding "{ not json") "*not a JSON object*") "a text that is not JSON is refused"
Check (Test-Refused (Read-Finding ("[" + $seedText + "]")) "*not a JSON object*") "a list of findings is refused: one file is one finding"
$twice = Read-Finding ($seedText.Replace('"confidence": "medium"', '"confidence": "medium", "confidence": "high"'))
Check (Test-Refused $twice "*says one thing twice*confidence*") ("a key given twice is refused, not read as whichever the parser kept (" + (Show $twice) + ")")
$wide = Read-Finding ($seedText.Replace('"claim": "A send', ('"claim": "' + [char]0x00E9 + ' A send')))
Check (Test-Refused $wide "*U+00E9, which is not ASCII*") ("a character that is not ASCII is refused, and named by its code (" + (Show $wide) + ")")
Check ((Read-Finding ($seedText.Replace('"claim": "A send', '"claim": "\u00e9 A send'))).state -ceq "read") "CONTROL: the same character written as a \u escape reads"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.claim = ("a bell" + [char]7 + " rings") })) "*U+0007*") "a control character inside a text is refused, through decisions/Rules.ps1's own check"

Section "conversation is refused"
$chatLines = "User: why are the sends slow?`nAssistant: because each one waits for delivery."
$chat = Read-Finding (New-FindingText { param($f) $f.limits = $chatLines }.GetNewClosure())
Check (Test-Refused $chat "*limits holds what looks like conversation: a line that opens with a speaker's label*") ("a chat transcript in a text is refused (" + (Show $chat) + ")")
Check (-not ((@($chat.findings) -join " ").Contains("why are the sends slow"))) "the refusal does not repeat the conversation"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.claim = "Sends are slow, as in human: they wait ai: yes" })) "*conversation: two or more speakers' labels*") "a chat pasted onto one line is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.proposedChange = "Lead reviewer: run sends in the background`nOwner: agreed, from today" })) "*conversation: two or more dialogue lines*") "two dialogue lines under any names are refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.proposedChange = "> the sends block`n> so run them in the background" })) "*conversation: two or more quoted reply lines*") "two quoted reply lines are refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.limits = '[10:02] you: is it done' })) "*a line that opens with a speaker's label*") "a time-stamped chat line is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.limits = '{"role": "user", "content": "hi"}' })) "*a transcript record's role field*") "a transcript record pasted into a text is refused"
Check ((Read-Finding (New-FindingText { param($f) $f.limits = "Note: one snapshot only." })).state -ceq "read") "CONTROL: one line opening with a word and a colon reads"
Check ((Read-Finding (New-FindingText { param($f) $f.limits = "Sends finished on the second try, plan a: retry once." })).state -ceq "read") "CONTROL: one speaker's label in the middle of a line reads"
Check ((Read-Finding (New-FindingText { param($f) $f.claim = "Users: 3 sessions answered the person in under a minute." })).state -ceq "read") "CONTROL: a word that only begins like a label ('Users:') reads"
Check ((Read-Finding (New-FindingText { param($f) $f.limits = "The person asked twice; the master answered once." })).state -ceq "read") "CONTROL (the stated limit): paraphrased conversation is not seen, and reads"

Section "credentials are refused, through the decisions check"
$tokenText = "ghp_" + ("aB3dE5fG7h" * 4)
$tok = Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.machine = ("one machine, token " + $tokenText) }.GetNewClosure())
Check (Test-Refused $tok "*machine holds what looks like an access token, a credential*") ("a key-shaped string is refused (" + (Show $tok) + ")")
Check (-not ((@($tok.findings) -join " ").Contains($tokenText))) "the refusal never repeats the key"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.proposedChange = "-----BEGIN RSA PRIVATE KEY----- MIIE" })) "*a private key, a credential*") "a private key header is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.limits = "password = hunter22" })) "*a password or key written as name=value*") "a password written as name=value is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.versions = @("Q7rT2mX9vB4nK8pL3sW6yH1jD5fG0cZa") })) "*a long random-looking string*") "a 32-character random-looking string in a list item is refused"
$keyName = Read-Finding ($seedText.Replace('"name": "foregroundSends"', ('"name": "foregroundSends", "' + $tokenText + '": 1')))
Check (Test-Refused $keyName "*a field name in*holds what looks like an access token*") ("a key used as a field's NAME is refused (" + (Show $keyName) + ")")
Check (-not ((@($keyName.findings) -join " ").Contains($tokenText))) "and that refusal does not repeat it either, not even through the schema's 'does not allow' finding"
$both = Read-Finding (New-FindingText { param($f) $f.confidence = $tokenText }.GetNewClosure())
Check ($both.state -ceq "refused" -and @($both.findings | Where-Object { $_ -like "*not one of*" }).Count -eq 0) "content is refused before the schema runs, whose finding for a closed list repeats the value"
Check ((Read-Finding (New-FindingText { param($f) $f.limits = "A password is needed for the store; ask the owner." })).state -ceq "read") "CONTROL: the word password in an ordinary sentence reads"

Section "customer data is refused (a minimal check)"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.countedFrom.machine = "the box of someone@example.com" })) "*machine holds what looks like an e-mail address, customer data*") "an e-mail address is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.limits = "reported by the caller on +1 202 555 0143" })) "*a phone number, customer data*") "an international phone number is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.limits = "call 202-555-0143 for the log" })) "*a phone number, customer data*") "a grouped ten-digit phone number is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.what = 'counted from C:\Users\someone\fleet\mail' })) "*a path into a person's home folder*") "a Windows home path is refused"
Check (Test-Refused (Read-Finding (New-FindingText { param($f) $f.metric.what = 'counted from /home/someone/fleet' })) "*a path into a person's home folder*") "a POSIX home path is refused"
Check ((Read-Finding (New-FindingText { param($f) $f.limits = "From 2026-10-05 to 2026-10-07, 1113 messages, 5.1.26100 build, 331000-598000 tokens." })).state -ceq "read") "CONTROL: dates, counts, versions and ranges are not phone numbers"
Check ((Read-Finding (New-FindingText { param($f) $f.limits = "Counted from the mail store under the home folder." })).state -ceq "read") "CONTROL: naming the home folder without a path reads"

Section "the writer keeps a finding locally, once, and never over another"
$work = Join-Path $env:TEMP ("horde-finding-" + [guid]::NewGuid().ToString("N"))
$savedHome = $env:HORDE_HOME
try {
    $folder = Join-Path $work "findings"
    $w1 = Save-HordeFinding -Text $seedText -HordeHome $work
    Check ($w1.state -ceq "written" -and [System.IO.File]::Exists($w1.path)) ("a finding that reads is written (" + $w1.state + ")")
    Check ((Split-Path -Parent $w1.path) -ceq $folder -and (Split-Path -Leaf $w1.path) -cmatch '\Afinding-[0-9a-f]{32}\.json\z') "it is written under <home>\findings, named by its content"
    Check ([System.IO.File]::ReadAllText($w1.path) -ceq $seedText) "the file holds the text exactly as given"
    $stamp = [System.IO.File]::GetLastWriteTimeUtc($w1.path)
    $w2 = Save-HordeFinding -Text $seedText -HordeHome $work
    Check ($w2.state -ceq "exists" -and $w2.path -ceq $w1.path -and [System.IO.File]::GetLastWriteTimeUtc($w1.path) -eq $stamp) "the same finding again is 'exists', and the file is not written again"
    $other = [System.IO.File]::ReadAllText((Join-Path $fxDir "g02.json"))
    $w3 = Save-HordeFinding -Text $other -HordeHome $work
    Check ($w3.state -ceq "written" -and $w3.path -cne $w1.path -and @(Get-ChildItem -LiteralPath $folder -Filter "finding-*.json").Count -eq 2) "another finding is a second file beside the first"
    Check (@(Get-ChildItem -LiteralPath $folder -Filter "*.part").Count -eq 0) "no temporary file is left behind"
    $refusedHome = Join-Path $work "refused-home"
    $w4 = Save-HordeFinding -Text (New-FindingText { param($f) $f.limits = $chatLines }.GetNewClosure()) -HordeHome $refusedHome
    Check ($w4.state -ceq "refused" -and $w4.path -ceq "" -and @($w4.findings).Count -ge 1) "a refused finding is answered 'refused' with its reasons"
    Check (-not (Test-Path -LiteralPath $refusedHome)) "and nothing is created for it: no home, no folder, no file"
    $blocked = Join-Path $work "blocked"
    $g3 = [System.IO.File]::ReadAllText((Join-Path $fxDir "g03.json"))
    [void][System.IO.Directory]::CreateDirectory((Join-Path (Join-Path $blocked "findings") (Get-HordeFindingFileName -Text $g3)))
    Check (Throws { Save-HordeFinding -Text $g3 -HordeHome $blocked } "taken by something that is not a finding") "a folder holding the finding's name is an error, not 'exists'"
    Check (@(Get-ChildItem -LiteralPath (Join-Path $blocked "findings") -Filter "*.part").Count -eq 0) "and the writer's temporary file is removed"
    # From inside this suite's own folder, so that a writer which did resolve it would write only there.
    # The process's folder, not only PowerShell's location: .NET resolves a relative path against the
    # first (a mutant of the writer left relative\home\findings in the checkout it ran from, 2026-10-08).
    $wasFolder = [System.IO.Directory]::GetCurrentDirectory()
    [System.IO.Directory]::SetCurrentDirectory($work)
    try { Check (Throws { Save-HordeFinding -Text $seedText -HordeHome "relative\home" } "absolute path") "a relative home is refused, never resolved against the current folder" } finally { [System.IO.Directory]::SetCurrentDirectory($wasFolder) }
    $envHome = Join-Path $work "env-home"
    $env:HORDE_HOME = $envHome
    $w5 = Save-HordeFinding -Text $seedText
    Check ($w5.state -ceq "written" -and $w5.path.StartsWith($envHome + "\findings\")) "without -HordeHome the home is HORDE_HOME's"
} finally {
    $env:HORDE_HOME = $savedHome
    if ((Split-Path -Leaf $work) -match '^horde-finding-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Section "nothing is sent anywhere"
# A text scan, with its control: the same scan finds a network call planted in a copy of the writer.
$netPattern = '(?i)Net\.WebClient|Net\.Http|Net\.Sockets|Invoke-WebRequest|Invoke-RestMethod|Send-MailMessage|\\remote\\|\\transports\\|Messaging\.ps1'
$storeText = [System.IO.File]::ReadAllText((Join-Path $root "core\FindingStore.ps1"))
$readerText = [System.IO.File]::ReadAllText((Join-Path $root "core\Finding.ps1"))
Check (-not [regex]::IsMatch($storeText, $netPattern) -and -not [regex]::IsMatch($readerText, $netPattern)) "neither file names a network call, a transport or the remote link"
Check ([regex]::IsMatch(($storeText + "`nInvoke-RestMethod -Uri x"), $netPattern)) "CONTROL: the scan finds a network call planted in the writer's text"

Complete-HordeSuite -Success "a finding is kept only when it reads, once, locally; every refusal held"
