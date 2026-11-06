# Mutations of the sessions step (fleet-db/sessions.mjs): the activity rules, the byte offset, liveness, and the rows. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-sessions.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/sessions.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\sessions.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        # ---- the activity rules
        @{ Name = "end-turn-does-not-close-the-turn"
           Find = 'out.inTurn = stop !== ''end_turn'' && !(stop === null && tools.length === 0);'
           Replace = 'out.inTurn = true;' }
        @{ Name = "text-only-answer-without-stop-reason-opens-a-turn"
           Find = 'out.inTurn = stop !== ''end_turn'' && !(stop === null && tools.length === 0);'
           Replace = 'out.inTurn = stop !== ''end_turn'';' }
        @{ Name = "meta-and-compaction-records-count"
           Find = 'if (r.isMeta || r.isCompactSummary) continue;'
           Replace = '' }
        @{ Name = "compaction-summary-opens-a-turn"
           Find = 'if (r.isMeta || r.isCompactSummary) continue;'
           Replace = 'if (r.isMeta) continue;' }
        @{ Name = "any-system-record-counts"
           Find = '} else if (r.type === ''system'' && TURN_END_SUBTYPES.includes(r.subtype)) {'
           Replace = '} else if (r.type === ''system'') {' }
        @{ Name = "ask-user-question-is-not-a-wait"
           Find = 'export const PERSON_TOOLS = [''ExitPlanMode'', ''AskUserQuestion''];'
           Replace = 'export const PERSON_TOOLS = [''ExitPlanMode''];' }
        @{ Name = "interrupt-does-not-close-the-turn"
           Find = 'out.inTurn = !isInterrupt(content);'
           Replace = 'out.inTurn = true;' }
        @{ Name = "slash-command-is-a-prompt"
           Find = 'if (r.type === ''user'' && typeof content === ''string'' && /^\s*(<command-name>|<local-command-)/.test(content)) continue;'
           Replace = '' }
        @{ Name = "subagent-activity-ignored"
           Find = 'if (res.act.inTurn === true && verdicts.get(e.id) !== ''dead'') {'
           Replace = 'if (false) {' }
        @{ Name = "subagent-time-is-the-file-time"
           Find = 'if (a !== null && (newest === null || a > newest)) newest = a;'
           Replace = 'newest = Math.max(newest ?? 0, f.mtime);' }
        # ---- the byte offset
        @{ Name = "offset-past-a-half-written-line"
           Find = 'return { act, offset: start + last + 1, bytes: n, status };'
           Replace = 'return { act, offset: start + n, bytes: n, status };' }
        @{ Name = "replaced-file-not-noticed"
           Find = 'if (offset !== null && size < offset) {'
           Replace = 'if (false) {' }
        @{ Name = "first-read-takes-the-whole-file"
           Find = 'const start = first ? Math.max(0, size - FIRST_READ_BYTES) : offset;'
           Replace = 'const start = first ? 0 : offset;' }
        @{ Name = "session-cap-ignored"
           Find = 'const want = Math.min(size - start, cap);'
           Replace = 'const want = size - start;' }
        @{ Name = "line-longer-than-any-read-waited-for-forever"
           Find = 'if (n >= lineMax) return { act, offset: start + n, bytes: n, status };'
           Replace = '' }
        @{ Name = "step-budget-ignored"
           Find = 'res = readTranscript(tp, prior, Math.min(sessionBytes, budget), sessionBytes);'
           Replace = 'res = readTranscript(tp, prior, sessionBytes, sessionBytes);' }
        # ---- liveness
        @{ Name = "unlistable-terminal-means-gone"
           Find = 'if (st === ''unknown'') pane = ''unknown'';'
           Replace = 'if (st === ''unknown'') pane = ''gone'';' }
        @{ Name = "unreadable-process-list-means-none-running"
           Find = 'const proc = snap.processes.known ? (snap.processes.running.has(e.id) ? ''alive'' : ''none'') : ''unknown'';'
           Replace = 'const proc = snap.processes.known ? (snap.processes.running.has(e.id) ? ''alive'' : ''none'') : ''none'';' }
        @{ Name = "terminal-the-list-does-not-name-is-unknown"
           Find = 'return k === undefined ? ''closed'' : k.state;'
           Replace = 'return k === undefined ? ''unknown'' : k.state;' }
        @{ Name = "oldest-record-owns-the-pane"
           Find = '(lastSeen.get(b) - lastSeen.get(a))'
           Replace = '(lastSeen.get(a) - lastSeen.get(b))' }
        @{ Name = "running-process-takes-the-pane"
           Find = 'const pool = [...ids].sort('
           Replace = 'const pool = [...(snap.processes.known && ids.some((id) => snap.processes.running.has(id)) ? ids.filter((id) => snap.processes.running.has(id)) : ids)].sort(' }
        @{ Name = "retired-record-claims-a-pane"
           Find = 'if (rec.retired === true) return null;'
           Replace = '' }
        @{ Name = "unknown-session-is-stamped-as-checked"
           Find = 'else { state = stateOf(v, res.act); counts[state]++; checked.push(e.id); }'
           Replace = 'else { state = stateOf(v, res.act); counts[state]++; } checked.push(e.id);' }
        # ---- the rows
        @{ Name = "every-row-written-every-tick"
           Find = 'if (row.some((x, i) => x !== was[i])) {'
           Replace = 'if (true) {' }
        @{ Name = "seat-reopened-every-tick"
           Find = 'if (rows.length === 1 && rows[0] === owner) continue;'
           Replace = '' }
        @{ Name = "gone-pane-not-closed"
           Find = '    closePane.run(now, p.id);'
           Replace = '' }
        @{ Name = "unlistable-terminal-panes-closed"
           Find = '    if (st === ''unknown'') continue;'
           Replace = '' }
        @{ Name = "snapshot-shape-unchecked"
           Find = 'if (!isObject(raw) || raw.v !== SNAPSHOT_VERSION) bad('
           Replace = 'if (false) bad(' }
    )
}
