# Mutations of surfaces/pwa/page/decision-cards.js, the cards at the head of the decisions page. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-decision-cards.psd1
# surfaces\pwa\test\test-pwa-site.ps1 (its units, section 10e3) must fail for each. Each find string
# occurs once.
@{
    Target = "surfaces\pwa\page\decision-cards.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "the-mark-is-a-sign-alone"
           Find = '    mark.textContent = " " + STOP_SIGN + " " + BLOCKS_WORDS;'
           Replace = '    mark.textContent = " " + STOP_SIGN;' }
        @{ Name = "a-published-orc-has-no-card"
           Find = '    names.add(l.lane);'
           Replace = '' }
        @{ Name = "the-published-count-is-left-off-the-card"
           Find = 'published: pub.get(lane) || 0, chosen: chosen === lane'
           Replace = 'published: 0, chosen: chosen === lane' }
        @{ Name = "the-published-words-are-left-out-of-the-slot"
           Find = 'pub.textContent = " - " + v.published + " published";'
           Replace = 'pub.textContent = "";' }
        @{ Name = "all-questions-counts-one-lane"
           Find = '  for (const v of by.values()) { open += v.open; blocksAll = blocksAll || v.blocksAll; }'
           Replace = '  for (const v of by.values()) { open = v.open; blocksAll = blocksAll || v.blocksAll; }' }
        @{ Name = "all-questions-never-marked"
           Find = '  for (const v of by.values()) { open += v.open; blocksAll = blocksAll || v.blocksAll; }'
           Replace = '  for (const v of by.values()) { open += v.open; }' }
        @{ Name = "no-card-says-it-is-chosen"
           Find = '    card.setAttribute("aria-pressed", v.chosen ? "true" : "false");'
           Replace = '    card.setAttribute("aria-pressed", "false");' }
        @{ Name = "a-lane-of-the-lanes-document-that-asks-nothing-has-no-card"
           Find = '  for (const c of lanes && Array.isArray(lanes.cards) ? lanes.cards : []) if (c && typeof c.lane === "string" && c.lane) names.add(c.lane);'
           Replace = '' }
        @{ Name = "all-questions-chooses-a-lane-named-all"
           Find = '    const pick = v.lane === ALL ? "" : v.lane;'
           Replace = '    const pick = v.lane;' }
    )
}
