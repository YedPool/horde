# Mutations of surfaces/pwa/page/app.css: the bar that keeps the way between Decisions and Chat on the
# screen (the founder's first live use, 2026-10-11). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-app-css.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 (headless Chrome) must fail for it. The find string occurs once.
@{
    Target = "surfaces\pwa\page\app.css"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "bar-scrolls-away"
           Find = '#bar { position: sticky;'
           Replace = '#bar { position: static;' }
    )
}
