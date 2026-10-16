# Mutations of decisions/page/list.js's ONE BUTTON THAT FOLDS OR UNFOLDS EVERY QUESTION (EVERY QUESTION
# STARTS UNFOLDED). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page-fold-browser.psd1
# test\test-decisions-page-browser.ps1 (headless Chrome, real touch events; its driver
# decisions\page\test\browser-fold.mjs) must fail for each. Each find string occurs once.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\test-decisions-page-browser.ps1"
    Mutations = @(
        @{ Name = "the-questions-start-folded"
           Find = '    var openFirst = options.expanded !== false;'
           Replace = '    var openFirst = options.expanded === true;' }
        @{ Name = "the-window-cannot-open-folded"
           Find = '    var openFirst = options.expanded !== false;'
           Replace = '    var openFirst = true;' }
        @{ Name = "the-button-does-nothing"
           Find = '      openFirst = open === true;'
           Replace = '      openFirst = openFirst;' }
        @{ Name = "the-button-word-never-flips"
           Find = '      foldButton.textContent = openFirst ? FOLD_WORDS.collapse : FOLD_WORDS.expand;'
           Replace = '      foldButton.textContent = FOLD_WORDS.collapse;' }
        @{ Name = "a-press-loses-his-place"
           Find = '      if (lastJson === null) { drawFoldButton(); return; }'
           Replace = '      if (lastJson === null) { drawFoldButton(); return; } draw({ keepBar: true }); window.scrollTo(0, 0); return;' }
        @{ Name = "a-list-that-arrives-forgets-what-he-folded"
           Find = '        questions = record.value.questions;'
           Replace = '        questions = record.value.questions; unfolded = Object.create(null);' }
        @{ Name = "a-tap-on-one-question-only-ever-unfolds"
           Find = '      unfolded[q.number] = opening;'
           Replace = '      unfolded[q.number] = true;' }
    )
}
