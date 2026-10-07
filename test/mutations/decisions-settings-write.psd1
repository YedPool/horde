# Mutations of decisions/settings.json, the defaults a WRITE to the decisions list runs on. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-settings-write.psd1
# Each changes one default; test\test-decisions-operations.ps1 must fail for every one.
#
# THE FIRST MUTANT IS SLOW ON PURPOSE: with it a write waits ten times as long on a held record, about
# 100 s, and the suite holds a record open to see exactly that. It was measured in
# test\mutations\decisions-operations.psd1, where this default lived before it was a setting.
@{
    Target = "decisions\settings.json"
    Suite  = "test\test-decisions-operations.ps1"
    Mutations = @(
        @{ Name = "held-record-waited-for-ten-times-as-long"
           Find = '"decisions.write.heldReads": { "default": 5,'
           Replace = '"decisions.write.heldReads": { "default": 50,' }
        @{ Name = "held-record-not-waited-for-by-a-write"
           Find = '"decisions.write.heldReads": { "default": 5,'
           Replace = '"decisions.write.heldReads": { "default": 1,' }
        @{ Name = "one-try-only"
           Find = '"decisions.write.raceTries": { "default": 200,'
           Replace = '"decisions.write.raceTries": { "default": 1,' }
    )
}
