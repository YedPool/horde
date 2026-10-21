# Mutations of the horde db verbs' node side (fleet-db/cli.mjs). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-cli.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "extra-arguments-accepted"
           Find = 'if (!VERBS.includes(verb) || (verb !== ''import'' && argv.length !== 1)) {'
           Replace = 'if (!VERBS.includes(verb)) {' }
        @{ Name = "import-flag-given-twice-accepted"
           Find = 'if (key in sources) throw'
           Replace = 'if (false) throw' }
        @{ Name = "import-unknown-flag-ignored"
           Find = 'if (!key) throw new Error(''import: unknown argument '' + a);'
           Replace = 'if (!key) continue;' }
        @{ Name = "import-flag-without-path-accepted"
           Find = 'if (v === undefined || v === '''' || v.startsWith(''--''))'
           Replace = 'if (v === undefined)' }
        @{ Name = "import-without-source-accepted"
           Find = 'if (Object.keys(sources).length === 0) throw'
           Replace = 'if (false) throw' }
        @{ Name = "import-makes-the-database"
           Find = '      if (!fs.existsSync(file)) throw'
           Replace = '      if (false) throw' }
        @{ Name = "dry-run-migrates-an-older-file"
           Find = 'if (request.dryRun) openForReading(file).close();'
           Replace = 'if (false) openForReading(file).close();' }
        @{ Name = "import-dry-run-flag-dropped"
           Find = 'dryRun: request.dryRun'
           Replace = 'dryRun: false' }
        @{ Name = "import-report-not-printed"
           Find = 'for (const u of report.unlinked) out('
           Replace = 'for (const u of []) out(' }
        @{ Name = "import-table-counts-not-printed"
           Find = 'for (const [t, c] of Object.entries(report.tables)) out('
           Replace = 'for (const [t, c] of []) out(' }
        @{ Name = "no-home-exit-1"
           Find = '    return 2;'
           Replace = '    return 1;' }
        @{ Name = "status-creates-the-file"
           Find = 'db = openForReading(file);'
           Replace = 'db = openStore(file);' }
        @{ Name = "init-always-created"
           Find = '(existed ? ''already there, now current'' : ''created'')'
           Replace = '''created''' }
        @{ Name = "short-list-not-found"
           Find = 'HAVING have <> s.item_count'
           Replace = 'HAVING have > s.item_count' }
        @{ Name = "foreign-keys-not-checked"
           Find = 'for (const r of db.prepare(''PRAGMA foreign_key_check'').all())'
           Replace = 'for (const r of [])' }
        @{ Name = "problems-exit-0"
           Find = 'return problems.length === 0 ? 0 : 1;'
           Replace = 'return 0;' }
        @{ Name = "hash-not-rechecked"
           Find = '!== s.sha256) problems.push'
           Replace = '=== ''never'') problems.push' }
        @{ Name = "registry-gaps-not-found"
           Find = 'if (missing > 0) problems.push'
           Replace = 'if (false) problems.push' }
        @{ Name = "registry-orphans-not-found"
           Find = 'if (orphans > 0) problems.push'
           Replace = 'if (false) problems.push' }
        @{ Name = "init-hint-lost"
           Find = 'e.message.replace(''open it for writing once'', ''run horde db init'')'
           Replace = 'e.message' }
    )
}
