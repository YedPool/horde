# Mutations of core/Wake.ps1 held by the shadow-ledger section of test\test-wake-run.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-shadow-ledger.psd1
# A shadow run keeps its own ledger and backs off, gives up and finds a silent fleet exactly as a live run would, so
# that what it looks at and journals is the live pace; the section drives the same scene through both and must fail for each.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-wake-run.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-shadow-would-nudge-is-not-recorded-in-the-ledger"
           Find = '$outcomes[$d.id] = "would-nudge"; [void]$entries.Add('
           Replace = '[void]$entries.Add(' }
        @{ Name = "a-shadow-pass-never-gives-up"
           Find = '$gave = Update-HordeWakeGaveUp -Ledger $nextLedger -Now $Now -Settings $Settings'
           Replace = '$gave = $(if ($shadowPass) { [pscustomobject]@{ ledger = $nextLedger; sessions = @(); entries = @() } } else { Update-HordeWakeGaveUp -Ledger $nextLedger -Now $Now -Settings $Settings })' }
        @{ Name = "the-silence-does-not-count-a-would-nudge"
           Find = '@("nudge", "nudge-killed", "would-nudge") -cnotcontains "$($e.kind)") { continue }'
           Replace = '@("nudge", "nudge-killed") -cnotcontains "$($e.kind)") { continue }' }
    )
}
