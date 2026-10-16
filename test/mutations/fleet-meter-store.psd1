# Mutations of the fleet meter's store (fleet-metrics/store.mjs): idempotent upserts, the alert flag that
# must survive them, the offset that makes a rerun read nothing, and the schema's own guards. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-meter-store.psd1
# test\test-fleet-meter.ps1 (the meter's node tests, on synthetic transcripts) must fail for every one.
# Every find string occurs once.
@{
    Target = "fleet-metrics\store.mjs"
    Suite  = "test\test-fleet-meter.ps1"
    Mutations = @(
        @{ Name = "request-upsert-keeps-first-time"
           Find = 'ON CONFLICT (request_id) DO UPDATE SET at = excluded.at,'
           Replace = 'ON CONFLICT (request_id) DO UPDATE SET at = at,' }
        @{ Name = "request-key-not-unique"
           Find = 'request_id TEXT NOT NULL UNIQUE,'
           Replace = 'request_id TEXT NOT NULL,' }
        @{ Name = "limit-upsert-forgets-the-alert"
           Find = 'ON CONFLICT (hit_uuid) DO UPDATE SET orc = excluded.orc,'
           Replace = 'ON CONFLICT (hit_uuid) DO UPDATE SET alerted_at = NULL, orc = excluded.orc,' }
        @{ Name = "offset-never-saved"
           Find = 'if (offsetRec) s.setOff.run('
           Replace = 'if (false) s.setOff.run(' }
        @{ Name = "migration-version-not-advanced"
           Find = "db.exec('PRAGMA user_version = ' + (v + 1));"
           Replace = "db.exec('PRAGMA user_version = ' + v);" }
        @{ Name = "no-wal"
           Find = "db.exec('PRAGMA journal_mode = WAL');"
           Replace = '' }
        @{ Name = "no-busy-timeout"
           Find = "db.exec('PRAGMA busy_timeout = 5000');"
           Replace = '' }
        @{ Name = "future-database-accepted"
           Find = 'if (have > SCHEMA_VERSION) {'
           Replace = 'if (false) {' }
        @{ Name = "alert-flag-overwritten-by-a-second-alert"
           Find = 'WHERE hit_uuid = ? AND alerted_at IS NULL'
           Replace = 'WHERE hit_uuid = ?' }
        @{ Name = "silent-flag-not-stored"
           Find = 'markAlerted(hit, at, silently = false) { return this.s.alerted.run(at, silently ? 1 : 0, hit).changes === 1; }'
           Replace = 'markAlerted(hit, at, silently = false) { return this.s.alerted.run(at, 0, hit).changes === 1; }' }
    )
}
