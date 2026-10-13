# Mutations of decisions/page/list.js for "Change my answer": an answer that is with the keeper can be
# changed, the change is sent as a correction naming the record of the answer, and nothing is edited
# in place. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-correct-page.psd1
# test\e2e\e2e-decisions-change-answer.ps1 must fail for each. The suite is a scenario in a real window
# (decisions-page.psd1 says why a page script has no other), about a minute and a half a mutant.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\e2e\e2e-decisions-change-answer.ps1"
    Mutations = @(
        @{ Name = "an-answered-question-does-not-offer-the-change"
           Find = '          change.offered = true;'
           Replace = '          change.offered = false; ans.removeChild(changeBtn);' }
        @{ Name = "the-change-is-sent-as-an-ordinary-answer"
           Find = 'return correct(q.number, s.text, Number(q.wordingVersion), s.id, Number(s.piece.msg.sequence), s.piece.letter); }).then(done,'
           Replace = 'return (s.piece.letter ? sayPart(q.number, s.piece.letter, s.text, Number(q.wordingVersion), s.id) : say(q.number, s.text, Number(q.wordingVersion), s.id)); }).then(done,' }
        @{ Name = "an-unchanged-answer-is-sent-as-a-correction"
           Find = '        if (text === undefined || text.trim() === "" || text === pieceText(q, p)) { return; }'
           Replace = '        if (text === undefined || text.trim() === "") { return; }' }
        @{ Name = "every-part-is-corrected-with-the-first-parts-record"
           Find = 's.id, Number(s.piece.msg.sequence), s.piece.letter); }).then(done,'
           Replace = 's.id, Number(pieces[0].msg.sequence), s.piece.letter); }).then(done,' }
        @{ Name = "a-refused-change-closes-the-field"
           Find = '          if (left === 0) { if (failed) { draw(); } else { closeChange(q); } }'
           Replace = '          if (left === 0) { closeChange(q); }' }
        @{ Name = "a-refused-change-shows-no-reason"
           Find = '          else { failed = true; changeRefused[s.key] = textOf(result && result.reason) || "Not saved, and no reason was given."; }'
           Replace = '          else { failed = true; }' }
        @{ Name = "cancel-sends-the-change"
           Find = '        cancelBtn.addEventListener("click", function (e) { e.stopPropagation(); closeChange(q); });'
           Replace = '        cancelBtn.addEventListener("click", function (e) { e.stopPropagation(); saveChange(q); });'
           Expect = "survives"
           Reason = "the scenario cancels with the step { do: change-cancel }, which calls closeChange itself: a press on the button cannot be made by a check (decisions-page.psd1: nothing can click the page). What cancelling does is held by that step; the real Escape key, which the scenario does press, is the mutant below." }
        @{ Name = "escape-in-the-field-saves-the-change"
           Find = '            if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); closeChange(q); }'
           Replace = '            if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); changeTyped[key] = cf.value; saveChange(q); }' }
        @{ Name = "escape-in-the-field-hands-the-keyboard-away"
           Find = '            if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); closeChange(q); }'
           Replace = '            if (e.key === "Escape") { closeChange(q); }' }
        @{ Name = "enter-in-the-field-saves-nothing"
           Find = 'e.preventDefault(); e.stopPropagation(); changeTyped[key] = cf.value; saveChange(q); return; }'
           Replace = 'e.preventDefault(); e.stopPropagation(); return; }' }
        @{ Name = "the-saved-change-is-not-shown-until-a-list-comes"
           Find = '          if (result && result.ok === true) { changeSaved[s.key] = { text: s.text, sequence: Number(result.sequence) }; delete changeTyped[s.key]; }'
           Replace = '          if (result && result.ok === true) { delete changeTyped[s.key]; }'
           Expect = "survives"
           Reason = "in a window the list that holds the correction arrives within the scenario's wait, so the row shows the changed words either way; the words kept in the meantime matter on the phone, where a snapshot takes a runner's turn. Not held by a check: the scenario cannot hold a list back." }
        @{ Name = "the-caret-is-taken-from-the-change-field"
           Find = '        if (document.activeElement && document.activeElement.getAttribute && document.activeElement.getAttribute("data-change")) { return; }'
           Replace = ''
           Expect = "survives"
           Reason = "the guard is for the window being given the keyboard while he is in a change field (the page's focus event): the scenario's window is hidden and is never given it in that moment. Written down, not held." }
    )
}
