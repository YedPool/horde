# Mutations of core/Finding.ps1, the pure reading of a finding's text. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\finding.psd1
# Each breaks one refusal, or the order that keeps a refusal from repeating what it found;
# test\test-finding.ps1 must fail a check for every one.
#
# NOT HERE: the patterns of the credential check and of what is not text. They are decisions/Rules.ps1's,
# and test\mutations\decisions-rules.psd1 holds them; here only their use is mutated.
@{
    Target = "core\Finding.ps1"
    Suite  = "test\test-finding.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "size-not-checked"
           Find = 'if ($Text.Length -gt $script:HordeFindingMaxLength) {'
           Replace = 'if ($false) {' }
        @{ Name = "non-ascii-kept"
           Find = '    if ($wide.Success) {'
           Replace = '    if ($false) {' }
        @{ Name = "non-object-read"
           Find = 'if ($null -eq $parsedValue -or $parsedValue -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($null -eq $parsedValue) {' }
        @{ Name = "content-not-checked"
           Find = '    if ($content.Count -gt 0) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "schema-before-content"
           Find = '    $content = @(Find-HordeFindingContentProblems -Value $parsedValue)'
           Replace = '    $content = @(@(Test-HordeSchema -Value $parsedValue -Schema (Get-HordeSchema -Name $script:HordeFindingSchemaName)) + @(Find-HordeFindingContentProblems -Value $parsedValue))' }
        @{ Name = "duplicate-keys-kept"
           Find = '    if ($twice.Count -gt 0) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "schema-not-checked"
           Find = '    if ($unfit.Count -gt 0) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "rules-not-checked"
           Find = '    if ($broken.Count -gt 0) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "refusal-carries-the-finding"
           Find = '    if ($broken.Count -gt 0) { return (New-HordeFindingAnswer -State "refused" -Finding $null -Problems $broken) }'
           Replace = '    if ($broken.Count -gt 0) { return (New-HordeFindingAnswer -State "refused" -Finding $parsedValue -Problems $broken) }' }
        @{ Name = "secret-not-checked"
           Find = '    if ($secret -ne "") { return'
           Replace = '    if ($false) { return' }
        @{ Name = "customer-data-not-checked"
           Find = 'if ([regex]::IsMatch($Text, $script:HordeFindingCustomerPatterns[$name])) {'
           Replace = 'if ($false) {' }
        @{ Name = "email-not-checked"
           Find = '"an e-mail address" = '
           Replace = '"an e-mail address" = ''\A\z''; "x" = ' }
        @{ Name = "home-path-not-checked"
           Find = '"a path into a person''s home folder" = '
           Replace = '"a path into a person''s home folder" = ''\A\z''; "y" = ' }
        @{ Name = "phone-grouped-not-checked"
           Find = '|(?<![0-9])\(?[0-9]{3}\)?[ .-][0-9]{3}[ .-][0-9]{4}(?![0-9])'''
           Replace = '''' }
        @{ Name = "conversation-not-checked"
           Find = 'if ([regex]::Matches($Text, $rule.pattern).Count -ge $rule.least) {'
           Replace = 'if ($false) {' }
        @{ Name = "one-label-is-conversation"
           Find = 'what = "two or more speakers'' labels, as a pasted chat has"; least = 2'
           Replace = 'what = "two or more speakers'' labels, as a pasted chat has"; least = 1' }
        @{ Name = "one-dialogue-line-is-conversation"
           Find = 'what = "two or more dialogue lines, each a name and a colon"; least = 2'
           Replace = 'what = "two or more dialogue lines, each a name and a colon"; least = 1' }
        @{ Name = "label-prefix-matches-words"
           Find = '$script:HordeFindingSpeakerLabel = ''(?:user|assistant|human|ai|you|me|bot|customer|caller|q|a)[ \t]*:'''
           Replace = '$script:HordeFindingSpeakerLabel = ''(?:user|assistant|human|ai|you|me|bot|customer|caller|q|a)[a-z]*[ \t]*:''' }
        @{ Name = "quoted-replies-not-checked"
           Find = "pattern = '(?m)^[ \t]*>' }"
           Replace = "pattern = '\A\z' }" }
        @{ Name = "role-field-not-checked"
           Find = 'pattern = ''(?i)"role"\s*:\s*"(?:user|assistant|system|tool|human)"'' }'
           Replace = 'pattern = ''\A\z'' }' }
        @{ Name = "names-not-checked"
           Find = '            $nameKind = Find-HordeFindingTextKind -Text ("" + $k)'
           Replace = '            $nameKind = ""' }
        @{ Name = "list-items-not-walked"
           Find = '        foreach ($item in $Value) { $i++; foreach ($f in'
           Replace = '        foreach ($item in @()) { $i++; foreach ($f in' }
        @{ Name = "not-text-not-checked"
           Find = '        if ($notText -ne "") { [void]$out.Add($Path + " " + $notText) }'
           Replace = '' }
        @{ Name = "too-few-items-read"
           Find = '    if ($n -lt $Least) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "too-many-items-read"
           Find = '    if ($n -gt $Most) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "numbers-bound-off-by-one"
           Find = '"metric.numbers"                  = @{ min = 1; max = 24 }'
           Replace = '"metric.numbers"                  = @{ min = 1; max = 25 }' }
        @{ Name = "values-not-counted"
           Find = '-Least $script:HordeFindingValuesBounds.min -Most $script:HordeFindingValuesBounds.max'
           Replace = '-Least 0 -Most 99' }
        @{ Name = "window-order-not-checked"
           Find = 'if ($null -ne $starts -and $null -ne $ends -and $ends -lt $starts) {'
           Replace = 'if ($false) {' }
        @{ Name = "equal-window-refused"
           Find = '$ends -lt $starts) {'
           Replace = '$ends -le $starts) {' }
        @{ Name = "impossible-date-read"
           Find = '    if ($null -eq $starts) { [void]$out.Add('
           Replace = '    if ($false) { [void]$out.Add(' }
    )
}
