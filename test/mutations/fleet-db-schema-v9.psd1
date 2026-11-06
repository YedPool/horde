# Mutations of migration 9 (fleet-db/schema.mjs): task_tree keeping every live task; task_now's mutants are in the v10 spec, since migration 10 replaces that view. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-schema-v9.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/glue.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
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
    )
}
