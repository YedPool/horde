# Mutations of migration 7 (fleet-db/schema.mjs): the session state columns the sessions step writes. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-schema-v7.psd1
# test\test-fleet-db.ps1 must fail for every one (fleet-db/test/sessions.test.mjs, "migration 7"). Every find string occurs once.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "in-turn-takes-any-number"
           Find = 'ALTER TABLE session ADD COLUMN in_turn INTEGER ${flag(''in_turn'')};'
           Replace = 'ALTER TABLE session ADD COLUMN in_turn INTEGER;' }
        @{ Name = "waits-person-takes-any-number"
           Find = 'ALTER TABLE session ADD COLUMN waits_person INTEGER ${flag(''waits_person'')};'
           Replace = 'ALTER TABLE session ADD COLUMN waits_person INTEGER;' }
        @{ Name = "state-takes-any-word"
           Find = 'ALTER TABLE session ADD COLUMN state TEXT CHECK (state IN (''live'', ''idle'', ''waiting-person'', ''waiting-job'', ''dead''));'
           Replace = 'ALTER TABLE session ADD COLUMN state TEXT;' }
        @{ Name = "negative-offset-allowed"
           Find = 'ALTER TABLE session ADD COLUMN transcript_offset INTEGER CHECK (transcript_offset >= 0);'
           Replace = 'ALTER TABLE session ADD COLUMN transcript_offset INTEGER;' }
        @{ Name = "negative-activity-time-allowed"
           Find = 'ALTER TABLE session ADD COLUMN last_activity_at INTEGER CHECK (last_activity_at >= 0);'
           Replace = 'ALTER TABLE session ADD COLUMN last_activity_at INTEGER;' }
        @{ Name = "state-checked-column-missing"
           Find = 'ALTER TABLE session ADD COLUMN state_checked_at INTEGER CHECK (state_checked_at >= 0);'
           Replace = '' }
    )
}
