# Mutations of the page showing the line for what a snapshot leaves out (surfaces/pwa/page/app.js, THE
# LIST IS SHORTER THAN THE MACHINE'S, AND SAYS SO; 2026-10-14). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-withheld-line-page.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 must fail for each: it is the suite that has a page. Every find
# string occurs exactly once. The page's other promises are pwa-app.psd1's (a spec of its own:
# CONTRIBUTING 15).
@{
    Target = "surfaces\pwa\page\app.js"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-line-is-never-shown"
           Find = '$("notShown").hidden = !notShown;'
           Replace = '$("notShown").hidden = true;' }
        @{ Name = "the-line-is-shown-with-no-words"
           Find = '$("notShown").textContent = notShown;'
           Replace = '' }
        @{ Name = "the-line-stays-after-a-whole-snapshot"
           Find = '$("notShown").hidden = !notShown;'
           Replace = 'if (notShown) $("notShown").hidden = false;' }
    )
}
