# Mutations of what the phone makes of the receipts (relay/js/protocol.js, WHAT BECAME OF EACH ANSWER; the
# founder, 2026-10-14, relay fixes 3 and 4): each answer's state, when it is sent again, the warning, and
# the answers drawn into the list so a pending one stands answered. Applied by hand, one at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-answer-receipts.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for every one. Every find string occurs exactly once.
# The protocol's other promises are pwa-protocol.psd1's.
@{
    Target = "relay\js\protocol.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "applied-is-never-seen"
           Find = 'if (r.applied.has(item.answerId)) state = "applied";'
           Replace = 'if (false) state = "applied";' }
        @{ Name = "refused-is-never-seen"
           Find = 'else if (r.refused.has(item.answerId)) state = "refused";'
           Replace = 'else if (false) state = "refused";' }
        @{ Name = "a-missing-seq-counts-as-received"
           Find = 's >= r.checked && !r.missing.has(s);'
           Replace = 's >= r.checked;' }
        @{ Name = "a-missing-answer-is-never-signed-again"
           Find = 'const lost = (s) => r.missing.has(s) ||'
           Replace = 'const lost = (s) => false ||' }
        @{ Name = "an-unseen-answer-is-put-again-without-the-grace"
           Find = 'newest > r.through && Number(receiptTs) > Number(item.lastSentAt) + ANSWER_TAIL_GRACE_MS'
           Replace = 'newest > r.through' }
        @{ Name = "resends-are-not-rate-limited"
           Find = 'const due = resend !== "" && now - last >= ANSWER_RESEND_MS;'
           Replace = 'const due = resend !== "";' }
        @{ Name = "the-rate-limit-forgets-a-resend-that-made-no-envelope"
           Find = 'const last = Math.max(Number(item.lastSentAt) || 0, Number(item.lastResendAt) || 0);'
           Replace = 'const last = Number(item.lastSentAt) || 0;' }
        @{ Name = "no-warning-ever"
           Find = 'const warning = (state === "sent" || state === "received") && now - Number(item.sentAt) > ANSWER_WARN_MS;'
           Replace = 'const warning = false;' }
        @{ Name = "a-receipt-is-trusted-whatever-it-holds"
           Find = '|| !ids(r.applied) || !ids(r.refused)) return null;'
           Replace = ') return null;' }
        @{ Name = "another-phones-receipt-is-read"
           Find = 'if (r.from !== from) continue;'
           Replace = '' }
        @{ Name = "a-pending-answer-is-not-drawn"
           Find = 'messages.push(m);'
           Replace = '' }
        @{ Name = "an-applied-answer-is-drawn-twice"
           Find = 'for (const a of mine.filter((x) => x.state !== "applied").sort('
           Replace = 'for (const a of mine.sort(' }
        @{ Name = "the-warning-is-not-drawn"
           Find = '(a.warning ? ANSWER_WARNING : "")'
           Replace = '""' }
        # --- the review of PR 262
        @{ Name = "a-seq-below-checked-is-received"
           Find = 'const arrived = (s) => s <= r.through && s >= r.checked && !r.missing.has(s);'
           Replace = 'const arrived = (s) => s <= r.through && !r.missing.has(s);' }
        @{ Name = "a-seq-below-checked-is-never-sent-again"
           Find = 'const lost = (s) => r.missing.has(s) || (s <= r.through && s < r.checked);'
           Replace = 'const lost = (s) => r.missing.has(s);' }
        @{ Name = "a-receipt-silent-on-checked-vouches-for-everything"
           Find = 'r.checked <= r.through ? r.checked : r.through;'
           Replace = 'r.checked <= r.through ? r.checked : 0;' }
        @{ Name = "an-answer-stuck-at-received-is-never-signed-again"
           Find = 'if (state === "received" && receipt && item.stuckResent !== true && now'
           Replace = 'if (false && now' }
        @{ Name = "an-answer-stuck-at-received-is-signed-again-for-ever"
           Find = 'item.stuckResent !== true && '
           Replace = '' }
        @{ Name = "unreadable-words-draw-nothing"
           Find = 'a.unreadable || typeof a.text !== "string" ? ANSWER_UNREADABLE : a.text'
           Replace = 'a.text' }
    )
}
