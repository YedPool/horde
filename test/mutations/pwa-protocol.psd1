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
        @{ Name = "progress-ordered-by-time"
           Find = 'const ordered = [...byId.values()].sort((a, b) => (a.n - b.n) || (a.seq - b.seq));'
           Replace = 'const ordered = [...byId.values()].sort((a, b) => (a.at - b.at) || (a.seq - b.seq));' }
        @{ Name = "progress-ordered-by-arrival"
           Find = 'const ordered = [...byId.values()].sort((a, b) => (a.n - b.n) || (a.seq - b.seq));'
           Replace = 'const ordered = [...byId.values()];' }
        @{ Name = "progress-later-copy-of-an-entry-wins"
           Find = 'if (!had || e.seq < had.seq) byId.set(e.id, e);'
           Replace = 'byId.set(e.id, e);' }
        @{ Name = "progress-unknown-kind-shown-as-written"
           Find = 'Object.prototype.hasOwnProperty.call(PROGRESS_KINDS, e.kind) ? e.kind : "note", title'
           Replace = 'e.kind, title' }
        @{ Name = "progress-kind-looked-up-on-the-prototype"
           Find = 'Object.prototype.hasOwnProperty.call(PROGRESS_KINDS, e.kind) ? e.kind : "note", title'
           Replace = '(e.kind in PROGRESS_KINDS) ? e.kind : "note", title' }
        @{ Name = "progress-entry-id-not-checked"
           Find = 'typeof e.id === "string" && ENTRY_ID.test(e.id) &&'
           Replace = 'typeof e.id === "string" &&' }
        @{ Name = "progress-entry-line-number-not-checked"
           Find = 'Number.isSafeInteger(e.n) && e.n >= 1 &&'
           Replace = 'true &&' }
        @{ Name = "progress-entry-time-not-checked"
           Find = 'e.n >= 1 && timeOf(e.ts) > 0 &&'
           Replace = 'e.n >= 1 &&' }
        @{ Name = "progress-blank-title-shown"
           Find = 'e.title.trim() !== "" &&'
           Replace = 'true &&' }
        @{ Name = "progress-long-title-shown"
           Find = 'e.title.length <= PROGRESS_LIMITS.title &&'
           Replace = 'true &&' }
        @{ Name = "progress-long-text-shown"
           Find = 'e.text.length <= PROGRESS_LIMITS.text &&'
           Replace = 'true &&' }
        @{ Name = "progress-corrects-of-any-shape-taken"
           Find = '(typeof e.corrects === "string" && ENTRY_ID.test(e.corrects))'
           Replace = '(typeof e.corrects === "string")' }
        @{ Name = "progress-label-of-any-length-shown"
           Find = 'typeof v === "string" && v.length <= most && PLAIN.test(v) ? v : ""'
           Replace = 'typeof v === "string" ? v : ""' }
        @{ Name = "progress-of-another-machine-taken"
           Find = 'if (b.horde !== horde || b.machine !== machine) return { error: "the progress body names another horde or machine" };'
           Replace = '' }
        @{ Name = "progress-notice-of-any-code-taken"
           Find = 'if (!Object.prototype.hasOwnProperty.call(PROGRESS_WORDS, b.code)) return'
           Replace = 'if (false) return' }
        @{ Name = "progress-skipped-lines-not-counted"
           Find = 'if (n.code === "lines-skipped") skipped += n.count;'
           Replace = 'if (n.code === "lines-skipped") skipped += 1;' }
        @{ Name = "progress-stop-never-lifted"
           Find = 'stopped = n.code === "file-replaced"; }'
           Replace = 'stopped = stopped || n.code === "file-replaced"; }' }
        @{ Name = "progress-any-colon-is-a-label"
           Find = 'if (PROGRESS_LABELS.indexOf(name) >= 0) out.push('
           Replace = 'if (at > 0) out.push(' }
        @{ Name = "progress-empty-line-is-a-paragraph"
           Find = 'if (!line.trim()) continue;'
           Replace = '' }
        @{ Name = "progress-position-without-its-line-taken"
           Find = ' || !Number.isSafeInteger(value.n) || value.n < 1) return null;'
           Replace = ') return null;' }
        @{ Name = "progress-position-with-any-id-taken"
           Find = ' || !ENTRY_ID.test(value.id) ||'
           Replace = ' ||' }
        @{ Name = "progress-place-lost-with-its-entry"
           Find = 'if (readIndex < 0) for (let i = 0; i < items.length && items[i].n <= pos.n; i++) readIndex = i;'
           Replace = '' }
        @{ Name = "progress-unread-miscounted"
           Find = 'unread: items.length - 1 - readIndex,'
           Replace = 'unread: items.length - readIndex,' }
        @{ Name = "progress-correction-not-on-its-entry"
           Find = 'target.corrections.push({ id: it.id, said: it.said, title: it.title, paragraphs: it.paragraphs });'
           Replace = '' }
        @{ Name = "progress-entry-corrects-itself"
           Find = 'it.corrects && it.corrects !== it.id ? at.get(it.corrects) : null'
           Replace = 'it.corrects ? at.get(it.corrects) : null' }
        @{ Name = "progress-time-without-its-day"
           Find = 'p.day + " " + MONTHS[p.month] + " " + two(p.hour)'
           Replace = 'two(p.hour)' }
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
           Find = 'messageId: r.messageId, text: r.text, at: had'
           Replace = 'messageId: r.messageId, text: had ? had.text : r.text, at: had' }
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
        # --- one part's answer (2026-10-12) ---
        @{ Name = "a-part-of-any-spelling-is-written-into-the-body"
           Find = '  if (part !== "" && !/^[a-z]$/.test(part)) throw new Error("a part is one lower-case letter");'
           Replace = '' }
        @{ Name = "a-parts-answer-says-it-is-version-1"
           Find = '  if (part !== "") return utf8(JSON.stringify({ v: 2, answerId, machine, snapshot, number, wordingVersion, text, part }));'
           Replace = '  if (part !== "") return utf8(JSON.stringify({ v: 1, answerId, machine, snapshot, number, wordingVersion, text, part }));' }
        @{ Name = "a-parts-answer-leaves-the-part-out"
           Find = '  if (part !== "") return utf8(JSON.stringify({ v: 2, answerId, machine, snapshot, number, wordingVersion, text, part }));'
           Replace = '  if (part !== "") return utf8(JSON.stringify({ v: 2, answerId, machine, snapshot, number, wordingVersion, text }));' }
        @{ Name = "what-a-snapshot-says-of-answers-is-believed-as-it-is"
           Find = '      answers: Number.isSafeInteger(first.answers) && first.answers >= 1 ? first.answers : 1 };'
           Replace = '      answers: first.answers };' }
        @{ Name = "every-machine-is-taken-to-read-parts"
           Find = '      answers: Number.isSafeInteger(first.answers) && first.answers >= 1 ? first.answers : 1 };'
           Replace = '      answers: 2 };' }
    )
}
