# Mutations of decisions/window/frame.js, where the document and the fleet line are put together. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-frame.psd1
# test\e2e\e2e-decisions-window.ps1 must fail for each: a page script runs only inside a page, so the
# suite is the scenario that opens a real window and reads back what it drew (about half a minute a
# mutant; see test\mutations\decisions-page.psd1).
@{
    Target = "decisions\window\frame.js"
    Suite  = "test\e2e\e2e-decisions-window.ps1"
    Mutations = @(
        @{ Name = "letters-not-moved-to-whole-device-pixels"
           Find = 'function whole(px) { return (Math.round(px * ratio) / ratio) + "px"; }'
           Replace = 'function whole(px) { return (px * 0.95) + "px"; }' }
        @{ Name = "a-question-counted-twice-for-its-orc"
           Find = 'counts[key] = (counts[key] || 0) + 1;'
           Replace = 'counts[key] = (counts[key] || 0) + 2;' }
        @{ Name = "the-picked-orcs-questions-are-the-dimmed-ones"
           Find = 'return keysOf(q).indexOf(picked) < 0;'
           Replace = 'return keysOf(q).indexOf(picked) >= 0;' }
        @{ Name = "the-fleet-line-not-unfolded-when-asked"
           Find = 'if (view.fleetOpen) { fleet.setOpen(true); }'
           Replace = '' }
        @{ Name = "standing-free-is-not-said"
           Find = 'notices.attachment = (a && a.attached) ? "" : ('
           Replace = 'notices.attachment = (a) ? "" : (' }
        @{ Name = "the-family-is-not-the-settings"
           Find = 'root.style.setProperty("--font", setup.look.fontFamily);'
           Replace = 'root.style.setProperty("--font", "serif");' }
    )
}
