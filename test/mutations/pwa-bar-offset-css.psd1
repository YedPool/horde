# Mutations of surfaces/pwa/page/app.css, the scroll margin the cards carry (the founder, 2026-10-20). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-bar-offset-css.psd1
# test\test-pwa-bar-offset-browser.ps1 (headless Chrome) must fail for each. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\app.css"
    Suite  = "test\test-pwa-bar-offset-browser.ps1"
    Mutations = @(
        @{ Name = "no-scroll-margin"
           Find = 'scroll-margin-top: calc(var(--bar-h, 0px) + 8px);'
           Replace = 'scroll-margin-top: 0;' }
        @{ Name = "margin-ignores-the-bar"
           Find = 'calc(var(--bar-h, 0px) + 8px)'
           Replace = '8px' }
        @{ Name = "margin-not-on-the-questions"
           Find = '#chatLog > .chat-item, #lists .hd-q {'
           Replace = '#chatLog > .chat-item {' }
    )
}
