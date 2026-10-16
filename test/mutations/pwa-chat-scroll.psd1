# Mutations of surfaces/pwa/page/chat-scroll.js, where the Chat tab stands in its log and its Jump to
# latest button (the founder, 2026-10-15). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-chat-scroll.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10i). Every find string
# occurs exactly once.
@{
    Target = "surfaces\pwa\page\chat-scroll.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "stick-threshold-zero"
           Find = 'export const STICK_PX = 48;'
           Replace = 'export const STICK_PX = 0;' }
        @{ Name = "stick-threshold-edge-excluded"
           Find = 'return distanceFromBottom(m) <= threshold;'
           Replace = 'return distanceFromBottom(m) < threshold;' }
        @{ Name = "jump-shown-at-the-bottom"
           Find = 'return !nearBottom(m, threshold);'
           Replace = 'return true;' }
        @{ Name = "refresh-yanks-him-down"
           Find = 'return s.near === true ? "bottom" : "keep";'
           Replace = 'return "bottom";' }
        @{ Name = "opening-keeps-the-inherited-place"
           Find = 'if (s.opening === true) return "bottom";'
           Replace = '' }
        @{ Name = "place-not-kept-when-the-anchor-moves"
           Find = 'return Math.max(0, scrollTop + (anchorAfter - anchorBefore));'
           Replace = 'return scrollTop;' }
        @{ Name = "new-count-not-on-the-button"
           Find = 'return count > 0 ? "Jump to latest (" + count + " new)" : "Jump to latest";'
           Replace = 'return "Jump to latest";' }
        @{ Name = "news-said-on-every-refresh"
           Find = 'if (!(after > before)) return null;'
           Replace = '' }
    )
}
