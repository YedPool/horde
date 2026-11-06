# Mutations of migration 8 (fleet-db/schema.mjs): the job and signal tables, their CHECKs, indexes and triggers. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-schema-v8.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/jobs.test.mjs, "migration 8" and the schema rules). Every find string occurs once.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "job-id-any-text"
           Find = 'id TEXT NOT NULL PRIMARY KEY CHECK (length(id) BETWEEN 1 AND 120 AND id NOT GLOB ''*[^!-~]*''),'
           Replace = 'id TEXT NOT NULL PRIMARY KEY,' }
        @{ Name = "job-owner-any-text"
           Find = 'owner TEXT NOT NULL CHECK (length(owner) BETWEEN 1 AND 64 AND owner NOT GLOB ''*[^!-~]*''),'
           Replace = 'owner TEXT NOT NULL,' }
        @{ Name = "job-session-any-text"
           Find = 'session_id TEXT ${uuid(''session_id'')},'
           Replace = 'session_id TEXT,' }
        @{ Name = "job-text-any-length"
           Find = 'job TEXT NOT NULL CHECK (length(job) BETWEEN 1 AND 4000),'
           Replace = 'job TEXT NOT NULL,' }
        @{ Name = "job-negative-due"
           Find = 'due_at INTEGER CHECK (due_at >= 0),'
           Replace = 'due_at INTEGER,' }
        @{ Name = "job-proof-any-length"
           Find = 'done_proof TEXT CHECK (length(done_proof) BETWEEN 1 AND 4000),'
           Replace = 'done_proof TEXT,' }
        @{ Name = "job-maker-any-text"
           Find = 'created_by TEXT NOT NULL CHECK (length(created_by) BETWEEN 1 AND 64 AND created_by NOT GLOB ''*[^!-~]*''),'
           Replace = 'created_by TEXT NOT NULL,' }
        @{ Name = "job-closer-any-text"
           Find = 'done_by TEXT CHECK (length(done_by) BETWEEN 1 AND 64 AND done_by NOT GLOB ''*[^!-~]*''),'
           Replace = 'done_by TEXT,' }
        @{ Name = "job-closer-without-close"
           Find = 'CHECK ((done_at IS NULL) = (done_by IS NULL))'
           Replace = 'CHECK (1 = 1)' }
        @{ Name = "job-waiting-on-any-length"
           Find = 'waiting_on TEXT CHECK (length(waiting_on) BETWEEN 1 AND 4000),'
           Replace = 'waiting_on TEXT,' }
        @{ Name = "job-done-before-start"
           Find = 'CHECK (done_at IS NULL OR done_at >= started_at),'
           Replace = '' }
        @{ Name = "job-done-without-proof"
           Find = 'CHECK ((done_at IS NULL) = (done_proof IS NULL))'
           Replace = 'CHECK (1 = 1)' }
        @{ Name = "job-open-index-gone"
           Find = 'CREATE INDEX job_open_due ON job (due_at) WHERE done_at IS NULL;'
           Replace = '' }
        @{ Name = "job-start-may-move"
           Find = 'WHEN NEW.id IS NOT OLD.id OR NEW.started_at IS NOT OLD.started_at OR NEW.created_by IS NOT OLD.created_by'
           Replace = 'WHEN NEW.id IS NOT OLD.id OR NEW.created_by IS NOT OLD.created_by' }
        @{ Name = "job-maker-may-change"
           Find = 'WHEN NEW.id IS NOT OLD.id OR NEW.started_at IS NOT OLD.started_at OR NEW.created_by IS NOT OLD.created_by'
           Replace = 'WHEN NEW.id IS NOT OLD.id OR NEW.started_at IS NOT OLD.started_at' }
        @{ Name = "job-done-not-final"
           Find = 'BEGIN SELECT RAISE(ABORT, ''job: a done job is final''); END;'
           Replace = 'BEGIN SELECT 1; END;' }
        @{ Name = "signal-key-any-text"
           Find = 'key TEXT NOT NULL PRIMARY KEY CHECK (length(key) BETWEEN 1 AND 200 AND key NOT GLOB ''*[^!-~]*''),'
           Replace = 'key TEXT NOT NULL PRIMARY KEY,' }
        @{ Name = "signal-kind-any-text"
           Find = 'kind TEXT NOT NULL CHECK (length(kind) BETWEEN 1 AND 64 AND kind NOT GLOB ''*[^!-~]*''),'
           Replace = 'kind TEXT NOT NULL,' }
        @{ Name = "signal-owner-any-text"
           Find = 'owner TEXT CHECK (length(owner) BETWEEN 1 AND 64 AND owner NOT GLOB ''*[^!-~]*''),'
           Replace = 'owner TEXT,' }
        @{ Name = "signal-text-any-length"
           Find = 'text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 4000),'
           Replace = 'text TEXT NOT NULL,' }
        @{ Name = "signal-negative-first"
           Find = 'first_at INTEGER NOT NULL CHECK (first_at >= 0),'
           Replace = 'first_at INTEGER NOT NULL,' }
        @{ Name = "signal-count-zero"
           Find = 'count INTEGER NOT NULL CHECK (count >= 1),'
           Replace = 'count INTEGER NOT NULL,' }
        @{ Name = "signal-negative-wake"
           Find = 'woke_at INTEGER CHECK (woke_at >= 0),'
           Replace = 'woke_at INTEGER,' }
        @{ Name = "signal-negative-close"
           Find = 'closed_at INTEGER CHECK (closed_at >= 0),'
           Replace = 'closed_at INTEGER,' }
        @{ Name = "signal-closer-any-text"
           Find = 'closed_by TEXT CHECK (length(closed_by) BETWEEN 1 AND 64 AND closed_by NOT GLOB ''*[^!-~]*''),'
           Replace = 'closed_by TEXT,' }
        @{ Name = "signal-last-before-first"
           Find = 'CHECK (last_at >= first_at),'
           Replace = '' }
        @{ Name = "signal-closer-without-close"
           Find = 'CHECK ((closed_at IS NULL) = (closed_by IS NULL))'
           Replace = 'CHECK (1 = 1)' }
        @{ Name = "signal-open-index-gone"
           Find = 'CREATE INDEX signal_open_last ON signal (last_at) WHERE closed_at IS NULL;'
           Replace = '' }
        @{ Name = "signal-closed-index-gone"
           Find = 'CREATE INDEX signal_closed ON signal (closed_at) WHERE closed_at IS NOT NULL;'
           Replace = '' }
        @{ Name = "signal-first-may-move"
           Find = 'WHEN NEW.key IS NOT OLD.key OR NEW.kind IS NOT OLD.kind OR NEW.first_at IS NOT OLD.first_at'
           Replace = 'WHEN NEW.key IS NOT OLD.key OR NEW.kind IS NOT OLD.kind' }
        @{ Name = "signal-kind-may-change"
           Find = 'WHEN NEW.key IS NOT OLD.key OR NEW.kind IS NOT OLD.kind OR NEW.first_at IS NOT OLD.first_at'
           Replace = 'WHEN NEW.key IS NOT OLD.key OR NEW.first_at IS NOT OLD.first_at' }
        @{ Name = "signal-last-may-go-back"
           Find = 'WHEN NEW.last_at < OLD.last_at OR NEW.count < OLD.count'
           Replace = 'WHEN NEW.count < OLD.count' }
        @{ Name = "signal-count-may-go-back"
           Find = 'WHEN NEW.last_at < OLD.last_at OR NEW.count < OLD.count'
           Replace = 'WHEN NEW.last_at < OLD.last_at' }
    )
}
