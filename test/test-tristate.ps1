# DOES HORDE KEEP "I DO NOT KNOW" APART FROM "THERE IS NONE"?
#
# Every lesson here is from the system Horde replaces, where an unknown silently read as none was
# behind sessions called dead that were alive, a kill reported done that killed nothing, and six
# panes reported closed that were open. planning/ledger/core-tristate.md cites each one.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
# The shared helper first, so an error while loading the module is recorded like any other. It sets
# $ErrorActionPreference = "Stop" for the suite; the checks that are about a reader's non-terminating
# errors set Continue in their own scope, because that is the preference such a reader runs under.
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
# The whole suite runs under the strictest mode, so the module is proved to work for a caller that
# uses it. The module once switched strict mode off at file scope, which - dot-sourced - switched it
# off for the caller too.
Set-StrictMode -Version Latest
. (Join-Path $root "core\Tristate.ps1")

Write-Host ""
Write-Host "--- loading the module ---" -ForegroundColor Cyan

$strictKept = & { Set-StrictMode -Version Latest; . (Join-Path $root "core\Tristate.ps1"); try { $null = $hordeNeverAssignedVariable; $false } catch { $true } }
Check ($strictKept -eq $true) "dot-sourcing the module leaves the caller's strict mode on"
# Under strict mode, reading a property an object does not have throws. Measured 2026-09-29: both of
# these threw "The property ... cannot be found" once the module stopped switching strict mode off.
$typeOnly = $null
try { $typeOnly = Test-HordeAnswer ([pscustomobject]@{ PSTypeName = "Horde.Answer" }) } catch { $typeOnly = "threw: $_" }
Check ($typeOnly -eq $false) "under strict mode, an object with the type name and no fields is not an answer, and does not throw"
$textError = $null
try { $textError = (New-HordeUnknown -Reason "could not read" -ErrorRecord "the mux did not answer").reason } catch { $textError = "threw: $_" }
Check ($textError -eq "could not read: the mux did not answer") "under strict mode, an unknown built from a plain-text error keeps the text"

Write-Host ""
Write-Host "--- reading a source ---" -ForegroundColor Cyan

$bad = Invoke-HordeRead -What "the pane list" -Read { throw "the mux did not answer" }
Check ($bad.state -eq "unknown") "an unreadable source reads as unknown"
Check ($bad.reason -like "*could not read the pane list*" -and $bad.reason -like "*the mux did not answer*") "an unknown from an exception keeps its message"
$good = Invoke-HordeRead -What "the pane list" -Read { , @(1, 2, 3) }
$goodValue = Get-HordeValue $good
Check ($good.state -eq "known" -and @($goodValue).Count -eq 3) "CONTROL: a readable source reads as known"
$silent = Invoke-HordeRead -What "the pane list" -Read { $null }
Check ($silent.state -eq "unknown") "a reader that returns nothing has not said none, so it reads as unknown"
$none = Invoke-HordeRead -What "the pane list" -Read { New-HordeAbsent -Note "no panes" }
Check ($none.state -eq "absent") "a reader that says none, in so many words, reads as absent"
# A stray line of pipeline output next to an answer turns the reader's result into an array, which
# used to be wrapped as KNOWN - so an absent or unknown answer came back as a known Object[].
$noisyAbsent = Invoke-HordeRead -What "the pane list" -Read { "listing panes"; New-HordeAbsent -Note "no panes" }
Check ($noisyAbsent.state -eq "unknown") "a reader that emits an answer plus other output reads as unknown"
$noisyUnknown = Invoke-HordeRead -What "the pane list" -Read { New-HordeUnknown -Reason "mux silent"; 0 }
Check ($noisyUnknown.state -eq "unknown" -and $noisyUnknown.reason -like "*plus other output*") "and so does one whose stray output follows an unknown"
# What the rule does NOT catch, pinned so nobody relies on the opposite: stray output next to a plain
# value is indistinguishable from a list, and comes back known with the stray line inside it.
$noisyList = Invoke-HordeRead -What "the pane list" -Read { "listing panes"; , @(1, 2) }
$noisyListValue = Get-HordeValue $noisyList
Check ($noisyList.state -eq "known" -and $noisyListValue.Count -eq 2 -and $noisyListValue[0] -eq "listing panes") "a reader's stray output next to a plain value is kept in the value, not caught"
# Most cmdlet failures are non-terminating: they write an error and carry on. Under the default
# Continue preference, a reader that failed that way still returned its fallback as known. Each read
# runs in a scope set to Continue, since the suite's own Stop would make the error terminating and
# prove nothing about a caller running with the default.
$softFail = & { $ErrorActionPreference = "Continue"; Invoke-HordeRead -What "the pane list" -Read { Write-Error "boom"; 0 } }
Check ($softFail.state -eq "unknown" -and $softFail.reason -like "*boom*") "a reader that writes a non-terminating error reads as unknown"
$noSuchDir = Join-Path $env:TEMP ("horde-no-such-dir-" + [guid]::NewGuid().ToString("N"))
$missingPath = & { $ErrorActionPreference = "Continue"; Invoke-HordeRead -What "the registry" -Read { , @(Get-ChildItem -LiteralPath $noSuchDir) } }
Check ($missingPath.state -eq "unknown") "a cmdlet error inside a reader is not swallowed into a known empty list"
$prefAfterRead = & { $ErrorActionPreference = "Continue"; $null = Invoke-HordeRead -What "the pane list" -Read { Write-Error "boom"; 0 }; $ErrorActionPreference }
Check ($prefAfterRead -eq "Continue") "the caller's error preference is untouched by a read"
# Deciding by the error preference was wrong both ways (review, 2026-09-29). Under Stop, PowerShell
# 5.1 turns a native program's stderr into a terminating error even when the reader discards it with
# 2>$null, so a reader whose stderr is only logging read as unknown - for a caller on Stop as well.
# And a reader defined in a module does not see the preference Invoke-HordeRead sets, so its
# non-terminating error returned the fallback as known 0.
$nativeLog = & { $ErrorActionPreference = "Continue"; Invoke-HordeRead -What "a native listing" -Read { cmd /c "echo out& echo INFO log 1>&2" 2>$null } }
Check ($nativeLog.state -eq "known" -and "$($nativeLog.value)" -eq "out") "a native reader whose discarded stderr is only logging reads as known"
$nativeLogStop = & { $ErrorActionPreference = "Stop"; Invoke-HordeRead -What "a native listing" -Read { cmd /c "echo out& echo INFO log 1>&2" 2>$null } }
Check ($nativeLogStop.state -eq "known" -and "$($nativeLogStop.value)" -eq "out") "and so it does for a caller whose preference is Stop"
$moduleReader = & (New-Module -Name "HordeTestReaderModule" -ScriptBlock { function Get-HordeTestModuleReader { { Write-Error "boom from a module"; 0 } } }) { Get-HordeTestModuleReader }
# A module's code sees the GLOBAL preference, not its caller's, and under powershell -File this
# suite's own scope is the global one (measured: Stop set here reads back from $global:). So the
# global preference is set to the default for this one read, and put back whatever happens.
$suitePreference = $global:ErrorActionPreference
$moduleFail = $null
try {
    $global:ErrorActionPreference = "Continue"
    $moduleFail = Invoke-HordeRead -What "the pane list" -Read $moduleReader
} finally { $global:ErrorActionPreference = $suitePreference }
Check ($moduleFail.state -eq "unknown" -and $moduleFail.reason -like "*boom from a module*") "a reader defined in a module that writes an error reads as unknown"
# Only an error that ESCAPES the reader counts. One it catches or silences on purpose is its own
# business: counting every entry added to $Error would have made both of these unknown.
$handled = & { $ErrorActionPreference = "Continue"; Invoke-HordeRead -What "the registry" -Read { try { $null = Get-Item -LiteralPath $noSuchDir -ErrorAction Stop } catch { }; New-HordeAbsent -Note "no registry" } }
Check ($handled.state -eq "absent") "CONTROL: a reader that catches its own error on purpose is not unknown"
$silenced = & { $ErrorActionPreference = "Continue"; Invoke-HordeRead -What "the registry" -Read { $item = Get-Item -LiteralPath $noSuchDir -ErrorAction SilentlyContinue; if ($null -eq $item) { New-HordeAbsent -Note "no registry" } } }
Check ($silenced.state -eq "absent") "CONTROL: nor is one that silences an error it expects"
# A native program's stderr that the reader does NOT discard reaches Invoke-HordeRead as an error
# record, and is read as a failure: logging must be discarded by the reader, which knows it is logging.
$nativeNoisy = & { $ErrorActionPreference = "Continue"; Invoke-HordeRead -What "a native listing" -Read { cmd /c "echo out& echo INFO log 1>&2" } }
Check ($nativeNoisy.state -eq "unknown" -and $nativeNoisy.reason -like "*INFO log*") "a native reader that leaves its stderr undiscarded reads as unknown"
# Invoke-HordeRead cannot see a native exit code: a reader that ignores it returns what the program
# printed as known. Pinned, so no caller relies on the opposite. The reader must check $LASTEXITCODE.
$exitIgnored = Invoke-HordeRead -What "a native listing" -Read { cmd /c "echo partial& exit 3" }
Check ($exitIgnored.state -eq "known" -and "$($exitIgnored.value)" -eq "partial") "a native reader that ignores its exit code reads as known, so the reader must check it"
$exitChecked = Invoke-HordeRead -What "a native listing" -Read { $o = cmd /c "echo partial& exit 3"; if ($LASTEXITCODE -ne 0) { throw ("the program exited " + $LASTEXITCODE) }; $o }
Check ($exitChecked.state -eq "unknown" -and $exitChecked.reason -like "*exited 3*") "a native reader that checks its exit code reads a failure as unknown"
# What a NATURAL reader delivers, measured, because the module's comment once claimed otherwise: a
# reader ending in a bare @() delivers nothing (so unknown), and one ending in @(5) delivers the bare
# 5. A reader that means "an empty list" must return ,@() - or say absent in so many words.
$bareEmpty = Invoke-HordeRead -What "the pane list" -Read { @() }
Check ($bareEmpty.state -eq "unknown") "a reader ending in a bare empty array reads as unknown, not as a known empty list"
$bareOne = Invoke-HordeRead -What "the pane list" -Read { @(5) }
$bareOneValue = Get-HordeValue $bareOne
Check ($bareOne.state -eq "known" -and $bareOneValue -is [int] -and $bareOneValue -eq 5) "a reader ending in a bare one-element array reads as the element, not a list"
$commaEmpty = Invoke-HordeRead -What "the pane list" -Read { , @() }
$commaEmptyValue = Get-HordeValue $commaEmpty
Check ($commaEmpty.state -eq "known" -and $commaEmptyValue -is [array] -and $commaEmptyValue.Count -eq 0) "CONTROL: a reader returning a comma-wrapped empty array reads as a known empty list"

Write-Host ""
Write-Host "--- absent and unknown stay apart ---" -ForegroundColor Cyan

$a = New-HordeAbsent
$u = New-HordeUnknown -Reason "wezterm did not answer"
Check ($a.state -ne $u.state -and (ConvertTo-HordeAnswerText $a) -ne (ConvertTo-HordeAnswerText $u)) "absent and unknown are never equal"
$texts = @((ConvertTo-HordeAnswerText (New-HordeKnown -Value 3)), (ConvertTo-HordeAnswerText $a), (ConvertTo-HordeAnswerText $u))
Check ($texts[0] -like "known*" -and $texts[1] -like "absent*" -and $texts[2] -like "unknown*") "each state renders as its own word"
Check (Throws { New-HordeUnknown -Reason "" } "needs a reason") "an unknown without a reason is refused"
Check (Throws { New-HordeUnknown -Reason "   " } "needs a reason") "and so is one whose reason is only spaces"
Check (Throws { New-HordeKnown -Value $null } "New-HordeAbsent") "a known nothing is refused and pointed at absent"
# A database null is a nothing too, and one a data reader hands back where $null was meant.
Check (Throws { New-HordeKnown -Value ([DBNull]::Value) } "New-HordeAbsent") "a known database null is refused as well"

Write-Host ""
Write-Host "--- real values are never sentinels ---" -ForegroundColor Cyan

$emptyList = New-HordeKnown -Value @()
$gotEmpty = Get-HordeValue $emptyList
Check ($emptyList.state -eq "known" -and $null -ne $gotEmpty -and @($gotEmpty).Count -eq 0) "an empty known collection stays known and empty"
$one = Get-HordeValue (New-HordeKnown -Value @(5))
Check ($one -is [array] -and $one.Count -eq 1 -and $one[0] -eq 5) "a single known item stays a collection"
# CONTROL for the two above: the trap is real in THIS PowerShell, so the checks are not vacuous.
function Get-RawEmpty { $o = @(); return $o }
function Get-RawOne { $o = @(5); return $o }
Check ($null -eq (Get-RawEmpty) -and (Get-RawOne) -isnot [array]) "CONTROL: returned bare, @() arrives as null and @(5) as a single number"
$map = New-HordeKnown -Value @{}
Check ($map.state -eq "known" -and (Get-HordeValue $map) -is [hashtable]) "an empty known map is not unknown"
$zero = New-HordeKnown -Value 0
Check ($zero.state -eq "known" -and (Get-HordeValue $zero) -eq 0) "a known zero is not unknown"
$blank = New-HordeKnown -Value ""
Check ($blank.state -eq "known" -and (Get-HordeValue $blank) -eq "") "a known empty string stays known"
$no = New-HordeKnown -Value $false
# -is [bool] as well as -eq: 0 -eq $false is true in PowerShell, so -eq alone would pass a known 0.
$noValue = Get-HordeValue $no
Check ($no.state -eq "known" -and $noValue -is [bool] -and $noValue -eq $false) "a known false is not absent"

Write-Host ""
Write-Host "--- there is nothing to read out of absent or unknown ---" -ForegroundColor Cyan

Check (Throws { Get-HordeValue $u } "unknown") "reading the value of unknown throws"
Check (Throws { Get-HordeValue $a } "absent") "reading the value of absent throws too"
Check (Throws { Get-HordeValue $null } "not a Horde answer") "a bare null is not an answer at all"
Check (Throws { Get-HordeValue @() } "not a Horde answer") "and neither is a bare empty array"
Check (Throws { Get-HordeValue -1 } "not a Horde answer") "nor a bare -1"
# Hand-built objects that carry the type name but break the shape's rules are not answers either.
$shouted = [pscustomobject]@{ PSTypeName = "Horde.Answer"; state = "KNOWN"; value = 1; reason = ""; observedAt = $null }
Check ((Test-HordeAnswer $shouted) -eq $false) "an answer whose state word is in the wrong case is not an answer"
$hollow = [pscustomobject]@{ PSTypeName = "Horde.Answer"; state = "known"; value = $null; reason = ""; observedAt = $null }
Check ((Test-HordeAnswer $hollow) -eq $false) "a known answer holding null is not an answer"
Check ((Test-HordeAnswer (New-HordeKnown -Value 0)) -eq $true) "CONTROL: a well-formed known answer is an answer"
# An observation time that is not a date was accepted when the answer was made, and Limit-HordeAge
# then threw a cast error far from the mistake (review, 2026-09-29: -ObservedAt "yesterday").
Check (Throws { New-HordeKnown -Value 1 -ObservedAt "yesterday" } "observation time") "a known answer refuses an observation time that is not a date"
Check (Throws { New-HordeAbsent -ObservedAt "yesterday" } "observation time") "and so does an absent one"
$textTime = [pscustomobject]@{ PSTypeName = "Horde.Answer"; state = "known"; value = 1; reason = ""; observedAt = "yesterday" }
Check ((Test-HordeAnswer $textTime) -eq $false) "an answer whose observation time is text is not an answer"
Check ((Test-HordeAnswer (New-HordeKnown -Value 1 -ObservedAt (Get-Date))) -eq $true) "CONTROL: an answer observed at a real date is an answer"
# THE CONSTRUCTORS BUILD THE ANSWER THEMSELVES (PR #31, 2026-10-02: a call through New-HordeAnswer
# doubled their cost), so each must still refuse exactly what New-HordeAnswer refuses, in its words,
# and build exactly what it builds. Same bad inputs, message for message.
function ErrorOf { param([scriptblock]$Block) try { $null = & $Block; return "(no error)" } catch { return "$($_.Exception.Message)" } }
$badTimes = @("yesterday", 5, @(1, 2), [pscustomobject]@{ when = "now" }, "2026-01-01T00:00:00Z")
$timeDiffs = @()
foreach ($t in $badTimes) {
    $want = ErrorOf { New-HordeAnswer -State "known" -Value 1 -Reason "" -ObservedAt $t }
    $gotK = ErrorOf { New-HordeKnown -Value 1 -ObservedAt $t }
    $gotA = ErrorOf { New-HordeAbsent -ObservedAt $t }
    if ($want -eq "(no error)" -or $gotK -cne $want -or $gotA -cne $want) { $timeDiffs += ("'" + $t + "': New-HordeAnswer [" + $want + "], known [" + $gotK + "], absent [" + $gotA + "]") }
}
foreach ($x in $timeDiffs) { Write-Host ("  " + $x) -ForegroundColor Red }
Check ($timeDiffs.Count -eq 0) "known and absent refuse every observation time New-HordeAnswer refuses, in its words"
$goodTime = Get-Date
$shapeDiffs = @()
foreach ($pair in @(
    @((New-HordeKnown -Value 7 -ObservedAt $goodTime), (New-HordeAnswer -State "known" -Value 7 -Reason "" -ObservedAt $goodTime)),
    @((New-HordeKnown -Value ""), (New-HordeAnswer -State "known" -Value "" -Reason "" -ObservedAt $null)),
    @((New-HordeAbsent -Note "none here" -ObservedAt $goodTime), (New-HordeAnswer -State "absent" -Value $null -Reason "none here" -ObservedAt $goodTime)),
    @((New-HordeAbsent), (New-HordeAnswer -State "absent" -Value $null -Reason "" -ObservedAt $null)),
    @((New-HordeUnknown -Reason "gone"), (New-HordeAnswer -State "unknown" -Value $null -Reason "gone" -ObservedAt $null)))) {
    $a = $pair[0]; $b = $pair[1]
    $ta = (@($a.PSObject.TypeNames) -join ","); $tb = (@($b.PSObject.TypeNames) -join ",")
    $pa = (@($a.PSObject.Properties | ForEach-Object { $_.Name + "=" + $_.Value }) -join ";"); $pb = (@($b.PSObject.Properties | ForEach-Object { $_.Name + "=" + $_.Value }) -join ";")
    if ($ta -cne $tb -or $pa -cne $pb) { $shapeDiffs += ($pa + " [" + $ta + "] against " + $pb + " [" + $tb + "]") }
}
foreach ($x in $shapeDiffs) { Write-Host ("  " + $x) -ForegroundColor Red }
Check ($shapeDiffs.Count -eq 0) "each constructor builds exactly the answer New-HordeAnswer builds"
Check ((ErrorOf { New-HordeKnown }) -ceq "a known answer needs a value; a known nothing is New-HordeAbsent" -and (Test-HordeAnswer (New-HordeKnown -Value @())) -and (Test-HordeAnswer (New-HordeKnown -Value $false))) "a known answer given no value at all is refused, and an empty list or false is still a value"
# Get-HordeField checks its name by hand since PR #31 (a Mandatory attribute cost 0.25 ms a call): an
# empty or missing name is still refused, in the words the attribute used.
Check ((Throws { Get-HordeField -Record ([pscustomobject]@{ a = 1 }) -Name "" } "because it is an empty string") -and (Throws { Get-HordeField -Record ([pscustomobject]@{ a = 1 }) -Name $null } "because it is an empty string") -and (Throws { Get-HordeField -Record ([pscustomobject]@{ a = 1 }) } "because it is an empty string")) "a field read with no name is refused"

Write-Host ""
Write-Host "--- stored answers and missing fields ---" -ForegroundColor Cyan

Check ((Get-HordeField -Record ([pscustomobject]@{ pane = 3 }) -Name "spawnedAt").state -eq "unknown") "a missing field reads as unknown"
Check ((Get-HordeField -Record @{ pane = 3 } -Name "spawnedAt").state -eq "unknown") "and so does one missing from a hashtable"
Check ((Get-HordeField -Record ([pscustomobject]@{ pane = 0 }) -Name "pane").state -eq "known") "CONTROL: a field that is there, even zero, reads as known"
$weird = ConvertFrom-HordeAnswerRecord -Record ([pscustomobject]@{ state = "probably"; value = 1 })
Check ($weird.state -eq "unknown" -and $weird.reason -like "*probably*") "an unrecognised state word is not known"
$cased = ConvertFrom-HordeAnswerRecord -Record ([pscustomobject]@{ state = "Known"; value = 1 })
Check ($cased.state -eq "unknown") "a state word in the wrong case is not recognised either"
Check ((ConvertFrom-HordeAnswerRecord -Record ([pscustomobject]@{ value = 1 })).state -eq "unknown") "a stored answer with no state is unknown, never inferred from its value"
# ["known"] is not "known": it only stringifies to it. JSON can carry either.
$listState = ConvertFrom-HordeAnswerRecord -Record ('{"state":["known"],"value":1}' | ConvertFrom-Json)
Check ($listState.state -eq "unknown") "a stored state that is a list, not a word, is not recognised"
$forgedList = [pscustomobject]@{ PSTypeName = "Horde.Answer"; state = @("known"); value = 1; reason = ""; observedAt = $null }
Check ((Test-HordeAnswer $forgedList) -eq $false) "an answer whose state is a list is not an answer"
Check ((ConvertFrom-HordeAnswerRecord -Record ([pscustomobject]@{ state = "known" })).state -eq "unknown") "a stored known with no value is unknown"
Check ((ConvertFrom-HordeAnswerRecord -Record $null).state -eq "unknown") "no report is unknown, not absent"
# A stored time with no zone cannot be placed in time: read as local, the same text written by a
# UTC writer at UTC-4 is four hours older than it looks, so a stale answer stayed known (review,
# 2026-09-29). It is treated as no observation time, which ages to unknown.
$zonelessText = (Get-Date).AddSeconds(-10).ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
$zoneless = ConvertFrom-HordeAnswerRecord -Record ([pscustomobject]@{ state = "known"; value = "idle"; reason = ""; observedAt = $zonelessText })
Check ($zoneless.state -eq "known" -and $null -eq $zoneless.observedAt) ("a stored time with no zone is not an observation time (" + $zonelessText + ")")
Check ((Limit-HordeAge -Answer $zoneless -TtlSeconds 60).state -eq "unknown") "so an answer stored with a zone-less time is unknown once aged"
$zonedText = (Get-Date).AddSeconds(-10).ToString("yyyy-MM-ddTHH:mm:sszzz", [System.Globalization.CultureInfo]::InvariantCulture)
$zoned = ConvertFrom-HordeAnswerRecord -Record ([pscustomobject]@{ state = "known"; value = "idle"; reason = ""; observedAt = $zonedText })
Check ((Limit-HordeAge -Answer $zoned -TtlSeconds 60).state -eq "known") ("CONTROL: a stored time with an offset keeps its place and stays known (" + $zonedText + ")")
# A record held in memory can carry a real [datetime]. Turned into text to be parsed, a UTC one lost its
# zone and was read as local - at UTC-4, observed ten seconds ago read as four hours in the future.
$inMemory = ConvertFrom-HordeAnswerRecord -Record @{ state = "known"; value = "idle"; reason = ""; observedAt = [datetime]::UtcNow.AddSeconds(-10) }
Check ((Limit-HordeAge -Answer $inMemory -TtlSeconds 60).state -eq "known") "a record holding a UTC time as a date keeps its zone"

# ConvertTo-Json's default depth is 2, counted from the record: anything deeper in the value is
# written as its type name. The documented rule is to pass -Depth; this pins why.
$deepRecord = ConvertTo-HordeAnswerRecord (New-HordeKnown -Value @{ pane = @{ id = @{ n = 3 } } })
Check (($deepRecord | ConvertTo-Json -Compress) -like "*System.Collections.Hashtable*") "CONTROL: a stored answer written at the default JSON depth loses a deep value"
Check (($deepRecord | ConvertTo-Json -Compress -Depth 10) -like '*"n":3*') "a stored answer written with enough depth keeps a deep value"

# The round trip through JSON, which is where shape is usually lost.
$now = [datetime]::UtcNow
# The state alone surviving is not enough: a known 0 that came back as @(0), or an empty list that
# came back as $null, would keep its state and lose its meaning. So the value's shape is compared too.
function Get-ValueShape { param($V)
    if ($null -eq $V) { return "null" }
    if ($V -is [array]) { return ("array[" + $V.Count + "](" + ((@($V) | ForEach-Object { Get-ValueShape $_ }) -join ",") + ")") }
    return ($V.GetType().Name + "=" + $V) }
function Get-AnswerShape { param($A)
    $shape = $A.state
    if ($A.state -eq "known") { $v = Get-HordeValue $A; $shape += " " + (Get-ValueShape $v) }
    if ($null -ne $A.observedAt) { $shape += " at " + ([datetime]$A.observedAt).ToUniversalTime().ToString("o") }
    return $shape }
foreach ($orig in @((New-HordeKnown -Value @() -ObservedAt $now), (New-HordeKnown -Value @(5) -ObservedAt $now), (New-HordeKnown -Value 0 -ObservedAt $now), (New-HordeKnown -Value $false -ObservedAt $now), (New-HordeKnown -Value "" -ObservedAt $now), (New-HordeAbsent -ObservedAt $now), $u)) {
    $json = ConvertTo-HordeAnswerRecord $orig | ConvertTo-Json -Compress -Depth 5
    $back = ConvertFrom-HordeAnswerRecord -Record ($json | ConvertFrom-Json)
    Check ($back.state -eq $orig.state) ("the stored form of an " + $orig.state + " answer survives a JSON round trip as " + $orig.state + " (" + $json + ")")
    Check ((Get-AnswerShape $back) -eq (Get-AnswerShape $orig)) ("and its value keeps its shape: " + (Get-AnswerShape $orig))
}

Write-Host ""
Write-Host "--- evidence expires, whatever it said ---" -ForegroundColor Cyan

$t = Get-Date "2026-09-29T12:00:00"
$busy = New-HordeKnown -Value "busy" -ObservedAt $t
Check ((Limit-HordeAge -Answer $busy -TtlSeconds 60 -Now $t.AddSeconds(61)).state -eq "unknown") "a known reading past its TTL becomes unknown"
$idle = New-HordeKnown -Value "idle" -ObservedAt $t
$gone = New-HordeAbsent -ObservedAt $t
Check ((Limit-HordeAge -Answer $idle -TtlSeconds 60 -Now $t.AddSeconds(61)).state -eq "unknown" -and (Limit-HordeAge -Answer $gone -TtlSeconds 60 -Now $t.AddSeconds(61)).state -eq "unknown") "a stale reassuring value also becomes unknown"
Check ((Limit-HordeAge -Answer $busy -TtlSeconds 60 -Now $t.AddSeconds(59)).state -eq "known") "CONTROL: a reading inside its TTL stays known"
Check ((Limit-HordeAge -Answer (New-HordeKnown -Value 1) -TtlSeconds 60 -Now $t).state -eq "unknown") "a reading with no observation time cannot be aged, so it is unknown"
Check ((Throws { Limit-HordeAge -Answer $busy -TtlSeconds 0 } "positive") -and (Throws { Limit-HordeAge -Answer $busy -TtlSeconds "6o" } "positive")) "a non-positive TTL is refused"
# NaN compares false with everything, so a NaN TTL was accepted and nothing ever went stale: a
# 400-day-old answer stayed known. Infinity says the same thing out loud.
$ancient = New-HordeKnown -Value "idle" -ObservedAt $t.AddDays(-400)
Check ((Throws { Limit-HordeAge -Answer $ancient -TtlSeconds "NaN" -Now $t } "positive") -and (Throws { Limit-HordeAge -Answer $ancient -TtlSeconds "Infinity" -Now $t } "positive") -and (Throws { Limit-HordeAge -Answer $ancient -TtlSeconds ([double]::NaN) -Now $t } "positive")) "a TTL that is not a finite number is refused"
# Parsed in the current culture, "1,5" was fifteen seconds here and 1.5 in a comma-decimal culture.
Check (Throws { Limit-HordeAge -Answer $busy -TtlSeconds "1,5" -Now $t } "positive") "a TTL written with a comma is refused, whatever the culture"
Check ((Limit-HordeAge -Answer $busy -TtlSeconds "60.5" -Now $t.AddSeconds(60)).state -eq "known") "CONTROL: a TTL with a decimal point is honoured"
# An observation time in the future has a negative age, which is never past any TTL: such an answer
# never went stale. A few seconds of clock skew between writers is allowed; more is not believed.
$future = New-HordeKnown -Value "idle" -ObservedAt $t.AddSeconds(60)
Check ((Limit-HordeAge -Answer $future -TtlSeconds 60 -Now $t).state -eq "unknown") "an answer observed in the future is unknown, not fresh forever"
$skewed = New-HordeKnown -Value "idle" -ObservedAt $t.AddSeconds(3)
Check ((Limit-HordeAge -Answer $skewed -TtlSeconds 60 -Now $t).state -eq "known") "CONTROL: a few seconds of clock skew is allowed"
# Real answers are stored and read back, which makes observedAt a UTC time, while the default -Now
# is local. Compared as they stood, a UTC- zone saw every stored answer as observed in the future,
# so none ever expired (measured at UTC-4, 2026-09-29: 120s old read as known with a 60s TTL).
$oldJson = ConvertTo-HordeAnswerRecord (New-HordeKnown -Value "idle" -ObservedAt (Get-Date).AddSeconds(-120)) | ConvertTo-Json -Compress -Depth 5
$oldBack = ConvertFrom-HordeAnswerRecord -Record ($oldJson | ConvertFrom-Json)
Check ((Limit-HordeAge -Answer $oldBack -TtlSeconds 60).state -eq "unknown") "a stored answer read back and aged with the default clock expires"
$utcStamped = New-HordeKnown -Value "idle" -ObservedAt ([datetime]::UtcNow.AddSeconds(-120))
Check ((Limit-HordeAge -Answer $utcStamped -TtlSeconds 60).state -eq "unknown") "an answer stamped in UTC expires against the default clock"
$freshJson = ConvertTo-HordeAnswerRecord (New-HordeKnown -Value "idle" -ObservedAt (Get-Date).AddSeconds(-10)) | ConvertTo-Json -Compress -Depth 5
Check ((Limit-HordeAge -Answer (ConvertFrom-HordeAnswerRecord -Record ($freshJson | ConvertFrom-Json)) -TtlSeconds 60).state -eq "known") "CONTROL: a stored answer read back inside its TTL stays known"
# The checks above do not isolate the UTC rule (review, 2026-09-29): west of UTC the broken module
# reads a stored answer as observed in the future, and the future-skew rule makes it unknown anyway.
# So the same instant is put on both clocks - observedAt in UTC, -Now in local time, and the reverse -
# and the answer must age by its TRUE age: a fresh one stays known, and a stale one reports the age it
# really has. Aged as they stood, each is off by the local offset, in either direction.
$localOffsetSeconds = [int][System.TimeZoneInfo]::Local.GetUtcOffset([datetime]::UtcNow).TotalSeconds
if ($localOffsetSeconds -eq 0) {
    Write-Host "  [SKIP] the local clock is UTC here, so a local time and a UTC time cannot disagree; the next two checks did not run" -ForegroundColor Yellow
} else {
    $instantUtc = [datetime]::UtcNow
    $instantLocal = $instantUtc.ToLocalTime()
    $freshUtc = Limit-HordeAge -Answer (New-HordeKnown -Value "idle" -ObservedAt $instantUtc.AddSeconds(-10)) -TtlSeconds 60 -Now $instantLocal
    $freshLocal = Limit-HordeAge -Answer (New-HordeKnown -Value "idle" -ObservedAt $instantLocal.AddSeconds(-10)) -TtlSeconds 60 -Now $instantUtc
    Check ($freshUtc.state -eq "known" -and $freshLocal.state -eq "known") ("an answer 10s old stays known when observedAt and the clock are in different zones (offset " + $localOffsetSeconds + "s)")
    $offsetMagnitude = [Math]::Abs($localOffsetSeconds)
    $staleUtc = Limit-HordeAge -Answer (New-HordeKnown -Value "idle" -ObservedAt $instantUtc.AddSeconds(-2 * $offsetMagnitude)) -TtlSeconds (1.5 * $offsetMagnitude) -Now $instantLocal
    Check ($staleUtc.state -eq "unknown" -and $staleUtc.reason -like ("stale: observed " + (2 * $offsetMagnitude) + "s ago*")) "an answer observed in UTC and aged against a local clock expires by its true age"
}

Write-Host ""
Write-Host "--- the caller states what an unknown costs ---" -ForegroundColor Cyan

# Checked on the declaration, not by calling without -OnUnknown: a missing mandatory parameter throws
# only in a non-interactive host - in a console it PROMPTS, and the suite hangs on stdin. Mandatory
# with no default is what makes the call fail (or stop and ask) rather than pick a policy silently.
$onUnknownParam = (Get-Command Resolve-HordeAnswer).Parameters["OnUnknown"]
$onUnknownMandatory = @($onUnknownParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count -gt 0
$onUnknownAst = @((Get-Command Resolve-HordeAnswer).ScriptBlock.Ast.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq "OnUnknown" })
Check ($onUnknownMandatory -and $onUnknownAst.Count -eq 1 -and $null -eq $onUnknownAst[0].DefaultValue) "resolving unknown without a policy throws"
$r = Resolve-HordeAnswer -Answer $u -OnUnknown Refuse
Check ($r.outcome -eq "refused" -and $r.reason -eq $u.reason) "refusing on unknown keeps the reason, so the refusal can say why"
Check ((Resolve-HordeAnswer -Answer $u -OnUnknown Permit).outcome -eq "permitted") "permitting is a separate, named outcome, never mistaken for known"
Check ((Resolve-HordeAnswer -Answer $u -OnUnknown AsAbsent).outcome -eq "absent") "treating unknown as none is possible only by writing it down"
Check (Throws { Resolve-HordeAnswer -Answer $u -OnUnknown Throw } "wezterm did not answer") "and throwing carries the reason"
Check ((Resolve-HordeAnswer -Answer (New-HordeKnown -Value 7) -OnUnknown Refuse).value -eq 7) "CONTROL: a known answer resolves to its value whatever the policy"

# THE TRAP THIS MODULE CANNOT REMOVE, pinned so nobody relies on the opposite: an answer is an
# object, and every object is true to `if`.
Check ([bool](New-HordeUnknown -Reason "x") -eq $true) "an unknown answer is still true to an if, so an answer is never tested with a bare if"
# The second trap, pinned the same way: .value is readable without the state check, and reads as
# null for an unknown - the silent "none". A value is read with Get-HordeValue.
$valueOfUnknown = "not read"
$valueOfUnknown = (New-HordeUnknown -Reason "x").value
Check ($null -eq $valueOfUnknown) "an unknown answer's value property reads as null without throwing, so a value is read with Get-HordeValue"

Complete-HordeSuite -Success "unknown is never read as none"
