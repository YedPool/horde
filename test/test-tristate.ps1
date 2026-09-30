# DOES HORDE KEEP "I DO NOT KNOW" APART FROM "THERE IS NONE"?
#
# Every lesson here is from the system Horde replaces, where an unknown silently read as none was
# behind sessions called dead that were alive, a kill reported done that killed nothing, and six
# panes reported closed that were open. planning/ledger/core-tristate.md cites each one.

$ErrorActionPreference = "Continue"
# The whole suite runs under the strictest mode, so the module is proved to work for a caller that
# uses it. The module once switched strict mode off at file scope, which - dot-sourced - switched it
# off for the caller too.
Set-StrictMode -Version Latest
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "core\Tristate.ps1")

$fails = @()
# A condition must be exactly true or false; anything else fails loudly. A helper that returned an
# array alongside $false once made a "must throw" check pass when nothing threw (see test-isolation.ps1).
function Check { param($Cond, [string]$What)
    if ($Cond -isnot [bool]) { Write-Host "  [FAIL] $What (the check's condition was not true or false)" -ForegroundColor Red; $script:fails += $What; return }
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }
function Throws { param([scriptblock]$Block, [string]$Like = "")
    try { $null = & $Block; return $false } catch { return ("$($_.Exception.Message)" -like "*$Like*") } }

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
# Most cmdlet failures are non-terminating: they write an error and carry on. Under this suite's
# Continue preference, a reader that failed that way still returned its fallback as known.
$softFail = Invoke-HordeRead -What "the pane list" -Read { Write-Error "boom"; 0 }
Check ($softFail.state -eq "unknown" -and $softFail.reason -like "*boom*") "a reader that writes a non-terminating error reads as unknown"
$noSuchDir = Join-Path $env:TEMP ("horde-no-such-dir-" + [guid]::NewGuid().ToString("N"))
$missingPath = Invoke-HordeRead -What "the registry" -Read { , @(Get-ChildItem -LiteralPath $noSuchDir) }
Check ($missingPath.state -eq "unknown") "a cmdlet error inside a reader is not swallowed into a known empty list"
Check ($ErrorActionPreference -eq "Continue") "the caller's error preference is untouched by a read"
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
Check ($no.state -eq "known" -and (Get-HordeValue $no) -eq $false) "a known false is not absent"

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

# ConvertTo-Json's default depth is 2, counted from the record: anything deeper in the value is
# written as its type name. The documented rule is to pass -Depth; this pins why.
$deepRecord = ConvertTo-HordeAnswerRecord (New-HordeKnown -Value @{ pane = @{ id = @{ n = 3 } } })
Check (($deepRecord | ConvertTo-Json -Compress) -like "*System.Collections.Hashtable*") "CONTROL: a stored answer written at the default JSON depth loses a deep value"
Check (($deepRecord | ConvertTo-Json -Compress -Depth 10) -like '*"n":3*') "a stored answer written with enough depth keeps a deep value"

# The round trip through JSON, which is where shape is usually lost.
$now = [datetime]::UtcNow
foreach ($orig in @((New-HordeKnown -Value @() -ObservedAt $now), (New-HordeKnown -Value 0 -ObservedAt $now), (New-HordeAbsent -ObservedAt $now), $u)) {
    $json = ConvertTo-HordeAnswerRecord $orig | ConvertTo-Json -Compress -Depth 5
    $back = ConvertFrom-HordeAnswerRecord -Record ($json | ConvertFrom-Json)
    Check ($back.state -eq $orig.state) ("the stored form of an " + $orig.state + " answer survives a JSON round trip as " + $orig.state + " (" + $json + ")")
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

Write-Host ""
Write-Host "--- the caller states what an unknown costs ---" -ForegroundColor Cyan

Check (Throws { Resolve-HordeAnswer -Answer $u } "OnUnknown") "resolving unknown without a policy throws"
$r = Resolve-HordeAnswer -Answer $u -OnUnknown Refuse
Check ($r.outcome -eq "refused" -and $r.reason -eq $u.reason) "refusing on unknown keeps the reason, so the refusal can say why"
Check ((Resolve-HordeAnswer -Answer $u -OnUnknown Permit).outcome -eq "permitted") "permitting is a separate, named outcome, never mistaken for known"
Check ((Resolve-HordeAnswer -Answer $u -OnUnknown AsAbsent).outcome -eq "absent") "treating unknown as none is possible only by writing it down"
Check (Throws { Resolve-HordeAnswer -Answer $u -OnUnknown Throw } "wezterm did not answer") "and throwing carries the reason"
Check ((Resolve-HordeAnswer -Answer (New-HordeKnown -Value 7) -OnUnknown Refuse).value -eq 7) "CONTROL: a known answer resolves to its value whatever the policy"

# THE TRAP THIS MODULE CANNOT REMOVE, pinned so nobody relies on the opposite: an answer is an
# object, and every object is true to `if`.
Check ([bool](New-HordeUnknown -Reason "x") -eq $true) "an unknown answer is still true to an if, so an answer is never tested with a bare if"

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== unknown is never read as none ====" -ForegroundColor Green
exit 0
