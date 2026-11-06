# Mutations of migration 9 (fleet-db/schema.mjs): task_now by the ledger's own rule, and task_tree keeping every live task. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-schema-v9.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/task-state.test.mjs, glue.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "resumed-keeps-its-word"
           Find = "WHEN m.kind IN ('resumed', 'reopened') THEN 'started'"
           Replace = "WHEN m.kind IN ('reopened') THEN 'started'" }
        @{ Name = "reopened-keeps-its-word"
           Find = "WHEN m.kind IN ('resumed', 'reopened') THEN 'started'"
           Replace = "WHEN m.kind IN ('resumed') THEN 'started'" }
        @{ Name = "handed-keeps-its-word"
           Find = "WHEN m.kind IS NOT NULL AND m.kind <> 'handed' THEN m.kind"
           Replace = "WHEN m.kind IS NOT NULL THEN m.kind" }
        @{ Name = "no-events-reads-opened"
           Find = "WHEN NOT EXISTS (SELECT 1 FROM task_event e WHERE e.task_id = t.id) THEN NULL"
           Replace = "" }
        @{ Name = "progress-never-begins-it"
           Find = "WHEN EXISTS (SELECT 1 FROM task_event p WHERE p.task_id = t.id AND p.kind = 'progress'"
           Replace = "WHEN EXISTS (SELECT 1 FROM task_event p WHERE 0 AND p.task_id = t.id AND p.kind = 'progress'" }
        @{ Name = "progress-before-a-hand-over-counts"
           Find = "AND (m.id IS NULL OR p.at > m.at OR (p.at = m.at AND p.id > m.id))) THEN 'started'"
           Replace = ") THEN 'started'" }
        @{ Name = "same-time-progress-not-later"
           Find = "AND (m.id IS NULL OR p.at > m.at OR (p.at = m.at AND p.id > m.id))) THEN 'started'"
           Replace = "AND (m.id IS NULL OR p.at > m.at)) THEN 'started'" }
        @{ Name = "late-opened-takes-the-priority"
           Find = "ORDER BY e.kind = 'opened', e.at DESC, e.id DESC LIMIT 1) AS prio,"
           Replace = "ORDER BY e.at DESC, e.id DESC LIMIT 1) AS prio," }
        @{ Name = "late-opened-takes-the-owner"
           Find = "ORDER BY e.kind = 'opened', e.at DESC, e.id DESC LIMIT 1) AS owner_orc_id,"
           Replace = "ORDER BY e.at DESC, e.id DESC LIMIT 1) AS owner_orc_id," }
        @{ Name = "opened-line-moves-the-state"
           Find = "AND e.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')"
           Replace = "AND e.kind IN ('opened', 'started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')" }
        @{ Name = "priority-moves-the-state"
           Find = "AND e.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')"
           Replace = "AND e.kind IN ('priority', 'started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')" }
        @{ Name = "progress-moves-the-state"
           Find = "AND e.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')"
           Replace = "AND e.kind IN ('progress', 'started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')" }
        @{ Name = "same-time-state-goes-to-the-older"
           Find = "ORDER BY e.at DESC, e.id DESC LIMIT 1);"
           Replace = "ORDER BY e.at DESC, e.id ASC LIMIT 1);" }
        @{ Name = "closed-parent-hides-its-live-subtasks"
           Find = "FROM live x WHERE x.parent_id IS NULL OR x.parent_id NOT IN (SELECT id FROM live)),"
           Replace = "FROM live x WHERE x.parent_id IS NULL)," }
        @{ Name = "every-subtask-also-tops-the-list"
           Find = "FROM live x WHERE x.parent_id IS NULL OR x.parent_id NOT IN (SELECT id FROM live)),"
           Replace = "FROM live x)," }
        @{ Name = "tree-keeps-done"
           Find = "WHERE n.state NOT IN ('done', 'verified', 'dropped', 'superseded') OR n.state IS NULL),"
           Replace = "WHERE 1)," }
        @{ Name = "tree-ignores-priority"
           Find = "ORDER BY x.prio IS NULL, x.prio, x.position IS NULL, x.position, x.created_at, x.id) AS n"
           Replace = "ORDER BY x.position IS NULL, x.position, x.created_at, x.id) AS n" }
        @{ Name = "tree-ignores-position"
           Find = "PARTITION BY x.parent_id ORDER BY x.position IS NULL, x.position, x.created_at, x.id) AS n"
           Replace = "PARTITION BY x.parent_id ORDER BY x.created_at, x.id) AS n" }
        @{ Name = "tree-one-list"
           Find = "row_number() OVER (PARTITION BY x.owner_orc_id ORDER BY"
           Replace = "row_number() OVER (ORDER BY" }
        @{ Name = "tree-sorts-as-text"
           Find = "tree.sort || '.' || printf('%06d', s.n)"
           Replace = "tree.sort || '.' || s.n" }
        @{ Name = "state-oldest-first"
           Find = "ORDER BY e.at DESC, e.id DESC LIMIT 1);"
           Replace = "ORDER BY e.at, e.id LIMIT 1);" }
    )
}
