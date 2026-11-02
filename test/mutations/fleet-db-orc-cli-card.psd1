# Mutations of the live status row `orc-cli.mjs ensure --card` appends (T-0389). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-orc-cli-card.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/status-card.test.mjs). Every find string occurs once.
@{
    Target = "fleet-db\orc-cli.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "card-flag-ignored"
           Find = 'if (''--card'' in flags) {'
           Replace = 'if (false) {' }
        @{ Name = "live-row-written-as-backfill"
           Find = 'backfill: 0 });'
           Replace = 'backfill: 1 });' }
        @{ Name = "existing-row-at-that-time-not-checked"
           Find = 'if (db.prepare(''SELECT 1 FROM orc_status WHERE orc_id = ? AND at = ? LIMIT 1'').get(orc.id, s.row.at)) { status = ''status row kept''; return orc; }'
           Replace = '' }
        @{ Name = "bad-doing-costs-the-orc-row"
           Find = 'if (s.skip) { status = ''no status row: '' + s.skip; return orc; }'
           Replace = 'if (s.skip) throw new Error(s.skip);' }
        @{ Name = "unreadable-card-costs-the-orc-row"
           Find = 'catch (e) { cardRead = { error: ''the card could not be read: '' + e.message }; }'
           Replace = 'catch (e) { throw e; }' }
        @{ Name = "relative-card-accepted"
           Find = 'if (''--card'' in got && !isRooted(got[''--card''])) throw'
           Replace = 'if (false) throw' }
        @{ Name = "status-outcome-not-printed"
           Find = '(status === null ? '''' : ''; '' + ascii(status))'
           Replace = '''''' }
    )
}
