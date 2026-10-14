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
        @{ Name = "photo-receipt-takes-any-code"
           Find = '  if (!Object.prototype.hasOwnProperty.call(PHOTO_WORDS, b.status) || !Object.prototype.hasOwnProperty.call(PHOTO_WORDS[b.status], b.code)) return { ok: false, reason: "the photo receipt''s status or code is not one this phone knows", value: null };'
           Replace = '' }
        @{ Name = "photo-receipt-file-unchecked"
           Find = '  const file = typeof b.file === "string" && /^[A-Za-z0-9._-]{0,80}$/.test(b.file) ? b.file : "";'
           Replace = '  const file = String(b.file || "");' }
        @{ Name = "turns-photo-offer-dropped"
           Find = '  const photoBytes = Number.isSafeInteger(b.photoBytes) && b.photoBytes > 0 ? b.photoBytes : 0;'
           Replace = '  const photoBytes = 0;' }
    )
}
