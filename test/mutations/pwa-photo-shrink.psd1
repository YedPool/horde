# Mutations of the phone's shrink and its text-or-photo heuristic (surfaces/pwa/page/photo.js). Applied by
# hand, one at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-photo-shrink.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\photo.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "shrink-text-like-without-edges"
           Find = '  return { textLike: flat >= 0.5 && edges >= 0.02, flat, edges };'
           Replace = '  return { textLike: flat >= 0.5, flat, edges };' }
        @{ Name = "shrink-text-like-without-flat"
           Find = '  return { textLike: flat >= 0.5 && edges >= 0.02, flat, edges };'
           Replace = '  return { textLike: edges >= 0.02, flat, edges };' }
        @{ Name = "shrink-text-gets-the-photo-size"
           Find = '  const cap = textLike ? PHOTO_TEXT_SIDE : PHOTO_SIDE;'
           Replace = '  const cap = PHOTO_SIDE;' }
        @{ Name = "shrink-photo-gets-the-text-size"
           Find = '  const cap = textLike ? PHOTO_TEXT_SIDE : PHOTO_SIDE;'
           Replace = '  const cap = PHOTO_TEXT_SIDE;' }
        @{ Name = "shrink-enlarges"
           Find = '  if (long <= cap) return { width, height };'
           Replace = '' }
        @{ Name = "shrink-byte-cap-ignored"
           Find = '      if (bytes.length <= maxBytes) return {'
           Replace = '      if (true) return {' }
        @{ Name = "shrink-any-format-out"
           Find = '      if (!isJpeg(bytes)) throw new Error("The phone could not make a JPEG of this picture.");'
           Replace = '' }
    )
}
