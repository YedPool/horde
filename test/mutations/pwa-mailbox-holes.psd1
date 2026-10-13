# Mutations of the phone's relay client where it reports a hole apart from its anomalies
# (surfaces/pwa/page/relay-client.js; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-mailbox-holes.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each. Every find string occurs exactly once. The
# client's other rules are pwa-relay-client.psd1's, and what the phone does with a hole is
# pwa-mailbox-holes-phone.psd1's: specs of their own, so that a review round reruns these and not the
# ones that were there before them (CONTRIBUTING 15).
@{
    Target = "surfaces\pwa\page\relay-client.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "gap-reported-as-an-anomaly"
           Find = 'gaps.push("a gap: seq "'
           Replace = 'anomalies.push("a gap: seq "' }
        @{ Name = "gaps-not-handed-to-the-caller"
           Find = 'anomalies: r.anomalies, gaps: r.gaps });'
           Replace = 'anomalies: r.anomalies, gaps: [] });' }
    )
}
