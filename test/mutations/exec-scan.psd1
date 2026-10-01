# Mutations of the no-exec scan. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\exec-scan.psd1
# Each mutation switches off one rule of tools\ExecScan.ps1, and test\test-link-contracts.ps1 must fail
# for every one: its control file names, line by line, the finding each form must get, so a rule that
# stops firing is seen even where another rule still catches the form. Every find string occurs once.
@{
    Target = "tools\ExecScan.ps1"
    Suite  = "test\test-link-contracts.ps1"
    Mutations = @(
        @{ Name = "allowlist-off"
           Find = 'if ($allowed -cnotcontains $name -and -not $funcs.Contains($name))'
           Replace = 'if ($false)' }
        @{ Name = "module-qualified-allowed"
           Find = 'if ($name.Contains("\") -or $name.Contains("/"))'
           Replace = 'if ($false)' }
        @{ Name = "denied-list-off"
           Find = 'if ($script:HordeExecDenied -contains $name.ToLowerInvariant()) {'
           Replace = 'if ($false) {' }
        @{ Name = "ampersand-allowed"
           Find = 'if ($c.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-dot-sourcing-allowed"
           Find = 'if (-not (Test-HordeExecLoaderDot $c))'
           Replace = 'if ($false)' }
        @{ Name = "loader-allowed-inside-a-function"
           Find = 'if ($p.Parent -isnot [System.Management.Automation.Language.ScriptBlockAst] -or $null -ne $p.Parent.Parent) { return $false }'
           Replace = '' }
        @{ Name = "loader-any-base"
           Find = '-cnotcontains $base) { return $false }'
           Replace = '-cnotcontains $base -and $false) { return $false }' }
        @{ Name = "loader-any-leaf"
           Find = '''\A((core|remote)\\)?[A-Za-z][A-Za-z0-9]*\.ps1\z'''
           Replace = '''\A.*\z''' }
        @{ Name = "foreach-takes-a-name"
           Find = '} elseif ($el -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "foreach-takes-any-parameter"
           Find = 'if (@("Process", "Begin", "End", "FilterScript") -notcontains $el.ParameterName)'
           Replace = 'if ($false)' }
        @{ Name = "com-object-allowed"
           Find = 'if ($el.ParameterName -like "Com*")'
           Replace = 'if ($false)' }
        @{ Name = "new-object-of-any-expression"
           Find = 'if ($null -eq $typeArg -or $typeArg -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {'
           Replace = 'if ($false) {' }
        @{ Name = "new-object-of-any-type"
           Find = 'elseif (Test-HordeExecTypeName $typeArg.Value)'
           Replace = 'elseif ($false)' }
        @{ Name = "dynamic-member-allowed"
           Find = 'if ($m.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {'
           Replace = 'if ($false) {' }
        @{ Name = "exec-methods-allowed"
           Find = '-and $script:HordeExecMembers -contains'
           Replace = '-and $false -and $script:HordeExecMembers -contains' }
        @{ Name = "exec-types-allowed"
           Find = 'if (Test-HordeExecTypeName $t.TypeName.FullName) {'
           Replace = 'if ($false) {' }
        @{ Name = "type-suffix-not-matched"
           Find = 'if ($n -ceq $t -or $n.EndsWith("." + $t)) { return $true }'
           Replace = 'if ($n -ceq $t) { return $true }' }
        @{ Name = "execution-context-allowed"
           Find = 'if ($v.VariablePath.UserPath -eq "ExecutionContext")'
           Replace = 'if ($false)' }
        @{ Name = "shadowing-function-allowed"
           Find = 'if ($script:HordeExecDenied -contains $d.Name.ToLowerInvariant() -or'
           Replace = 'if ($false -and $script:HordeExecDenied -contains $d.Name.ToLowerInvariant() -or' }
        @{ Name = "parse-errors-ignored"
           Find = 'foreach ($e in @($errs)) {'
           Replace = 'foreach ($e in @()) {' }
        @{ Name = "known-functions-ignored"
           Find = 'if ($null -ne $Known) { foreach ($k in $Known) { [void]$funcs.Add($k) } }'
           Replace = '' }
        @{ Name = "core-and-remote-functions-not-read"
           Find = '[void]$names.Add($d.Name)'
           Replace = '' }
    )
}
