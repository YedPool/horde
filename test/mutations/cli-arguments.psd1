# Mutations of the argument reader. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\cli-arguments.psd1
# Each breaks one rule cli\Arguments.ps1 enforces; test\test-cli.ps1 must fail for every one of them.
@{
    Target = "cli\Arguments.ps1"
    Suite  = "test\test-cli.ps1"
    Mutations = @(
        @{ Name = "parameter-tag-ignored"
           Find = 'if ($p) { return "$($p.Value)" }'
           Replace = 'if ($false) { return "$($p.Value)" }' }
        # Colon joining.
        @{ Name = "colon-value-not-joined"
           Find = 'if ($pname -and "$item".EndsWith(":")) {'
           Replace = 'if ($false) {' }
        # The word "$true" or "$false" is refused wherever it arrives.
        @{ Name = "quoted-colon-text-bool-accepted"
           Find = 'if ($value -is [string] -and ($value -ieq ''$true'' -or $value -ieq ''$false'')) {'
           Replace = 'if ($false) {' }
        @{ Name = "positional-text-bool-accepted"
           Find = 'if ($item -is [string] -and ($item -ieq ''$true'' -or $item -ieq ''$false'')) {'
           Replace = 'if ($false) {' }
        # "--".
        @{ Name = "double-dash-accepted"
           Find = 'if ("$item" -ceq "--") {'
           Replace = 'if ($false) {' }
        # A switch followed by a truth word.
        @{ Name = "switch-word-accepted"
           Find = 'if ($pname -and $j + 1 -lt $items.Count) {'
           Replace = 'if ($false) {' }
        @{ Name = "switch-word-needs-dollar"
           Find = '-imatch ''\A\$?(true|false)\z'''
           Replace = '-imatch ''\A\$(true|false)\z''' }
        @{ Name = "switch-word-case-sensitive"
           Find = '-imatch ''\A\$?(true|false)\z'''
           Replace = '-cmatch ''\A\$?(true|false)\z''' }
        @{ Name = "common-switches-forgotten"
           Find = '$switches = @("Verbose", "Debug", "WhatIf", "Confirm")'
           Replace = '$switches = @()' }
        @{ Name = "aliases-forgotten"
           Find = 'foreach ($n in @(@($p.name) + @($p.aliases)))'
           Replace = 'foreach ($n in @(@($p.name)))' }
        @{ Name = "prefix-not-matched"
           Find = '$_.s -and $_.n.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)'
           Replace = '$_.s -and $_.n -ieq $Name' }
        @{ Name = "exact-name-does-not-decide"
           Find = 'if ($exact.Count -gt 0) { return [bool]$exact[0].s }'
           Replace = '' }
    )
}
