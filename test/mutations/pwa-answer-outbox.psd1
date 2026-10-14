# Mutations of the phone's outbox (surfaces/pwa/page/phone-core.js, AN ANSWER IS KEPT UNTIL THE PC HAS
# APPLIED IT; the founder, 2026-10-14, relay fixes 3 and 4). Applied by hand, one at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-answer-outbox.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for every one. Every find string occurs exactly once.
# The phone's other promises are pwa-phone-core.psd1's.
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "nothing-is-kept"
           Find = 'if (Array.isArray(v.receipts)) await keepAnswer('
           Replace = 'if (false) await keepAnswer(' }
        @{ Name = "kept-for-a-machine-that-never-confirms"
           Find = 'if (Array.isArray(v.receipts)) await keepAnswer('
           Replace = 'if (true) await keepAnswer(' }
        @{ Name = "his-words-are-kept-as-text"
           Find = 'sealed: { enc: P.b64u(sealed.enc), box: P.b64u(sealed.sealed) }, seqs: [env.seq]'
           Replace = 'text: a.text, sealed: { enc: P.b64u(sealed.enc), box: P.b64u(sealed.sealed) }, seqs: [env.seq]' }
        @{ Name = "a-resend-seq-is-not-recorded"
           Find = 'seqs: items[i].seqs.concat([env.seq])'
           Replace = 'seqs: items[i].seqs' }
        @{ Name = "settled-answers-stay-kept"
           Find = 'if (settled.length) await store.update('
           Replace = 'if (false) await store.update(' }
        @{ Name = "the-rate-limit-is-not-written"
           Find = '(i.answerId === item.answerId ? { ...i, lastResendAt: now() } : i)'
           Replace = 'i' }
        @{ Name = "a-missing-answer-is-put-again-as-the-same-envelope"
           Find = 'if (st.resend === "reput") {'
           Replace = 'if (true) {' }
        @{ Name = "an-unseen-answer-is-signed-again"
           Find = 'if (st.resend === "reput") {'
           Replace = 'if (false) {' }
        @{ Name = "a-session-that-cannot-sign-signs"
           Find = 'if (st.resend === "resign" && s.mode !== "passkey") continue;'
           Replace = '' }
        @{ Name = "the-snapshot-time-is-not-kept"
           Find = 'relaySeq: item.seq, ts: o.value.header.ts, page: page.value'
           Replace = 'relaySeq: item.seq, page: page.value' }
        @{ Name = "forget-leaves-the-outbox"
           Find = 'await store.delete(ENTRY + id); await store.delete(OUTBOX + id);'
           Replace = 'await store.delete(ENTRY + id);' }
    )
}
