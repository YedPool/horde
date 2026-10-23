# Mutations of the work-unit write verb (fleet-db/work.mjs): start, end and list. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-work.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\work.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "kind-not-checked"
           Find = 'if (!WORK_KINDS.includes(kind)) throw refuse(''kind must be agent or warg'');'
           Replace = 'if (false) throw refuse(''kind must be agent or warg'');' }
        @{ Name = "session-uuid-case-kept"
           Find = 'const s = typeof v === ''string'' ? v.toLowerCase() : '''';'
           Replace = 'const s = typeof v === ''string'' ? v : '''';' }
        @{ Name = "agent-id-trimmed"
           Find = 'function textOf(v, what, max, asciiOnly) {'
           Replace = 'function textOf(v, what, max, asciiOnly) { if (what === ''AgentId'' && typeof v === ''string'') v = v.trim();' }
        @{ Name = "agent-id-lower-cased"
           Find = 'function textOf(v, what, max, asciiOnly) {'
           Replace = 'function textOf(v, what, max, asciiOnly) { if (what === ''AgentId'' && typeof v === ''string'') v = v.toLowerCase();' }
        @{ Name = "agent-id-ascii-not-checked"
           Find = 'if (asciiOnly && /[^!-~]/.test(v)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "text-length-not-checked"
           Find = 'if (typeof v !== ''string'' || v.length < 1 || v.length > max) throw'
           Replace = 'if (typeof v !== ''string'') throw' }
        @{ Name = "warg-own-parent-allowed"
           Find = 'if (session === parent) throw refuse(''a warg is not its own parent'');'
           Replace = 'if (false) throw refuse(''a warg is not its own parent'');' }
        @{ Name = "agent-with-session-allowed"
           Find = 'if (req.session !== undefined && req.session !== null) throw refuse(''an agent has no session of its own'');'
           Replace = '' }
        @{ Name = "warg-with-agent-id-allowed"
           Find = 'if (req.agentId !== undefined && req.agentId !== null) throw refuse(''a warg has no AgentId'');'
           Replace = '' }
        @{ Name = "warg-with-agent-type-allowed"
           Find = 'if (req.agentType !== undefined && req.agentType !== null) throw refuse(''a warg has no AgentType'');'
           Replace = '' }
        @{ Name = "task-key-too-loose"
           Find = 'const TASK_KEY = /^T-\d{4,}$/;'
           Replace = 'const TASK_KEY = /^T-\d+$/;' }
        @{ Name = "work-type-not-checked"
           Find = 'if (!WORK_TYPES.includes(req.workType)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "start-repeat-not-recognised"
           Find = 'SELECT id FROM work_unit WHERE parent_session_id = ? AND agent_id = ?'
           Replace = 'SELECT id FROM work_unit WHERE parent_session_id = ? AND agent_id = ? AND 0' }
        @{ Name = "warg-of-another-parent-accepted"
           Find = 'if (kind === ''warg'' && find.parent_session_id !== parent) throw'
           Replace = 'if (false) throw' }
        @{ Name = "parent-stub-rank"
           Find = '"INSERT INTO session (id, node_id, rank, first_seen, last_seen) VALUES (?, ?, ''unknown'', ?, ?)"'
           Replace = '"INSERT INTO session (id, node_id, rank, first_seen, last_seen) VALUES (?, ?, ''warg'', ?, ?)"' }
        @{ Name = "warg-stub-without-orc"
           Find = '.run(session, nodeId, p.orc_id, parent, at, at);'
           Replace = '.run(session, nodeId, null, parent, at, at);' }
        @{ Name = "warg-stub-without-parent"
           Find = '.run(session, nodeId, p.orc_id, parent, at, at);'
           Replace = '.run(session, nodeId, p.orc_id, null, at, at);' }
        @{ Name = "warg-session-other-parent-accepted"
           Find = '} else if (w.parent_session_id !== null && w.parent_session_id !== parent) {'
           Replace = '} else if (false) {' }
        @{ Name = "unknown-task-not-warned"
           Find = 'else warnings.push(''warning: task '' + taskKey'
           Replace = 'else void (''warning: task '' + taskKey'
        }
        @{ Name = "unknown-task-refused"
           Find = 'if (t) taskId = t.id;'
           Replace = 'if (t) taskId = t.id; else throw refuse(''no such task'');' }
        @{ Name = "no-task-flagged-backfill"
           Find = 'taskId === null ? ''no_task'' : null'
           Replace = 'taskId === null ? ''backfill'' : null' }
        @{ Name = "unit-without-orc"
           Find = '.run(id, kind, parent, p.orc_id, agentId,'
           Replace = '.run(id, kind, parent, null, agentId,' }
        @{ Name = "start-time-ignored"
           Find = 'const at = timeOf(req.at ?? now(), ''At'');'
           Replace = 'const at = timeOf(now(), ''At'');' }
        @{ Name = "end-outcome-running-accepted"
           Find = '|| req.outcome === ''running'') throw'
           Replace = ') throw' }
        @{ Name = "end-names-two-ways"
           Find = 'if (byAgent === bySession) throw'
           Replace = 'if (false) throw' }
        @{ Name = "end-session-with-parent-accepted"
           Find = 'if (req.parentSession !== undefined && req.parentSession !== null) throw refuse(''a Session names the unit alone; drop ParentSession'');'
           Replace = '' }
        @{ Name = "end-of-unknown-unit-quiet"
           Find = 'if (!u) throw refuse(''no work unit was started for '''
           Replace = 'if (!u) return { action: ''already'', id: null, outcome: req.outcome }; if (false) throw refuse(''no work unit was started for '''
        }
        @{ Name = "end-with-other-outcome-quiet"
           Find = 'if (u.outcome === req.outcome) return {'
           Replace = 'if (true) return {' }
        @{ Name = "end-repeat-is-not-a-repeat"
           Find = 'if (u.outcome === req.outcome) return { action: ''already'''
           Replace = 'if (u.outcome === req.outcome) return { action: ''ended'''
        }
        @{ Name = "early-end-accepted"
           Find = 'if (at < u.started_at && explicit) throw'
           Replace = 'if (false) throw' }
        @{ Name = "early-clock-not-clamped"
           Find = 'const endedAt = Math.max(at, u.started_at);'
           Replace = 'const endedAt = at;' }
        @{ Name = "end-time-not-written"
           Find = 'UPDATE work_unit SET ended_at = ?, outcome = ? WHERE id = ?'').run(endedAt, req.outcome, u.id);'
           Replace = 'UPDATE work_unit SET ended_at = ?, outcome = ? WHERE id = ?'').run(u.started_at, req.outcome, u.id);' }
        @{ Name = "list-running-filter-dropped"
           Find = '(?2 = 0 OR w.outcome = ''running'')'
           Replace = '(1)' }
        @{ Name = "list-orc-filter-dropped"
           Find = '(?1 IS NULL OR w.orc_id = ?1)'
           Replace = '(1)' }
        @{ Name = "list-oldest-first"
           Find = 'ORDER BY w.started_at DESC, w.id DESC'
           Replace = 'ORDER BY w.started_at ASC, w.id ASC' }
        @{ Name = "list-unknown-orc-quiet"
           Find = 'if (!o) throw refuse(''no Orc is called '' + orc);'
           Replace = 'if (!o) return [];' }
        @{ Name = "list-orc-letter-only"
           Find = 'WHERE letter = ? OR lane_dir = ?'').get(orc, orc);'
           Replace = 'WHERE letter = ?'').get(orc);' }
    )
}
