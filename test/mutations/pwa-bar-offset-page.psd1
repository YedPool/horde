# Mutations of surfaces/pwa/page/app.js, where app.js starts the bar's height tracker (the founder, 2026-10-20). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-bar-offset-page.psd1
# test\test-pwa-bar-offset-browser.ps1 (headless Chrome) must fail for each. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\app.js"
    Suite  = "test\test-pwa-bar-offset-browser.ps1"
    Mutations = @(
        @{ Name = "bar-not-tracked"
           Find = 'trackBarHeight($("bar"), document.documentElement);'
           Replace = '' }
    )
}
