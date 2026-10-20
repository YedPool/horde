# Mutations of surfaces/pwa/page/chat-scroll.js, where Jump to latest brings the newest message into view (the founder, 2026-10-20). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-bar-offset.psd1
# test\test-pwa-bar-offset-browser.ps1 (headless Chrome) must fail for each. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\chat-scroll.js"
    Suite  = "test\test-pwa-bar-offset-browser.ps1"
    Mutations = @(
        @{ Name = "newest-not-brought-below-the-bar"
           Find = 'if (newest && newest.getBoundingClientRect().top < topInset()) newest.scrollIntoView({ block: "start", behavior: "instant" });'
           Replace = '' }
        @{ Name = "newest-compared-with-the-window-top-not-the-bar"
           Find = 'newest.getBoundingClientRect().top < topInset()'
           Replace = 'newest.getBoundingClientRect().top < 0' }
        @{ Name = "newest-brought-to-the-foot-not-the-top"
           Find = 'newest.scrollIntoView({ block: "start", behavior: "instant" });'
           Replace = 'newest.scrollIntoView({ block: "end", behavior: "instant" });' }
    )
}
