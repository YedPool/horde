# Mutations of the photo's bytes on the wire (relay/js/protocol.js, photos in the chat). Applied by hand,
# one at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-photo-protocol.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for every one. Every find string occurs exactly once. The
# machine reads the same bytes in test\test-relay-chat-photos.ps1 and surfaces\pwa\test\test-pwa-phone-e2e.ps1.
@{
    Target = "relay\js\protocol.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "sniff-takes-anything"
           Find = '  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "jpeg";'
           Replace = '  if (bytes.length >= 3) return "jpeg";' }
        @{ Name = "part-digest-of-the-plain-bytes"
           Find = '    const digest = hex(await sha256(ct));'
           Replace = '    const digest = hex(await sha256(chunk));' }
        # The relay key names the part's digest, so junk put first cannot squat it (review of PR 285).
        @{ Name = "part-key-without-its-digest"
           Find = '  return from + "/photo-part/" + photoId + "/" + n + "/" + digest.slice(0, 16);'
           Replace = '  return from + "/photo-part/" + photoId + "/" + n;' }
        @{ Name = "part-aad-without-its-number"
           Find = 'utf8(PHOTO_PART_AAD + "\n" + from + "\n" + photoId + "\n" + n), chunk);'
           Replace = 'utf8(PHOTO_PART_AAD + "\n" + from + "\n" + photoId + "\n" + 1), chunk);' }
        # Review of PR 285: the window a photo names, and how many wait for a word.
        @{ Name = "photo-window-longer-than-the-machine"
           Find = 'Math.min(PHOTO_WINDOW_MS, machineWindowMs)'
           Replace = 'PHOTO_WINDOW_MS' }
        @{ Name = "photo-window-not-read"
           Find = 'const photoWindowMs = Number.isSafeInteger(b.photoWindowMs) && b.photoWindowMs > 0 ? b.photoWindowMs : 0;'
           Replace = 'const photoWindowMs = 0;' }
        @{ Name = "photos-waiting-counts-answered"
           Find = '!answered.has(p.photoId) && '
           Replace = '' }
        @{ Name = "photos-waiting-counts-late"
           Find = ' && !(Number.isSafeInteger(p.expiresAt) && now >= p.expiresAt)).length;'
           Replace = ').length;' }
        @{ Name = "photo-manifest-resend-unchecked"
           Find = '  if (resendOf !== "" && !(typeof resendOf === "string" && /^[0-9a-f]{32}$/.test(resendOf) && resendOf !== photoId)) throw new Error("resendOf is the 32 lower-case hex id of another photo");'
           Replace = '' }
        @{ Name = "photo-manifest-resend-dropped"
           Find = '  if (resendOf !== "") body.resendOf = resendOf;'
           Replace = '' }
        @{ Name = "photo-receipt-takes-any-code"
           Find = '  if (!Object.prototype.hasOwnProperty.call(PHOTO_WORDS, b.status) || !Object.prototype.hasOwnProperty.call(PHOTO_WORDS[b.status], b.code)) return { ok: false, reason: "the photo receipt''s status or code is not one this phone knows", value: null };'
           Replace = '' }
        @{ Name = "photo-receipt-file-unchecked"
           Find = '  const file = typeof b.file === "string" && /^[A-Za-z0-9._-]{0,80}$/.test(b.file) ? b.file : "";'
           Replace = '  const file = String(b.file || "");' }
        @{ Name = "turns-photo-offer-dropped"
           Find = '  const photoBytes = Number.isSafeInteger(b.photoBytes) && b.photoBytes > 0 ? b.photoBytes : 0;'
           Replace = '  const photoBytes = 0;' }
        # THE HOUR (the founder's choice, 2026-10-16).
        @{ Name = "photo-window-five-minutes"
           Find = 'export const PHOTO_WINDOW_MS = 3600000;'
           Replace = 'export const PHOTO_WINDOW_MS = 300000;' }
        @{ Name = "photo-never-late"
           Find = '    const late = Number.isSafeInteger(p.expiresAt) && now >= p.expiresAt;'
           Replace = '    const late = false;' }
        @{ Name = "photo-late-a-moment-early"
           Find = '    const late = Number.isSafeInteger(p.expiresAt) && now >= p.expiresAt;'
           Replace = '    const late = Number.isSafeInteger(p.expiresAt) && now >= p.expiresAt - 1000;' }
        @{ Name = "photo-waiting-said-as-sending"
           Find = 'words: late ? PHOTO_NOT_DELIVERED : p.sent ? PHOTO_WAITING : PHOTO_SENDING,'
           Replace = 'words: late ? PHOTO_NOT_DELIVERED : PHOTO_SENDING,' }
        @{ Name = "photo-receipt-never-sent-again"
           Find = 'sendAgain: r.status === "refused" && PHOTO_SEND_AGAIN.indexOf(r.code) >= 0,'
           Replace = 'sendAgain: false,' }
        @{ Name = "photo-receipt-any-refusal-sent-again"
           Find = 'sendAgain: r.status === "refused" && PHOTO_SEND_AGAIN.indexOf(r.code) >= 0,'
           Replace = 'sendAgain: r.status === "refused",' }
    )
}
