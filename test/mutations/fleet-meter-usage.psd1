# Mutations of the fleet meter's live view and phone-message hops (fleet-metrics/store.mjs): the one-row-per-
# session key, the idle rule that closes a quiet session, the rule that an agent whose call returned is done
# (but not one still writing), the context window, and the hop table's guards. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-meter-usage.psd1
# test\test-fleet-meter.ps1 (the meter's node tests, on synthetic transcripts and a synthetic journal) must
# fail for every one. Every find string occurs once. NOT RUN when written (the machine was short of memory).
@{
    Target = "fleet-metrics\store.mjs"
    Suite  = "test\test-fleet-meter.ps1"
    Mutations = @(
        @{ Name = "usage-key-not-unique"
           Find = "    UNIQUE (session_id, agent_id)"
           Replace = "    CHECK (1)" }
        @{ Name = "usage-upsert-forgets-the-update"
           Find = "ON CONFLICT (session_id, agent_id) DO UPDATE SET updated_at = excluded.updated_at, at = excluded.at,"
           Replace = "ON CONFLICT (session_id, agent_id) DO UPDATE SET updated_at = excluded.updated_at, at = at," }
        @{ Name = "idle-never-closes-a-session"
           Find = "const done = (returned != null && seen <= returned) || now - seen > IDLE_DONE_MS;"
           Replace = "const done = (returned != null && seen <= returned);" }
        @{ Name = "returned-agent-never-done"
           Find = "const done = (returned != null && seen <= returned) || now - seen > IDLE_DONE_MS;"
           Replace = "const done = now - seen > IDLE_DONE_MS;" }
        @{ Name = "background-agent-done-at-its-first-result"
           Find = "const done = (returned != null && seen <= returned) || now - seen > IDLE_DONE_MS;"
           Replace = "const done = (returned != null) || now - seen > IDLE_DONE_MS;" }
        @{ Name = "start-moves-forward"
           Find = "let started = Math.min(mark ? mark.started_at : Infinity, old ? old.started_at : Infinity);"
           Replace = "let started = mark ? mark.started_at : old.started_at;" }
        @{ Name = "context-from-first-request"
           Find = "SELECT model, context_tokens FROM tokens_requests WHERE session_id = ? AND agent_id IS ? ORDER BY at DESC"
           Replace = "SELECT model, context_tokens FROM tokens_requests WHERE session_id = ? AND agent_id IS ? ORDER BY at ASC" }
        @{ Name = "cache-write-counts-5m-only"
           Find = "COALESCE(SUM(cache_write_5m + cache_write_1h), 0) AS cw"
           Replace = "COALESCE(SUM(cache_write_5m), 0) AS cw" }
        @{ Name = "hop-twice-for-one-message"
           Find = "    UNIQUE (message_id, hop)"
           Replace = "    CHECK (1)" }
        @{ Name = "hop-clock-unchecked"
           Find = "clock TEXT NOT NULL CHECK (clock IN (`${q(CLOCKS)}))"
           Replace = "clock TEXT NOT NULL" }
        @{ Name = "orc-id-guessed-not-from-the-registry"
           Find = "const orcId = this.orcIdOf(session);"
           Replace = "const orcId = session.slice(0, 1);" }
        @{ Name = "settle-closes-fresh-rows"
           Find = "settleUsage(now = Date.now()) { return Number(this.s.settle.run(now, now - IDLE_DONE_MS).changes); }"
           Replace = "settleUsage(now = Date.now()) { return Number(this.s.settle.run(now, now + IDLE_DONE_MS).changes); }" }
        @{ Name = "updated-at-not-bumped-by-an-upsert"
           Find = 'ON CONFLICT (session_id, agent_id) DO UPDATE SET updated_at = excluded.updated_at, at = excluded.at,'
           Replace = 'ON CONFLICT (session_id, agent_id) DO UPDATE SET at = excluded.at,' }
        @{ Name = "settle-leaves-updated-at"
           Find = 'SET state = ''done'', updated_at = ? WHERE'
           Replace = 'SET state = ''done'', updated_at = updated_at + 0 * ? WHERE' }
        @{ Name = "migration-does-not-re-read-the-version"
           Find = 'if (db.prepare(''PRAGMA user_version'').get().user_version <= v) {'
           Replace = 'if (true) {' }
        @{ Name = "first-row-starts-at-the-newest-chunk"
           Find = 'if (!old) { const f = s.usageFirst.get(session, ag);'
           Replace = 'if (false) { const f = s.usageFirst.get(session, ag);' }
        @{ Name = "hops-of-one-message-not-atomic"
           Find = 'for (const h of list) if (this.addHop(h)) n++;'
           Replace = 'for (const h of list) { if (this.addHop(h)) n++; this.db.exec(''COMMIT''); this.db.exec(''BEGIN IMMEDIATE''); }' }
        @{ Name = "latency-window-cuts-a-message-in-half"
           Find = 'WHERE message_id IN (SELECT message_id FROM mail_hops WHERE at >= ?)'
           Replace = 'WHERE at >= ? AND message_id IN (SELECT message_id FROM mail_hops)' }
    )
}
