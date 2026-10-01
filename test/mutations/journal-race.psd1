# Mutations of remote/Journal.ps1 that only racing processes can see. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\journal-race.psd1
# test\test-journal-race.ps1 must fail for each, except those declared Expect = "survives".
#
# Each run of the suite starts 8 powershell.exe processes (4 racers, twice) and takes about a minute.
@{
    Target = "remote\Journal.ps1"
    Suite  = "test\test-journal-race.ps1"
    Mutations = @(
        @{ Name = "create-overwrites"
           Find = '[System.IO.FileMode]::CreateNew'
           Replace = '[System.IO.FileMode]::OpenOrCreate' }
        @{ Name = "check-then-create"
           Find = 'try { $made = New-HordeJournalFile -Path $recPath -Text $recText }'
           Replace = 'try { if ([System.IO.File]::Exists($recPath)) { $made = "exists" } else { [System.IO.File]::WriteAllText($recPath, $recText); $made = "created" } }' }
    )
}
