# Mutations of the horde db verbs' node side (fleet-db/cli.mjs). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-cli.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "extra-arguments-accepted"
           Find = 'if (argv.length !== 1 || !VERBS.includes(argv[0])) {'
           Replace = 'if (!VERBS.includes(argv[0])) {' }
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
        @{ Name = "init-hint-lost"
           Find = 'e.message.replace(''open it for writing once'', ''run horde db init'')'
           Replace = 'e.message' }
    )
}
