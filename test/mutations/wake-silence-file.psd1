# Mutations of how a silent fleet's last probe is saved and read back (core/Wake.ps1, Save-HordeWakeSilence
# and Read-HordeWakeSilence, probeAt). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-silence-file.psd1
# test\test-wake-run.ps1 must fail for every one. Every find string occurs exactly once. The file is
# read and written by the tick, so the tick's suite is the one that sees it; the watcher's other
# promises are wake.psd1's, against test\test-wake.ps1.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-wake-run.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-last-probe-of-a-silence-is-not-saved"
           Find = 'quietSince = $since; probes = $sent; probeAt = $lastProbe }'
           Replace = 'quietSince = $since; probes = $sent; probeAt = $null }' }
        @{ Name = "the-last-probe-of-a-silence-is-not-read-back"
           Find = 'probes = $sent; probeAt = $lastProbe } }))'
           Replace = 'probes = $sent; probeAt = $null } }))' }
    )
}
