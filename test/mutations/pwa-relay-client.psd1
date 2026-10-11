# Mutations of surfaces/pwa/page/relay-client.js, the phone's relay client and its distrust of the
# relay. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-relay-client.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\relay-client.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "batch-not-sorted"
           Find = 'const sorted = [...bySeq.values()].sort((a, b) => a.seq - b.seq);'
           Replace = 'const sorted = [...bySeq.values()];' }
        @{ Name = "item-at-cursor-kept"
           Find = 'if (it.seq <= since) {'
           Replace = 'if (it.seq < since) {' }
        @{ Name = "second-item-under-a-seq-kept"
           Find = 'if (bySeq.has(it.seq)) {'
           Replace = 'if (false) {' }
        @{ Name = "non-ascii-text-kept"
           Find = '|| !TEXT.test(text)) return "a relay holds printable ASCII'
           Replace = ') return "a relay holds printable ASCII' }
        @{ Name = "transport-throw-escapes"
           Find = 'try { return await fn(); } catch (x) {'
           Replace = 'try { return await fn(); } finally { } if (false) { const x = null;' }
    )
}
