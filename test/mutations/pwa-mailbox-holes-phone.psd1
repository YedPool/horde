# Mutations of what the phone does with a hole in its mailbox (surfaces/pwa/page/phone-core.js, A HOLE
# IN THIS MAILBOX IS NOT AN ANOMALY; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-mailbox-holes-phone.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each. Every find string occurs exactly once. The
# phone's other promises are pwa-phone-core.psd1's (a spec of its own: CONTRIBUTING 15).
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "trimmed-mailbox-holes-shown-on-the-screen"
           Find = 'anomalies.push(...r.value.anomalies);'
           Replace = 'anomalies.push(...r.value.anomalies, ...r.value.gaps);' }
    )
}
