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
           Find = 'if (st.resend === "resign" && s.mode !== "passkey") { cannot += 1; continue; }'
           Replace = '' }
        @{ Name = "the-snapshot-time-is-not-kept"
           Find = 'relaySeq: item.seq, ts: o.value.header.ts, page: page.value'
           Replace = 'relaySeq: item.seq, page: page.value' }
        @{ Name = "forget-leaves-the-outbox"
           Find = 'await store.delete(OUTBOX + id); await store.delete(ENTRY + id);'
           Replace = 'await store.delete(ENTRY + id);' }
        # --- the review of PR 262
        @{ Name = "two-windows-take-one-seq"
           Find = 'if ((counts[channel] || 0) >= seq) return e;'
           Replace = '' }
        @{ Name = "the-seq-is-spent-before-the-passkey-signs"
           Find = 'const text = await P.signEnvelope(parts, assert);'
           Replace = 'await claimSeq(e.id, channel, seq); const text = await P.signEnvelope(parts, assert); return { text, key: P.replayKey(parts.header), ts: parts.header.ts, seq };' }
        @{ Name = "an-older-answer-stays-beside-the-newer"
           Find = '.filter((y) => y.answerId === a.answerId || slotOf(y.number, y.part) !== slot)'
           Replace = '' }
        @{ Name = "an-answer-that-is-not-his-latest-is-sent-again"
           Find = 'Number(i.signedAt || i.sentAt) > Number(item.signedAt || item.sentAt))) continue;'
           Replace = 'false)) continue;' }
        @{ Name = "signed-again-under-the-time-of-now"
           Find = 'assertWith(e), Number(item.signedAt || item.sentAt));'
           Replace = 'assertWith(e));' }
        @{ Name = "every-missing-answer-is-a-prompt-at-once"
           Find = 'if (st.resend === "resign" && (!sign || signed >= 1)) continue;'
           Replace = 'if (st.resend === "resign" && !sign) continue;' }
        @{ Name = "a-hidden-page-signs-again"
           Find = 'if (st.resend === "resign" && (!sign || signed >= 1)) continue;'
           Replace = 'if (st.resend === "resign" && signed >= 1) continue;' }
        @{ Name = "a-recovery-session-says-nothing"
           Find = 'if (cannot) problems.push('
           Replace = 'if (false) problems.push(' }
        @{ Name = "unreadable-words-leave-the-question-empty"
           Find = 'const a = { answerId: item.answerId, number: item.number, part: item.part, text, unreadable: text === null,'
           Replace = 'if (text === null) continue; const a = { answerId: item.answerId, number: item.number, part: item.part, text, unreadable: text === null,' }
        @{ Name = "a-full-outbox-takes-one-more"
           Find = 'if (held.length >= OUTBOX_MOST) throw fail('
           Replace = 'if (false) throw fail(' }
        @{ Name = "the-one-stuck-re-sign-is-not-remembered"
           Find = 'stuckResent: items[i].stuckResent === true || stuck'
           Replace = 'stuckResent: false' }
    )
}
