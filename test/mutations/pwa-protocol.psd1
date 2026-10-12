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
        @{ Name = "time-shown-in-utc-not-local"
           Find = 'const d = new Date(ms - off * 60000);'
           Replace = 'const d = new Date(ms);' }
        @{ Name = "time-zone-sign-flipped"
           Find = 'const east = -p.offsetMinutes, a = Math.abs(east);'
           Replace = 'const east = p.offsetMinutes, a = Math.abs(east);' }
        @{ Name = "no-time-shown-as-1970"
           Find = 'if (!Number.isSafeInteger(ms) || ms <= 0) return null;'
           Replace = 'if (!Number.isSafeInteger(ms)) return null;' }
        @{ Name = "time-with-no-zone-taken"
           Find = 'if (typeof text !== "string" || !ISO_TIME.test(text)) return 0;'
           Replace = 'if (typeof text !== "string") return 0;' }
        @{ Name = "day-divider-on-every-item"
           Find = 'if (key && key !== last) { out.push('
           Replace = 'if (key) { out.push(' }
        @{ Name = "day-divider-for-a-thing-with-no-time"
           Find = 'if (key && key !== last) { out.push({ kind: "day", key, label: dayLabel(it.said, offsetMinutes) }); last = key; }'
           Replace = 'if (key !== last) { out.push({ kind: "day", key, label: dayLabel(it.said, offsetMinutes) }); last = key; }' }
        @{ Name = "exact-time-without-seconds"
           Find = 'two(p.hour) + ":" + two(p.minute) + ":" + two(p.second) + " (" + zone + ")"'
           Replace = 'two(p.hour) + ":" + two(p.minute) + " (" + zone + ")"' }
        @{ Name = "turn-time-not-shown"
           Find = 'said: timeOf(t.time), saidHow: "turn", order: g.seq });'
           Replace = 'said: 0, saidHow: "turn", order: g.seq });' }
        @{ Name = "receipt-envelope-time-shown-as-when-he-said-it"
           Find = 'const said = r.sentAt || (had ? had.said : 0);'
           Replace = 'const said = r.sentAt || (had ? had.said : 0) || r.ts;' }
        @{ Name = "signed-send-time-dropped-from-the-receipt"
           Find = 'sentAt: Number.isSafeInteger(b.sentAt) && b.sentAt > 0 ? b.sentAt : 0 } };'
           Replace = 'sentAt: 0 } };' }
        @{ Name = "receipt-time-of-any-shape-taken"
           Find = 'sentAt: Number.isSafeInteger(b.sentAt) && b.sentAt > 0 ? b.sentAt : 0 } };'
           Replace = 'sentAt: b.sentAt || 0 } };' }
        @{ Name = "delivered-time-replaces-the-signed-one"
           Find = 'if (!had.said) { had.said = timeOf(t.time); had.saidHow = "delivered"; }'
           Replace = 'had.said = timeOf(t.time); had.saidHow = "delivered";' }
        @{ Name = "delivered-line-with-no-time"
           Find = 'said: timeOf(t.time), saidHow: "delivered", session: t.session'
           Replace = 'said: 0, saidHow: "delivered", session: t.session' }
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
        @{ Name = "offer-without-a-grant-read"
           Find = 'if (typeof o.grant !== "string" || !/^[A-Za-z0-9_-]{86}$/.test(o.grant)) return no('
           Replace = 'if (false) return no(' }
        @{ Name = "high-s-machine-signature-taken"
           Find = 'if (BigInt("0x" + hex(sig.slice(32))) > P256_HALF_ORDER) return false;'
           Replace = '' }
        @{ Name = "grant-unbound-to-its-expiry"
           Find = 'machine + "\n" + expiresAt + "\n" + label); }'
           Replace = 'machine + "\n" + "\n" + label); }' }
        @{ Name = "grant-unbound-to-its-label"
           Find = 'expiresAt + "\n" + label); }'
           Replace = 'expiresAt + "\n"); }' }
        @{ Name = "offer-label-unchecked"
           Find = 'if (!validLabel(o.label)) return no('
           Replace = 'if (false) return no(' }
    )
}
