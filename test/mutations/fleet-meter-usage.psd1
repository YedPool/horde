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
           Find = "ON CONFLICT (session_id, agent_id) DO UPDATE SET at = excluded.at, orc_id = excluded.orc_id, model = excluded.model,"
           Replace = "ON CONFLICT (session_id, agent_id) DO UPDATE SET at = at, orc_id = excluded.orc_id, model = excluded.model," }
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
           Find = "const started = Math.min(mark ? mark.started_at : Infinity, old ? old.started_at : Infinity);"
           Replace = "const started = mark ? mark.started_at : old.started_at;" }
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
           Find = "settleUsage(now = Date.now()) { return Number(this.s.settle.run(now - IDLE_DONE_MS).changes); }"
           Replace = "settleUsage(now = Date.now()) { return Number(this.s.settle.run(now + IDLE_DONE_MS).changes); }" }
    )
}
