# Mutations of fleet.db's migration 3 (fleet-db/schema.mjs): the entity registry, tags, links, people,
# Orc status, the per-turn check-in and the task tree. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-schema-v3.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "entity-not-made"
           Find = 'INSERT INTO entity (id, kind, created_at) VALUES (NEW.id'
           Replace = 'SELECT (NEW.id'
        }
        @{ Name = "entity-time-of-writing"
           Find = '${ENTITY_TABLES[table] ? ''NEW.'' + ENTITY_TABLES[table] : NOW_MS}'
           Replace = '${NOW_MS}' }
        @{ Name = "entity-not-touched"
           Find = 'UPDATE entity SET updated_at = ${NOW_MS} WHERE id = NEW.id;'
           Replace = 'SELECT 1;' }
        @{ Name = "entity-not-dropped"
           Find = 'BEGIN DELETE FROM entity WHERE id = OLD.id; END;'
           Replace = 'BEGIN SELECT 1; END;' }
        @{ Name = "id-may-change"
           Find = 'BEGIN SELECT RAISE(ABORT, ''${table}: an id never changes''); END;'
           Replace = 'BEGIN SELECT 1; END;' }
        @{ Name = "entity-removable-under-object"
           Find = 'BEGIN SELECT RAISE(ABORT, ''entity: its ${table} row is still there''); END;'
           Replace = 'BEGIN SELECT 1; END;' }
        @{ Name = "entity-without-object"
           Find = 'BEGIN SELECT RAISE(ABORT, ''entity: no ${table} row has this id''); END;'
           Replace = 'BEGIN SELECT 1; END;' }
        @{ Name = "task-loop-allowed"
           Find = 'BEGIN SELECT RAISE(ABORT, ''task: it cannot sit under its own subtask''); END;'
           Replace = 'BEGIN SELECT 1; END;' }
        @{ Name = "task-loop-one-step-only"
           Find = 'SELECT NEW.parent_id UNION SELECT p.parent_id FROM task p JOIN up ON p.id = up.x WHERE p.parent_id IS NOT NULL'
           Replace = 'SELECT NEW.parent_id'
        }
        @{ Name = "entity-kind-editable"
           Find = 'WHEN NEW.id IS NOT OLD.id OR NEW.kind IS NOT OLD.kind OR NEW.created_at IS NOT OLD.created_at'
           Replace = 'WHEN NEW.id IS NOT OLD.id' }
        @{ Name = "no-backfill"
           Find = '${ENTITY_KINDS.map(entityBackfill).join(''\n  '')}'
           Replace = '' }
        @{ Name = "backfill-time-of-writing"
           Find = 'SELECT id, ''${table}'', ${ENTITY_TABLES[table] ?? NOW_MS} FROM ${table};'
           Replace = 'SELECT id, ''${table}'', ${NOW_MS} FROM ${table};' }
        @{ Name = "entity-any-kind"
           Find = 'kind TEXT NOT NULL CHECK (kind IN (${q(ENTITY_KINDS)})),'
           Replace = 'kind TEXT NOT NULL,' }
        @{ Name = "entity-made-by-itself"
           Find = 'CHECK (created_by_id IS NULL OR created_by_id <> id)'
           Replace = 'CHECK (1)' }
        @{ Name = "two-founders"
           Find = 'CREATE UNIQUE INDEX person_one_founder'
           Replace = 'CREATE INDEX person_one_founder' }
        @{ Name = "handle-any-case"
           Find = 'AND handle NOT GLOB ''*[^a-z0-9._-]*'')'
           Replace = ')' }
        @{ Name = "tag-any-case"
           Find = 'AND name NOT GLOB ''*[^a-z0-9:._-]*'')'
           Replace = ')' }
        @{ Name = "link-any-relation"
           Find = 'relation TEXT NOT NULL CHECK (relation IN (${q(LINK_RELATIONS)})),'
           Replace = 'relation TEXT NOT NULL,' }
        @{ Name = "link-to-itself"
           Find = 'CHECK (subject_id <> object_id),'
           Replace = 'CHECK (1),' }
        @{ Name = "link-live-twice"
           Find = 'CREATE UNIQUE INDEX link_one_live'
           Replace = 'CREATE INDEX link_one_live' }
        @{ Name = "link-unique-forever"
           Find = 'ON link (subject_id, relation, object_id) WHERE retired_at IS NULL;'
           Replace = 'ON link (subject_id, relation, object_id);' }
        @{ Name = "link-retired-before-made"
           Find = 'CHECK (retired_at IS NULL OR retired_at >= at)'
           Replace = 'CHECK (1)' }
        @{ Name = "status-too-long"
           Find = 'doing TEXT NOT NULL CHECK (length(doing) BETWEEN 1 AND 120),'
           Replace = 'doing TEXT NOT NULL CHECK (length(doing) BETWEEN 1 AND 121),' }
        @{ Name = "status-editable"
           Find = '  ${appendOnly(''orc_status'')}'
           Replace = '' }
        @{ Name = "checkin-editable"
           Find = '  ${appendOnly(''task_checkin'')}'
           Replace = '' }
        @{ Name = "status-now-oldest"
           Find = 'PARTITION BY st.orc_id ORDER BY st.at DESC, st.id DESC) AS rn FROM orc_status st)'
           Replace = 'PARTITION BY st.orc_id ORDER BY st.at ASC, st.id DESC) AS rn FROM orc_status st)' }
        @{ Name = "tree-keeps-done"
           Find = 'WHERE n.state IS NULL OR n.state NOT IN (''done'', ''verified'', ''dropped'', ''superseded'')),'
           Replace = 'WHERE 1),' }
        @{ Name = "tree-ignores-priority"
           Find = 'ORDER BY prio IS NULL, prio, position IS NULL, position, created_at, id) AS n'
           Replace = 'ORDER BY position IS NULL, position, created_at, id) AS n' }
        @{ Name = "tree-ignores-position"
           Find = 'PARTITION BY parent_id ORDER BY position IS NULL, position, created_at, id) AS n'
           Replace = 'PARTITION BY parent_id ORDER BY created_at, id) AS n' }
        @{ Name = "tree-one-list"
           Find = 'row_number() OVER (PARTITION BY owner_orc_id ORDER BY'
           Replace = 'row_number() OVER (ORDER BY' }
        @{ Name = "tree-sorts-as-text"
           Find = 'tree.sort || ''.'' || printf(''%06d'', sib.n)'
           Replace = 'tree.sort || ''.'' || sib.n' }
    )
}
