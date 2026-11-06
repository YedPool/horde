# Mutations of migration 10 (fleet-db/schema.mjs): task_event_extra, task_promise_open, and task_now by the ledger's own rule. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-schema-v10.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/task-state.test.mjs, task-extra.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "resumed-keeps-its-word"
           Find = "WHEN mv.kind IN ('resumed', 'reopened') THEN 'started'"
           Replace = "WHEN mv.kind IN ('reopened') THEN 'started'" }
        @{ Name = "reopened-keeps-its-word"
           Find = "WHEN mv.kind IN ('resumed', 'reopened') THEN 'started'"
           Replace = "WHEN mv.kind IN ('resumed') THEN 'started'" }
        @{ Name = "handed-keeps-its-word"
           Find = "WHEN mv.kind IS NOT NULL AND mv.kind <> 'handed' THEN mv.kind"
           Replace = "WHEN mv.kind IS NOT NULL THEN mv.kind" }
        @{ Name = "no-events-reads-opened"
           Find = "WHEN NOT EXISTS (SELECT 1 FROM task_event ev WHERE ev.task_id = t.id) THEN NULL"
           Replace = "" }
        @{ Name = "progress-never-begins-it"
           Find = "WHEN EXISTS (SELECT 1 FROM task_event pg WHERE pg.task_id = t.id AND pg.kind = 'progress'"
           Replace = "WHEN EXISTS (SELECT 1 FROM task_event pg WHERE 0 AND pg.task_id = t.id AND pg.kind = 'progress'" }
        @{ Name = "progress-before-a-hand-over-counts"
           Find = "AND (mv.id IS NULL OR pg.at > mv.at OR (pg.at = mv.at AND pg.id > mv.id))) THEN 'started'"
           Replace = ") THEN 'started'" }
        @{ Name = "same-time-progress-not-later"
           Find = "AND (mv.id IS NULL OR pg.at > mv.at OR (pg.at = mv.at AND pg.id > mv.id))) THEN 'started'"
           Replace = "AND (mv.id IS NULL OR pg.at > mv.at)) THEN 'started'" }
        @{ Name = "late-opened-takes-the-priority"
           Find = "ORDER BY ev.kind = 'opened', ev.at DESC, ev.id DESC LIMIT 1) AS prio,"
           Replace = "ORDER BY ev.at DESC, ev.id DESC LIMIT 1) AS prio," }
        @{ Name = "late-opened-takes-the-owner"
           Find = "ORDER BY ev.kind = 'opened', ev.at DESC, ev.id DESC LIMIT 1) END AS owner_orc_id,"
           Replace = "ORDER BY ev.at DESC, ev.id DESC LIMIT 1) END AS owner_orc_id," }
        @{ Name = "opened-line-moves-the-state"
           Find = "AND ev.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')"
           Replace = "AND ev.kind IN ('opened', 'started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')" }
        @{ Name = "priority-moves-the-state"
           Find = "AND ev.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')"
           Replace = "AND ev.kind IN ('priority', 'started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')" }
        @{ Name = "progress-moves-the-state"
           Find = "AND ev.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')"
           Replace = "AND ev.kind IN ('progress', 'started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')" }
        @{ Name = "same-time-state-goes-to-the-older"
           Find = "ORDER BY ev.at DESC, ev.id DESC LIMIT 1)"
           Replace = "ORDER BY ev.at DESC, ev.id ASC LIMIT 1)" }
        @{ Name = "state-oldest-first"
           Find = "ORDER BY ev.at DESC, ev.id DESC LIMIT 1)"
           Replace = "ORDER BY ev.at, ev.id LIMIT 1)" }
        @{ Name = "no-orc-hand-over-keeps-the-state"
           Find = "WHEN hx.id IS NOT NULL THEN 'opened'"
           Replace = "" }
        @{ Name = "progress-after-no-orc-hand-over-ignored"
           Find = "WHEN hx.id IS NOT NULL AND EXISTS (SELECT 1 FROM task_event qg WHERE qg.task_id = t.id AND qg.kind = 'progress'"
           Replace = "WHEN hx.id IS NOT NULL AND EXISTS (SELECT 1 FROM task_event qg WHERE 0 AND qg.task_id = t.id AND qg.kind = 'progress'" }
        @{ Name = "progress-before-no-orc-hand-over-counts"
           Find = "AND (qg.at > hx.at OR (qg.at = hx.at AND qg.id > hx.id))) THEN 'started'"
           Replace = ") THEN 'started'" }
        @{ Name = "old-no-orc-hand-over-beats-a-later-move"
           Find = "AND (mv.id IS NULL OR hx.at > mv.at OR (hx.at = mv.at AND hx.id > mv.id));"
           Replace = ";" }
        @{ Name = "oldest-no-orc-hand-over-read"
           Find = "ORDER BY y.at DESC, y.id DESC LIMIT 1)"
           Replace = "ORDER BY y.at, y.id LIMIT 1)" }
        @{ Name = "no-orc-hand-over-keeps-the-owner"
           Find = "CASE WHEN EXISTS (SELECT 1 FROM task_event_extra ox WHERE ox.task_id = t.id AND ox.kind = 'handed' AND ox.to_text IS NOT NULL"
           Replace = "CASE WHEN EXISTS (SELECT 1 FROM task_event_extra ox WHERE 0 AND ox.task_id = t.id AND ox.kind = 'handed' AND ox.to_text IS NOT NULL" }
        @{ Name = "hand-over-naming-nobody-clears-the-owner"
           Find = "ox.kind = 'handed' AND ox.to_text IS NOT NULL"
           Replace = "ox.kind = 'handed'" }
        @{ Name = "a-later-orc-hand-over-does-not-restore-the-owner"
           Find = "AND NOT EXISTS (SELECT 1 FROM task_event ol WHERE ol.task_id = t.id AND ol.kind = 'handed' AND (ol.at > ox.at OR (ol.at = ox.at AND ol.id > ox.id)))) THEN NULL"
           Replace = ") THEN NULL" }
        @{ Name = "kept-closes-nothing"
           Find = "w.closed + (l.kind = 'kept' AND w.closed < w.promised)"
           Replace = "w.closed" }
        @{ Name = "a-kept-is-saved-up-for-a-later-promise"
           Find = "w.closed + (l.kind = 'kept' AND w.closed < w.promised)"
           Replace = "w.closed + (l.kind = 'kept')" }
        @{ Name = "promises-not-counted-after-the-first-line"
           Find = "w.promised + (l.kind = 'promise'),"
           Replace = "w.promised," }
        @{ Name = "first-line-promise-not-counted"
           Find = "SELECT l.task_id, 1, l.kind = 'promise', 0 FROM line l WHERE l.n = 1"
           Replace = "SELECT l.task_id, 1, 0, 0 FROM line l WHERE l.n = 1" }
        @{ Name = "lines-walked-newest-first"
           Find = "row_number() OVER (PARTITION BY x.task_id ORDER BY x.at, x.id) AS n"
           Replace = "row_number() OVER (PARTITION BY x.task_id ORDER BY x.at DESC, x.id DESC) AS n" }
        @{ Name = "lines-of-one-time-by-the-newer-id"
           Find = "row_number() OVER (PARTITION BY x.task_id ORDER BY x.at, x.id) AS n"
           Replace = "row_number() OVER (PARTITION BY x.task_id ORDER BY x.at, x.id DESC) AS n" }
        @{ Name = "a-kept-closes-the-newest"
           Find = "row_number() OVER (PARTITION BY p.task_id ORDER BY p.at, p.id) AS i,"
           Replace = "row_number() OVER (PARTITION BY p.task_id ORDER BY p.at DESC, p.id DESC) AS i," }
        @{ Name = "promises-of-one-time-by-the-newer-id"
           Find = "row_number() OVER (PARTITION BY p.task_id ORDER BY p.at, p.id) AS i,"
           Replace = "row_number() OVER (PARTITION BY p.task_id ORDER BY p.at, p.id DESC) AS i," }
        @{ Name = "a-kept-on-another-task-closes-it"
           Find = "closed AS (SELECT task_id, max(closed) AS n FROM walk GROUP BY task_id),"
           Replace = "closed AS (SELECT p2.task_id AS task_id, (SELECT max(closed) FROM walk) AS n FROM task_event_extra p2 GROUP BY p2.task_id)," }
        @{ Name = "open-promises-list-other-lines"
           Find = "FROM task_event_extra p WHERE p.kind = 'promise'"
           Replace = "FROM task_event_extra p WHERE 1" }
        @{ Name = "later-promises-miscounted"
           Find = "p.total - p.i AS later_promises"
           Replace = "p.i AS later_promises" }
        @{ Name = "task-state-is-not-the-task"
           Find = "JOIN task_now s ON s.id = p.task_id"
           Replace = "JOIN task_now s ON 1" }
        @{ Name = "closed-ones-listed"
           Find = "WHERE p.i > c.n;"
           Replace = ";" }
        @{ Name = "named-still-listed"
           Find = "AND NOT EXISTS (SELECT 1 FROM named b WHERE b.task_id = p.task_id AND b.no = p.promise_no))"
           Replace = ")" }
        @{ Name = "named-still-takes-a-fallback-kept"
           Find = "OR (x.kind = 'promise' AND NOT EXISTS (SELECT 1 FROM named a WHERE a.task_id = x.task_id AND a.no = x.promise_no))),"
           Replace = "OR (x.kind = 'promise'))," }
        @{ Name = "naming-reaches-another-task-in-the-list"
           Find = "SELECT 1 FROM named b WHERE b.task_id = p.task_id AND b.no = p.promise_no"
           Replace = "SELECT 1 FROM named b WHERE b.no = p.promise_no" }
        @{ Name = "naming-reaches-another-task-in-the-walk"
           Find = "SELECT 1 FROM named a WHERE a.task_id = x.task_id AND a.no = x.promise_no"
           Replace = "SELECT 1 FROM named a WHERE a.no = x.promise_no" }
        @{ Name = "a-kept-that-names-is-also-a-fallback"
           Find = "WHERE (x.kind = 'kept' AND x.closes_no IS NULL)"
           Replace = "WHERE (x.kind = 'kept')" }
        @{ Name = "closes-ignored"
           Find = "SELECT c.task_id, c.closes_no FROM task_event_extra c WHERE c.closes_no IS NOT NULL"
           Replace = "SELECT c.task_id, c.closes_no FROM task_event_extra c WHERE 0" }
        @{ Name = "replaces-ignored"
           Find = "UNION SELECT r.task_id, r.replaces_no FROM task_event_extra r WHERE r.replaces_no IS NOT NULL),"
           Replace = "),"}
        @{ Name = "number-not-shown"
           Find = "s.state AS task_state, p.promise_no, p.at,"
           Replace = "s.state AS task_state, NULL AS promise_no, p.at," }
        @{ Name = "only-a-promise-has-a-number-not-checked"
           Find = "CHECK ((promise_no IS NOT NULL) = (kind = 'promise')),"
           Replace = "" }
        @{ Name = "only-a-promise-replaces-not-checked"
           Find = "CHECK (replaces_no IS NULL OR kind = 'promise'),"
           Replace = "" }
        @{ Name = "only-a-kept-closes-not-checked"
           Find = "CHECK (closes_no IS NULL OR kind = 'kept'),"
           Replace = "" }
        @{ Name = "number-zero-allowed"
           Find = "promise_no INTEGER CHECK (promise_no >= 1),"
           Replace = "promise_no INTEGER," }
        @{ Name = "closes-zero-allowed"
           Find = "closes_no INTEGER CHECK (closes_no >= 1),"
           Replace = "closes_no INTEGER," }
        @{ Name = "a-number-twice-on-a-task"
           Find = "CREATE UNIQUE INDEX task_event_extra_promise ON task_event_extra (task_id, promise_no) WHERE promise_no IS NOT NULL;"
           Replace = "" }
        @{ Name = "due-on-any-kind"
           Find = "CHECK (due_at IS NULL OR kind = 'promise'),"
           Replace = "" }
        @{ Name = "promise-with-no-due-written-by-hand"
           Find = "CHECK (kind <> 'promise' OR due_at IS NOT NULL OR backfill = 1),"
           Replace = "" }
        @{ Name = "to-text-on-any-kind"
           Find = "CHECK (to_text IS NULL OR kind = 'handed')"
           Replace = "CHECK (1)" }
        @{ Name = "other-kinds-allowed"
           Find = "kind TEXT NOT NULL CHECK (kind IN ('promise', 'kept', 'handed')),"
           Replace = "kind TEXT NOT NULL," }
        @{ Name = "extra-lines-can-change"
           Find = "  `${appendOnly('task_event_extra')}"
           Replace = "" }
    )
}
