# Mutations of surfaces/pwa/page/app.css: the bar that keeps the way between Decisions and Chat on the
# screen (the founder's first live use, 2026-10-11). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-app-css.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 (headless Chrome) must fail for it. The find string occurs once.
@{
    Target = "surfaces\pwa\page\app.css"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "progress-foot-scrolls-away"
           Find = '#progressFoot { position: fixed;'
           Replace = '#progressFoot { position: static;' }
        @{ Name = "progress-title-not-bold"
           Find = '.progress-title { font-weight: 600;'
           Replace = '.progress-title { font-weight: 400;' }
        @{ Name = "bar-scrolls-away"
           Find = '#bar { position: sticky;'
           Replace = '#bar { position: static;' }
        # A stream's entries folded to one line (the founder asked, 2026-10-14; test-pwa-browser section 12b).
        @{ Name = "progress-folded-entry-shows-everything"
           Find = '.progress-item.collapsed > :not(.progress-line) { display: none; }'
           Replace = '' }
        @{ Name = "progress-folded-long-title-wraps"
           Find = 'margin: 0; white-space: nowrap;'
           Replace = 'margin: 0; white-space: normal;' }
        @{ Name = "progress-open-entry-shows-two-times"
           Find = '.progress-item:not(.collapsed) .progress-when { display: none; }'
           Replace = '' }
    )
}
