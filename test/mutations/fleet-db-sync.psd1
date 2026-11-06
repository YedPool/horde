# Mutations of the sync's node half (fleet-db/sync.mjs): the saved sources, the cadence, the state a run leaves. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-sync.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/sync.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\sync.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "save-waits-out-the-pace"
           Find = 'filesDue(state, start, req.force || req.save)'
           Replace = 'filesDue(state, start, req.force)' }
        @{ Name = "files-step-every-tick"
           Find = 'return ok === null || now - ok >= FILES_EVERY_MS || now < ok;'
           Replace = 'return true;' }
        @{ Name = "files-step-late-by-one-tick"
           Find = 'now - ok >= FILES_EVERY_MS'
           Replace = 'now - ok > FILES_EVERY_MS' }
        @{ Name = "force-ignored"
           Find = 'if (force) return true;'
           Replace = '' }
        @{ Name = "clock-gone-back-parks-the-sync"
           Find = ' || now < ok;'
           Replace = ';' }
        @{ Name = "no-saved-sources-not-refused"
           Find = 'if (!fs.existsSync(file)) throw new Error(''sync: no sources are saved'
           Replace = 'if (false) throw new Error(''sync: no sources are saved' }
        @{ Name = "relative-source-accepted-on-read"
           Find = 'if (typeof v !== ''string'' || !rooted(v)) throw'
           Replace = 'if (typeof v !== ''string'') throw' }
        @{ Name = "relative-source-accepted-on-save"
           Find = 'if (!rooted(v)) throw new Error(''sync: the '''
           Replace = 'if (false) throw new Error(''sync: the ''' }
        @{ Name = "unknown-source-accepted"
           Find = 'if (!SOURCE_KEYS.includes(k)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "source-flag-without-save-accepted"
           Find = 'if (!out.save && Object.keys(out.sources).length > 0) throw'
           Replace = 'if (false) throw' }
        @{ Name = "sessions-source-taken"
           Find = '''--thrall-card'': ''thrallCard'' };'
           Replace = '''--thrall-card'': ''thrallCard'', ''--registry'': ''registry'' };' }
        @{ Name = "failed-run-moves-last-ok"
           Find = 'state.files = { ...state.files, lastRunAt: start, lastResult: ''failed'','
           Replace = 'state.files = { lastOkAt: now(), lastRunAt: start, lastResult: ''failed'',' }
        @{ Name = "failed-run-recorded-as-ok"
           Find = 'lastRunAt: start, lastResult: ''failed'''
           Replace = 'lastRunAt: start, lastResult: ''ok''' }
        @{ Name = "timeout-moves-last-ok"
           Find = 'state.files = { ...state.files, lastRunAt: now(), lastResult: ''timeout'','
           Replace = 'state.files = { lastOkAt: now(), lastRunAt: now(), lastResult: ''timeout'',' }
        @{ Name = "good-run-not-recorded"
           Find = 'state.files = { lastOkAt: now(), lastRunAt: start, lastResult: ''ok'', lastMs: now() - start };'
           Replace = 'void start;' }
        @{ Name = "state-keys-of-other-steps-dropped"
           Find = '    ...obj,'
           Replace = '' }
        @{ Name = "sessions-step-skipped-when-files-skipped"
           Find = 'if (req.snapshot !== null || req.snapshotError !== null) {'
           Replace = 'if ((req.snapshot !== null || req.snapshotError !== null) && !parts[0].startsWith(''files skipped'')) {' }
        @{ Name = "sessions-step-stopped-by-a-files-failure"
           Find = 'if (req.snapshot !== null || req.snapshotError !== null) {'
           Replace = 'if ((req.snapshot !== null || req.snapshotError !== null) && failures.length === 0) {' }
        @{ Name = "sessions-failure-recorded-as-ok"
           Find = 'lastRunAt: t0, lastResult: ''failed'''
           Replace = 'lastRunAt: t0, lastResult: ''ok''' }
        @{ Name = "sessions-failure-loses-the-files-result"
           Find = 'state.sessions = { ...state.sessions, lastRunAt: t0, lastResult: ''failed'', lastMs: now() - t0 };'
           Replace = 'state.files = { ...state.files, lastResult: ''failed'' }; state.sessions = { ...state.sessions, lastRunAt: t0, lastResult: ''failed'', lastMs: now() - t0 };' }
        @{ Name = "sessions-good-run-not-recorded"
           Find = 'state.sessions = { lastOkAt: now(), lastRunAt: t0, lastResult: ''ok'', lastMs: now() - t0, counts: r.counts };'
           Replace = 'void t0;' }
        @{ Name = "snapshot-error-ignored"
           Find = 'if (req.snapshotError !== null) throw new Error(''no session snapshot this tick: '' + req.snapshotError);'
           Replace = '' }
        @{ Name = "timeout-leaves-the-sessions-step-unmarked"
           Find = 'state.sessions = { ...state.sessions, lastRunAt: now(), lastResult: ''timeout'', lastMs: req.noteTimeoutMs };'
           Replace = '' }
        @{ Name = "failure-line-names-one-step"
           Find = 'err(''fleet.db: '' + (parts.length === 1 ? failures[0] : ''sync: '' + parts.join(''; '')));'
           Replace = 'err(''fleet.db: '' + failures[0]);' }
        @{ Name = "failed-step-exits-zero"
           Find = 'if (failures.length > 0) {'
           Replace = 'if (false) {' }
        @{ Name = "both-snapshot-flags-accepted"
           Find = 'if (out.snapshot !== null && out.snapshotError !== null) throw'
           Replace = 'if (false) throw' }
        @{ Name = "missing-database-made"
           Find = 'if (!fs.existsSync(file)) throw new Error(''fleet.db does not exist yet at '' + file + ''; run horde db init'');'
           Replace = '' }
        @{ Name = "sessions-step-makes-a-missing-database"
           Find = 'if (!fs.existsSync(file)) throw new Error(''sessions: fleet.db does not exist yet at '' + file + ''; run horde db init'');'
           Replace = '' }
    )
}
