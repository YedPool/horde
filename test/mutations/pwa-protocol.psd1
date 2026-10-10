# Mutations of relay/js/protocol.js, the phone's side of the relay protocol, shared by the phone app
# and the test phone. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-protocol.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each: its module checks run the protocol of a
# built site against machines made in JavaScript. Every find string occurs exactly once.
#
# NOT HERE, and why: the check that an envelope's sender is the paired machine (a forged sender is
# refused by the signature check under the pinned key all the same, so dropping it is invisible -
# it is the second layer), and the strings the machine alone compares (the pairing fingerprint's
# domain, the vouch's): test\test-relay-phone-e2e.ps1 and surfaces\pwa\test\test-pwa-phone-e2e.ps1
# put those through the real machine.
@{
    Target = "relay\js\protocol.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "machine-signature-not-checked"
           Find = 'if (!verified) return no("the machine''s signature does not verify");'
           Replace = 'if (false) return no("the machine''s signature does not verify");' }
        @{ Name = "non-canonical-envelope-taken"
           Find = '"}}'' !== text) return no("not canonical, or not signed ES256");'
           Replace = '"}}'' !== text && false) return no("not canonical, or not signed ES256");' }
        @{ Name = "base64url-stray-bits-taken"
           Find = 'if (bits > 0 && (acc & ((1 << bits) - 1)) !== 0) throw'
           Replace = 'if (false) throw' }
        @{ Name = "incomplete-snapshot-drawn"
           Find = 'if (g.byNumber.size !== g.pages) continue;'
           Replace = 'if (g.byNumber.size === 0) continue;' }
        @{ Name = "older-snapshot-wins"
           Find = 'if (best && best.seq >= g.seq) continue;'
           Replace = 'if (best && best.seq <= g.seq) continue;' }
        @{ Name = "answer-members-reordered"
           Find = 'JSON.stringify({ v: 1, answerId, machine, snapshot, number, wordingVersion, text })'
           Replace = 'JSON.stringify({ v: 1, machine, answerId, snapshot, number, wordingVersion, text })' }
        @{ Name = "hpke-kem-label-wrong"
           Find = 'labeledExtract(new Uint8Array(0), KEM_ID, "eae_prk", dh)'
           Replace = 'labeledExtract(new Uint8Array(0), KEM_ID, "eae-prk", dh)' }
        @{ Name = "offer-code-unchecked"
           Find = 'if (typeof o.code !== "string" || !/^[A-Za-z0-9_-]{16,128}$/.test(o.code)) return no('
           Replace = 'if (false) return no(' }
        @{ Name = "offer-id-unchecked"
           Find = 'if (typeof o.offer !== "string" || !/^[0-9a-f]{32}$/.test(o.offer)) return no('
           Replace = 'if (false) return no(' }
        @{ Name = "expired-offer-taken"
           Find = 'if (now >= o.expiresAt) return no('
           Replace = 'if (false) return no(' }
        @{ Name = "chat-receipt-any-code-shown"
           Find = 'if (!Object.prototype.hasOwnProperty.call(CHAT_WORDS, b.status) || !Object.prototype.hasOwnProperty.call(CHAT_WORDS[b.status], b.code)) return'
           Replace = 'if (false) return' }
        @{ Name = "chat-receipt-words-not-shown"
           Find = 'text: r.text, at: had && had.at ? had.at : r.ts'
           Replace = 'text: had ? had.text : r.text, at: had && had.at ? had.at : r.ts' }
        @{ Name = "chat-founder-turn-shown-twice"
           Find = 'if (t.role === "founder") {'
           Replace = 'if (false) {' }
        @{ Name = "chat-founder-turn-without-line-kept"
           Find = '(t.role !== "founder" || (typeof t.line === "string" && /^[0-9a-f]{32}$/.test(t.line))) &&'
           Replace = 'true &&' }
        @{ Name = "chat-turn-shown-before-its-parts"
           Find = 'if (g.parts.size !== n) continue;'
           Replace = 'if (g.parts.size === 0) continue;' }
        @{ Name = "chat-other-machine-read"
           Find = 'if (b.horde !== horde || b.machine !== machine) return { error: "the chat body names another horde or machine" };'
           Replace = 'if (b.horde !== horde) return { error: "the chat body names another horde or machine" };' }
        @{ Name = "chat-role-off-the-list-kept"
           Find = 'CHAT_ROLES.indexOf(t.role) >= 0 &&'
           Replace = 'true &&' }
        @{ Name = "chat-line-unbound-to-session"
           Find = 'return utf8(JSON.stringify({ v: 1, messageId, horde, machine, session, text }));'
           Replace = 'return utf8(JSON.stringify({ v: 1, messageId, horde, machine, session: "any", text }));' }
        @{ Name = "pairing-mailbox-not-checked"
           Find = 'if (typeof o.pairMailbox !== "string" || o.pairMailbox !== o.horde + "/pair-" + o.offer) return no('
           Replace = 'if (typeof o.pairMailbox !== "string") return no(' }
        @{ Name = "sealed-response-not-bound-to-offer"
           Find = 'aad\n" + offer.horde + "\n" + offer.offer + "\n" + kid)'
           Replace = 'aad\n" + offer.horde + "\n" + kid)' }
        @{ Name = "sealed-response-not-bounded"
           Find = '|| responseText.length > PAIRING_LIMITS.maxResponseChars) throw'
           Replace = ') throw' }
    )
}
