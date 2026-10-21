# Mutations of the work verb's command line (fleet-db/work-cli.mjs): flags, exit codes, output, the busy
# timeout. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-work-cli.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\work-cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "unknown-flag-accepted"
           Find = 'if (!isValue && !spec.bare.includes(a)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "flag-twice-accepted"
           Find = 'if (a in got) throw'
           Replace = 'if (false) throw' }
        @{ Name = "flag-without-value-accepted"
           Find = 'if (i + 1 >= args.length) throw'
           Replace = 'if (false) throw' }
        @{ Name = "value-must-not-start-with-dashes"
           Find = 'got[a] = args[++i];'
           Replace = 'if (args[i + 1].startsWith(''--'')) throw refuse(verb + '': '' + a + '' needs a value''); got[a] = args[++i];' }
        @{ Name = "flag-error-not-ascii"
           Find = 'err(''refused: '' + ascii(e.message));'
           Replace = 'err(''refused: '' + e.message);' }
        @{ Name = "refusal-not-ascii"
           Find = 'err(e.refusal ? ''refused: '' + ascii(e.message)'
           Replace = 'err(e.refusal ? ''refused: '' + e.message' }
        @{ Name = "milliseconds-not-read"
           Find = 'if (/^\d{1,15}$/.test(v)) return Number(v);'
           Replace = '' }
        @{ Name = "bad-time-accepted"
           Find = 'if (t === null) throw refuse(''--at must be'
           Replace = 'if (false) throw refuse(''--at must be' }
        @{ Name = "busy-is-exit-1"
           Find = 'if (isBusy(e)) { err(''fleet.db busy''); return 3; }'
           Replace = 'if (isBusy(e)) { err(''fleet.db busy''); return 1; }' }
        @{ Name = "busy-not-recognised"
           Find = '/database is locked|database table is locked|SQLITE_BUSY/i'
           Replace = '/never matches this/i' }
        @{ Name = "busy-message-changed"
           Find = 'err(''fleet.db busy'');'
           Replace = 'err(''fleet.db is locked'');' }
        @{ Name = "busy-timeout-env-ignored"
           Find = '? Number(env.HORDE_WORK_BUSY_MS) :'
           Replace = '? BUSY_MS_DEFAULT :' }
        @{ Name = "busy-timeout-not-applied"
           Find = 'openStore(file, { busyMs })'
           Replace = 'openStore(file)' }
        @{ Name = "no-home-is-exit-1"
           Find = '    return 2;'
           Replace = '    return 1;' }
        @{ Name = "unknown-verb-accepted"
           Find = 'if (!VERBS.includes(verb)) {'
           Replace = 'if (false) {' }
        @{ Name = "warnings-not-printed"
           Find = 'for (const w of r.warnings) out(ascii(w));'
           Replace = '' }
        @{ Name = "start-repeat-not-said"
           Find = '(r.action === ''started'' ? ''started '' : ''already started '')'
           Replace = '''started ''' }
        @{ Name = "end-repeat-not-said"
           Find = '(r.action === ''ended'' ? ''ended '' : ''already ended '')'
           Replace = '''ended ''' }
        @{ Name = "start-time-flag-dropped"
           Find = 'model: flags[''--model''], at: timeFlag(flags[''--at'']),'
           Replace = 'model: flags[''--model''],' }
        @{ Name = "end-time-flag-dropped"
           Find = 'outcome: flags[''--outcome''], at: timeFlag(flags[''--at'']) });'
           Replace = 'outcome: flags[''--outcome''] });' }
        @{ Name = "list-opens-for-writing"
           Find = 'db = verb === ''list'' ? openForReading(file, busyMs) : openStore(file, { busyMs });'
           Replace = 'db = openStore(file, { busyMs });' }
        @{ Name = "list-orc-ignored"
           Find = 'orc: flags[''--orc''] ?? null'
           Replace = 'orc: null' }
        @{ Name = "list-running-ignored"
           Find = 'running: flags[''--running''] === true'
           Replace = 'running: false' }
        @{ Name = "list-json-not-ascii"
           Find = 'out(ascii(JSON.stringify({ units })));'
           Replace = 'out(JSON.stringify({ units }));' }
        @{ Name = "list-empty-fails"
           Find = 'out(''no work units''); return 0;'
           Replace = 'out(''no work units''); return 1;' }
    )
}
