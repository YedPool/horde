# Mutations of the job and signal rules (fleet-db/jobs.mjs): validation, idempotence, the reopen rule, the wake marks, the prune. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-jobs.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/jobs.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\jobs.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "word-takes-a-space-or-non-ascii"
           Find = 'const bad = /[^!-~]/.exec(v);'
           Replace = 'const bad = null;' }
        @{ Name = "word-length-not-checked"
           Find = 'if (v.length > max) throw refuse(what + '' is '' + v.length + '' characters; the most is '' + max);'
           Replace = 'if (false) throw refuse(what + '' is '' + v.length + '' characters; the most is '' + max);' }
        @{ Name = "text-takes-non-ascii"
           Find = 'const bad = /[^\x20-\x7E\n\t]/.exec(t);'
           Replace = 'const bad = null;' }
        @{ Name = "text-keeps-its-byte-order-mark"
           Find = '(v.charCodeAt(0) === 0xFEFF ? v.slice(1) : v)'
           Replace = 'v' }
        @{ Name = "text-keeps-crlf"
           Find = '.replace(/\r\n?/g, ''\n'')'
           Replace = '' }
        @{ Name = "text-keeps-trailing-white-space"
           Find = '.replace(/\s+$/, '''')'
           Replace = '' }
        @{ Name = "text-length-not-checked"
           Find = 'if (t.length > max) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "zone-less-time-accepted"
           Find = 'if (/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/.test(t)) throw refuse(what + '' has no time zone'
           Replace = 'if (false) throw refuse(what + '' has no time zone' }
        @{ Name = "short-number-taken-as-milliseconds"
           Find = 'if (!/^\d{13,15}$/.test(v)) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "time-before-2001-accepted"
           Find = 'if (ms < 1e12) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "rolled-date-accepted"
           Find = ') throw refuse(what + '' is not a real time'');'
           Replace = ') { /* mutant */ }' }
        @{ Name = "impossible-offset-accepted"
           Find = 'if (oh > 23 || om > 59) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "time-far-ahead-accepted"
           Find = 'if (ahead && ms > now + MAX_AHEAD_MS) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "session-any-text"
           Find = 'if (!UUID.test(s)) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "repeat-upsert-not-kept"
           Find = 'if (changed.length === 0) return { action: ''kept'', changed };'
           Replace = 'if (false) return { action: ''kept'', changed };' }
        @{ Name = "session-change-not-seen"
           Find = 'if (session !== null && session !== row.session_id) changed.push(''session'');'
           Replace = '' }
        @{ Name = "due-change-not-seen"
           Find = 'if (due !== null && due !== row.due_at) changed.push(''due'');'
           Replace = '' }
        @{ Name = "upsert-on-done-job-allowed"
           Find = 'if (row.done_at !== null) throw refuse(''job '' + id + '' is done; a new piece of work takes a new id'');'
           Replace = '' }
        @{ Name = "done-with-another-proof-kept"
           Find = 'if (row.done_proof === proof) return { action: ''kept'', doneAt: row.done_at };'
           Replace = 'return { action: ''kept'', doneAt: row.done_at };' }
        @{ Name = "waiting-on-and-not-waiting-both-accepted"
           Find = 'if (notWaiting && given(req.waitingOn)) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "not-waiting-does-not-clear"
           Find = 'const newWaiting = notWaiting ? null : (waiting ?? row.waiting_on);'
           Replace = 'const newWaiting = waiting ?? row.waiting_on;' }
        @{ Name = "omitted-waiting-on-clears-it"
           Find = 'const newWaiting = notWaiting ? null : (waiting ?? row.waiting_on);'
           Replace = 'const newWaiting = waiting;' }
        @{ Name = "waiting-change-not-seen"
           Find = 'if (newWaiting !== row.waiting_on) changed.push(''waiting_on'');'
           Replace = '' }
        @{ Name = "not-waiting-filter-ignored"
           Find = 'AND (?5 = 0 OR waiting_on IS NULL)'
           Replace = 'AND (?5 = 0 OR 1)' }
        @{ Name = "not-waiting-filter-only-open"
           Find = 'AND (?5 = 0 OR waiting_on IS NULL)'
           Replace = 'AND (?5 = 0 OR (waiting_on IS NULL AND done_at IS NULL))' }
        @{ Name = "done-by-not-stored"
           Find = 'UPDATE job SET done_at = ?, done_proof = ?, done_by = ? WHERE id = ?'').run(doneAt, proof, by, id);'
           Replace = 'UPDATE job SET done_at = ?, done_proof = ?, done_by = ? WHERE id = ?'').run(doneAt, proof, ''X'', id);' }
        @{ Name = "done-before-start-accepted"
           Find = 'if (explicit && at < row.started_at) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "done-time-not-lifted-to-start"
           Find = 'const doneAt = Math.max(at, row.started_at);'
           Replace = 'const doneAt = at;' }
        @{ Name = "overdue-includes-done-jobs"
           Find = '(done_at IS NULL AND due_at IS NOT NULL AND due_at < ?4)'
           Replace = '(due_at IS NOT NULL AND due_at < ?4)' }
        @{ Name = "open-filter-ignored"
           Find = '(?1 = 0 OR done_at IS NULL)'
           Replace = '(?1 = 0 OR 1)' }
        @{ Name = "retry-of-a-raise-counts-twice"
           Find = 'if (at <= row.last_at) return { action: ''kept'', count: row.count };'
           Replace = 'if (at < row.last_at) return { action: ''kept'', count: row.count };' }
        @{ Name = "older-raise-moves-last-at-back"
           Find = 'if (at <= row.last_at) return { action: ''kept'', count: row.count };'
           Replace = '' }
        @{ Name = "reopen-keeps-it-closed"
           Find = ', closed_at = NULL, closed_by = NULL WHERE key = ?'
           Replace = ' WHERE key = ?' }
        @{ Name = "reopen-not-told"
           Find = 'action: row.closed_at === null ? ''updated'' : ''reopened'''
           Replace = 'action: ''updated''' }
        @{ Name = "key-of-another-kind-merged"
           Find = 'if (row.kind !== kind) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "raise-without-owner-clears-it"
           Find = '.run(at, text, owner ?? row.owner, key);'
           Replace = '.run(at, text, owner, key);' }
        @{ Name = "raise-owner-never-changes"
           Find = '.run(at, text, owner ?? row.owner, key);'
           Replace = '.run(at, text, row.owner, key);' }
        @{ Name = "close-before-last-at"
           Find = 'Math.max(clock, row.last_at), by, key)'
           Replace = 'clock, by, key)' }
        @{ Name = "second-close-overwrites"
           Find = 'if (row.closed_at !== null) return { action: ''kept'' };'
           Replace = '' }
        @{ Name = "mark-woke-without-open"
           Find = 'if (markWoke && !open) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "at-without-mark-woke"
           Find = 'if (at !== null && !markWoke) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "unwoken-ignores-a-later-happening"
           Find = '(woke_at IS NULL OR woke_at < last_at)'
           Replace = '(woke_at IS NULL)' }
        @{ Name = "mark-not-written"
           Find = 'for (const r of got) { mark.run(wokeAt, r.key); r.woke_at = wokeAt; }'
           Replace = 'for (const r of got) { r.woke_at = wokeAt; }' }
        @{ Name = "mark-written-outside-the-listing-filter"
           Find = 'const mark = db.prepare(''UPDATE signal SET woke_at = ? WHERE key = ?'');'
           Replace = 'const mark = db.prepare(''UPDATE signal SET woke_at = ? WHERE key = ? OR 1'');' }
        @{ Name = "prune-takes-zero-days"
           Find = '|| Number(d) < 1)'
           Replace = '|| Number(d) < 0)' }
        @{ Name = "prune-without-days-defaults"
           Find = 'if (d === undefined || d === null || '
           Replace = 'if (false && ' }
        @{ Name = "prune-deletes-open-signals"
           Find = 'DELETE FROM signal WHERE closed_at IS NOT NULL AND closed_at < ?'
           Replace = 'DELETE FROM signal WHERE (closed_at IS NULL OR closed_at < ?)' }
        @{ Name = "prune-takes-the-edge"
           Find = 'AND closed_at < ?'').run(cutoff)'
           Replace = 'AND closed_at <= ?'').run(cutoff)' }
    )
}
