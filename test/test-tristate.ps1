# DOES HORDE KEEP "I DO NOT KNOW" APART FROM "THERE IS NONE"?
#
# Every lesson here is from the system Horde replaces, where an unknown silently read as none was
# behind sessions called dead that were alive, a kill reported done that killed nothing, and six
# panes reported closed that were open. planning/ledger/core-tristate.md cites each one.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "core\Tristate.ps1")

$fails = @()
function Check { param($Cond, [string]$What)
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }
function Throws { param([scriptblock]$Block, [string]$Like = "")
    try { & $Block; return $false } catch { return ("$($_.Exception.Message)" -like "*$Like*") } }

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
Check ((ConvertFrom-HordeAnswerRecord -Record ([pscustomobject]@{ state = "known" })).state -eq "unknown") "a stored known with no value is unknown"
Check ((ConvertFrom-HordeAnswerRecord -Record $null).state -eq "unknown") "no report is unknown, not absent"

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
