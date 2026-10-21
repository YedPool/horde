# Mutations of the bare S4U probe in test\test-metrics-schedule.ps1 (T-0325). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\metrics-schedule-s4u-probe.psd1
# The suite probes whether this shell may register a NEW S4U task at all; only a refused probe may
# excuse the install/replace/status/remove checks. The target here is the suite itself.
# NON-ELEVATED ONLY: both Expect values hold in a shell whose bare probe is refused. Elevated, the
# probe registers, so probe-always-registers survives and probe-always-refused is caught - both
# report BAD. Mutate has no per-environment expectation; run this spec from a non-elevated shell.
@{
    Target = "test\test-metrics-schedule.ps1"
    Suite  = "test\test-metrics-schedule.ps1"
    Mutations = @(
        @{ Name = "probe-always-registers"
           Find = '            $probeSaid = & $probeS4U'
           Replace = '            $probeSaid = ""' }
        @{ Name = "probe-always-refused"
           Find = '            $probeSaid = & $probeS4U'
           Replace = '            $probeSaid = "Access is denied."'
           Expect = "survives"
           Reason = "on a shell whose bare probe is refused (non-elevated, the case this was measured in on 2026-10-21) the mutant changes nothing, so it survives there; in an elevated run the probe registers, the mutant skips the install/replace/status/remove checks, and the refusal-path check that install exits non-zero and registers nothing goes red because install then succeeds. Run it elevated to see it die." }
    )
}
