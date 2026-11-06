# Mutations of migration 9 (fleet-db/schema.mjs): task_now by the ledger's own rule. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-schema-v9.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/task-state.test.mjs). Every find string occurs once.
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
           Find = "WHERE e.task_id = t.id AND e.kind IN ('opened', 'priority')`r`n"
           Replace = "WHERE e.task_id = t.id AND e.kind IN ('priority')`r`n" }
        @{ Name = "opened-line-moves-the-state"
           Find = "AND e.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')"
           Replace = "AND e.kind IN ('opened', 'started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')" }
        @{ Name = "priority-moves-the-state"
           Find = "AND e.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')"
           Replace = "AND e.kind IN ('priority', 'started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')" }
        @{ Name = "progress-moves-the-state"
           Find = "AND e.kind IN ('started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')"
           Replace = "AND e.kind IN ('progress', 'started', 'waiting', 'resumed', 'handed', 'done', 'verified', 'reopened', 'dropped', 'superseded')" }
        @{ Name = "state-oldest-first"
           Find = "'dropped', 'superseded')`r`n    ORDER BY e.at DESC, e.id DESC LIMIT 1);"
           Replace = "'dropped', 'superseded')`r`n    ORDER BY e.at, e.id LIMIT 1);" }
    )
}
