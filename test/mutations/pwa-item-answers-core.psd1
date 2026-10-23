# Mutations of the founder's answer to a published item in the phone core (surfaces/pwa/page/phone-core.js, answerItem; T-0352). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-item-answers-core.psd1
# surfaces\pwa\test\test-pwa-site.ps1 (its units) must fail for every one. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\phone-core.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "an-item-the-phone-does-not-hold-can-be-answered"
           Find = 'if (!list || !list.items.some((it) => it.position === index)) throw fail('
           Replace = 'if (false) throw fail(' }
        @{ Name = "a-recovery-unlock-can-answer"
           Find = 'if (s.mode !== "passkey") throw fail("Read only: this horde was unlocked with the recovery code, which cannot sign. Unlock with the passkey to answer an item.");'
           Replace = '' }
        @{ Name = "other-words-under-one-answer-id-are-sent"
           Find = 'if (s.chat.itemSent.some((x) => x.messageId === messageId && (x.text !== text || x.snapshot !== snapshot || x.index !== index))) throw fail('
           Replace = 'if (false) throw fail(' }
        @{ Name = "the-receipts-are-dropped"
           Find = 'c.itemReceipts.push({ ...r.value, seq: h.seq, ts: h.ts });'
           Replace = '' }
        @{ Name = "an-answer-is-sealed-as-a-line"
           Find = 'const env = await sealAndSign(e, "answer", "chat", body, assertWith(e));'
           Replace = 'const env = await sealAndSign(e, "line", "chat", body, assertWith(e));' }
        @{ Name = "the-refresh-hands-on-no-answers"
           Find = 'itemAnswers: [...P.itemAnswerView({ sent: s.chat.itemSent, receipts: s.chat.itemReceipts })],'
           Replace = 'itemAnswers: [],' }
        @{ Name = "a-sent-answer-is-not-remembered"
           Find = 'if (!s.chat.itemSent.some((x) => x.messageId === messageId)) s.chat.itemSent.push({ messageId, lane, snapshot, index, text, at: env.ts });'
           Replace = '' }
    )
}
