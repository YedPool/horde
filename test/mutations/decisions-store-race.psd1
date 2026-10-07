# Mutations of decisions/Store.ps1 that only racing processes can see. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-store-race.psd1
# test\test-decisions-store-race.ps1 must fail for each.
#
# Each run of the suite starts 16 powershell.exe processes (4 racers, four races), kills about 18
# writers one after another, and stops four more at a named step; measured 2026-10-06 on a throttled
# machine, one run took about 75 s.
@{
    Target = "decisions\Store.ps1"
    Suite  = "test\test-decisions-store-race.ps1"
    Mutations = @(
        @{ Name = "move-overwrites"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $fs'
           Replace = '[System.IO.File]::WriteAllBytes($recPath, $bytes); $moved = "moved"' }
        # --- the sweep's invariant, with the writer and the sweep in two processes ---
        @{ Name = "writer-lets-go-before-the-move"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $fs'
           Replace = '$fs.Dispose(); $moved = Move-HordeFileNewDurable -From $tmpPath -To $recPath -Open $null' }
        @{ Name = "held-leftover-deleted-by-name"
           Find = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)'
           Replace = '[System.IO.File]::Delete($leftover); $claim = New-Object System.IO.MemoryStream' }
        @{ Name = "record-written-under-its-own-name"
           Find = '$tmpPath = Join-Path $Root ("writing-" + [guid]::NewGuid().ToString("N") + ".part")'
           Replace = '$tmpPath = $recPath' }
        @{ Name = "check-then-create"
           Find = '    $recPath = Join-Path $Root (Get-HordeDecisionRecordName -Sequence $Sequence)'
           Replace = '    $recPath = Join-Path $Root (Get-HordeDecisionRecordName -Sequence $Sequence); if ([System.IO.File]::Exists($recPath)) { return "exists" } else { [System.IO.File]::WriteAllBytes($recPath, $script:HordeDecisionStoreUtf8.GetBytes($Text)); return "created" }' }
    )
}
