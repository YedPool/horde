# Mutations of decisions/page/list.js for the founder's rules of 2026-10-12, as a real window draws
# them: an answered question leaves his list; the list is in the order he chose, and the choice is
# kept; the plain words that stand out; the question a follow-up follows; saved words green, then the
# question folded to Answered; a refused answer never green. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page-answered.psd1
# test\e2e\e2e-decisions-order.ps1 must fail for each. THE SUITE IS A SCENARIO (decisions-page.psd1
# says why a page script has no other), about a minute and a half a mutant, so this spec holds the
# faults a reader would meet and no more; the sorting itself is decisions-page-order.psd1, in seconds.
# NOT MUTATED HERE, because the scenario cannot tell them apart by anything but the clock: how long the
# words stand green and how long the folded line lingers (GREEN_MS, LINGER_MS) - the scenario waits for
# green, then folded, then gone, whatever the two numbers are - and the keyboard kept on a fold's
# heading across a redraw, which depends on a list arriving between two key presses (the turns
# scenario failed on exactly that before the heading's focus was kept, 2026-10-12).
@{
    Target = "decisions\page\list.js"
    Suite  = "test\e2e\e2e-decisions-order.ps1"
    Mutations = @(
        @{ Name = "an-answered-question-stays-in-his-list"
           Find = '      if (st.answered) { return (st.local || lingers(q)) ? "main" : "thrall"; }'
           Replace = '      if (st.answered && false) { return (st.local || lingers(q)) ? "main" : "thrall"; }' }
        @{ Name = "the-list-is-not-sorted"
           Find = '      inOrder(mine, orderKey, orderTurned).forEach(function (q) {'
           Replace = '      mine.forEach(function (q) {' }
        @{ Name = "what-is-with-the-keeper-is-not-sorted"
           Find = '      folds.thrall = inOrder(folds.thrall, orderKey, orderTurned);'
           Replace = '' }
        @{ Name = "the-chosen-order-is-not-kept"
           Find = '      try { if (prefs) { prefs.setItem(ORDER_KEY, orderKey); prefs.setItem(ORDER_TURN_KEY, orderTurned ? "1" : "0"); } } catch (e) { /* only the remembering is lost */ }'
           Replace = '' }
        @{ Name = "an-order-that-is-none-of-the-three-is-taken"
           Find = '    return DEFAULT_ORDER;'
           Replace = '    return key;' }
        @{ Name = "choosing-an-order-draws-nothing"
           Find = '      if (lastJson === null) { drawOrderBar(); return; }'
           Replace = '      drawOrderBar(); return;' }
        @{ Name = "the-button-pressed-is-always-the-first"
           Find = '        var on = o.key === orderKey;'
           Replace = '        var on = i === 0;' }
        @{ Name = "only-the-importance-is-said-in-plain-words"
           Find = '      [textOf(q.importanceShown), textOf(q.blocksShown)].forEach(function (words) {'
           Replace = '      [textOf(q.importanceShown)].forEach(function (words) {' }
        @{ Name = "a-follow-up-does-not-say-what-it-follows"
           Find = '      var old = (q.followsUp && typeof q.followsUp === "object") ? q.followsUp : null;'
           Replace = '      var old = null;' }
        @{ Name = "the-question-followed-never-unfolds"
           Find = '        more.hidden = !shown;'
           Replace = '        more.hidden = true;' }
        @{ Name = "the-question-followed-shows-no-answer"
           Find = '          if (textOf(old.answer) === "") { was.textContent = "You had not answered it."; }'
           Replace = '          if (true) { was.textContent = "You had not answered it."; }' }
        @{ Name = "saved-words-never-turn-green"
           Find = '      var green = !line.parts && st.answered && isGreen(String(q.number));'
           Replace = '      var green = false;' }
        @{ Name = "an-answered-question-never-folds"
           Find = '      line.wrap.classList.toggle("answered", folded);'
           Replace = '      line.wrap.classList.toggle("answered", false);' }
        @{ Name = "a-refused-answer-is-taken-for-saved"
           Find = '      var savedNow = !!result && result.ok === true;'
           Replace = '      var savedNow = !!result;' }
        @{ Name = "the-last-question-answered-keeps-the-caret"
           Find = '      if (!moved && sentNow && document.activeElement && document.activeElement.blur) { document.activeElement.blur(); }'
           Replace = '' }
        @{ Name = "a-new-question-is-not-marked-new"
           Find = '          line.wrap.classList.toggle("new", zone === "main" && isNew(q));'
           Replace = '          line.wrap.classList.toggle("new", false);' }
    )
}
