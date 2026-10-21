# Mutations of fleet/Lots.ps1, the parking lots as the founder reads them (T-0216). Each breaks one rule of listing, waking or backfilling a lot; test/test-fleet-lots.ps1 must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-lots.psd1
@{
    Target = "fleet\Lots.ps1"
    Suite  = "test\test-fleet-lots.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "lots-listed-oldest-first"
           Find = '@{ Expression = { $_.created_at }; Descending = $true }'
           Replace = '@{ Expression = { $_.created_at }; Descending = $false }' }
        @{ Name = "running-member-counts-as-asleep"
           Find = 'if ($Running) { if ($Stored -ceq "woken") { return "woken" }; return "still-awake" }'
           Replace = 'if ($false) { return "still-awake" }' }
        @{ Name = "liveness-never-read-for-a-member"
           Find = '$running = ("" + (Get-HordeFleetMember $v "state") -ceq "running")'
           Replace = '$running = $false' }
        @{ Name = "unreadable-liveness-reads-as-asleep"
           Find = 'if ("" + (Get-HordeFleetMember $v "kind") -ceq "reading") { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "one-corrupt-lot-stalls-the-list"
           Find = 'if ($one.state -cne "known") { [void]$skipped.Add("lot " + $id + " is skipped: " + $one.reason); continue }'
           Replace = 'if ($one.state -cne "known") { return (New-HordeUnknown -Reason "a lot is unreadable") }' }
        @{ Name = "subset-wake-wakes-the-whole-lot"
           Find = '$only = $(if ($named.Count -eq 0) { @() } else { $wakeIds })'
           Replace = '$only = @()' }
        @{ Name = "unknown-member-name-is-dropped"
           Find = 'if ($hit.Count -eq 0) { throw ("lot " + $Lot + " holds no member'
           Replace = 'if ($false) { throw ("lot " + $Lot + " holds no member' }
        @{ Name = "ambiguous-prefix-is-guessed"
           Find = 'if ($hit.Count -gt 1) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "backfill-writes-again-on-a-second-run"
           Find = 'if (Test-Path -LiteralPath (Join-Path $dir "parking_lot.json") -PathType Leaf) {'
           Replace = 'if ($false) {' }
        @{ Name = "backfill-id-from-chance"
           Find = '$seed = "backfill|" + (Format-HordeFleetTime -At $at) + "|" + $dl.why'
           Replace = '$seed = ""' }
        @{ Name = "wake-not-recorded"
           Find = 'if ($recordable.Count -gt 0) { $wakeId ='
           Replace = 'if ($false) { $wakeId =' }
        @{ Name = "dry-run-records-a-wake"
           Find = 'if (-not $DryRun -and $outcomes.Count -gt 0) {'
           Replace = 'if ($outcomes.Count -gt 0) {' }
    )
}
