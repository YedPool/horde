# Mutations of the status-card rule the importer and `horde status set` share (fleet-db/import.mjs readStatusCard, statusRowFor,
# stepStatus). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-status-card.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/status-card.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\import.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "sync-doubles-a-live-status-row"
           Find = 'if (there.get(orcId, s.row.at)) { rep.count(''orc_status'', false); continue; }'
           Replace = '' }
        @{ Name = "any-older-row-blocks-a-new-card"
           Find = 'WHERE orc_id = ? AND at = ? LIMIT 1'
           Replace = 'WHERE orc_id = ? AND ? IS NOT NULL LIMIT 1' }
        @{ Name = "doing-limit-too-wide"
           Find = 'if (doing.length < 1 || doing.length > 120) return'
           Replace = 'if (doing.length < 1 || doing.length > 121) return' }
        @{ Name = "empty-doing-gets-a-row"
           Find = 'if (doing.length < 1 || doing.length > 120) return'
           Replace = 'if (doing.length > 120) return' }
        @{ Name = "blocked-limit-too-wide"
           Find = 'if (blocked !== null && blocked.length > 200) return'
           Replace = 'if (blocked !== null && blocked.length > 201) return' }
        @{ Name = "card-folder-not-checked"
           Find = 'if (!/^[a-z0-9-]{1,64}$/.test(folder)) return { error'
           Replace = 'if (false) return { error' }
        @{ Name = "card-time-not-the-files"
           Find = 'mtime: Math.floor(fs.statSync(file).mtimeMs)'
           Replace = 'mtime: Math.floor(fs.statSync(file).mtimeMs) + 1' }
    )
}
