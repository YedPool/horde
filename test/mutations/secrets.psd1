# Mutations of core/Secrets.ps1 in REDACT mode, as the conversation port uses it. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\secrets.psd1
# Each lets part of a secret through, or damages the text around it; test\test-secrets.ps1 must fail
# for every one. The refuse-mode patterns have their own spec, test\mutations\secrets-decisions.psd1.
@{
    Target = "core\Secrets.ps1"
    Suite  = "test\test-secrets.ps1"
    Mutations = @(
        # --- which kinds are looked for (Find-HordeSecretKind -Kinds) ---
        @{ Name = "kinds-that-were-named-are-ignored"
           Find = 'if ($asked.Count -gt 0 -and $asked -cnotcontains $name) { continue }'
           Replace = '' }
        @{ Name = "no-kind-named-is-no-kind-looked-for"
           Find = 'if ($asked.Count -gt 0 -and $asked -cnotcontains $name) { continue }'
           Replace = 'if ($asked -cnotcontains $name) { continue }' }
        @{ Name = "long-runs-looked-for-whatever-was-named"
           Find = 'if ($asked.Count -gt 0 -and $asked -cnotcontains $script:HordeSecretRunKind) { return "" }'
           Replace = '' }
        @{ Name = "long-runs-never-looked-for-once-a-kind-is-named"
           Find = 'if ($asked.Count -gt 0 -and $asked -cnotcontains $script:HordeSecretRunKind) { return "" }'
           Replace = 'if ($asked.Count -gt 0) { return "" }' }
        @{ Name = "long-runs-not-looked-for-when-no-kind-is-named"
           Find = 'if ($asked.Count -gt 0 -and $asked -cnotcontains $script:HordeSecretRunKind) { return "" }'
           Replace = 'if ($asked -cnotcontains $script:HordeSecretRunKind) { return "" }' }
        @{ Name = "a-name-that-is-no-kind-is-let-by"
           Find = '-and $kindName -cne $script:HordeSecretRunKind) { throw'
           Replace = '-and $false) { throw' }
        @{ Name = "the-long-run-kind-cannot-be-named"
           Find = ' -and $kindName -cne $script:HordeSecretRunKind) { throw'
           Replace = ') { throw' }
        @{ Name = "a-kind-named-in-another-case-is-taken"
           Find = '-cnotcontains $kindName -and'
           Replace = '-notcontains $kindName -and' }
        @{ Name = "key-body-left-after-its-header"
           Find = 'if ($close.Success) { $end = $end + $close.Index + $close.Length } else { $end = $Text.Length }'
           Replace = '$null = $close' }
        @{ Name = "match-not-widened-to-the-end-of-its-word"
           Find = 'while ($end -lt $Text.Length -and -not [char]::IsWhiteSpace($Text[$end])) { $end++ }'
           Replace = '$null = $end' }
        @{ Name = "match-widened-past-the-white-space"
           Find = '-and -not [char]::IsWhiteSpace($Text[$end])) { $end++ }'
           Replace = ') { $end++ }' }
        @{ Name = "overlapping-matches-not-merged"
           Find = 'if ($merged.Count -gt 0 -and $s.start -le $merged[$merged.Count - 1].end) {'
           Replace = 'if ($false) {' }
        @{ Name = "random-run-not-hidden"
           Find = 'if (Test-HordeSecretRun -Run $m.Value) { [void]$raw.Add('
           Replace = 'if ($false) { [void]$raw.Add(' }
        @{ Name = "slash-run-not-hidden"
           Find = 'if (Test-HordeSecretSlashRun -Piece $m.Value) { [void]$raw.Add('
           Replace = 'if ($false) { [void]$raw.Add(' }
        @{ Name = "hidden-count-not-counted"
           Find = 'return [pscustomobject]@{ text = $sb.ToString(); count = $spans.Count }'
           Replace = 'return [pscustomobject]@{ text = $sb.ToString(); count = 1 }' }
        @{ Name = "text-after-the-last-secret-dropped"
           Find = '[void]$sb.Append($Text, $at, $Text.Length - $at)'
           Replace = '$null = $at' }
        @{ Name = "marker-looks-like-a-secret"
           Find = '$script:HordeSecretMark = "<redacted>"'
           Replace = '$script:HordeSecretMark = "<redacted Q1w2E3r4T5y6U7i8O9p0Aa1Ss2Dd3Ff4>"' }
    )
}
