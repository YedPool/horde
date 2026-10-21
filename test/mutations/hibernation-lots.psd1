# Mutations of the lot half of fleet/Hibernation.ps1: every park is one lot (T-0216). test/test-fleet-lots.ps1 must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hibernation-lots.psd1
@{
    Target = "fleet\Hibernation.ps1"
    Suite  = "test\test-fleet-lots.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-park-writes-no-lot"
           Find = '[void](Write-HordeFleetLot -Dir $dir -Lot $lot -Members $lotMembers)'
           Replace = '$null = $lotMembers' }
        @{ Name = "the-lots-reason-is-lost"
           Find = '$lot = New-HordeFleetLot -At $at -ById $By -Reason $Why -Kind ("" + $Selection.kind)'
           Replace = '$lot = New-HordeFleetLot -At $at -ById $By -Reason "park" -Kind ("" + $Selection.kind)' }
        @{ Name = "record-write-leaves-the-members-stale"
           Find = 'try { Sync-HordeFleetLotMembers -Dir $Dir -Record $Record } catch { $null = $_ }'
           Replace = '$null = 1' }
    )
}
