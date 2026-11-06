# Mutations of the one allocator of T-numbers (fleet-db/label-cli.mjs). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-label-cli.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/label-cli.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\label-cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "task-rows-ignored"
           Find = 'Math.max(top, above) + 1'
           Replace = 'above + 1' }
        @{ Name = "counter-can-go-back"
           Find = 'SET next = max(next, ?)'
           Replace = 'SET next = ?' }
        @{ Name = "numbers-sorted-as-text"
           Find = 'max(CAST(substr(key, 3) AS INTEGER))'
           Replace = 'CAST(substr(max(key), 3) AS INTEGER)' }
        @{ Name = "above-not-checked"
           Find = "if (!/^\d{1,9}$/.test(argv[2])) { err('refused: --above is a whole number, 0 or more'); return 1; }"
           Replace = '' }
        @{ Name = "no-database-is-made"
           Find = "if (!fs.existsSync(file)) { err('fleet.db does not exist yet (run horde db init)'); return 4; }"
           Replace = '' }
        @{ Name = "migrates-an-older-database"
           Find = "openStore(file, { readOnly: true, busyMs }).close();"
           Replace = '' }
        @{ Name = "busy-is-not-its-own-exit"
           Find = "if (isBusy(e)) { err('fleet.db busy'); return 3; }"
           Replace = '' }
        @{ Name = "busy-wait-ignored"
           Find = 'db = openStore(file, { busyMs });'
           Replace = 'db = openStore(file);' }
        @{ Name = "not-under-the-write-lock"
           Find = 'out(inWrite(db, () => takeTaskNumber(db, Number(argv[2]))));'
           Replace = 'out(takeTaskNumber(db, Number(argv[2])));'
           Expect = "survives"
           Reason = "Numbers stay unique without the transaction: the raise and the take are each one atomic UPDATE, and the raise never lowers the counter. The transaction is kept for the one-write-path rule (inWrite checks recursive_triggers), which no test here can tell apart." }
        @{ Name = "no-home-is-not-its-own-exit"
           Find = 'return 2;'
           Replace = 'return 1;' }
    )
}
