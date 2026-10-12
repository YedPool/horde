# One mutation of decisions/window/frame.js: the answer to one part of a question goes to Horde as the
# request say-part, with the part's letter - never as say, which takes no part.
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-frame-parts.psd1
# test\e2e\e2e-decisions-answering-parts.ps1 must fail for it. A spec of its own beside
# decisions-frame.psd1, whose suite answers no question of parts.
@{
    Target = "decisions\window\frame.js"
    Suite  = "test\e2e\e2e-decisions-answering-parts.ps1"
    Mutations = @(
        @{ Name = "a-part-is-asked-of-horde-as-say"
           Find = 'return asked("say-part", { number: number, text: text, wording: wording, id: id, part: letter }); },'
           Replace = 'return asked("say", { number: number, text: text, wording: wording, id: id }); },' }
    )
}
