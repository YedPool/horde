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
        @{ Name = "http-refusal-read-as-an-answer"
           Find = 'if (response.status !== 200) return unknown('
           Replace = 'if (false) return unknown(' }
        @{ Name = "http-answers-from-a-cache"
           Find = 'credentials: "same-origin", cache: "no-store", redirect: "error",'
           Replace = 'credentials: "same-origin", redirect: "error",' }
        @{ Name = "http-watch-of-zero-opens-a-socket"
           Find = '(timeoutMs <= 0 ? read(mailbox, since, max, "watch")'
           Replace = '(false ? read(mailbox, since, max, "watch")' }
        @{ Name = "http-watch-socket-left-open"
           Find = 'try { socket.close(); } catch (x) { /* already closed */ }'
           Replace = '' }
        @{ Name = "http-watch-failure-read-as-nothing"
           Find = 'socket.onerror = () => finish(unknown("the relay''s watch failed"));'
           Replace = 'socket.onerror = () => finish(known({ items: [] }));' }
        @{ Name = "transport-throw-escapes"
           Find = 'try { return await fn(); } catch (x) {'
           Replace = 'try { return await fn(); } finally { } if (false) { const x = null;' }
    )
}
