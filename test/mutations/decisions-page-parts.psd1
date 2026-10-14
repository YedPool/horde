# Mutations of decisions/page/list.js's QUESTION OF SEVERAL PARTS as the founder asked for it on
# 2026-10-12: each part sent by itself, its own green and its own Answered, the question out of his
# list when the last part is answered, a part that was not saved kept with its reason. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page-parts.psd1
# test\e2e\e2e-decisions-answering-parts.ps1 must fail for each. The suite is a scenario with real keys
# in a real window, about a minute and a half a mutant (decisions-page.psd1 says why a page script has
# no other), so the spec holds the faults a reader would meet.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\e2e\e2e-decisions-answering-parts.ps1"
    Mutations = @(
        @{ Name = "leaving-a-part-sends-nothing"
           Find = '      var leave = function () { onward(savePart(line, at)); };'
           Replace = '      var leave = function () { onward(false); };' }
        @{ Name = "a-part-is-sent-as-an-answer-to-the-whole-question"
           Find = '      Promise.resolve().then(function () { return sayPart(number, letter, text, Number(q.wordingVersion), id); }).then('
           Replace = '      Promise.resolve().then(function () { return say(number, text, Number(q.wordingVersion), id); }).then(' }
        @{ Name = "one-letter-on-a-tab-is-sent"
           Find = '        if (field.value.trim().length === 1) { onward(false); return true; }'
           Replace = '' }
        @{ Name = "a-saved-part-never-turns-green"
           Find = '      var green = isSaved && isGreen(key);'
           Replace = '      var green = false;' }
        @{ Name = "a-saved-part-never-folds"
           Find = '      row.el.classList.toggle("answered", folded);'
           Replace = '      row.el.classList.toggle("answered", false);' }
        @{ Name = "a-folded-part-does-not-show-his-words"
           Find = '      row.done.textContent = folded ? textOf(saved.text) : "";'
           Replace = '      row.done.textContent = "";' }
        @{ Name = "the-question-leaves-with-a-part-still-to-answer"
           Find = '        if (!a) { return { answered: false, local: false }; }'
           Replace = '        if (!a) { continue; }' }
        @{ Name = "a-refused-part-does-not-bring-the-caret-back"
           Find = '        var elsewhere = !!line && (now !== line || (partAt >= 0 && line.fields[partAt] !== inField));'
           Replace = '        var elsewhere = !!line && now !== line;' }
        @{ Name = "a-refused-parts-reason-is-not-shown-under-it"
           Find = '      row.refusal.textContent = (s && s.refusal) ? s.refusal : (isSaved ? textOf(saved.receiptNote) : "");'
           Replace = '      row.refusal.textContent = (isSaved ? textOf(saved.receiptNote) : "");' }
        @{ Name = "ctrl-enter-on-the-first-part-sends-only-that-part"
           Find = '          line.parts.forEach(function (p, i) { if (savePart(line, i)) { any = true; } });'
           Replace = '          line.parts.forEach(function (p, i) { if (i === 0 && savePart(line, i)) { any = true; } });' }
        @{ Name = "with-the-keeper-only-his-last-part-is-shown"
           Find = '      if (mine && textOf(mine.part)) { mine = {'
           Replace = '      if (false) { mine = {' }
        @{ Name = "a-folded-part-cannot-be-brought-back"
           Find = '      rows.forEach(function (r, i) { r.done.addEventListener("click", function (e) { e.stopPropagation(); unfold(drawn, i); }); });'
           Replace = ''
           Expect = "survives"
           Reason = "the scenario brings a folded part back with the step { do: focus, part }, which calls unfold itself: a press on the folded line cannot be made by a check (decisions-page.psd1: nothing can click the page), so the listener that answers the press is not exercised. unfold, which both use, is: the scenario fails without it (a-folded-part-is-not-unfolded-for-the-caret)." }
        @{ Name = "a-folded-part-is-not-unfolded-for-the-caret"
           Find = '      if (line.parts) { var row = line.rows[part === undefined ? 0 : part]; row.el.classList.remove("answered"); row.done.hidden = true; }'
           Replace = '' }
    )
}
