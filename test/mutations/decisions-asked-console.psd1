# Mutations of the remind verb and of how the command line says when a question was asked
# (decisions/Console.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-asked-console.psd1
# test\e2e\e2e-decisions-asked.ps1 must fail for each.
@{
    Target = "decisions\Console.ps1"
    Suite  = "test\e2e\e2e-decisions-asked.ps1"
    Mutations = @(
        @{ Name = "the-note-text-is-dropped"
           Find = '            if ($noted) { $request["note"] = "$($have[''NoteText''])" }'
           Replace = '' }
        @{ Name = "a-bare-note-flag-is-taken"
           Find = '            if ($noted -ne $have.ContainsKey("NoteText")) {'
           Replace = '            if ($false) {' }
        @{ Name = "a-stray-word-is-called-a-flag"
           Find = '        if ($flag -eq "NoteText") { if (-not $spec.ContainsKey("noteText")) {'
           Replace = '        if ($flag -eq "NoteText") { if ($false) {' }
        @{ Name = "remind-says-nothing-of-when"
           Find = '        if ($Verb -ceq "remind") { [void]$lines.Add("  " + (Format-HordeDecisionAskedLine -Question $value.question)) }'
           Replace = '' }
        @{ Name = "the-list-says-nothing-of-when"
           Find = '            if ($askedLine -ne "") { [void]$lines.Add($pad + $askedLine) }'
           Replace = '' }
        @{ Name = "show-says-nothing-of-when"
           Find = '        foreach ($a in $whenAsked) {'
           Replace = '        foreach ($a in @()) {' }
    )
}
