# Mutations of surfaces/pwa/page/bar-height.js, the bar's measured height (the founder, 2026-10-20). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-bar-offset-height.psd1
# test\test-pwa-bar-offset-browser.ps1 (headless Chrome) must fail for each. Every find string occurs exactly once.
@{
    Target = "surfaces\pwa\page\bar-height.js"
    Suite  = "test\test-pwa-bar-offset-browser.ps1"
    Mutations = @(
        @{ Name = "bar-height-never-set"
           Find = 'const set = () => root.style.setProperty("--bar-h", Math.ceil(bar.getBoundingClientRect().height) + "px");'
           Replace = 'const set = () => {};' }
        @{ Name = "bar-height-not-followed"
           Find = 'watcher.observe(bar);'
           Replace = '' }
        @{ Name = "bar-height-rounded-down"
           Find = 'Math.ceil(bar.getBoundingClientRect().height)'
           Replace = 'Math.floor(bar.getBoundingClientRect().height) - 40' }
        @{ Name = "newest-top-never-brought-below-the-bar"
           Find = 'if (newest && newest.getBoundingClientRect().top < barBottom) newest.scrollIntoView({ block: "start", behavior: "instant" });'
           Replace = '' }
        @{ Name = "newest-compared-with-the-window-top"
           Find = 'newest.getBoundingClientRect().top < barBottom'
           Replace = 'newest.getBoundingClientRect().top < 0' }
        @{ Name = "newest-brought-to-the-foot-not-the-top"
           Find = 'newest.scrollIntoView({ block: "start", behavior: "instant" });'
           Replace = 'newest.scrollIntoView({ block: "end", behavior: "instant" });' }
    )
}
