# Mutations of fleet.db's entry point that belong to the sync (fleet-db/cli.mjs): the verb is reached and `status` ends with the
# last sync. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-sync-cli.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/sync.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "sync-verb-not-routed"
           Find = 'if (verb === ''sync'') return syncMain(argv.slice(1), env, out, err);'
           Replace = '' }
        @{ Name = "status-sync-line-dropped"
           Find = 'out(describeSync(homeFromEnv(env)));'
           Replace = '' }
        @{ Name = "status-sessions-line-dropped"
           Find = 'out(describeSessions(homeFromEnv(env)));'
           Replace = '' }
    )
}
