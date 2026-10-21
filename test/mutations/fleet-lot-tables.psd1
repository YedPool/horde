# Mutations of fleet/LotTables.ps1, the parking lot's four tables (T-0216). Each breaks one rule of the rows; test/test-fleet-lots.ps1 must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-lot-tables.psd1
@{
    Target = "fleet\LotTables.ps1"
    Suite  = "test\test-fleet-lots.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "ulid-time-is-not-the-lots-time"
           Find = '[void]$bits.Append([Convert]::ToString([int](($ms -shr (8 * $i)) -band 255), 2).PadLeft(8, "0"))'
           Replace = '[void]$bits.Append("00000000")' }
        @{ Name = "woken-member-reads-parked"
           Find = 'if ($RecordState -ceq "woken") { return "woken" }'
           Replace = 'if ($false) { return "woken" }' }
        @{ Name = "old-record-gets-a-new-id-each-read"
           Find = '-Seed ("legacy|" + $hid)'
           Replace = '-Seed ""' }
        @{ Name = "member-copy-not-refreshed"
           Find = 'Write-HordeFleetTableFile -Path $path -Table $script:HordeFleetTableNames.member -Rows $rows'
           Replace = '$null = $rows' }
    )
}
