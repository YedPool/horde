# Mutations of the Orc-row command line (fleet-db/orc-cli.mjs): flags, exit codes, output, the busy timeout, the
# refusal to make a database. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-orc-cli.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/orc-row.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\orc-cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "unknown-flag-accepted"
           Find = 'if (!isValue && !BARE.includes(a)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "flag-twice-accepted"
           Find = 'if (a in got) throw'
           Replace = 'if (false) throw' }
        @{ Name = "flag-without-value-accepted"
           Find = 'if (i + 1 >= args.length) throw'
           Replace = 'if (false) throw' }
        @{ Name = "folder-or-letter-not-required"
           Find = 'if (!(f in got)) throw'
           Replace = 'if (false) throw' }
        @{ Name = "lane-text-required"
           Find = 'if (!(typeof got[''--lane''] === ''string'')) got[''--lane''] = '''';'
           Replace = '' }
        @{ Name = "bad-folder-not-refused-in-words"
           Find = 'if (!/^[a-z0-9-]{1,64}$/.test(got[''--folder'']))'
           Replace = 'if (false)' }
        @{ Name = "bad-letter-not-refused-in-words"
           Find = 'if (!/^[A-Z]$/.test(got[''--letter'']))'
           Replace = 'if (false)' }
        @{ Name = "thrall-flag-ignored"
           Find = 'isThrall: flags[''--thrall''] === true,'
           Replace = 'isThrall: false,' }
        @{ Name = "missing-database-made"
           Find = 'if (!fs.existsSync(file)) { err(''fleet.db does not exist yet (run horde db init)''); return 4; }'
           Replace = '' }
        @{ Name = "busy-not-answered-as-busy"
           Find = 'if (isBusy(e)) { err(''fleet.db busy''); return 3; }'
           Replace = '' }
        @{ Name = "busy-wait-longer-than-asked"
           Find = 'Number(env.HORDE_ORC_BUSY_MS)'
           Replace = '(Number(env.HORDE_ORC_BUSY_MS) + 4000)' }
        @{ Name = "no-home-not-exit-2"
           Find = 'return 2;'
           Replace = 'return 1;' }
        @{ Name = "kept-reported-as-added"
           Find = 'out(r.added ? ''added'' : ''kept'');'
           Replace = 'out(''added'');' }
    )
}
