# The mutation of files/Key.ps1 that racing processes must see. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\files-key-race.psd1
# test\test-files-race.ps1 must fail for it.
#
# IT IS THE SUITE'S OWN CONTROL, RUN AS A MUTANT: a key put in place by a copy that replaces. Four
# processes make the first share of each of six new homes, in an order the worker stages
# (test\fixtures\files\race-worker.ps1 says why it is staged and not left to the machine): with this
# mutant each racer after the first replaces the key and reads its own, so racers of one round are
# told different ids for one path. The same mutant is caught without any race by
# test\mutations\files-key.psd1.
@{
    Target = "files\Key.ps1"
    Suite  = "test\test-files-race.ps1"
    Mutations = @(
        @{ Name = "key-move-replaces-the-key-that-is-there"
           Find = '$moved = Move-HordeFileNewDurable -From $tmpPath -To $Path'
           Replace = '[System.IO.File]::Copy($tmpPath, $Path, $true); $moved = "moved"' }
    )
}
