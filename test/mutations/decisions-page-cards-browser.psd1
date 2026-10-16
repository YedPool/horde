# Mutations of decisions/page/list.js's LANES (ONE LANE AT A TIME): what is counted on the cards, the
# lane chosen, and the filter. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page-cards-browser.psd1
# test\test-decisions-page-browser.ps1 (headless Chrome, real touch events; its driver
# decisions\page\test\browser-cards.mjs) must fail for each. Each find string occurs once. The cards
# themselves (decision-cards.js) are test\mutations\pwa-decision-cards.psd1.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\test-decisions-page-browser.ps1"
    Mutations = @(
        @{ Name = "a-card-filters-nothing"
           Find = '        if (laneChosen && laneOf(q) !== laneChosen) { return; }'
           Replace = '' }
        @{ Name = "answered-questions-are-counted"
           Find = '    function toAnswer(q) { return sectionOf(q) === "main" && !stateOf(q).answered; }'
           Replace = '    function toAnswer(q) { return textOf(q.state) === LISTED_STATE; }' }
        @{ Name = "the-blocks-mark-is-never-set"
           Find = '      if (textOf(q.blocks) === BLOCKINGS[0]) { by[lane].blocksAll = true; }'
           Replace = '' }
        @{ Name = "a-question-that-names-nobody-has-a-lane-of-its-own"
           Find = '    return letter === "M" ? KEEPER_LANE : letter;'
           Replace = '    return letter;' }
        @{ Name = "the-lane-chosen-is-not-kept"
           Find = ' prefs.setItem(LANE_KEY, laneChosen);'
           Replace = '' }
        @{ Name = "the-lane-kept-is-not-read"
           Find = '    try { laneChosen = laneWord(prefs ? prefs.getItem(LANE_KEY) : ""); } catch (e) { laneChosen = ""; }'
           Replace = '' }
        @{ Name = "a-tap-on-a-card-leaves-the-list-off-screen"
           Find = '      if (orderBar.parentNode === root) { window.scrollBy(0, orderBar.getBoundingClientRect().top - topInset() - NEAR_TOP_PX); }'
           Replace = '' }
    )
}
