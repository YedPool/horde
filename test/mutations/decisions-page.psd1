# Mutations of decisions/page/list.js, the list of questions drawn as a document. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page.psd1
# test\e2e\e2e-decisions-window.ps1 must fail for each.
#
# THE SUITE IS A SCENARIO, on purpose. A page script runs only inside a page: nothing but a real
# window can draw it, and the scenario is what reads back what it drew. It opens real windows
# (hidden, and one where no screen is) and takes about half a minute a mutant, so this spec is short:
# the faults a reader would meet - a question lost to its group's name, a redraw that folds what was
# unfolded or forgets the dimming, a wrong sub-number, a suffix that lost its words. NOT MUTATED,
# because nothing can click or scroll the page: a click on a line, and the scroll place kept across
# a redraw.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\e2e\e2e-decisions-window.ps1"
    Mutations = @(
        @{ Name = "groups-kept-in-an-ordinary-object"
           Find = 'var byKey = Object.create(null);'
           Replace = 'var byKey = {};'
           Expect = "survives"
           Reason = "a heading's key is the group's name after the word group: or state:, so a group named __proto__ is not the bare key that an ordinary object trips on, and the scenario's two such groups are drawn whole either way (run 2026-10-07). The map with no prototype is the second layer, kept so that the guard does not rest on how a key happens to be spelt; what the fault looked like - such a group's questions drawn under another heading - is the mutant below." }
        @{ Name = "a-group-named-like-a-built-in-member-loses-its-heading"
           Find = 'run = head("group:" + name + (runs[name] > 1 ? "#" + runs[name] : ""), "group", name || "No group");'
           Replace = 'run = head("group:" + (name === "__proto__" ? "constructor" : name) + (runs[name] > 1 ? "#" + runs[name] : ""), "group", name || "No group");' }
        @{ Name = "a-redraw-folds-what-was-unfolded"
           Find = 'questions = record.value.questions;'
           Replace = 'questions = record.value.questions; unfolded = Object.create(null);' }
        @{ Name = "a-redraw-forgets-the-dimming"
           Find = '(open ? " open" : "") + (dim && dim(q) ? " dim" : ""));'
           Replace = '(open ? " open" : ""));' }
        @{ Name = "sub-lines-numbered-without-their-question"
           Find = 'q.number + "." + (i + 1));'
           Replace = '"" + (i + 1));' }
        # Dropped 2026-10-08: "the-suffix-does-not-say-recommended" - the muted suffix is gone (the owner, 2026-10-07: the recommendation is the grey suggestion in the answer field), so there is no line left for it to mutate.
        # Dropped 2026-10-08: "the-suffix-carries-the-reason-in-brackets" - the same: no suffix is drawn any more.
        @{ Name = "a-note-of-background-is-shown-unasked"
           Find = '(head.note && noteShown[head.key] === true ? " note-open" : "");'
           Replace = '(head.note ? " note-open" : "");' }
        # Dropped 2026-10-08: "the-number-drawn-is-the-line-position" - a question's number is now drawn by two identical lines (a row of his turn and a folded row), so no Find occurs once; the scenario still checks every number drawn against the list.
        @{ Name = "the-text-reported-is-the-data-not-the-page"
           Find = 'n: line.num.textContent, l: line.letter.textContent, t: cut(line.txt.textContent, limits.lineChars), s: "", g: line.head,'
           Replace = 'n: line.num.textContent, l: line.letter.textContent, t: cut(line.txt.textContent.toUpperCase(), limits.lineChars), s: "", g: line.head,' }
    )
}
