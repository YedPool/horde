# DOES THE CONVERSATION PORT FIND ONE THRALL, READ IT BOUNDED, REDACT EVERY TURN, AND SURVIVE AN ADAPTER THAT LIES?
#
# Relay design 2026-10-09, Q2 and PR plan item 9. conversations/Port.ps1 against the memory source
# (test/lib/MemoryConversation.ps1), which can be told to lie. This suite attacks:
#   - REGISTRATION. An adapter with no conversation.json, an invalid one, one naming another folder, or
#     a second registration of a name is refused, by name of what is wrong.
#   - SELECTION BY REQUIREMENTS. Only "yes" satisfies -Require; a hazard (partialTurns, mutableHistory)
#     that is anything but "no" fails -Refuse, so an unverified hazard counts as present.
#   - FINDING THE THRALL. One adapter that locates it: known. None: absent. Two: unknown, naming both,
#     never one chosen. An adapter that throws, answers garbage, says unknown or gives a bad session id:
#     unknown, with the reason.
#   - READING, BOUNDED. A cursor of another vendor, of a bad shape, or a batch or byte limit outside the
#     port's: refused before the adapter is asked. An adapter that answers more turns than asked: unknown.
#   - EVERY TURN CHECKED AND REBUILT. A bad role, empty text, bad or repeated id, bad time, bad group id,
#     a non-object: dropped or repaired, each an anomaly that never repeats the bad value.
#   - REDACTION IN CORE. The adapter hands over raw text with secrets in it; the port's turns hold none
#     of it, and neither do its anomalies or its reasons. No adapter loads core/Secrets.ps1.
#   - A NEW SESSION (the harness's clear) is a reset: the old cursor reads the new session from its start.
#   - A SESSION DESCRIBED BY ITS ID. Known for one adapter that has it, unknown for none, for two, and for
#     an adapter that throws, answers garbage or answers about another session. Inside a known answer a
#     label, a role or a parent the adapter got wrong is unknown and never repeated: a table of labels
#     just inside and just outside the shape, text where an answer belongs, a number for a parent. Only
#     an adapter declaring sessionLookup yes is asked.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
. (Join-Path $root "conversations\Port.ps1")
. (Join-Path $root "core\Schema.ps1")
. (Join-Path $root "test\lib\MemoryConversation.ps1")

$mark = Get-HordeSecretMark
$turnSchema = Get-HordeSchema -Name "conversation-turn.v1"
function Find-Mem {
    param($Store, [string]$Fleet = "alpha", [string[]]$Require = @(), [string[]]$Refuse = @())
    return (Find-HordeConversationSource -Fleet $Fleet -Require $Require -Refuse $Refuse -Options @{ memory = $Store })
}
function Texts { param($Answer) return (@($Answer.value.turns | ForEach-Object { $_.text }) -join "|") }

Write-Host ""
Write-Host "--- registration ---" -ForegroundColor Cyan
Check (@(Get-HordeConversationAdapterNames) -ccontains "memory") "CONTROL: the memory source is registered through the port"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-conv-port-" + [guid]::NewGuid().ToString("N").Substring(0, 12))
try {
    $bare = Join-Path $tmp "bare"; [void][System.IO.Directory]::CreateDirectory($bare)
    Check (Throws { Register-HordeConversationAdapter -Folder $bare -Locate {} -Read {} } "has no conversation.json") "an adapter folder with no conversation.json is refused"
    $bad = Join-Path $tmp "bad"; [void][System.IO.Directory]::CreateDirectory($bad)
    $caps = Get-Content -Raw (Join-Path $root "test\fixtures\conversations\memory\conversation.json") | ConvertFrom-Json
    $caps.vendor = "bad"; $caps.capabilities.PSObject.Properties.Remove("mutableHistory")
    [System.IO.File]::WriteAllText((Join-Path $bad "conversation.json"), ($caps | ConvertTo-Json -Depth 5))
    Check (Throws { Register-HordeConversationAdapter -Folder $bad -Locate {} -Read {} } "mutableHistory") "a conversation.json missing a capability of the closed list is refused, naming it"
    $other = Join-Path $tmp "other"; [void][System.IO.Directory]::CreateDirectory($other)
    $caps2 = Get-Content -Raw (Join-Path $root "test\fixtures\conversations\memory\conversation.json") | ConvertFrom-Json
    $caps2.vendor = "elsewhere"
    [System.IO.File]::WriteAllText((Join-Path $other "conversation.json"), ($caps2 | ConvertTo-Json -Depth 5))
    Check (Throws { Register-HordeConversationAdapter -Folder $other -Locate {} -Read {} } "sits in the folder 'other'") "a conversation.json naming another vendor than its folder is refused"
    Check (Throws { Register-HordeConversationAdapter -Folder (Join-Path $root "test\fixtures\conversations\memory") -Locate {} -Read {} } "already registered") "a second registration of one vendor is refused; the first stands"
} finally { if ([System.IO.Directory]::Exists($tmp)) { Remove-Item -LiteralPath $tmp -Recurse -Force } }
Check ((@(Get-HordeConversationCapabilityNames) -join ",") -ceq "incremental,stableTurnIds,timestamps,roles,partialTurns,mutableHistory,sessionLookup") "the closed list of capabilities, in order"
Check ((@(Get-HordeConversationHazardNames) -join ",") -ceq "partialTurns,mutableHistory") "two of them are hazards"

Write-Host ""
Write-Host "--- selection by requirements ---" -ForegroundColor Cyan
$mem = Get-HordeConversationAdapter -Name "memory"
Check ((Find-HordeConversationAdapter -Require @("incremental", "stableTurnIds") -Refuse @("partialTurns", "mutableHistory")).state -ceq "known") "the memory source meets every requirement and has no hazard"
$saved = $mem.capabilities.capabilities.incremental.support
$savedHazard = $mem.capabilities.capabilities.mutableHistory.support
try {
    $mem.capabilities.capabilities.incremental.support = "unverified"
    $r = Resolve-HordeConversationAdapter -Name "memory" -Require @("incremental") -Refuse @()
    Check ($r.state -ceq "unknown" -and $r.reason -like "*memory*incremental*unverified*") ("an unverified capability does not satisfy -Require, and the reason names the adapter and the word (" + $r.reason + ")")
    $mem.capabilities.capabilities.incremental.support = $saved
    $mem.capabilities.capabilities.mutableHistory.support = "unverified"
    $r = Resolve-HordeConversationAdapter -Name "memory" -Require @() -Refuse @("mutableHistory")
    Check ($r.state -ceq "unknown" -and $r.reason -like "*mutableHistory*") "an unverified hazard fails -Refuse: it may be present"
    $r = Find-HordeConversationAdapter -Require @() -Refuse @("mutableHistory")
    Check ($r.state -ceq "unknown" -and $r.reason -like "*memory*") "and Find passes it over, saying why"
} finally { $mem.capabilities.capabilities.incremental.support = $saved; $mem.capabilities.capabilities.mutableHistory.support = $savedHazard }
Check (Throws { Find-HordeConversationAdapter -Require @("telepathy") -Refuse @() } "not a conversation capability") "a requirement outside the closed list is a programming error"
Check (Throws { Find-HordeConversationAdapter -Require @() -Refuse @("incremental") } "not a hazard") "refusing a capability that is not a hazard is a programming error"

Write-Host ""
Write-Host "--- finding the Thrall ---" -ForegroundColor Cyan
$store = New-HordeMemoryConversationStore
$f = Find-Mem $store
Check ($f.state -ceq "absent") ("no adapter locates a Thrall for the horde: absent (" + $f.state + ")")
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "user" -Text "first words"
$f = Find-Mem $store
Check ($f.state -ceq "known" -and $f.value.vendor -ceq "memory" -and $f.value.fleet -ceq "alpha" -and $f.value.session -like "mem-*") "one adapter locates it: known, with vendor, horde and session"
Check ((Find-Mem $store -Fleet "Not A Horde").state -ceq "unknown") "a horde name that is not one is refused"
foreach ($lie in @("locate-throw", "locate-garbage", "locate-unknown", "locate-bad-session")) {
    Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie $lie
    $f = Find-Mem $store
    Check ($f.state -ceq "unknown" -and $f.reason -like "*memory*") ("an adapter that answers " + $lie + ": unknown, naming it (" + $f.reason + ")")
}
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie ""
# TWO ADAPTERS THAT EACH SAY THEY HOLD THE THRALL: never one chosen over the other.
$twin = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-conv-twin-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$twinDir = Join-Path $twin "twin"
try {
    [void][System.IO.Directory]::CreateDirectory($twinDir)
    $tc = Get-Content -Raw (Join-Path $root "test\fixtures\conversations\memory\conversation.json") | ConvertFrom-Json
    $tc.vendor = "twin"
    [System.IO.File]::WriteAllText((Join-Path $twinDir "conversation.json"), ($tc | ConvertTo-Json -Depth 5))
    $null = Register-HordeConversationAdapter -Folder $twinDir -Locate { param($Request) return (New-HordeKnown -Value ([pscustomobject]@{ session = "twin-1"; locator = "x" })) } -Read { param($Source, $Position, $MaxTurns, $MaxBytes) return (New-HordeKnown -Value ([pscustomobject]@{ turns = @(); position = ""; more = $false; reset = "" })) }
    $f = Find-Mem $store
    Check ($f.state -ceq "unknown" -and $f.reason -like "*memory*" -and $f.reason -like "*twin*") ("two adapters each locate a Thrall: unknown, naming both (" + $f.reason + ")")
    $f = Find-HordeConversationSource -Fleet "alpha" -Vendor "memory" -Require @() -Refuse @() -Options @{ memory = $store }
    Check ($f.state -ceq "known" -and $f.value.vendor -ceq "memory") "a caller that names the vendor asks only that adapter"
} finally {
    # The port is dot-sourced into this suite, so its registry is this script's: the twin is taken out
    # again here, and no shipped function exists to unregister an adapter.
    [void]$script:HordeConversationAdapters.Remove("twin")
    if ([System.IO.Directory]::Exists($twin)) { Remove-Item -LiteralPath $twin -Recurse -Force }
}

Write-Host ""
Write-Host "--- reading, resuming, bounded ---" -ForegroundColor Cyan
$store = New-HordeMemoryConversationStore
foreach ($i in 1..5) { Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role $(if ($i % 2) { "user" } else { "assistant" }) -Text ("turn " + $i) }
$src = (Find-Mem $store).value
$r = Read-HordeConversationTurns -Source $src -Cursor $null
Check ($r.state -ceq "known" -and (Texts $r) -ceq "turn 1|turn 2|turn 3|turn 4|turn 5" -and -not $r.value.more -and $r.value.reset -ceq "none") "from no cursor: every turn, in order, nothing more, no reset"
$bad = @(@($r.value.turns) | Where-Object { @(Test-HordeSchema -Value $_ -Schema $turnSchema).Count -gt 0 })
Check ($bad.Count -eq 0) "every turn passes schema/conversation-turn.v1"
Check (@($r.value.turns | Where-Object { $_.source.vendor -cne "memory" -or $_.source.fleet -cne "alpha" -or $_.source.session -cne $src.session }).Count -eq 0) "every turn's source is filled by the port: vendor, session, horde"
$c1 = Read-HordeConversationTurns -Source $src -Cursor $null -MaxTurns 2
Check ((Texts $c1) -ceq "turn 1|turn 2" -and $c1.value.more) "a batch of 2: two turns, and more to come"
$c2 = Read-HordeConversationTurns -Source $src -Cursor $c1.value.next -MaxTurns 2
$c3 = Read-HordeConversationTurns -Source $src -Cursor $c2.value.next -MaxTurns 2
Check ((Texts $c2) -ceq "turn 3|turn 4" -and (Texts $c3) -ceq "turn 5" -and -not $c3.value.more) "resumed from each cursor: the next turns, and the end"
$again = Read-HordeConversationTurns -Source $src -Cursor $c3.value.next
Check ($again.state -ceq "known" -and @($again.value.turns).Count -eq 0 -and $again.value.next.position -ceq $c3.value.next.position) "at the end: no turns, and the cursor stays where it was"
$json = $c3.value.next | ConvertTo-Json -Compress
$back = Read-HordeConversationTurns -Source $src -Cursor ($json | ConvertFrom-Json)
Check ($back.state -ceq "known" -and @($back.value.turns).Count -eq 0) ("a cursor survives being written as JSON and read back (" + $json + ")")
foreach ($case in @(
        @{ what = "a cursor of another vendor"; cursor = [pscustomobject]@{ schemaVersion = 1; vendor = "other"; session = $src.session; position = "" } },
        @{ what = "a cursor of another schema version"; cursor = [pscustomobject]@{ schemaVersion = 2; vendor = "memory"; session = $src.session; position = "" } },
        @{ what = "a cursor whose position is not printable ASCII"; cursor = [pscustomobject]@{ schemaVersion = 1; vendor = "memory"; session = $src.session; position = ("g1" + [char]10) } },
        @{ what = "a cursor whose position is too long"; cursor = [pscustomobject]@{ schemaVersion = 1; vendor = "memory"; session = $src.session; position = ("p" * 1025) } },
        @{ what = "a cursor that is a bare string"; cursor = "g1.i0" },
        @{ what = "a cursor with no session"; cursor = [pscustomobject]@{ schemaVersion = 1; vendor = "memory"; position = "" } }
    )) {
    $x = Read-HordeConversationTurns -Source $src -Cursor $case.cursor
    Check ($x.state -ceq "unknown" -and $x.reason -like "*cursor*") ("refused before the adapter is asked: " + $case.what)
}
Check ((Read-HordeConversationTurns -Source $src -Cursor $null -MaxTurns 0).state -ceq "unknown") "a batch of 0 is refused"
Check ((Read-HordeConversationTurns -Source $src -Cursor $null -MaxTurns ((Get-HordeConversationCeilings).maxTurns + 1)).state -ceq "unknown") "a batch over the port's ceiling is refused"
Check ((Read-HordeConversationTurns -Source $src -Cursor $null -MaxBytes ((Get-HordeConversationCeilings).maxBytes + 1)).state -ceq "unknown") "a byte limit over the port's ceiling is refused"
$fake = [pscustomobject]@{ PSTypeName = "Horde.ConversationSource"; id = $src.id; vendor = "memory"; session = $src.session; fleet = "alpha"; locator = $src.locator; adapter = $src.adapter }
Check ((Read-HordeConversationTurns -Source $fake -Cursor $null).state -ceq "unknown") "a look-alike source carrying a real id is refused: only what Find-HordeConversationSource made is read"

Write-Host ""
Write-Host "--- every turn checked, and rebuilt by the port ---" -ForegroundColor Cyan
$cases = [ordered]@{
    "bad-role" = @(4, "role")
    "empty-text" = @(4, "text")
    "bad-turn-id" = @(4, "turnId")
    "duplicate-turn-id" = @(4, "turnId")
    "not-an-object" = @(4, "not an object")
}
foreach ($lie in $cases.Keys) {
    Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie $lie
    $x = Read-HordeConversationTurns -Source $src -Cursor $null
    $anom = @($x.value.anomalies) -join " | "
    Check ($x.state -ceq "known" -and @($x.value.turns).Count -eq $cases[$lie][0] -and $anom -like ("*" + $cases[$lie][1] + "*") -and -not $anom.Contains("hunter2")) ("an adapter that gives " + $lie + ": that turn dropped, an anomaly says why, without the value (" + $anom + ")")
}
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie "bad-time"
$x = Read-HordeConversationTurns -Source $src -Cursor $null
Check ($x.state -ceq "known" -and @($x.value.turns).Count -eq 5 -and $null -eq $x.value.turns[0].PSObject.Properties["time"] -and (@($x.value.anomalies) -join " ") -like "*time*") "a time that is not one: the turn kept without a time, and an anomaly"
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie "no-time"
$x = Read-HordeConversationTurns -Source $src -Cursor $null
Check ($x.state -ceq "known" -and @($x.value.turns).Count -eq 5 -and (@($x.value.anomalies) -join " ") -like "*declares timestamps*") "no time from an adapter that declares timestamps: kept, and an anomaly says the claim did not hold"
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie "bad-group-id"
$x = Read-HordeConversationTurns -Source $src -Cursor $null
Check ($x.state -ceq "known" -and $null -eq $x.value.turns[0].PSObject.Properties["groupId"] -and (@($x.value.anomalies) -join " ") -like "*groupId*") "a bad group id: the turn kept without it, and an anomaly"
foreach ($lie in @("read-throw", "read-garbage", "read-unknown", "read-absent", "overfill", "bad-position", "long-position", "bad-more", "bad-reset", "no-turns", "rotate-always")) {
    Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie $lie
    $x = Read-HordeConversationTurns -Source $src -Cursor $null -MaxTurns 3
    Check ($x.state -ceq "unknown" -and $x.reason -like "*memory*" -and -not "$($x.reason)".Contains("hunter2")) ("an adapter that answers " + $lie + ": unknown, naming it, never repeating a secret (" + $x.reason + ")")
}
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie "secret-anomaly"
$x = Read-HordeConversationTurns -Source $src -Cursor $null
Check ($x.state -ceq "known" -and -not ((@($x.value.anomalies) -join " ").Contains("q8Wv3Lm9Zr4")) -and (@($x.value.anomalies) -join " ").Contains($mark)) "an adapter's own anomaly is redacted too"
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie ""

Write-Host ""
Write-Host "--- redaction is the port's, never an adapter's ---" -ForegroundColor Cyan
$store = New-HordeMemoryConversationStore
$secretUser = "the deploy key is " + ("gh" + "p_" + ("Ab1" * 12)) + " for now"
$secretAsst = "use password=" + "hunter2longer" + " then restart"
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "user" -Text $secretUser
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "assistant" -Text $secretAsst
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "assistant" -Text "nothing secret here"
$src = (Find-Mem $store).value
$r = Read-HordeConversationTurns -Source $src -Cursor $null
$all = ($r.value | ConvertTo-Json -Depth 8 -Compress)
Check ($r.state -ceq "known" -and -not $all.Contains("Ab1Ab1") -and -not $all.Contains("hunter2")) "no secret survives anywhere in the answer: turns, cursor, anomalies"
Check ($r.value.turns[0].text -ceq ("the deploy key is " + $mark + " for now") -and $null -ne $r.value.turns[0].PSObject.Properties["redactions"] -and $r.value.turns[0].redactions -eq 1) "the user's secret is replaced by the marker, the words around it kept, and counted"
Check ($r.value.turns[1].text.Contains($mark) -and $r.value.turns[1].text.EndsWith(" then restart") -and $null -ne $r.value.turns[1].PSObject.Properties["redactions"] -and $r.value.turns[1].redactions -eq 1) "the assistant's too"
Check ($r.value.turns[2].text -ceq "nothing secret here" -and $null -eq $r.value.turns[2].PSObject.Properties["redactions"]) "CONTROL: a turn with no secret is untouched, and carries no count"
$adapterFiles = @(Get-ChildItem -LiteralPath (Join-Path $root "agents") -Directory | ForEach-Object { Join-Path $_.FullName "Conversation.ps1" } | Where-Object { Test-Path -LiteralPath $_ })
Check ($adapterFiles.Count -ge 1) ("CONTROL: the adapters are found (" + $adapterFiles.Count + ")")
$redacting = @($adapterFiles | Where-Object { $t = [System.IO.File]::ReadAllText($_); $t.Contains("Secrets.ps1") -or $t.Contains("Protect-HordeSecretText") -or $t.Contains("Find-HordeSecretKind") })
Check ($redacting.Count -eq 0) ("no adapter loads or calls the secret detector: redaction is the port's alone (" + (@($redacting) -join ", ") + ")")
$portText = [System.IO.File]::ReadAllText((Join-Path $root "conversations\Port.ps1"))
Check ($portText.Contains("Protect-HordeSecretText")) "CONTROL: the same search finds the call in the port"

Write-Host ""
Write-Host "--- a long turn is cut, after it is redacted ---" -ForegroundColor Cyan
$store = New-HordeMemoryConversationStore
$ceil = (Get-HordeConversationCeilings).textChars
$long = ("word " * ([int]($ceil / 5) + 100))
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "assistant" -Text $long
# A secret that straddles the ceiling: cut first, its first half would no longer match and would leak.
$straddle = ("x" * ($ceil - 10)) + " " + ("gh" + "p_" + ("Cd2" * 12)) + " tail"
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "user" -Text $straddle
$src = (Find-Mem $store).value
$r = Read-HordeConversationTurns -Source $src -Cursor $null
Check ($r.value.turns[0].text.Length -eq $ceil -and $r.value.turns[0].truncated -eq $true) ("a text over the ceiling is cut to " + $ceil + " characters and marked truncated")
Check (-not $r.value.turns[1].text.Contains("ghp_C") -and -not $r.value.turns[1].text.Contains("Cd2Cd2")) "a secret across the ceiling is hidden before the cut, so no piece of it is left"

Write-Host ""
Write-Host "--- a new session is a reset, and a rotation is reported ---" -ForegroundColor Cyan
$store = New-HordeMemoryConversationStore
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "user" -Text "old one"
$src = (Find-Mem $store).value
$r = Read-HordeConversationTurns -Source $src -Cursor $null
Clear-HordeMemoryConversation -Store $store -Fleet "alpha"
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "user" -Text "new one"
$src2 = (Find-Mem $store).value
Check ($src2.session -cne $src.session) "CONTROL: the clear gave the Thrall a new session"
$x = Read-HordeConversationTurns -Source $src2 -Cursor $r.value.next
Check ($x.state -ceq "known" -and $x.value.reset -ceq "session" -and (Texts $x) -ceq "new one" -and $x.value.next.session -ceq $src2.session) "the old cursor on the new session: reset session, the new session from its start"
Reset-HordeMemoryConversationHistory -Store $store -Fleet "alpha"
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "user" -Text "rewritten"
$y = Read-HordeConversationTurns -Source $src2 -Cursor $x.value.next
Check ($y.state -ceq "known" -and $y.value.reset -ceq "rotated" -and (Texts $y) -ceq "rewritten") "a history the adapter says was rewritten: reset rotated, read from its start"

Write-Host ""
Write-Host "--- a delivered turn is a role of its own ---" -ForegroundColor Cyan
$store = New-HordeMemoryConversationStore
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "delivered" -Text "handed over by a messenger"
$r = Read-HordeConversationTurns -Source (Find-Mem $store).value -Cursor $null
Check ($r.state -ceq "known" -and @($r.value.turns).Count -eq 1 -and $r.value.turns[0].role -ceq "delivered" -and @(Test-HordeSchema -Value $r.value.turns[0] -Schema (Get-HordeSchema -Name "conversation-turn.v1")).Count -eq 0) "a turn a messenger handed over keeps the role delivered, and the turn schema takes it"

Write-Host ""
Write-Host "--- a past session by its id: the tail a clear left behind ---" -ForegroundColor Cyan
$store = New-HordeMemoryConversationStore
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "user" -Text "before the cursor"
$src = (Find-Mem $store).value
$r = Read-HordeConversationTurns -Source $src -Cursor $null
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "assistant" -Text ("last words, token=" + "q8Wv3Lm9Zr4Xy7")
Clear-HordeMemoryConversation -Store $store -Fleet "alpha"
Add-HordeMemoryConversationTurn -Store $store -Fleet "alpha" -Role "user" -Text "in the new session"
$old = Find-HordeConversationSource -Fleet "alpha" -Session $src.session -Require @() -Refuse @() -Options @{ memory = $store }
Check ($old.state -ceq "known" -and $old.value.session -ceq $src.session) ("the old session is located by its id after the clear (" + $old.state + ")")
$tail = Read-HordeConversationTurns -Source $old.value -Cursor $r.value.next
Check ($tail.state -ceq "known" -and $tail.value.reset -ceq "none" -and @($tail.value.turns).Count -eq 1 -and $tail.value.turns[0].text.StartsWith("last words") -and -not $tail.value.more) "read from the old cursor, it gives the tail written after it, and not the new session's words"
Check (-not $tail.value.turns[0].text.Contains("q8Wv3Lm9Zr4Xy7") -and $tail.value.turns[0].source.session -ceq $src.session) "the tail is redacted by the port like any read, and carries the old session's id"
$now = Find-HordeConversationSource -Fleet "alpha" -Session (Find-Mem $store).value.session -Require @() -Refuse @() -Options @{ memory = $store }
Check ($now.state -ceq "known" -and $now.value.session -cne $src.session) "asked by the id of the session now, it is that session"
$none = Find-HordeConversationSource -Fleet "alpha" -Session "mem-never-was" -Require @() -Refuse @() -Options @{ memory = $store }
Check ($none.state -ceq "absent" -and $none.reason.Contains("that session")) ("an id the Thrall never had is absent, said so (" + $none.reason + ")")
$bad = Find-HordeConversationSource -Fleet "alpha" -Session "has spaces" -Require @() -Refuse @() -Options @{ memory = $store }
Check ($bad.state -ceq "unknown" -and $bad.reason.Contains("session asked for")) "an id that is not a session id is refused before any adapter is asked"
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie "locate-other-session"
$liar = Find-HordeConversationSource -Fleet "alpha" -Session $src.session -Require @() -Refuse @() -Options @{ memory = $store }
Check ($liar.state -ceq "unknown" -and $liar.reason.Contains("located another one")) ("an adapter that answers with another session than the one asked for is not believed (" + $liar.reason + ")")
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie ""

Write-Host ""
Write-Host "--- a session described by its id ---" -ForegroundColor Cyan
function Get-Mem { param($Store, [string]$Id, [string]$Fleet = "alpha") return (Get-HordeConversationSession -Fleet $Fleet -SessionId $Id -Options @{ memory = $Store }) }
function Test-Clean {
    # Is nothing an adapter handed over in this part of an answer? Read from the part itself: as JSON a
    # "<" is written <, so a search of the JSON for such a text could never find it.
    param($Part)
    if ($null -ne $Part.value) { return $false }
    foreach ($bad in @("Thrall", "hunter2longer", "q8Wv3Lm9Zr4", "emperor", "has spaces", "<b>")) { if ("$($Part.reason)".Contains($bad)) { return $false } }
    return $true
}
$recordLabel = "$((Get-HordeSchema -Name 'session-record.v1').properties.label.pattern)"
Check ($recordLabel.StartsWith("^") -and $recordLabel.EndsWith('$') -and $script:HordeConversationLabelPattern -ceq ('\A' + $recordLabel.Substring(1, $recordLabel.Length - 2) + '\z')) "the port's label shape is schema/session-record.v1's, anchored to the very end of the text"
$store = New-HordeMemoryConversationStore
$thrall = (Get-HordeMemoryConversationHorde -Store $store -Fleet "alpha").session
$orc = Set-HordeMemoryConversationMember -Store $store -Fleet "alpha" -Role "orc" -Label "E"
$warg = Set-HordeMemoryConversationMember -Store $store -Fleet "alpha" -Role "warg" -Label "E3" -Parent $orc
$bare = Set-HordeMemoryConversationMember -Store $store -Fleet "alpha"
$d = Get-Mem $store $warg
Check ($d.state -ceq "known" -and (@($d.value.PSObject.Properties | ForEach-Object { $_.Name }) -join ",") -ceq "vendor,session,fleet,label,role,parent") ("a session one adapter has is known: vendor, session, fleet, label, role, parent (" + $d.state + " " + $d.reason + ")")
Check ($d.value.vendor -ceq "memory" -and $d.value.session -ceq $warg -and $d.value.fleet -ceq "alpha" -and $d.value.label.value -ceq "E3" -and $d.value.role.value -ceq "warg" -and $d.value.parent.value -ceq $orc) "with its label, its role, and its parent's session id"
Check ((Test-HordeAnswer $d.value.label) -and (Test-HordeAnswer $d.value.role) -and (Test-HordeAnswer $d.value.parent)) "label, role and parent are each an answer of their own"
$d = Get-Mem $store $bare
Check ($d.state -ceq "known" -and $d.value.label.state -ceq "absent" -and $d.value.role.state -ceq "absent" -and $d.value.parent.state -ceq "absent") "a session with no label, role or parent is known, and each is said to be none"
$d = Get-Mem $store $thrall
Check ($d.state -ceq "known" -and $d.value.role.value -ceq "warchief") "the Thrall's session is a session like any other"
$d = Get-Mem $store "mem-never-was"
Check ($d.state -ceq "unknown" -and $d.reason -like "*no adapter has a record*mem-never-was*") ("an id no adapter has is unknown - never absent - and says so (" + $d.state + ": " + $d.reason + ")")
$d = Get-Mem $store $warg -Fleet "beta"
Check ($d.state -ceq "unknown") "a horde the adapter holds nothing for is unknown"
$d = Get-Mem $store $warg.ToUpperInvariant()
Check ($d.state -ceq "unknown") "an id is matched exactly: in another case it is another id"
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie "describe-throw"
$d = Get-Mem $store "has spaces"
Check ($d.state -ceq "unknown" -and $d.reason -like "*session id asked about*") ("an id that is not a session id is refused before any adapter is asked (" + $d.reason + ")")
$d = Get-Mem $store ""
Check ($d.state -ceq "unknown" -and $d.reason -like "*session id asked about*") "and so is an empty one"
$d = Get-Mem $store $warg -Fleet "Not A Horde"
Check ($d.state -ceq "unknown" -and $d.reason -like "*horde asked about*") "a horde name that is not one is refused before any adapter is asked"
$d = Get-Mem $store $warg
Check ($d.state -ceq "unknown" -and $d.reason -like "*memory*failed*" -and -not $d.reason.Contains("hunter2longer")) ("an adapter that throws: unknown, naming it, its message redacted (" + $d.reason + ")")
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie "describe-garbage"
$d = Get-Mem $store $warg
Check ($d.state -ceq "unknown" -and $d.reason -like "*memory*not an answer*") "an adapter that answers with something that is not an answer: unknown, naming it"
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie "describe-unknown"
$d = Get-Mem $store $warg
Check ($d.state -ceq "unknown" -and $d.reason -like "*memory*" -and -not $d.reason.Contains("q8Wv3Lm9Zr4")) "an adapter that cannot tell: unknown, naming it, its reason redacted"
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie "describe-other-session"
$d = Get-Mem $store $warg
Check ($d.state -ceq "unknown" -and $d.reason -like "*answered about another*") ("an adapter that answers about another session than the one asked about is not believed (" + $d.state + ")")

# INSIDE A KNOWN ANSWER, EACH PART IS CHECKED ALONE: one bad part is unknown, and the others stand.
$partLies = [ordered]@{
    "describe-bad-label" = "label"; "describe-label-not-text" = "label"; "describe-label-look-alike" = "label"; "describe-no-label" = "label"; "describe-label-unknown" = "label"
    "describe-bad-role" = "role"; "describe-bad-parent" = "parent"; "describe-parent-not-text" = "parent"
}
foreach ($lie in $partLies.Keys) {
    Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie $lie
    $d = Get-Mem $store $warg
    $part = $partLies[$lie]
    $others = @(@("label", "role", "parent") | Where-Object { $_ -cne $part } | Where-Object { $d.state -ceq "known" -and $d.value.$_.state -ceq "known" })
    Check ($d.state -ceq "known" -and $d.value.$part.state -ceq "unknown" -and $others.Count -eq 2) ("an adapter that answers " + $lie + ": the session is known, its " + $part + " unknown, the other two kept")
    Check ($d.state -ceq "known" -and (Test-Clean ($d.value.$part))) ("and what it handed over for " + $lie + " is neither the " + $part + "'s value nor in its reason")
}
Set-HordeMemoryConversationLie -Store $store -Fleet "alpha" -Lie ""
Check ((Get-Mem $store $warg).value.label.value -ceq "E3") "CONTROL: honest again, the label is back"
Check (-not (Test-Clean (Get-Mem $store $warg).value.label) -and -not (Test-Clean (New-HordeUnknown -Reason "it said <b>Thrall</b>"))) "CONTROL: the check for handed-over text fails on a value, and on a reason that repeats one"

# THE LABEL'S SHAPE, ATTACKED FROM BOTH SIDES. Anything outside it would be shown as a session's name.
$lineEnd = "E3" + [char]10
$accented = "" + [char]0xC9 + "3"
foreach ($ok in @("M", "E", "AB", "E3", "A9999", "AB12")) {
    $null = Set-HordeMemoryConversationMember -Store $store -Fleet "alpha" -Session $bare -Label $ok
    $d = Get-Mem $store $bare
    Check ($d.state -ceq "known" -and $d.value.label.state -ceq "known" -and $d.value.label.value -ceq $ok) ("the label " + $ok + " is a label")
}
$n = 0
foreach ($no in @("e3", "E0", "E03", "E10000", "ABC", "E 3", "E3 ", " E3", "3", "E-3", "E3x", $lineEnd, $accented, "E3<b>")) {
    $n++
    $null = Set-HordeMemoryConversationMember -Store $store -Fleet "alpha" -Session $bare -Label $no
    $d = Get-Mem $store $bare
    Check ($d.state -ceq "known" -and $d.value.label.state -ceq "unknown" -and $null -eq $d.value.label.value -and -not $d.value.label.reason.Contains($no)) ("a label outside the shape (case " + $n + ", " + $no.Length + " characters) is unknown, and not handed on")
}
foreach ($pair in @(@("warchief", "known"), @("orc", "known"), @("warg", "known"), @("master", "unknown"), @("Orc", "unknown"), @("orc ", "unknown"))) {
    $null = Set-HordeMemoryConversationMember -Store $store -Fleet "alpha" -Session $bare -Role $pair[0]
    $d = Get-Mem $store $bare
    Check ($d.state -ceq "known" -and $d.value.role.state -ceq $pair[1]) ("the role '" + $pair[0] + "' from an adapter is " + $pair[1] + ": only core/roles.json's own names are a role")
}

# ONLY AN ADAPTER THAT DECLARES sessionLookup yes IS ASKED.
$savedLookup = $mem.capabilities.capabilities.sessionLookup.support
try {
    $mem.capabilities.capabilities.sessionLookup.support = "unverified"
    $d = Get-Mem $store $warg
    Check ($d.state -ceq "unknown" -and $d.reason -like "*memory*sessionLookup*unverified*") ("an adapter whose sessionLookup is unverified is not asked, and the reason names it (" + $d.reason + ")")
    $d = Get-HordeConversationSession -Fleet "alpha" -SessionId $warg -Vendor "memory" -Options @{ memory = $store }
    Check ($d.state -ceq "unknown" -and $d.reason -like "*memory*sessionLookup*") "nor when the caller names it"
} finally { $mem.capabilities.capabilities.sessionLookup.support = $savedLookup }
$d = Get-HordeConversationSession -Fleet "alpha" -SessionId $warg -Vendor "nobody" -Options @{ memory = $store }
Check ($d.state -ceq "unknown" -and $d.reason -like "*nobody*") "a vendor nobody registered is unknown"

# TWO ADAPTERS: one that has no record of the session says nothing; two that each have one are never chosen between.
$twin = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-conv-twin-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$twinDir = Join-Path $twin "twin"
try {
    [void][System.IO.Directory]::CreateDirectory($twinDir)
    $tc = Get-Content -Raw (Join-Path $root "test\fixtures\conversations\memory\conversation.json") | ConvertFrom-Json
    $tc.vendor = "twin"
    [System.IO.File]::WriteAllText((Join-Path $twinDir "conversation.json"), ($tc | ConvertTo-Json -Depth 5))
    $twinAdapter = Register-HordeConversationAdapter -Folder $twinDir -Locate { param($Request) return (New-HordeAbsent -Note "none") } -Read { param($Source, $Position, $MaxTurns, $MaxBytes) return (New-HordeUnknown -Reason "never read") } -Describe { param($Request) return (New-HordeAbsent -Note "no such session") }
    $d = Get-Mem $store $warg
    Check ($d.state -ceq "known" -and $d.value.vendor -ceq "memory") ("a second adapter with no record of the session says nothing: the first one's answer stands (" + $d.state + " " + $d.reason + ")")
    $twinAdapter.describe = { param($Request) return (New-HordeKnown -Value ([pscustomobject]@{ session = $Request.session; role = (New-HordeKnown -Value "orc"); label = (New-HordeKnown -Value "Z"); parent = (New-HordeAbsent -Note "none") })) }
    $d = Get-Mem $store $warg
    Check ($d.state -ceq "unknown" -and $d.reason -like "*2 adapters*memory*twin*") ("two adapters that each describe the session: unknown, naming both, never one chosen (" + $d.reason + ")")
    $d = Get-HordeConversationSession -Fleet "alpha" -SessionId $warg -Vendor "memory" -Options @{ memory = $store }
    Check ($d.state -ceq "known" -and $d.value.label.value -ceq "E3") "a caller that names the vendor asks only that adapter"
    $twinAdapter.describe = $null
    $d = Get-Mem $store $warg
    Check ($d.state -ceq "unknown" -and $d.reason -like "*twin*gave no Describe*") ("an adapter that declares sessionLookup yes and gave nothing to ask: unknown, in those words (" + $d.reason + ")")
} finally {
    [void]$script:HordeConversationAdapters.Remove("twin")
    if ([System.IO.Directory]::Exists($twin)) { Remove-Item -LiteralPath $twin -Recurse -Force }
}
$null = Set-HordeMemoryConversationMember -Store $store -Fleet "alpha" -Session $warg -Role "warg" -Label "E9" -Parent $orc
Check ((Get-Mem $store $warg).value.label.value -ceq "E9") "the records changed between two calls: the second call reads them again"

Complete-HordeSuite -Success "the port finds one Thrall, reads it bounded and redacted, describes a session by its id, and survives every lie"
