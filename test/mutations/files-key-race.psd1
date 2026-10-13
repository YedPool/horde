# The mutation of files/Key.ps1 that racing processes must see. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-key-race.psd1
# test\test-files-race.ps1 must fail for it.
#
# IT IS THE SUITE'S OWN CONTROL, RUN AS A MUTANT: a key put in place by a copy that replaces. Four
# processes make the first share of each of six new homes on one tick; with this mutant some of them
# use a key that another then replaces, and are told different ids for one path. Measured 2026-10-13
# on a throttled machine: 4 of the 6 rounds split with the mutant, and 0 of 6 without it. A run in
# which no round splits is possible, and would be reported here as not caught; the same mutant is
# caught without any race by test\mutations\files-key.psd1.
@{
    Target = "files\Key.ps1"
    Suite  = "test\test-files-race.ps1"
    Mutations = @(
        @{ Name = "key-move-replaces-the-key-that-is-there"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $Path'
           Replace = '[System.IO.File]::Copy($tmpPath, $Path, $true); $moved = "moved"' }
    )
}
