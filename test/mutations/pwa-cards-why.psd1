# Mutations of surfaces/pwa/page/cards-why.js, the Progress tab's one line when there are no cards. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-cards-why.psd1
# surfaces\pwa\test\test-pwa-site.ps1 must fail for each (its units.mjs, section 10e2). Every find string
# occurs exactly once.
@{
    Target = "surfaces\pwa\page\cards-why.js"
    Suite  = "surfaces\pwa\test\test-pwa-site.ps1"
    Mutations = @(
        @{ Name = "a-line-with-cards-present"
           Find = 'if (v && Array.isArray(v.machines) && v.machines.length > 0) return "";'
           Replace = '' }
        @{ Name = "a-stranger-pc-not-said"
           Find = 'if (v && v.unpaired === true) return "This phone is not paired to the PC that sends cards.";'
           Replace = '' }
        @{ Name = "a-control-character-kept"
           Find = '.replace(/[^\x20-\x7e]/g, "")'
           Replace = '' }
        @{ Name = "a-long-reason-not-cut"
           Find = '.slice(0, MAX_REASON)'
           Replace = '' }
        @{ Name = "a-refusal-not-said"
           Find = 'if (reason) return "Cards could not be read: " + reason + ".";'
           Replace = '' }
    )
}
