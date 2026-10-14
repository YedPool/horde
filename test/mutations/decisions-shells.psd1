# Mutations of decisions/Operations.ps1's two parses, each put back to the plain ConvertFrom-Json that
# issue #274 found refusing under PowerShell 7. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-shells.psd1
# test\test-decisions-shells.ps1 must fail for each; it needs pwsh.exe to (without it the suite exits 3,
# which this spec does not accept, so a machine without PowerShell 7 reports these as not caught).
# The store's reader has its own spec: test\mutations\decisions-shells-store.psd1.
@{
    Target = "decisions\Operations.ps1"
    Suite  = "test\test-decisions-shells.ps1"
    Mutations = @(
        @{ Name = "new-record-read-back-with-dates"
           Find = 'data = (ConvertFrom-HordeJson $text); reason = "" }'
           Replace = 'data = ($text | ConvertFrom-Json); reason = "" }' }
        @{ Name = "request-read-back-with-dates"
           Find = '$plain = ConvertFrom-HordeJson (ConvertTo-Json -InputObject $Request -Compress -Depth 12) }'
           Replace = '$plain = (ConvertTo-Json -InputObject $Request -Compress -Depth 12) | ConvertFrom-Json }' }
    )
}
