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
           Find = 'if (Test-HordeTextValue -Item $value) {'
           Replace = 'if ($false) {' }
        @{ Name = "positional-text-bool-accepted"
           Find = 'if (Test-HordeTextValue -Item $item) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-null-accepted"
           Find = '@(''$true'', ''$false'', ''$null'') -contains $Item'
           Replace = '@(''$true'', ''$false'') -contains $Item' }
        @{ Name = "text-value-case-sensitive"
           Find = '@(''$true'', ''$false'', ''$null'') -contains $Item'
           Replace = '@(''$true'', ''$false'', ''$null'') -ccontains $Item' }
        # "--".
        @{ Name = "double-dash-accepted"
           Find = 'if ("$item" -ceq "--") {'
           Replace = 'if ($false) {' }
        # A switch followed by a truth word.
        @{ Name = "switch-word-accepted"
           Find = 'if ($pname -and $j + 1 -lt $items.Count) {'
           Replace = 'if ($false) {' }
        @{ Name = "switch-word-needs-dollar"
           Find = '\A(\$?(true|false)|'
           Replace = '\A(\$(true|false)|' }
        @{ Name = "switch-word-case-sensitive"
           Find = '-imatch ''\A(\$?(true|false)|[01]|yes|no|on|off)\z'''
           Replace = '-cmatch ''\A(\$?(true|false)|[01]|yes|no|on|off)\z''' }
        @{ Name = "switch-word-forgets-digits"
           Find = '(true|false)|[01]|yes'
           Replace = '(true|false)|yes' }
        @{ Name = "switch-word-forgets-yes-no"
           Find = '|yes|no|'
           Replace = '|' }
        @{ Name = "switch-word-forgets-on-off"
           Find = '|on|off)'
           Replace = ')' }
        # A switch followed by a [bool].
        @{ Name = "switch-bool-accepted"
           Find = 'if ($next -is [bool] -and'
           Replace = 'if ($false -and' }
        @{ Name = "common-switches-forgotten"
           Find = '$switches = @("Verbose", "Debug", "WhatIf", "Confirm")'
           Replace = '$switches = @()' }
        @{ Name = "aliases-forgotten"
           Find = 'foreach ($n in @(@($p.name) + @($p.aliases)))'
           Replace = 'foreach ($n in @(@($p.name)))' }
        @{ Name = "prefix-not-matched"
           Find = 'if (@($prefixed | Where-Object { $_.s }).Count -gt 0) { return "switch" }'
           Replace = '' }
        @{ Name = "exact-name-does-not-decide"
           Find = 'if ($exact.Count -gt 0) { if ($exact[0].s) { return "switch" } else { return "value" } }'
           Replace = '' }
        # -?, -h and --help ask for help, unless a parameter's value.
        @{ Name = "command-help-forgets-h"
           Find = '@("-?", "-h", "--help") -contains "$($items[$j])"'
           Replace = '@("-?", "--help") -contains "$($items[$j])"' }
        @{ Name = "help-word-value-ignored"
           Find = '-not (Test-HordeParameterValue -Items $items -Index $j -Parameters $Parameters)) { return $true }'
           Replace = '$true) { return $true }' }
        @{ Name = "help-word-after-colon-is-help"
           Find = 'if ("$before".EndsWith(":")) { return $true }'
           Replace = '' }
        @{ Name = "help-word-after-value-parameter-is-help"
           Find = 'return ((Get-HordeParameterKind -Name $name -Parameters $Parameters) -eq "value")'
           Replace = 'return $false' }
        @{ Name = "value-prefix-not-matched"
           Find = 'if ($prefixed.Count -gt 0) { return "value" }'
           Replace = '' }
        @{ Name = "help-word-value-stays-tagged"
           Find = '            $item = "$item"'
           Replace = '' }
    )
}
