# Mutations of the fleet meter's command line (fleet-metrics/cli.mjs): the exit codes a scheduler's history
# is read by. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-meter-cli.psd1
# test\test-fleet-meter.ps1 (the meter's node tests, on synthetic transcripts) must fail for every one.
# Every find string occurs once.
@{
    Target = "fleet-metrics\cli.mjs"
    Suite  = "test\test-fleet-meter.ps1"
    Mutations = @(
        @{ Name = "unreadable-file-exits-zero"
           Find = 'if (r.errors > 0) return 1;'
           Replace = '' }
        @{ Name = "failed-delivery-exits-zero"
           Find = 'if (r.failed > 0) return 1;'
           Replace = '' }
        @{ Name = "no-home-exits-one"
           Find = 'if (!home.ok) { err(home.message); return 2; }'
           Replace = 'if (!home.ok) { err(home.message); return 1; }' }
        @{ Name = "unreadable-file-not-named"
           Find = "for (const f of r.failures.slice(0, 5)) err('could not read ' + f.file + ': ' + f.message);"
           Replace = '' }
    )
}
