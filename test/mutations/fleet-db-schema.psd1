# Mutations of fleet.db's schema and store (fleet-db/schema.mjs, fleet-db/store.mjs): each removes one rule
# the SSOT audit of 2026-10-19 asked for. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-schema.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "two-live-seats-allowed"
           Find = "WHERE retired_at IS NULL AND rank IN ('thrall', 'orc');"
           Replace = "WHERE retired_at IS NULL AND rank IN ('none');" }
        @{ Name = "one-seat-across-all-pcs"
           Find = 'CREATE UNIQUE INDEX session_one_live_seat ON session (orc_id, node_id)'
           Replace = 'CREATE UNIQUE INDEX session_one_live_seat ON session (orc_id)' }
        @{ Name = "founder-wait-needs-no-question"
           Find = "CHECK (on_kind <> 'founder' OR question_id IS NOT NULL OR backfill = 1),"
           Replace = "" }
        @{ Name = "question-needs-no-task"
           Find = 'CHECK (task_id IS NOT NULL OR backfill = 1),'
           Replace = '' }
        @{ Name = "changelog-needs-no-task"
           Find = 'CHECK (task_id IS NOT NULL OR fleet_wide = 1 OR backfill = 1),'
           Replace = '' }
        @{ Name = "history-can-be-edited"
           Find = "BEFORE UPDATE ON `${table} BEGIN SELECT RAISE(ABORT, '`${table} is append-only'); END;"
           Replace = "BEFORE UPDATE ON `${table} WHEN 0 BEGIN SELECT 1; END;" }
        @{ Name = "merged-pr-without-time"
           Find = "CHECK ((state = 'merged') = (merged_at IS NOT NULL))"
           Replace = "CHECK (1)" }
        @{ Name = "reopened-reads-closed"
           Find = "WHEN 'closed' THEN 'closed' WHEN 'acked' THEN 'closed' ELSE 'open' END AS state"
           Replace = "WHEN 'open' THEN 'open' ELSE 'closed' END AS state" }
        @{ Name = "tie-not-broken-by-id"
           Find = "ORDER BY e.at DESC, e.id DESC LIMIT 1) AS state,"
           Replace = "ORDER BY e.at DESC, e.id ASC LIMIT 1) AS state," }
        @{ Name = "second-thrall-allowed"
           Find = "CREATE UNIQUE INDEX orc_one_thrall ON orc (rank) WHERE rank = 'thrall' AND retired_at IS NULL;"
           Replace = "" }
        @{ Name = "retired-thrall-blocks-a-new-one"
           Find = "CREATE UNIQUE INDEX orc_one_thrall ON orc (rank) WHERE rank = 'thrall' AND retired_at IS NULL;"
           Replace = "CREATE UNIQUE INDEX orc_one_thrall ON orc (rank) WHERE rank = 'thrall';" }
        @{ Name = "answer-reopen-ignored"
           Find = "AND e.kind IN ('closed', 'reopened', 'acked') AND e.at <= a.at ORDER BY e.at DESC, e.id DESC LIMIT 1) IN ('closed', 'acked') THEN 0 ELSE 1 END AS open_at_arrival,"
           Replace = "AND e.kind IN ('closed', 'acked') AND e.at <= a.at ORDER BY e.at DESC, e.id DESC LIMIT 1) IN ('closed', 'acked') THEN 0 ELSE 1 END AS open_at_arrival," }
        @{ Name = "replaces-any-question"
           Find = "BEGIN SELECT RAISE(ABORT, 'an answer replaces an answer to the same question'); END;"
           Replace = "BEGIN SELECT 1; END;" }
        @{ Name = "negative-process-start"
           Find = "process_started_at INTEGER CHECK (process_started_at >= 0),"
           Replace = "process_started_at INTEGER," }
        @{ Name = "pid-without-start-time"
           Find = "CHECK ((pid IS NULL) = (process_started_at IS NULL))"
           Replace = "CHECK (1)" }
        @{ Name = "unsigned-passkey-answer-authorizes"
           Find = "WHEN a.signed_by IS NULL AND qn.needs_passkey = 1 THEN 0 ELSE 1 END AS authorizes"
           Replace = "ELSE 1 END AS authorizes" }
        @{ Name = "uuid-dashes-anywhere"
           Find = 'AND substr(${col}, 9, 1) = ''-'' AND substr(${col}, 14, 1) = ''-'''
           Replace = 'AND 1 = 1 AND 1 = 1' }
        @{ Name = "part-any-text"
           Find = "part TEXT CHECK (part GLOB '[A-Z]' AND length(part) = 1),"
           Replace = "part TEXT," }
        @{ Name = "taken-row-editable"
           Find = '${appendOnly(''answer_route_taken'')}'
           Replace = '' }
        @{ Name = "confirm-of-any-snapshot-allowed"
           Find = 'WHEN NEW.snapshot_id IS NOT (SELECT l.id FROM decisions_live l WHERE l.orc_id = NEW.orc_id)'
           Replace = 'WHEN 0' }
        @{ Name = "confirm-before-publish-allowed"
           Find = 'WHEN NEW.confirmed_at < (SELECT s.published_at'
           Replace = 'WHEN 0 AND NEW.confirmed_at < (SELECT s.published_at' }
        @{ Name = "confirm-editable"
           Find = '${appendOnly(''decisions_confirm'')}'
           Replace = '' }
        @{ Name = "confirmed-at-ignores-confirms"
           Find = 'max(published_at, COALESCE('
           Replace = 'min(published_at, COALESCE(' }
        @{ Name = "confirmed-at-off-by-one"
           Find = '), 0)) AS confirmed_at'
           Replace = '), 0) + 1) AS confirmed_at' }
        @{ Name = "live-view-loses-session"
           Find = 'SELECT id, orc_id, published_at, by_session_id, item_count, sha256,'
           Replace = 'SELECT id, orc_id, published_at, item_count, sha256,' }
        @{ Name = "confirm-same-time-twice"
           Find = 'UNIQUE (snapshot_id, confirmed_at)'
           Replace = 'CHECK (1)' }
    )
}
