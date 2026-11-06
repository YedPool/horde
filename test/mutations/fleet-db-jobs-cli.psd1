# Mutations of the job and signal command line (fleet-db/jobs-cli.mjs): flags, -File reading, exit codes, the read-only first open, the output lines. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-jobs-cli.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/jobs.test.mjs, "cli:"). Every find string occurs once.
@{
    Target = "fleet-db\jobs-cli.mjs"
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
        @{ Name = "required-flags-not-checked"
           Find = 'for (const f of REQUIRED[verb])'
           Replace = 'for (const f of [])' }
        @{ Name = "text-and-file-together-accepted"
           Find = 'if ((textFlag in got) === (''--file'' in got)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "relative-file-path-accepted"
           Find = 'if (!isRooted(file)) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "file-size-not-limited"
           Find = 'if (st.size > LIMITS.fileBytes) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "directory-read-as-file"
           Find = 'if (!st.isFile()) throw refuse('
           Replace = 'if (false) throw refuse(' }
        @{ Name = "utf16-file-not-named"
           Find = 'if (buf.length >= 2 && ('
           Replace = 'if (false && (' }
        @{ Name = "bad-utf8-repaired"
           Find = 'new TextDecoder(''utf-8'', { fatal: true })'
           Replace = 'new TextDecoder(''utf-8'')' }
        @{ Name = "refusal-not-ascii"
           Find = 'err(''refused: '' + ascii(e.message));'
           Replace = 'err(''refused: '' + e.message);' }
        @{ Name = "no-database-is-exit-1"
           Find = 'err(''fleet.db does not exist yet (run horde db init)''); return 4; }'
           Replace = 'err(''fleet.db does not exist yet (run horde db init)''); return 1; }' }
        @{ Name = "no-database-not-checked"
           Find = 'if (!fs.existsSync(file)) {'
           Replace = 'if (false) {' }
        @{ Name = "no-home-is-exit-1"
           Find = '    return 2;'
           Replace = '    return 1;' }
        @{ Name = "busy-is-exit-1"
           Find = 'if (isBusy(e)) { err(''fleet.db busy''); return 3; }'
           Replace = 'if (isBusy(e)) { err(''fleet.db busy''); return 1; }' }
        @{ Name = "busy-not-recognised"
           Find = '/database is locked|database table is locked|SQLITE_BUSY/i'
           Replace = '/never matches this/i' }
        @{ Name = "busy-timeout-env-ignored"
           Find = '? Number(env.HORDE_JOBS_BUSY_MS) :'
           Replace = '? BUSY_MS_DEFAULT :' }
        @{ Name = "write-wait-not-applied"
           Find = 'db = openStore(file, { busyMs });'
           Replace = 'db = openStore(file);' }
        @{ Name = "migrates-an-older-file"
           Find = 'db = openStore(file, { readOnly: true, busyMs });'
           Replace = 'db = openStore(file, { busyMs });' }
        @{ Name = "older-file-not-told-how-to-mend"
           Find = '.replace(''open it for writing once'', ''run horde db init'')'
           Replace = '' }
        @{ Name = "mark-woke-list-opens-read-only"
           Find = 'const writes = !verb.endsWith('' list'') || flags[''--mark-woke''] === true;'
           Replace = 'const writes = !verb.endsWith('' list'');' }
        @{ Name = "overdue-flag-dropped"
           Find = 'overdue: flags[''--overdue''] === true'
           Replace = 'overdue: false' }
        @{ Name = "owner-filter-dropped"
           Find = 'open: flags[''--open''] === true, owner: flags[''--owner''] ?? null, overdue'
           Replace = 'open: flags[''--open''] === true, owner: null, overdue' }
        @{ Name = "updated-fields-not-named"
           Find = '(r.action === ''updated'' ? '' ('' + r.changed.join('', '') + '')'' : '''')'
           Replace = '''''' }
        @{ Name = "raise-count-not-shown"
           Find = '(r.action === ''kept'' ? '''' : '' (count '' + r.count + '')'')'
           Replace = '''''' }
        @{ Name = "prune-plural-wrong"
           Find = '(r.pruned === 1 ? '''' : ''s'')'
           Replace = '''''' }
        @{ Name = "json-list-not-json"
           Find = 'out(ascii(JSON.stringify({ jobs: rows })));'
           Replace = 'out(ascii(String(rows.length)));' }
    )
}
