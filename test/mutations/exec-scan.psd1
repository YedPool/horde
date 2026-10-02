# Mutations of the no-exec scan. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\exec-scan.psd1
# Each mutation switches off or widens one allowlist of tools\ExecScan.ps1, and test\test-link-contracts.ps1
# must fail for every one: its control file names, line by line, the finding each form must get, so a
# rule that stops firing is seen even where another rule still catches the form. Every find string
# occurs once, on one line.
@{
    Target = "tools\ExecScan.ps1"
    Suite  = "test\test-link-contracts.ps1"
    Mutations = @(
        @{ Name = "command-allowlist-off"
           Find = 'if ($script:HordeExecCmdlets -cnotcontains $name -and -not $funcs.Contains($name))'
           Replace = 'if ($false)' }
        @{ Name = "module-qualified-allowed"
           Find = 'if ($name.Contains("\") -or $name.Contains("/"))'
           Replace = 'if ($false)' }
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
           Find = '''\A[A-Za-z][A-Za-z0-9]*\.ps1\z'''
           Replace = '''\A.*\z''' }
        @{ Name = "loader-any-core-file"
           Find = 'return ($script:HordeExecCoreFiles -ccontains $leaf.Value.Substring(5))'
           Replace = 'return $true' }
        @{ Name = "journal-file-any-static"
           Find = '"io.file" = @("Delete")'
           Replace = '"io.file" = @("Delete", "Copy")' }
        @{ Name = "core-function-that-runs-a-block-callable"
           Find = '"Test-HordeSchema", "Read-HordeSchemaFile",'
           Replace = '"Test-HordeSchema", "Read-HordeSchemaFile", "Invoke-HordeRead",' }
        @{ Name = "shadowing-function-allowed"
           Find = 'if ($script:HordeExecCmdlets -contains $d.Name -or $script:HordeExecCoreFunctions -contains $d.Name) {'
           Replace = 'if ($false) {' }
        @{ Name = "classes-and-using-allowed"
           Find = '[void]$out.Add("line " + $n.Extent.StartLineNumber + ": a class or a using statement")'
           Replace = '' }
        @{ Name = "any-attribute-allowed"
           Find = 'if ($script:HordeExecAttributes -notcontains $a.TypeName.FullName)'
           Replace = 'if ($false)' }
        @{ Name = "foreach-any-parameter"
           Find = 'if (@("Process", "FilterScript") -notcontains $pn)'
           Replace = 'if ($false)' }
        @{ Name = "foreach-colon-argument-any"
           Find = 'elseif ($null -ne $bound -and $bound -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst])'
           Replace = 'elseif ($false)' }
        @{ Name = "foreach-positional-any"
           Find = 'if ($el -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { [void]$out.Add($At + $Name + " given "'
           Replace = 'if ($false) { [void]$out.Add($At + $Name + " given "' }
        @{ Name = "select-named-calculated-property-allowed"
           Find = 'if ($null -ne $bound -and ($bound -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or $bound -is [System.Management.Automation.Language.HashtableAst]))'
           Replace = 'if ($false)' }
        @{ Name = "select-positional-calculated-property-allowed"
           Find = 'if ($el -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or $el -is [System.Management.Automation.Language.HashtableAst]) {'
           Replace = 'if ($false) {' }
        @{ Name = "select-variable-allowed"
           Find = 'elseif (-not $isCount -and $el -isnot [System.Management.Automation.Language.StringConstantExpressionAst])'
           Replace = 'elseif ($false)' }
        @{ Name = "add-member-any-parameter"
           Find = 'if (@("NotePropertyName", "NotePropertyValue", "InputObject", "Force", "PassThru") -notcontains $pn)'
           Replace = 'if ($false)' }
        @{ Name = "add-member-positional-allowed"
           Find = 'if (@("NotePropertyName", "NotePropertyValue", "InputObject") -notcontains $prev)'
           Replace = 'if ($false)' }
        @{ Name = "new-object-any-parameter"
           Find = 'if (@("TypeName", "ArgumentList") -notcontains $pn)'
           Replace = 'if ($false)' }
        @{ Name = "new-object-of-any-expression"
           Find = 'if ($null -eq $typeArg -or $typeArg -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {'
           Replace = 'if ($false) {' }
        @{ Name = "new-object-of-any-type"
           Find = 'elseif ($script:HordeExecNewTypes -notcontains $typeArg.Value)'
           Replace = 'elseif ($false)' }
        @{ Name = "script-block-anywhere"
           Find = 'if (-not $ok) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-type-named"
           Find = 'if ($script:HordeExecTypes -notcontains (ConvertTo-HordeExecTypeKey $t.TypeName.FullName))'
           Replace = 'if ($false)' }
        @{ Name = "scriptblock-type-allowed"
           Find = '    "int32", "int64")'
           Replace = '    "int32", "int64", "scriptblock")' }
        @{ Name = "type-key-keeps-system-prefix"
           Find = 'if ($n.StartsWith("system.")) { $n = $n.Substring(7) }'
           Replace = '' }
        @{ Name = "type-key-keeps-array-brackets"
           Find = 'while ($n.EndsWith("[]")) { $n = $n.Substring(0, $n.Length - 2) }'
           Replace = '' }
        @{ Name = "dynamic-member-allowed"
           Find = 'if ($m.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {'
           Replace = 'if ($false) {' }
        @{ Name = "static-member-of-any-expression"
           Find = 'if ($m.Expression -isnot [System.Management.Automation.Language.TypeExpressionAst]) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-static-member"
           Find = 'if ($allowedStatic -cnotcontains $member) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-instance-method"
           Find = 'if ($script:HordeExecInstanceMethods -cnotcontains $member) {'
           Replace = 'if ($false) {' }
        @{ Name = "engine-properties-allowed"
           Find = '} elseif ($script:HordeExecProperties -contains $member) {'
           Replace = '} elseif ($false) {' }
        @{ Name = "engine-variables-allowed"
           Find = 'if ($script:HordeExecVariables -contains $bare) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-scope-allowed"
           Find = 'if (-not ($vp.IsUnqualified -or $vp.IsScript))'
           Replace = 'if ($false)' }
        @{ Name = "scoped-engine-variable-not-unwrapped"
           Find = 'if ($colon -ge 0) { $bare = $bare.Substring($colon + 1) }'
           Replace = '' }
        @{ Name = "parse-errors-ignored"
           Find = 'foreach ($e in @($errs)) {'
           Replace = 'foreach ($e in @()) {' }
        @{ Name = "remote-functions-ignored"
           Find = 'if ($null -ne $Known) { foreach ($k in $Known) { [void]$funcs.Add($k) } }'
           Replace = '' }
        @{ Name = "core-functions-ignored"
           Find = 'foreach ($k in $script:HordeExecCoreFunctions) { [void]$funcs.Add($k) }'
           Replace = '' }
        @{ Name = "remote-functions-not-read"
           Find = '[void]$names.Add($d.Name)'
           Replace = '' }
    )
}
