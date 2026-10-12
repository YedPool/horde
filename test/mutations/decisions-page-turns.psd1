# One mutation of decisions/page/list.js that only the turns scenario sees: the key that answered the
# LAST question of the list, and so let go of the caret, must not be taken a second time by the page
# as "a key pressed with the caret nowhere" - which would put the caret straight back into a field.
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page-turns.psd1
# test\e2e\e2e-decisions-answering-turns.ps1 must fail for it. A spec of its own because a spec has one
# suite, and this suite is a scenario of two minutes.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\e2e\e2e-decisions-answering-turns.ps1"
    Mutations = @(
        @{ Name = "the-key-that-answered-the-last-question-takes-the-caret-back"
           Find = '      if (e.defaultPrevented || focusedLine() || e.ctrlKey || e.altKey || e.metaKey) { return; }'
           Replace = '      if (focusedLine() || e.ctrlKey || e.altKey || e.metaKey) { return; }' }
    )
}
