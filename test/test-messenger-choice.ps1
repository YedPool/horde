# DOES EVERY TELL THAT LOADS THE MESSENGERS PICK THE REAL ONE, AND NEVER STALL ON THE TEST ONE? (T-0336)
#
# Every messenger folder is loaded together (Get-HordeMessengerFiles), so a tell that asks only for
# body.untyped and idempotent.post finds TWO messengers that offer them - memory, the in-process test
# store, and wezfleet - and Find-HordeMessenger never chooses between two: nothing was sent. The analyst's
# tells failed that way 2031 times from 2026-10-15, and the first `horde merge` ended "MERGED, NOT
# FINISHED". memory DECLINES receipt.receiver on purpose, so a tell that also requires it has one answer.
#
# This suite loads the REAL memory and the REAL wezfleet messenger files (no double defines the seam),
# reads each of the five tells' own need-lists, and proves each one picks wezfleet and posts through it,
# using wezfleet's fake fleet command (messengers/wezfleet/test/FakeWezfleet.ps1) as the messenger's tests do.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest
foreach ($f in @("Tristate", "SessionSeat", "Device")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
. (Join-Path $root "messengers\Port.ps1")
foreach ($m in @(Get-HordeMessengerFiles)) { . $m }
. (Join-Path $root "test\lib\MessengerPins.ps1")
$pinned = Enter-HordeTestPinnedHome -Root $root
foreach ($f in @("Merge", "RelayRunTell", "AnalystTend", "MeterTell", "ServicesTell")) { . (Join-Path $root ("cli\" + $f + ".ps1")) }

$fx = & (Join-Path $root "messengers\wezfleet\test\Fixture.ps1") -Root $root
$script:seq = 0
function New-Msg {
    $script:seq++
    return [pscustomobject]@{
        messageId = ("0e000000-0000-4000-8000-" + $script:seq.ToString("000000000000"))
        sessionId = "22222222-3333-4444-8555-666666666666"
        label = "A"
        from = [pscustomobject]@{ deviceId = "0f000000-0000-4000-8000-000000000001"; sessionId = "33333333-4444-4555-8666-777777777777"; label = "M" }
        body = "a tell from the choice suite"
        ttlSeconds = 3600
    }
}

try {
    Write-Host ""
    Write-Host "--- both real messengers are loaded, and the old need-list is ambiguous (CONTROL) ---" -ForegroundColor Cyan
    Check ((@(Get-HordeMessengerNames) -join ",") -ceq "memory,wezfleet") ("the loaded messengers are the real memory and wezfleet (" + (@(Get-HordeMessengerNames) -join ",") + ")")
    $old = Find-HordeMessenger -Require @("body.untyped", "idempotent.post")
    Check ($old.state -ceq "unknown" -and "$($old.reason)".Contains("memory, wezfleet")) "CONTROL: asking for body.untyped and idempotent.post alone is two messengers, and none is chosen"

    Write-Host ""
    Write-Host "--- each tell's own need-list picks wezfleet, and a post through it lands in the fleet ---" -ForegroundColor Cyan
    foreach ($case in @(
            @{ n = "horde merge"; needs = { $script:HordeMergeTellNeeds } },
            @{ n = "the relay run"; needs = { $script:HordeRelayRunTellNeeds } },
            @{ n = "the analyst"; needs = { $script:HordeAnalystTellNeeds } },
            @{ n = "the fleet meter"; needs = { $script:HordeMeterTellNeeds } },
            @{ n = "the services"; needs = { $script:HordeServiceTellNeeds } })) {
        $needs = [string[]]@(& $case.needs)
        Check ($needs.Count -gt 0) ($case.n + ": its need-list is there")
        $found = Find-HordeMessenger -Require $needs
        Check ($found.state -ceq "known" -and "$($found.value.name)" -ceq "wezfleet") ($case.n + ": its need-list picks wezfleet (" + $found.state + ")")
        if ($found.state -cne "known") { continue }
        $st = & $fx.New
        try {
            $msg = New-Msg
            $r = Send-HordeMessengerMessage -Messenger $found.value -Message $msg
            $seen = & $fx.Observe $st $msg.messageId
            Check ($r.state -ceq "known" -and $seen.records -eq 1) ($case.n + ": the tell is posted through the picked messenger, one record in the fleet (" + $r.state + ": " + $r.reason + "; records " + $seen.records + ")")
        } finally { & $fx.Remove $st }
    }
} finally { Exit-HordeTestPinnedHome -State $pinned }

Complete-HordeSuite -Success "every tell that loads the messengers has one messenger to choose, wezfleet, and posts through it"