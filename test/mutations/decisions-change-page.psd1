# Mutations of decisions/page/list.js for CHANGE MY ANSWER (T-0152), as a real phone draws them: the button
# on an answered question that is not closed and no other, the line that says why a closed one has none,
# the tap that reopens the box with his answer selected, Keep my answer, and the status lines of what
# became of a change. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-change-page.psd1
# test\test-decisions-page-change-browser.ps1 (headless Chrome, real touch events; its driver
# decisions\page\test\browser-change.mjs) must fail for each. Each find string occurs once.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\test-decisions-page-change-browser.ps1"
    Mutations = @(
        # --- the button, and the line that says why there is none
        @{ Name = "a-closed-question-is-offered-the-button"
           Find = '      if (textOf(q.state) === LISTED_STATE) { out.button = !!answeredNow && !reopened[q.number]; }'
           Replace = '      if (true) { out.button = !!answeredNow && !reopened[q.number]; }' }
        @{ Name = "a-closed-question-he-never-answered-says-it-is-closed"
           Find = '      else if (answeredNow) { out.closed = '
           Replace = '      else { out.closed = ' }
        @{ Name = "the-closed-line-does-not-say-who-acted"
           Find = '(textOf(q.actedBy) || "the warchief") + " has acted on it. To change course, ask a follow-up."; }'
           Replace = '"the warchief" + " has acted on it. To change course, ask a follow-up."; }' }
        @{ Name = "the-closed-line-does-not-say-what-to-do-instead"
           Find = ' has acted on it. To change course, ask a follow-up."; }'
           Replace = ' has acted on it."; }' }
        # --- what became of a change
        @{ Name = "no-line-says-the-answer-changed"
           Find = '          out.lines.push("answer changed - waiting for " + orc + " to confirm");'
           Replace = '' }
        @{ Name = "the-line-does-not-say-which-orc-is-waited-for"
           Find = '          out.lines.push("answer changed - waiting for " + orc + " to confirm");'
           Replace = '          out.lines.push("answer changed - waiting to confirm");' }
        @{ Name = "waiting-is-never-said-for-an-orc"
           Find = '        } else if (orc !== "" && textOf(q.state) === LISTED_STATE) {'
           Replace = '        } else if (false) {' }
        @{ Name = "the-time-of-the-change-is-left-out"
           Find = '        var told = "You changed your answer" + (when ? " at " + when : "") + ".";'
           Replace = '        var told = "You changed your answer.";' }
        @{ Name = "not-acted-is-not-said-plainly"
           Find = 'told + " " + by + " had not acted yet and is using the new answer."'
           Replace = 'told + " " + by + " has replied."' }
        @{ Name = "undoing-is-not-said-plainly"
           Find = '" had already acted on the first one and is undoing it."'
           Replace = '" has replied."' }
        @{ Name = "cannot-undo-does-not-say-why"
           Find = '" had already acted on the first one and says it cannot undo: " + textOf(reply.why) + ".");'
           Replace = '" had already acted on the first one and says it cannot undo.");' }
        @{ Name = "the-newest-change-is-not-the-one-told"
           Find = '      var last = list.length ? list[list.length - 1] : null;'
           Replace = '      var last = list.length ? list[0] : null;' }
        # --- the tap, the box and Keep my answer
        @{ Name = "a-tap-does-not-reopen-the-question"
           Find = '      reopened[q.number] = true;'
           Replace = '' }
        @{ Name = "the-reopened-answer-is-not-selected"
           Find = '      if (field && line.fields.indexOf(field) >= 0 && typeof field.select === "function") { field.select(); }'
           Replace = '' }
        @{ Name = "the-caret-is-not-put-in-the-reopened-box"
           Find = '      enter(line, line.parts ? 0 : undefined);'
           Replace = '' }
        @{ Name = "a-reopened-question-stays-in-the-answered-fold"
           Find = '      if (reopened[q.number] === true) { return "main"; }'
           Replace = '' }
        @{ Name = "keep-my-answer-is-never-shown"
           Find = '      line.keep.hidden = reopened[q.number] !== true;'
           Replace = '      line.keep.hidden = true;' }
        @{ Name = "keep-my-answer-leaves-the-question-reopened"
           Find = '        delete reopened[n];'
           Replace = '' }
        @{ Name = "keep-my-answer-keeps-what-he-typed"
           Find = '        delete drafts[n];'
           Replace = '' }
        @{ Name = "a-saved-change-leaves-the-question-reopened"
           Find = '      if (savedNow && drafts[number] === undefined) { delete reopened[number]; }'
           Replace = '' }
        # --- the button on the folded Answered line, and a question of parts
        @{ Name = "the-folded-answered-line-has-no-change-button"
           Find = '      line.chg.hidden = !(folded && textOf(q.state) === LISTED_STATE && reopened[q.number] !== true);'
           Replace = '      line.chg.hidden = true;' }
        @{ Name = "the-button-on-the-folded-line-reopens-nothing"
           Find = '      chg.addEventListener("click", function (e) { e.stopPropagation(); reopen(drawn.q); });'
           Replace = '' }
        @{ Name = "changing-one-part-sends-every-part"
           Find = '      if (text.trim() === "" || (saved && text === textOf(saved.text))) { return false; }'
           Replace = '      if (text.trim() === "") { return false; }' }
    )
}
