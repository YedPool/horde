# Mutations of files/Store.ps1 that only racing processes can see. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-store-race.psd1
# test\test-files-race.ps1 must fail for each.
#
# Each run of the suite starts 16 powershell.exe processes (4 racers, three races, and four writers
# stopped at a named step and killed); measured 2026-10-13 on a throttled machine, one run took about
# 12 s.
@{
    Target = "files\Store.ps1"
    Suite  = "test\test-files-race.ps1"
    Mutations = @(
        @{ Name = "move-overwrites"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $fs'
           Replace = '[System.IO.File]::WriteAllBytes($entryPath, $Bytes); $moved = "moved"' }
        @{ Name = "check-then-create"
           Find = '    $entryPath = Join-Path $Root $Name'
           Replace = '    $entryPath = Join-Path $Root $Name; if ([System.IO.File]::Exists($entryPath)) { return "exists" } else { [System.IO.File]::WriteAllBytes($entryPath, $Bytes); return "created" }' }
        # --- the sweep's invariant, with the writer and the sweep in two processes ---
        @{ Name = "writer-lets-go-before-the-move"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $fs'
           Replace = '$fs.Dispose(); $moved = Move-HordeFileNewDurable -From $tmpPath -To $entryPath -Open $null' }
        @{ Name = "held-leftover-deleted-by-name"
           Find = '$claim = New-Object System.IO.FileStream($leftover, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)'
           Replace = '[System.IO.File]::Delete($leftover); $claim = New-Object System.IO.MemoryStream' }
        @{ Name = "entry-written-under-its-own-name"
           Find = '$tmpPath = Join-Path $Root ("writing-" + [guid]::NewGuid().ToString("N") + ".part")'
           Replace = '$tmpPath = $entryPath' }
    )
}
