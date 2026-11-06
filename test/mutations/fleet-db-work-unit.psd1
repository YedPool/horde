# Mutations of migration 6, the work_unit table (fleet-db/schema.mjs). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-work-unit.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
# The verb (fleet-db/work.mjs), its command line (work-cli.mjs) and the registry importer's kind have specs of
# their own: fleet-db-work.psd1, fleet-db-work-cli.psd1, fleet-db-import-kind.psd1.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "kind-not-checked"
           Find = 'kind TEXT NOT NULL CHECK (kind IN (${q(WORK_KINDS)})),'
           Replace = 'kind TEXT NOT NULL,' }
        @{ Name = "agent-may-lack-its-id"
           Find = 'CHECK (kind <> ''agent'' OR (agent_id IS NOT NULL AND session_id IS NULL)),'
           Replace = 'CHECK (kind <> ''agent'' OR session_id IS NULL),' }
        @{ Name = "agent-may-hold-a-session"
           Find = 'CHECK (kind <> ''agent'' OR (agent_id IS NOT NULL AND session_id IS NULL)),'
           Replace = 'CHECK (kind <> ''agent'' OR agent_id IS NOT NULL),' }
        @{ Name = "warg-may-hold-an-agent-type"
           Find = 'CHECK (kind <> ''warg'' OR (session_id IS NOT NULL AND agent_id IS NULL AND agent_type IS NULL)),'
           Replace = 'CHECK (kind <> ''warg'' OR (session_id IS NOT NULL AND agent_id IS NULL)),' }
        @{ Name = "warg-may-hold-an-agent-id"
           Find = 'CHECK (kind <> ''warg'' OR (session_id IS NOT NULL AND agent_id IS NULL AND agent_type IS NULL)),'
           Replace = 'CHECK (kind <> ''warg'' OR (session_id IS NOT NULL AND agent_type IS NULL)),' }
        @{ Name = "warg-may-lack-its-session"
           Find = 'CHECK (kind <> ''warg'' OR (session_id IS NOT NULL AND agent_id IS NULL AND agent_type IS NULL)),'
           Replace = 'CHECK (kind <> ''warg'' OR (agent_id IS NULL AND agent_type IS NULL)),' }
        @{ Name = "warg-may-be-its-own-parent"
           Find = 'CHECK (session_id IS NULL OR session_id <> parent_session_id),'
           Replace = 'CHECK (1),' }
        @{ Name = "task-and-flag-together"
           Find = 'CHECK ((task_id IS NOT NULL) <> (task_flag IS NOT NULL)),'
           Replace = 'CHECK ((task_id IS NOT NULL) OR (task_flag IS NOT NULL)),' }
        @{ Name = "neither-task-nor-flag"
           Find = 'CHECK ((task_id IS NOT NULL) <> (task_flag IS NOT NULL)),'
           Replace = 'CHECK (NOT (task_id IS NOT NULL AND task_flag IS NOT NULL)),' }
        @{ Name = "task-flag-not-checked"
           Find = 'task_flag TEXT CHECK (task_flag IN (${q(WORK_TASK_FLAGS)})),'
           Replace = 'task_flag TEXT,' }
        @{ Name = "work-type-not-checked"
           Find = 'work_type TEXT NOT NULL CHECK (work_type IN (${q(WORK_TYPES)})),'
           Replace = 'work_type TEXT NOT NULL,' }
        @{ Name = "outcome-not-checked"
           Find = 'outcome TEXT NOT NULL CHECK (outcome IN (${q(WORK_OUTCOMES)})),'
           Replace = 'outcome TEXT NOT NULL,' }
        @{ Name = "ended-without-an-end-time"
           Find = 'CHECK ((outcome = ''running'') = (ended_at IS NULL)),'
           Replace = 'CHECK (ended_at IS NULL OR outcome <> ''running''),' }
        @{ Name = "end-before-start"
           Find = 'CHECK (ended_at IS NULL OR ended_at >= started_at)'
           Replace = 'CHECK (1)' }
        @{ Name = "negative-start"
           Find = 'started_at INTEGER NOT NULL CHECK (started_at >= 0),'
           Replace = 'started_at INTEGER NOT NULL,' }
        @{ Name = "agent-id-twice-for-one-parent"
           Find = 'UNIQUE (parent_session_id, agent_id),'
           Replace = '' }
        @{ Name = "one-session-two-units"
           Find = 'UNIQUE (session_id),'
           Replace = '' }
        @{ Name = "agent-id-not-ascii"
           Find = ' AND agent_id NOT GLOB ''*[^!-~]*'''
           Replace = '' }
        @{ Name = "agent-id-too-long"
           Find = 'length(agent_id) BETWEEN 1 AND 200'
           Replace = 'length(agent_id) BETWEEN 1 AND 2000' }
        @{ Name = "agent-type-not-ascii"
           Find = ' AND agent_type NOT GLOB ''*[^!-~]*'''
           Replace = '' }
        @{ Name = "agent-type-too-long"
           Find = 'length(agent_type) BETWEEN 1 AND 80'
           Replace = 'length(agent_type) BETWEEN 1 AND 800' }
        @{ Name = "domain-may-be-empty"
           Find = 'CHECK (length(domain) BETWEEN 1 AND 120)'
           Replace = 'CHECK (length(domain) BETWEEN 0 AND 120)' }
        @{ Name = "model-too-long"
           Find = 'model TEXT CHECK (length(model) BETWEEN 1 AND 80),'
           Replace = 'model TEXT CHECK (length(model) BETWEEN 1 AND 800),' }
        @{ Name = "parent-not-a-session"
           Find = 'parent_session_id TEXT NOT NULL REFERENCES session (id),'
           Replace = 'parent_session_id TEXT NOT NULL,' }
        @{ Name = "identity-id-may-change"
           Find = 'WHEN NEW.id IS NOT OLD.id OR NEW.kind IS NOT OLD.kind OR NEW.parent_session_id'
           Replace = 'WHEN NEW.kind IS NOT OLD.kind OR NEW.parent_session_id' }
        @{ Name = "identity-kind-may-change"
           Find = ' OR NEW.kind IS NOT OLD.kind OR NEW.parent_session_id'
           Replace = ' OR NEW.parent_session_id' }
        @{ Name = "identity-parent-may-change"
           Find = ' OR NEW.parent_session_id IS NOT OLD.parent_session_id'
           Replace = '' }
        @{ Name = "identity-agent-id-may-change"
           Find = ' OR NEW.agent_id IS NOT OLD.agent_id'
           Replace = '' }
        @{ Name = "identity-session-may-change"
           Find = ' OR NEW.session_id IS NOT OLD.session_id'
           Replace = '' }
        @{ Name = "identity-start-may-change"
           Find = ' OR NEW.session_id IS NOT OLD.session_id OR NEW.started_at IS NOT OLD.started_at'
           Replace = ' OR NEW.session_id IS NOT OLD.session_id' }
        @{ Name = "ended-outcome-may-change"
           Find = 'WHEN OLD.outcome <> ''running'' AND (NEW.outcome IS NOT OLD.outcome OR NEW.ended_at IS NOT OLD.ended_at)'
           Replace = 'WHEN OLD.outcome <> ''running'' AND (NEW.ended_at IS NOT OLD.ended_at)' }
        @{ Name = "ended-end-time-may-change"
           Find = 'WHEN OLD.outcome <> ''running'' AND (NEW.outcome IS NOT OLD.outcome OR NEW.ended_at IS NOT OLD.ended_at)'
           Replace = 'WHEN OLD.outcome <> ''running'' AND (NEW.outcome IS NOT OLD.outcome)' }
        @{ Name = "ended-unit-may-run-again"
           Find = 'WHEN OLD.outcome <> ''running'' AND (NEW.outcome IS NOT OLD.outcome OR NEW.ended_at IS NOT OLD.ended_at)'
           Replace = 'WHEN OLD.outcome <> ''running'' AND NEW.outcome <> ''running'' AND (NEW.outcome IS NOT OLD.outcome OR NEW.ended_at IS NOT OLD.ended_at)' }
        @{ Name = "backfill-unit-may-take-a-task"
           Find = 'AND NOT (OLD.task_id IS NULL AND OLD.task_flag = ''no_task''))'
           Replace = 'AND NOT (OLD.task_id IS NULL))' }
        @{ Name = "set-task-may-change"
           Find = 'WHEN (NEW.task_id IS NOT OLD.task_id AND NOT'
           Replace = 'WHEN (OLD.task_id IS NULL AND NEW.task_id IS NOT OLD.task_id AND NOT' }
        @{ Name = "flag-may-be-swapped"
           Find = ' OR (NEW.task_id IS OLD.task_id AND NEW.task_flag IS NOT OLD.task_flag)'
           Replace = '' }
        @{ Name = "unit-may-be-deleted"
           Find = 'CREATE TRIGGER work_unit_no_delete BEFORE DELETE ON work_unit'
           Replace = 'CREATE TRIGGER work_unit_no_delete BEFORE DELETE ON work_unit WHEN 0' }
        @{ Name = "running-index-not-partial"
           Find = 'CREATE INDEX work_unit_running ON work_unit (outcome) WHERE outcome = ''running'';'
           Replace = 'CREATE INDEX work_unit_running ON work_unit (outcome);' }
        @{ Name = "orc-index-without-time"
           Find = 'CREATE INDEX work_unit_orc ON work_unit (orc_id, started_at);'
           Replace = 'CREATE INDEX work_unit_orc ON work_unit (orc_id);' }
        @{ Name = "task-index-missing"
           Find = 'CREATE INDEX work_unit_task ON work_unit (task_id);'
           Replace = '' }
    )
}
