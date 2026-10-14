# Mutations of the one lane card (surfaces/pwa/page/lane-card.js), shared by every page of the phone. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-lane-card.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10e). Every find string
# occurs exactly once.
@{
    Target = "surfaces\pwa\page\lane-card.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "the-slot-is-only-made-when-filled"
           Find = '  head.appendChild(slot);'
           Replace = '  if (slot.textContent || badge) head.appendChild(slot);' }
        @{ Name = "the-badge-is-dropped"
           Find = 'if (typeof badge === "string") slot.textContent = badge; else slot.appendChild(badge);'
           Replace = 'if (typeof badge === "string") slot.textContent = badge;' }
        @{ Name = "the-tap-is-not-the-pages"
           Find = 'box.addEventListener("click", () => onOpen({ lane: v.lane, machine: v.machine, entry: v.entry }));'
           Replace = 'box.addEventListener("click", () => onOpen({ lane: v.lane, machine: v.machine }));' }
        @{ Name = "a-lane-of-another-machine-is-drawn"
           Find = 'const c = (lanes.cards || []).find((x) => x.lane === laneId && (!machine || x.machine === machine));'
           Replace = 'const c = (lanes.cards || []).find((x) => x.lane === laneId);' }
        @{ Name = "the-thrall-is-not-lane-thrall"
           Find = 'export const THRALL_LANE = "thrall";'
           Replace = 'export const THRALL_LANE = "Thrall";' }
    )
}
