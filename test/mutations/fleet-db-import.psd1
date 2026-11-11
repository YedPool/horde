# Mutations of the fleet.db importer (fleet-db/import.mjs). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-import.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\import.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "events-in-file-order"
           Find = 'events.sort((a, b) => a.at - b.at || a.n - b.n);'
           Replace = 'events.sort((a, b) => a.n - b.n);' }
        @{ Name = "offset-ignored"
           Find = 'return ms + frac - offsetMin * 60000;'
           Replace = 'return ms + frac;' }
        @{ Name = "us-locale-day-month-swapped"
           Find = 'parts = [m[3], m[1], m[2], m[4], m[5], m[6]].map(Number);'
           Replace = 'parts = [m[3], m[2], m[1], m[4], m[5], m[6]].map(Number);' }
        @{ Name = "bom-not-stripped"
           Find = '? buf.subarray(3) : buf;'
           Replace = '? buf : buf;' }
        @{ Name = "card-crlf-not-read"
           Find = 'const lines = buf.toString(''latin1'').split(/\r?\n/);'
           Replace = 'const lines = buf.toString(''latin1'').split(''\n'');' }
        @{ Name = "invalid-card-letter-accepted"
           Find = 'if (!/^[A-Z]$/.test(card.orc)) return'
           Replace = 'if (!/^[A-Z]\d?$/.test(card.orc)) return' }
        @{ Name = "lane-folder-not-mapped"
           Find = 'ctx.byLetter.get(name) ?? ctx.byDir.get(name) ?? null'
           Replace = 'ctx.byLetter.get(name) ?? null' }
        @{ Name = "blocked-no-is-case-sensitive"
           Find = 'const blocked = /^no$/i.test(c.blocked)'
           Replace = 'const blocked = /^no$/.test(c.blocked)' }
        @{ Name = "blocked-none-is-not-blocked"
           Find = 'const blocked = /^no$/i.test(c.blocked)'
           Replace = 'const blocked = /^no(ne)?$/i.test(c.blocked)' }
        @{ Name = "thrall-role-not-read"
           Find = 'if (rec.role === ''master'') return ''thrall'';'
           Replace = 'if (rec.role === ''master'') return ''orc'';' }
        @{ Name = "stub-takes-no-child-time"
           Find = '.run(p, ctx.nodeId, child.first, child.first);'
           Replace = '.run(p, ctx.nodeId, child.last, child.last);' }
        @{ Name = "second-live-seat-not-refused"
           Find = 'if (!takeSeat(row)) {'
           Replace = 'if (false) {' }
        @{ Name = "later-retirement-not-carried"
           Find = 'if (have !== undefined && have.retired_at === null && row.rec.retired === true) retire.run'
           Replace = 'if (false) retire.run' }
        @{ Name = "retirement-redated"
           Find = 'if (have !== undefined && have.retired_at === null && row.rec.retired === true) retire.run'
           Replace = 'if (have !== undefined && row.rec.retired === true) db.prepare(''UPDATE session SET retired_at = ? WHERE id = ?'').run' }
        @{ Name = "existing-row-never-reseated"
           Find = 'if (seatKind && have.retired_at === null && have.orc_id === sessionOrc(ctx, rec, kind)) {'
           Replace = 'if (false) {' }
        @{ Name = "retired-row-reseated"
           Find = 'if (seatKind && have.retired_at === null && have.orc_id === sessionOrc(ctx, rec, kind)) {'
           Replace = 'if (seatKind && have.orc_id === sessionOrc(ctx, rec, kind)) {' }
        @{ Name = "other-orc-record-reseats"
           Find = 'if (seatKind && have.retired_at === null && have.orc_id === sessionOrc(ctx, rec, kind)) {'
           Replace = 'if (seatKind && have.retired_at === null) {' }
        @{ Name = "seat-loser-of-other-rank-reseated"
           Find = '(have.rank === kind || have.rank === ''unknown'')'
           Replace = 'true' }
        @{ Name = "tie-takes-the-seat"
           Find = 'if (holderLast >= row.last) {'
           Replace = 'if (holderLast > row.last) {' }
        @{ Name = "holder-left-out-loses"
           Find = 'rows.has(holder.id) ? rows.get(holder.id).last : holder.last_seen'
           Replace = 'rows.has(holder.id) ? rows.get(holder.id).last : 0' }
        @{ Name = "tie-holder-not-named"
           Find = '{ claimed.set(row.orcId, holder.id); return false; }'
           Replace = '{ claimed.set(row.orcId, row.id); return false; }' }
        @{ Name = "new-holder-not-promoted"
           Find = 'if (have.rank !== kind) db.prepare(''UPDATE session SET rank = ? WHERE id = ?'').run(kind, row.id);'
           Replace = 'void 0;' }
        @{ Name = "stalest-session-takes-the-seat"
           Find = '.sort((a, b) => b.last - a.last ||'
           Replace = '.sort((a, b) => a.last - b.last ||' }
        @{ Name = "existing-session-reinserted"
           Find = 'if (exists.get(row.id)) { rep.count(''session'', false);'
           Replace = 'if (false) { rep.count(''session'', false);' }
        @{ Name = "merged-without-time-kept-merged"
           Find = 'if (state === ''merged'' && mergedAt === null) {'
           Replace = 'if (false) {' }
        @{ Name = "any-merge-sha-kept"
           Find = 'typeof sha === ''string'' && SHA40.test(sha) ? sha : null'
           Replace = 'typeof sha === ''string'' ? sha : null' }
        @{ Name = "ledger-merged-flag-trusted"
           Find = '''open'', null, null, at, null);'
           Replace = 'ev.merged ? ''merged'' : ''open'', ev.merged ? at : null, null, at, null);' }
        @{ Name = "parent-opened-later-dropped"
           Find = 'if (visiting.has(p.parentKey)) rep.unlink'
           Replace = 'if (true) rep.unlink' }
        @{ Name = "opened-prio-default-changed"
           Find = 'row.prio = prio ?? 2;'
           Replace = 'row.prio = prio ?? 0;' }
        @{ Name = "known-letter-not-linked"
           Find = 'else if (ctx.byLetter.has(by)) row.by_orc_id = ctx.byLetter.get(by);'
           Replace = 'else if (false) row.by_orc_id = ctx.byLetter.get(by);' }
        @{ Name = "superseded-not-linked"
           Find = 'if (to !== null && ctx.taskIds.has(to)) row.superseded_by_id'
           Replace = 'if (false) row.superseded_by_id' }
        @{ Name = "handed-without-target-written"
           Find = 'if (target === null) {'
           Replace = 'if (false) {' }
        @{ Name = "device-wait-not-external"
           Find = 'if (EXTERNAL_WAITS.includes(raw)) return'
           Replace = 'if (false) return' }
        @{ Name = "thrall-wait-not-an-orc"
           Find = 'if (/^[A-Z]$/.test(raw)) return'
           Replace = 'if (/^[A-LN-Z]$/.test(raw)) return' }
        @{ Name = "session-label-wait-not-an-orc-wait"
           Find = 'if (/^[A-Z]\d+$/.test(raw)) return'
           Replace = 'if (false) return' }
        @{ Name = "identical-line-not-reported"
           Find = 'if (!r.inserted && ctx.seen.has(r.id)) rep.unlink('
           Replace = 'if (false) rep.unlink(' }
        @{ Name = "task-pr-link-time-wrong"
           Find = 'ON CONFLICT DO NOTHING").run(row.task_id, prId, e.at);'
           Replace = 'ON CONFLICT DO NOTHING").run(row.task_id, prId, 0);' }
        @{ Name = "task-suffix-kept"
           Find = '/^(T-\d{4,})/.exec(String(e.task).trim())'
           Replace = '/^(T-\d{4,}$)/.exec(String(e.task).trim())' }
        @{ Name = "comma-lanes-last-letter-owns"
           Find = 'const first = tokens[0];'
           Replace = 'const first = tokens[tokens.length - 1];' }
        @{ Name = "only-first-lane-tagged"
           Find = 'for (const t of tokens) tagEntry('
           Replace = 'for (const t of tokens.slice(0, 1)) tagEntry(' }
        @{ Name = "thrall-lane-unmapped"
           Find = 'row.orc_id = first === ''Thrall'' ? ctx.thrallId : orcRef(ctx, first);'
           Replace = 'row.orc_id = orcRef(ctx, first);' }
        @{ Name = "fleet-wide-lost"
           Find = 'if (t === ''fleet-wide'') row.fleet_wide = 1;'
           Replace = 'if (t === ''fleet-wide'') row.fleet_wide = 0;' }
        @{ Name = "correction-written-before-its-original"
           Find = 'if (target && !visiting.has(target.legacy) && target.legacy !== x.legacy) put(target);'
           Replace = 'if (false) put(target);' }
        @{ Name = "tag-name-case-kept"
           Find = 'const name = ''lane:'' + lane.toLowerCase();'
           Replace = 'const name = ''lane:'' + lane;' }
        @{ Name = "dry-run-commits"
           Find = 'if (dryRun) throw new DryRunDone();'
           Replace = 'if (false) throw new DryRunDone();' }
        @{ Name = "stalest-session-claims-the-seat-first"
           Find = 'for (const row of order) {'
           Replace = 'for (const row of [...order].reverse()) {' }
        @{ Name = "seat-claims-not-remembered"
           Find = 'if (claimed.has(row.orcId)) return'
           Replace = 'if (false) return' }
        @{ Name = "seats-in-the-database-ignored"
           Find = 'const holder = seat.get(row.orcId, ctx.nodeId);'
           Replace = 'const holder = undefined;' }
        @{ Name = "sub-session-writer-gives-no-orc"
           Find = 'if (lead !== null) row.by_orc_id = lead;'
           Replace = 'if (false) row.by_orc_id = lead;' }
        @{ Name = "sub-session-handed-target-not-resolved"
           Find = '(orcRef(ctx, to) ?? labelOrc(ctx, to))'
           Replace = 'orcRef(ctx, to)' }
        @{ Name = "sub-session-wait-not-resolved"
           Find = 'orc: labelOrc(ctx, raw), unlinked: labelOrc(ctx, raw) === null }'
           Replace = 'orc: null, unlinked: true }' }
        @{ Name = "handed-needs-a-person-not-said"
           Find = 'names no Orc row (kept in task_event_extra; needs a person)'
           Replace = 'names no Orc row (kept in task_event_extra)' }
        @{ Name = "promise-and-kept-not-known"
           Find = "const EXTRA_ONLY_KINDS = ['promise', 'kept'];"
           Replace = "const EXTRA_ONLY_KINDS = [];" }
        @{ Name = "kept-not-known"
           Find = "const EXTRA_ONLY_KINDS = ['promise', 'kept'];"
           Replace = "const EXTRA_ONLY_KINDS = ['promise'];" }
        @{ Name = "replaces-not-kept"
           Find = "if (nz(ev.replaces)) row.replaces_no = promiseNo(rep, ev.replaces, 'replaces', ev.task);"
           Replace = "" }
        @{ Name = "closes-not-kept"
           Find = "row.closes_no = promiseNo(rep, ev.closes, 'closes', ev.task);"
           Replace = "" }
        @{ Name = "bad-name-silent"
           Find = "if (!m) { rep.unlink('ledger', flag + ' names no promise number (read as naming nothing)', task); return null; }"
           Replace = "if (!m) { return null; }" }
        @{ Name = "number-not-kept"
           Find = "row.promise_no = e.promiseNo;"
           Replace = "row.promise_no = 1;" }
        @{ Name = "number-by-time-not-by-file"
           Find = "promiseNumber = (promisesSeen.get(obj.task) ?? 0) + 1;"
           Replace = "promiseNumber = promisesSeen.size + 1;" }
        @{ Name = "numbers-do-not-climb"
           Find = "promisesSeen.set(obj.task, promiseNumber);"
           Replace = "" }
        @{ Name = "due-not-kept"
           Find = "else row.due_at = due;"
           Replace = "else row.due_at = undefined;" }
        @{ Name = "bad-due-silent"
           Find = "if (due === null) rep.unlink('ledger', 'promise has no usable due (kept with no due time)', ev.task);"
           Replace = "if (due === null) { }" }
        @{ Name = "extra-pr-silent"
           Find = "if (nz(ev.pr)) rep.unlink('ledger', ev.event + ' line names a PR (the PR is not linked from it)', ev.task);"
           Replace = "" }
        @{ Name = "hand-over-words-lost"
           Find = "if (to !== null) row.to_text = fit(rep, 'ledger', 'to', to, 120, ev.task);"
           Replace = "" }
        @{ Name = "hand-over-to-no-orc-dropped"
           Find = "      putExtra(ctx, e, row);"
           Replace = "" }
        @{ Name = "extra-repeat-silent"
           Find = "if (!r.inserted && ctx.seen.has(r.id)) ctx.rep.unlink('ledger', 'line is identical to an earlier line (one event)', e.ev.task + ' ' + e.ev.event);"
           Replace = "if (false) { }" }
        @{ Name = "first-seen-substitution-silent"
           Find = '{ rep.unlink(''registry'', ''firstSeen is not a time (lastSeen used)'', id); first = last; }'
           Replace = '{ first = last; }' }
        @{ Name = "last-seen-substitution-silent"
           Find = '{ rep.unlink(''registry'', ''lastSeen is not a time (firstSeen used)'', id); last = first; }'
           Replace = '{ last = first; }' }
        @{ Name = "retired-at-substitution-silent"
           Find = '    rep.unlink(''registry'', ''retiredAt is not a time (lastSeen used)'', row.id);'
           Replace = '' }
        @{ Name = "ledger-without-orcs-accepted"
           Find = '.get().n === 0) {'
           Replace = '.get().n === -1) {' }
        @{ Name = "changelog-without-orcs-accepted"
           Find = '(data.ledger !== null || data.changelog !== null) &&'
           Replace = 'data.ledger !== null &&' }
        @{ Name = "older-duplicate-card-reported-as-newer"
           Find = 'const drop = c.mtime > prev.mtime ? prev : c;'
           Replace = 'const drop = c.mtime > prev.mtime ? c : prev;' }
        @{ Name = "older-duplicate-card-imported"
           Find = 'newest.set(c.orc, c.mtime > prev.mtime ? c : prev);'
           Replace = 'newest.set(c.orc, c.mtime > prev.mtime ? prev : c);' }
        @{ Name = "cut-text-not-reported"
           Find = 'rep.unlink(source, field + '' longer than '' + max + '' characters (cut)'', example);'
           Replace = 'void example;' }
        @{ Name = "pr-repo-case-kept"
           Find = 'const repo = m[1].toLowerCase();'
           Replace = 'const repo = m[1];' }
        @{ Name = "pr-checked-time-is-now"
           Find = 'checked = firstNamed.get(m.key) ?? mergedAt ?? Date.now();'
           Replace = 'checked = Date.now();' }
        @{ Name = "pr-first-named-is-the-last"
           Find = '!(firstNamed.get(ref.key) <= t)'
           Replace = 'true' }
        @{ Name = "failure-after-changelog-not-seen"
           Find = 'onStep(''changelog'');'
           Replace = '' }
    )
}
