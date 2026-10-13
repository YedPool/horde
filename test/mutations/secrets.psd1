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
           Find = '-and $kindName -cne $script:HordeSecretRunKind -and $kindName -cne $script:HordeSecretNamedKind) { throw'
           Replace = '-and $false) { throw' }
        @{ Name = "the-long-run-kind-cannot-be-named"
           Find = ' -and $kindName -cne $script:HordeSecretRunKind -and'
           Replace = ' -and' }
        @{ Name = "a-kind-named-in-another-case-is-taken"
           Find = '-cnotcontains $kindName -and'
           Replace = '-notcontains $kindName -and' }
        # --- a secret under its own name: only when that kind is named (review of the files deny list, 2026-10-13) ---
        @{ Name = "named-secret-looked-for-by-every-caller"
           Find = 'if ($asked -ccontains $script:HordeSecretNamedKind -and (Test-HordeSecretNamed -Text $Text)) {'
           Replace = 'if ((Test-HordeSecretNamed -Text $Text)) {' }
        @{ Name = "named-secret-looked-for-when-any-kind-is-named"
           Find = 'if ($asked -ccontains $script:HordeSecretNamedKind -and (Test-HordeSecretNamed -Text $Text)) {'
           Replace = 'if ($asked.Count -gt 0 -and (Test-HordeSecretNamed -Text $Text)) {' }
        @{ Name = "named-secret-never-looked-for"
           Find = 'if ($asked -ccontains $script:HordeSecretNamedKind -and (Test-HordeSecretNamed -Text $Text)) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-named-secret-kind-cannot-be-named"
           Find = ' -and $kindName -cne $script:HordeSecretNamedKind) { throw'
           Replace = ') { throw' }
        @{ Name = "a-placeholder-is-a-value"
           Find = 'if (-not [regex]::IsMatch($value, $script:HordeSecretNamedPlaceholder, $invariant)) { return $true }'
           Replace = 'return $true' }
        @{ Name = "only-the-first-named-match-is-looked-at"
           Find = 'if (-not [regex]::IsMatch($value, $script:HordeSecretNamedPlaceholder, $invariant)) { return $true }'
           Replace = 'return (-not [regex]::IsMatch($value, $script:HordeSecretNamedPlaceholder, $invariant))' }
        @{ Name = "a-bare-value-is-not-looked-at"
           Find = '$value = $(if ($bare.Success) { $bare.Value } else { $m.Groups["value"].Value })'
           Replace = '$value = $m.Groups["value"].Value' }
        # --- an unquoted value with a parenthesis is code (the review's next round, 2026-10-13) ---
        @{ Name = "a-bare-value-with-a-parenthesis-is-a-value"
           Find = 'if ($bare.Success -and $bare.Value.IndexOfAny([char[]]@(''('', '')'')) -ge 0) { continue }'
           Replace = '' }
        @{ Name = "only-an-open-parenthesis-makes-code"
           Find = '[char[]]@(''('', '')'')'
           Replace = '[char[]]@(''('')' }
        @{ Name = "only-a-close-parenthesis-makes-code"
           Find = '[char[]]@(''('', '')'')'
           Replace = '[char[]]@('')'')' }
        @{ Name = "a-quoted-value-with-a-parenthesis-is-code-too"
           Find = 'if ($bare.Success -and $bare.Value.IndexOfAny('
           Replace = 'if ($m.Value.IndexOfAny(' }
        @{ Name = "named-secret-name-client-secret-off"
           Find = 'client_secret|private_key|refresh_token|access_token|api_key|password'''
           Replace = 'zzzzzz_zzzzzz|private_key|refresh_token|access_token|api_key|password''' }
        @{ Name = "named-secret-name-private-key-off"
           Find = 'client_secret|private_key|refresh_token|access_token|api_key|password'''
           Replace = 'client_secret|zzzzzz_zzzzzz|refresh_token|access_token|api_key|password''' }
        @{ Name = "named-secret-name-refresh-token-off"
           Find = 'client_secret|private_key|refresh_token|access_token|api_key|password'''
           Replace = 'client_secret|private_key|zzzzzz_zzzzzz|access_token|api_key|password''' }
        @{ Name = "named-secret-name-access-token-off"
           Find = 'client_secret|private_key|refresh_token|access_token|api_key|password'''
           Replace = 'client_secret|private_key|refresh_token|zzzzzz_zzzzzz|api_key|password''' }
        @{ Name = "named-secret-name-api-key-off"
           Find = 'client_secret|private_key|refresh_token|access_token|api_key|password'''
           Replace = 'client_secret|private_key|refresh_token|access_token|zzzzzz_zzzzzz|password''' }
        @{ Name = "named-secret-name-password-off"
           Find = 'client_secret|private_key|refresh_token|access_token|api_key|password'''
           Replace = 'client_secret|private_key|refresh_token|access_token|api_key|zzzzzzzz''' }
        # --- the name is folded, and may have a prefix (the review's next round, 2026-10-13) ---
        @{ Name = "named-secret-name-case-sensitive"
           Find = '$script:HordeSecretNamedName = ''[A-Za-z0-9_-]*?(?i:'''
           Replace = '$script:HordeSecretNamedName = ''[A-Za-z0-9_-]*?(?:''' }
        @{ Name = "named-secret-no-prefix-allowed"
           Find = '$script:HordeSecretNamedName = ''[A-Za-z0-9_-]*?(?i:'''
           Replace = '$script:HordeSecretNamedName = ''(?i:''' }
        @{ Name = "named-secret-name-not-folded-of-separators"
           Find = '-join ''[_-]*'''
           Replace = '-join ''''' }
        @{ Name = "named-secret-dash-not-folded"
           Find = '-join ''[_-]*'''
           Replace = '-join ''_*''' }
        @{ Name = "named-secret-underscores-kept-in-the-name"
           Find = '($_.Replace("_", "").ToCharArray()'
           Replace = '($_.ToCharArray()' }
        @{ Name = "named-secret-equals-sign-may-be-on-another-line"
           Find = ')[ \t]*=[ \t]*(?:'
           Replace = ')\s*=\s*(?:' }
        # --- YAML: a colon and a value that is the rest of its line ---
        @{ Name = "named-secret-yaml-not-looked-for"
           Find = ')[ \t]*:[ \t]+(?:'
           Replace = ')[ \t]*:[ \t]+(?!)(?:' }
        @{ Name = "named-secret-yaml-value-need-not-end-its-line"
           Find = '(?=[ \t]*(?:\r|\n|\z|#))'
           Replace = '' }
        @{ Name = "named-secret-yaml-comment-ends-no-value"
           Find = '(?:\r|\n|\z|#))'
           Replace = '(?:\r|\n|\z))' }
        @{ Name = "named-secret-yaml-colon-may-be-on-another-line"
           Find = ')[ \t]*:[ \t]+(?:'
           Replace = ')\s*:\s+(?:' }
        @{ Name = "named-secret-member-value-of-any-length"
           Find = '[^\\\s]){8,})\k<v>'
           Replace = '[^\\\s]){1,})\k<v>' }
        @{ Name = "named-secret-quoted-pair-value-of-any-length"
           Find = '(?!\k<w>)\S){8,})\k<w>'
           Replace = '(?!\k<w>)\S){1,})\k<w>' }
        @{ Name = "named-secret-bare-pair-value-of-any-length"
           Find = '=]\S{7,}))'' +'
           Replace = '=]\S{0,}))'' +' }
        @{ Name = "named-secret-bare-yaml-value-of-any-length"
           Find = '=]\S{7,}))(?='
           Replace = '=]\S{0,}))(?=' }
        @{ Name = "named-secret-quoted-yaml-value-of-any-length"
           Find = '(?!\k<y>)\S){8,})\k<y>'
           Replace = '(?!\k<y>)\S){1,})\k<y>' }
        @{ Name = "named-secret-member-value-may-hold-white-space"
           Find = '(?!\k<v>)[^\\\s]){8,}'
           Replace = '(?!\k<v>)[^\\]){8,}' }
        @{ Name = "named-secret-a-comparison-is-a-pair"
           Find = '\k<w>|(?<bare>[^\s"''''=]'
           Replace = '\k<w>|(?<bare>[^\s"'''']' }
        @{ Name = "named-secret-angle-bracket-is-no-placeholder"
           Find = '$script:HordeSecretNamedPlaceholder = ''[<>${]|'
           Replace = '$script:HordeSecretNamedPlaceholder = ''[${]|' }
        @{ Name = "named-secret-dollar-is-no-placeholder"
           Find = '$script:HordeSecretNamedPlaceholder = ''[<>${]|'
           Replace = '$script:HordeSecretNamedPlaceholder = ''[<>{]|' }
        @{ Name = "named-secret-brace-is-no-placeholder"
           Find = '$script:HordeSecretNamedPlaceholder = ''[<>${]|'
           Replace = '$script:HordeSecretNamedPlaceholder = ''[<>$]|' }
        @{ Name = "named-secret-three-dots-are-no-placeholder"
           Find = '|\.\.\.|(?i:your|'
           Replace = '|(?i:your|' }
        @{ Name = "named-secret-your-is-no-placeholder"
           Find = '(?i:your|xxx|'
           Replace = '(?i:xxx|' }
        @{ Name = "named-secret-xxx-is-no-placeholder"
           Find = '|xxx|example|'
           Replace = '|example|' }
        @{ Name = "named-secret-example-is-no-placeholder"
           Find = '|example|changeme|'
           Replace = '|changeme|' }
        @{ Name = "named-secret-changeme-is-no-placeholder"
           Find = '|changeme|redacted)'
           Replace = '|redacted)' }
        @{ Name = "named-secret-redacted-is-no-placeholder"
           Find = '|changeme|redacted)'
           Replace = '|changeme)' }
        @{ Name = "named-secret-placeholder-words-in-their-own-case-only"
           Find = '|\.\.\.|(?i:your|'
           Replace = '|\.\.\.|(?:your|' }
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
