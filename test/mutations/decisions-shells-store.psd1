# Mutation of decisions/Store.ps1's record reader, put back to the plain ConvertFrom-Json that issue
# #274 found reading every timestamp as a date under PowerShell 7. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-shells-store.psd1
# test\test-decisions-shells.ps1 must fail for it; it needs pwsh.exe to (see decisions-shells.psd1).
@{
    Target = "decisions\Store.ps1"
    Suite  = "test\test-decisions-shells.ps1"
    Mutations = @(
        @{ Name = "record-read-with-dates"
           Find = 'try { $data = ConvertFrom-HordeJson $text } catch {'
           Replace = 'try { $data = $text | ConvertFrom-Json } catch {' }
    )
}
