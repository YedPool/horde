# Mutations of fleet.db's store (fleet-db/store.mjs): opening, migrating and handing out labels. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-store.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\store.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "label-off-by-one"
           Find = "RETURNING next - 1 AS n"
           Replace = "RETURNING next AS n" }
        @{ Name = "label-three-digits"
           Find = "String(row.n).padStart(4, '0')"
           Replace = "String(row.n).padStart(3, '0')" }
        @{ Name = "future-database-opened"
           Find = "if (have > SCHEMA_VERSION) {"
           Replace = "if (false) {" }
        @{ Name = "relative-home-resolved"
           Find = "if (!path.isAbsolute(h)) throw"
           Replace = "if (false) throw" }
        @{ Name = "failed-write-kept"
           Find = "if (db.isTransaction) db.exec('ROLLBACK');"
           Replace = "if (db.isTransaction) db.exec('COMMIT');" }
        @{ Name = "no-wal"
           Find = "db.exec('PRAGMA journal_mode = WAL');"
           Replace = "" }
    )
}
