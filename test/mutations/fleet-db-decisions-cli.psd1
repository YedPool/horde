# Mutations of the decisions verbs' node side (fleet-db/decisions-cli.mjs), the confirm record of T-0299. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-decisions-cli.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\decisions-cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "json-confirmed-is-published"
           Find = 'confirmedAt: new Date(l.confirmed_at).toISOString()'
           Replace = 'confirmedAt: new Date(l.published_at).toISOString()' }
        @{ Name = "select-confirmed-is-published"
           Find = 'l.published_at, l.confirmed_at, l.item_count'
           Replace = 'l.published_at, l.published_at AS confirmed_at, l.item_count' }
        @{ Name = "text-confirmed-is-published"
           Find = "', confirmed ' + l.confirmedAt"
           Replace = "', confirmed ' + l.publishedAt" }
        @{ Name = "unchanged-names-no-time"
           Find = "new Date(r.confirmedAt).toISOString()"
           Replace = "new Date(0).toISOString()" }
    )
}
