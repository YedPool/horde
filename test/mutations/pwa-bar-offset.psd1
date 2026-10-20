# Mutations of surfaces/pwa/page/chat-scroll.js, where Jump to latest brings the newest message into view (the founder, 2026-10-20). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-bar-offset.psd1
# test\test-pwa-bar-offset-browser.ps1 (headless Chrome) must fail for each. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\chat-scroll.js"
    Suite  = "test\test-pwa-bar-offset-browser.ps1"
    Mutations = @(
        @{ Name = "arrival-follow-forgets-the-tall-newest"
           Find = 'near: caughtUp(metrics())'
           Replace = 'near: nearBottom(metrics())' }
        @{ Name = "jump-button-ignores-the-newest-top"
           Find = 'return !caughtUp(m, threshold);'
           Replace = 'return !nearBottom(m, threshold);' }
        @{ Name = "caught-up-ignores-the-bar"
           Find = 'm.newestTop >= m.barBottom && m.newestTop < m.composeTop'
           Replace = 'm.newestTop < m.composeTop' }
        @{ Name = "caught-up-whenever-the-top-is-below-the-bar"
           Find = 'm.newestTop >= m.barBottom && m.newestTop < m.composeTop'
           Replace = 'm.newestTop >= m.barBottom' }
        @{ Name = "arrival-always-follows"
           Find = 'return s.near === true ? "bottom" : "keep";'
           Replace = 'return "bottom";' }
    )
}
