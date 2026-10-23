# Mutations of the node side of an answer's item lookup (fleet-db/decisions-cli.mjs, published-item; T-0352). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-published-item.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "fleet-db\decisions-cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "archived-lists-are-not-found"
           Find = 'FROM decisions_snapshot_item WHERE snapshot_id = ? AND position = ?'
           Replace = 'FROM decisions_live_item WHERE snapshot_id = ? AND position = ?' }
        @{ Name = "a-retired-orc-is-not-reported"
           Find = 'retired: s.retired_at !== null,'
           Replace = 'retired: false,' }
        @{ Name = "every-list-is-said-to-be-live"
           Find = 'live: Boolean(live),'
           Replace = 'live: true,' }
        @{ Name = "item-zero-is-looked-for"
           Find = 'if (!Number.isSafeInteger(position) || position < 1) return'
           Replace = 'if (!Number.isSafeInteger(position) || position < 0) return' }
        @{ Name = "a-malformed-snapshot-id-is-asked-for"
           Find = 'if (typeof snapshot !== ''string'' || !SNAPSHOT_ID.test(snapshot)) return { found: false, reason: ''the snapshot id is not one'' };'
           Replace = '' }
        @{ Name = "the-thrall-is-not-named-by-rank"
           Find = 'rank: s.rank,'
           Replace = 'rank: ''orc'',' }
    )
}
