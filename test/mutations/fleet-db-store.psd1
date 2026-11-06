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
           Find = "if (!rooted) throw"
           Replace = "if (false) throw" }
        @{ Name = "driveless-home-accepted"
           Find = "process.platform === 'win32' ? /^"
           Replace = "process.platform === 'never' ? /^" }
        @{ Name = "failed-write-kept"
           Find = "if (db.isTransaction) db.exec('ROLLBACK');"
           Replace = "if (db.isTransaction) db.exec('COMMIT');" }
        @{ Name = "write-with-triggers-off"
           Find = "if (db.prepare('PRAGMA recursive_triggers').get().recursive_triggers !== 1) throw"
           Replace = "if (false) throw" }
        @{ Name = "no-wal"
           Find = "db.exec('PRAGMA journal_mode = WAL');"
           Replace = "" }
        @{ Name = "wal-lock-not-retried"
           Find = "if (!/database is locked/i.test(String(e && e.message)) || now() >= giveUp) throw e;"
           Replace = "throw e;" }
        @{ Name = "wal-any-error-retried"
           Find = "if (!/database is locked/i.test(String(e && e.message)) || now() >= giveUp) throw e;"
           Replace = "if (now() >= giveUp) throw e;" }
        @{ Name = "wal-wait-ignored"
           Find = "const giveUp = now() + Number(busyMs);"
           Replace = "const giveUp = now() + 5000;" }
        @{ Name = "replace-erases-history"
           Find = "db.exec('PRAGMA recursive_triggers = ON');"
           Replace = "db.exec('PRAGMA recursive_triggers = OFF');" }
        @{ Name = "stale-migration-rerun"
           Find = "user_version > v) { db.exec('COMMIT'); continue; }"
           Replace = "user_version > 99) { db.exec('COMMIT'); continue; }" }
        @{ Name = "missing-file-read-only-unexplained"
           Find = "if (readOnly && !fs.existsSync(file)) throw"
           Replace = "if (false) throw" }
    )
}
