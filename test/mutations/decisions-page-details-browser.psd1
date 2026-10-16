# Mutations of decisions/page/list.js's ONE STAGE, AND A BOX TO ANSWER IN and THE ANSWERED ARE HIDDEN
# UNTIL ASKED FOR, and THE SWITCH IS REACHED BY KEYS. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page-details-browser.psd1
# test\test-decisions-page-browser.ps1 (headless Chrome, real touch events; its driver
# decisions\page\test\browser-details.mjs) must fail for each. Each find string occurs once.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\test-decisions-page-browser.ps1"
    Mutations = @(
        @{ Name = "the-context-goes-back-under-the-box"
           Find = '      ans.appendChild(subBox);'
           Replace = '      wrap.appendChild(subBox);' }
        @{ Name = "the-label-is-not-tied-to-its-field"
           Find = '        ansLabel.htmlFor = field.id;'
           Replace = '' }
        @{ Name = "the-send-key-sends-nothing"
           Find = '      key.addEventListener("click", function (e) { e.stopPropagation(); send(); });'
           Replace = '      key.addEventListener("click", function (e) { e.stopPropagation(); });' }
        @{ Name = "the-answered-are-shown-by-default"
           Find = '    var answeredShown = options.answered === true;'
           Replace = '    var answeredShown = options.answered !== false;' }
        @{ Name = "the-switch-hides-nothing"
           Find = '(answeredShown || ANSWERED_FOLDS[f] !== true)'
           Replace = '(true || ANSWERED_FOLDS[f] !== true)' }
        @{ Name = "the-switch-is-not-kept"
           Find = '      try { if (prefs) { prefs.setItem(ANSWERED_KEY, answeredShown ? "1" : "0"); } } catch (e) { /* only the remembering is lost */ }'
           Replace = '' }
        @{ Name = "the-switch-loses-his-place"
           Find = '      if (lastJson === null) { drawAnsweredButton(); return; }'
           Replace = '      if (lastJson === null) { drawAnsweredButton(); return; } draw({ keepBar: true }); window.scrollTo(0, 0); return;' }
        # THE SWITCH IS REACHED BY KEYS (review of PR 311).
        @{ Name = "ctrl-down-with-no-fold-goes-nowhere"
           Find = '      toSwitch();'
           Replace = '' }
        @{ Name = "up-from-the-first-fold-goes-nowhere"
           Find = 'else if (e.key === "ArrowUp" && at === 0) { toSwitch(); }'
           Replace = '' }
        @{ Name = "down-from-the-switch-goes-nowhere"
           Find = 'if (e.key === "ArrowDown" && !e.ctrlKey && !e.altKey) {'
           Replace = 'if (false) {' }
        @{ Name = "the-switch-names-only-the-answered"
           Find = 'var ANSWERED_WORDS = { on: "Show answered and closed: on", off: "Show answered and closed: off",'
           Replace = 'var ANSWERED_WORDS = { on: "Show answered: on", off: "Show answered: off",' }
    )
}
