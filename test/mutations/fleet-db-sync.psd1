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
           Find = 'lastResult: ''failed'''
           Replace = 'lastResult: ''ok''' }
        @{ Name = "timeout-moves-last-ok"
           Find = 'state.files = { ...state.files, lastRunAt: now(), lastResult: ''timeout'','
           Replace = 'state.files = { lastOkAt: now(), lastRunAt: now(), lastResult: ''timeout'',' }
        @{ Name = "good-run-not-recorded"
           Find = 'state.files = { lastOkAt: now(), lastRunAt: start, lastResult: ''ok'', lastMs: now() - start };'
           Replace = 'void start;' }
        @{ Name = "state-keys-of-other-steps-dropped"
           Find = 'return { ...obj, schema: STATE_SCHEMA, files:'
           Replace = 'return { schema: STATE_SCHEMA, files:' }
        @{ Name = "missing-database-made"
           Find = 'if (!fs.existsSync(file)) throw new Error(''fleet.db does not exist yet at '' + file + ''; run horde db init'');'
           Replace = '' }
    )
}
