# Mutations of the one rule for an Orc's fleet.db row (fleet-db/orc-row.mjs), used by the importer and by
# `horde status set`. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-orc-row.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/orc-row.test.mjs). Every find string occurs once.
# The importer's old mutation "existing-orc-matched-by-both" lives here now, because the SQL moved with the rule.
@{
    Target = "fleet-db\orc-row.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "existing-orc-matched-by-both"
           Find = 'WHERE lane_dir = ? OR letter = ? ORDER BY'
           Replace = 'WHERE lane_dir = ? AND letter = ? ORDER BY' }
        @{ Name = "live-thrall-row-not-looked-for"
           Find = 'if (isThrall) {'
           Replace = 'if (false) {' }
        @{ Name = "existing-row-not-kept"
           Find = 'if (found !== null) return { id: found, added: false, cut: false };'
           Replace = '' }
        @{ Name = "long-lane-not-cut"
           Find = 'name = name.slice(0, NAME_MAX);'
           Replace = 'name = name;' }
        @{ Name = "empty-lane-not-named-for-folder"
           Find = 'let name = lane === '''' ||'
           Replace = 'let name = false ||' }
        @{ Name = "thrall-rank-lost"
           Find = 'isThrall ? ''thrall'' : ''orc'''
           Replace = '''orc''' }
        @{ Name = "created-at-ignored"
           Find = '''orc'', createdAt)'
           Replace = '''orc'', 0)' }
        @{ Name = "added-not-reported"
           Find = 'return { id, added: true, cut };'
           Replace = 'return { id, added: false, cut };' }
    )
}
