# Mutations of decisions/Window.ps1's request say-part: the answer to one part of a question, handed to
# the operation say with the part's letter. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-window-say-part.psd1
# test\test-decisions-window-say.ps1 must fail for each.
@{
    Target = "decisions\Window.ps1"
    Suite  = "test\test-decisions-window-say.ps1"
    Mutations = @(
        @{ Name = "the-part-is-not-handed-to-the-operation"
           Find = '    if ($partLetter -is [string] -and $partLetter -ne "") { $request["part"] = $partLetter }'
           Replace = '' }
        @{ Name = "an-empty-part-is-handed-on"
           Find = '    if ($partLetter -is [string] -and $partLetter -ne "") { $request["part"] = $partLetter }'
           Replace = '    if ($partLetter -is [string]) { $request["part"] = $partLetter }' }
        @{ Name = "a-part-may-be-more-than-a-letter"
           Find = 'id = @{ type = "string"; most = 32 }; part = @{ type = "string"; most = 1 } }'
           Replace = 'id = @{ type = "string"; most = 32 }; part = @{ type = "string"; most = 32 } }' }
        @{ Name = "say-part-takes-no-part"
           Find = 'id = @{ type = "string"; most = 32 }; part = @{ type = "string"; most = 1 } }'
           Replace = 'id = @{ type = "string"; most = 32 } }' }
        # --- "Change my answer" (2026-10-13) ---
        @{ Name = "the-record-corrected-is-not-handed-to-the-operation"
           Find = '    if (($correctsRecord -is [int] -or $correctsRecord -is [long]) -and [long]$correctsRecord -ge 1) { $request["corrects"] = [long]$correctsRecord }'
           Replace = '' }
        @{ Name = "record-zero-is-handed-on-as-corrected"
           Find = '    if (($correctsRecord -is [int] -or $correctsRecord -is [long]) -and [long]$correctsRecord -ge 1) {'
           Replace = '    if (($correctsRecord -is [int] -or $correctsRecord -is [long])) {' }
        @{ Name = "correct-takes-no-record"
           Find = 'part = @{ type = "string"; most = 1 }; corrects = @{ type = "integer"; most = (Get-HordeDecisionMaxSequence) } }'
           Replace = 'part = @{ type = "string"; most = 1 } }' }
    )
}
