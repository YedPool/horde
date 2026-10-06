# Mutations of tools/StartSites.ps1, the start-site list of messengers/ (remote plan R21, slice 3b,
# merge condition 2). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\start-sites.psd1
# Each switches off one rule; test\test-start-sites.ps1 must fail for every one.
@{
    Target = "tools\StartSites.ps1"
    Suite  = "test\test-start-sites.ps1"
    Mutations = @(
        @{ Name = "call-unseen"
           Find = 'if ($c.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand) { & $add $c "call" $c.Extent.Text; continue }'
           Replace = '' }
        @{ Name = "dot-unseen"
           Find = 'if ($c.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) { & $add $c "dot" $c.Extent.Text; continue }'
           Replace = '' }
        @{ Name = "start-commands-unseen"
           Find = 'if ($script:HordeStartSiteCommands -contains $name.ToLowerInvariant() -or $name -match'
           Replace = 'if ($name -match' }
        @{ Name = "program-names-unseen"
           Find = ' -or $name -match ''[.\\/:]'') { & $add $c "command" $c.Extent.Text; continue }'
           Replace = ') { & $add $c "command" $c.Extent.Text; continue }' }
        @{ Name = "dynamic-member-unseen"
           Find = 'if ($mc.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { & $add $mc "method" $mc.Extent.Text; continue }'
           Replace = 'if ($mc.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }' }
        @{ Name = "methods-unseen"
           Find = 'if ($script:HordeStartSiteMethods -contains $mc.Member.Value.ToLowerInvariant()) {'
           Replace = 'if ($false) {' }
        @{ Name = "types-unseen"
           Find = 'if ($script:HordeStartSiteTypes -notcontains $t.TypeName.FullName.ToLowerInvariant()) { continue }'
           Replace = 'continue' }
        @{ Name = "static-call-text-dropped"
           Find = 'if ($t.Parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and [object]::ReferenceEquals($t.Parent.Expression, $t)) { $site = $t.Parent }'
           Replace = '' }
        @{ Name = "new-object-unseen"
           Find = 'if ($null -ne $typeArg -and $script:HordeStartSiteTypes -contains "$($typeArg.Value)".ToLowerInvariant()) { & $add $nb "type" $nb.Extent.Text }'
           Replace = '' }
        @{ Name = "test-folders-read"
           Find = 'if (@($rel -split ''/'') -contains "test") { continue }'
           Replace = '' }
        @{ Name = "one-line-many-sites"
           Find = 'if ($used.ContainsKey($e.line)) { continue }'
           Replace = '' }
        @{ Name = "stale-line-kept"
           Find = 'if (-not $used.ContainsKey($e.line)) { [void]$out.Add('
           Replace = 'if ($false) { [void]$out.Add(' }
        @{ Name = "kind-unchecked"
           Find = 'if ($script:HordeStartSiteKinds -cnotcontains $cells[2]) {'
           Replace = 'if ($false) {' }
        @{ Name = "why-unchecked"
           Find = 'if ($why -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "short-line-read"
           Find = 'if ($cells.Count -lt 5) {'
           Replace = 'if ($cells.Count -lt 2) {' }
        @{ Name = "parse-error-passes"
           Find = 'if (@($errors).Count -gt 0) { [void]$out.Add([pscustomobject]@{ file = $rel; function = "(top)"; kind = "parse"; text = "the file does not parse" }); continue }'
           Replace = '' }
        @{ Name = "assign-unseen"
           Find = 'if ($lhs.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $script:HordeStartSiteProperties -contains $lhs.Member.Value.ToLowerInvariant()) { & $add $as "assign" $as.Extent.Text }'
           Replace = '' }
        @{ Name = "named-assign-unseen"
           Find = 'if ($lhs.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $script:HordeStartSiteProperties -contains $lhs.Member.Value.ToLowerInvariant()) {'
           Replace = 'if ($script:HordeStartSiteProperties -contains "$($lhs.Member.Value)".ToLowerInvariant()) {' }
        @{ Name = "indexed-assign-unseen"
           Find = 'if ($lhs -is [System.Management.Automation.Language.IndexExpressionAst]) { $lhs = $lhs.Target; continue }'
           Replace = '' }
        @{ Name = "starter-unseen"
           Find = 'if ($starters.ContainsKey($name.ToLowerInvariant())) { & $add $c "starter" $c.Extent.Text; continue }'
           Replace = '' }
        @{ Name = "starters-never-found"
           Find = 'if ($hasStart) { $starters[$fd.Name.ToLowerInvariant()] = $true }'
           Replace = '' }
        @{ Name = "com-unseen"
           Find = 'if ($name -ieq "New-Object" -and @($c.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ilike "com*" }).Count -gt 0) { & $add $c "command" $c.Extent.Text }'
           Replace = '' }
        @{ Name = "add-type-unseen"
           Find = '"add-type", "get-wmiobject"'
           Replace = '"get-wmiobject"' }
        @{ Name = "wmi-unseen"
           Find = '"get-wmiobject", "gwmi"'
           Replace = '"gwmi"' }
        @{ Name = "cim-unseen"
           Find = '"invoke-wmimethod", "invoke-cimmethod",'
           Replace = '"invoke-wmimethod",' }
        @{ Name = "missing-list-passes"
           Find = 'if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) { return @('
           Replace = 'if ($false) { return @(' }
    )
}
