# Mutations of migration 4's views (fleet-db/schema.mjs): an acknowledgement closes its question. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-db-import-acked.psd1
# test\test-fleet-db.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "fleet-db\schema.mjs"
    Suite  = "test\test-fleet-db.ps1"
    Mutations = @(
        @{ Name = "question-now-ack-does-not-close"
           Find = 'WHEN ''acked'' THEN ''closed'' ELSE ''open'' END AS state'
           Replace = 'ELSE ''open'' END AS state' }
        @{ Name = "answer-now-ack-does-not-close"
           Find = 'IN (''closed'', ''acked'') THEN 0 ELSE 1 END AS open_at_arrival'
           Replace = 'IN (''closed'') THEN 0 ELSE 1 END AS open_at_arrival' }
    )
}
