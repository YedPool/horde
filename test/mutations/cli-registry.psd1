# Mutations of the command registry. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\cli-registry.psd1
# Each breaks one rule cli\Commands.ps1 enforces; test\test-cli.ps1 must fail for every one of them.
@{
    Target = "cli\Commands.ps1"
    Suite  = "test\test-cli.ps1"
    Mutations = @(
        # A command file only declares.
        @{ Name = "allows-more-than-one-statement"
           Find = 'if ($stmts.Count -ne 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "allows-dynamicparam-block"
           Find = ' -or $ast.DynamicParamBlock'
           Replace = '' }
        @{ Name = "allows-using-statement"
           Find = 'if (@($ast.UsingStatements).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "allows-requires-line"
           Find = 'if ($null -ne $ast.ScriptRequirements) {'
           Replace = 'if ($false) {' }
        @{ Name = "allows-redirected-declaration"
           Find = 'if (Test-HordeRedirected -Ast $s.Right) {'
           Replace = 'if ($false) {' }
        @{ Name = "allows-redirected-value"
           Find = 'if (Test-HordeRedirected -Ast $pair.Item2) {'
           Replace = 'if ($false) {' }
        @{ Name = "redirection-never-seen"
           Find = 'return ($v -is [System.Management.Automation.Language.CommandBaseAst] -and @($v.Redirections).Count -gt 0)'
           Replace = 'return $false' }
        @{ Name = "allows-computed-declaration"
           Find = 'if ($null -eq $text) { [void]$findings.Add('
           Replace = 'if ($false) { [void]$findings.Add(' }
        @{ Name = "reads-key-from-trimmed-source"
           Find = '$key = $pair.Item1.Value'
           Replace = '$key = $pair.Item1.Extent.Text.Trim([char[]]"''`"")' }
        @{ Name = "allows-unknown-key"
           Find = 'if ((Get-HordeCommandKeys) -notcontains $key) {'
           Replace = 'if ($false) {' }
        @{ Name = "allows-missing-key"
           Find = 'if (-not $info.Contains($k) -or "$($info[$k])".Trim() -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "allows-plain-run-block"
           Find = 'if (-not $pb -or @($pb.Attributes | Where-Object { $_.TypeName.Name -eq "CmdletBinding" }).Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "allows-name-other-than-file"
           Find = '"$($info["name"])" -cne $base'
           Replace = '$false' }
        @{ Name = "allows-unlisted-group"
           Find = '-and -not (Get-HordeCommandGroups).Contains("$($info["group"])")'
           Replace = '-and $false' }
        @{ Name = "allows-foreign-usage"
           Find = '-and -not "$($info["usage"])".StartsWith("$($info["name"]) ")) {'
           Replace = '-and $false) {' }
        @{ Name = "loads-without-validating"
           Find = 'if (-not $r.info) { throw ("not a valid command file: "'
           Replace = 'if ($false) { throw ("not a valid command file: "' }
        @{ Name = "help-hides-broken-files"
           Find = 'if (@($all.findings).Count -gt 0) {'
           Replace = 'if ($false) {' }
        # The one name rule.
        @{ Name = "name-rule-anchored-with-dollar"
           Find = '''\A[a-z][a-z0-9-]*\z'''
           Replace = '''^[a-z][a-z0-9-]*$''' }
        @{ Name = "any-name-claims-findings"
           Find = 'if (Test-HordeCommandName -Name $Name) { $mine ='
           Replace = 'if ($true) { $mine =' }
        # Help and dispatch find commands through one listing.
        @{ Name = "dispatch-builds-its-own-path"
           Find = '$command = @($all.commands | Where-Object { $_.name -ceq $Name }) | Select-Object -First 1'
           Replace = '$command = $null; $pp = Join-Path $Dir ($Name + ".ps1"); if (Test-Path -LiteralPath $pp) { $command = [pscustomobject]@{ name = $Name; path = $pp; usage = $Name; summary = "x" } }' }
        @{ Name = "lists-reserved-device-names"
           Find = 'if ($f.BaseName -imatch ''\A(con|prn|aux|nul|com[1-9]|lpt[1-9])\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "lists-uppercase-extension"
           Find = 'if ($f.Extension -cne ".ps1") {'
           Replace = 'if ($false) {' }
        # Which run-block parameters are switches, for the switch-word refusal.
        @{ Name = "no-parameter-is-a-switch"
           Find = 'switch = ($p.StaticType -eq [System.Management.Automation.SwitchParameter])'
           Replace = 'switch = $false' }
        @{ Name = "parameters-not-recorded"
           Find = 'else { $info["parameters"] = @(Get-HordeRunParameters -ValueAst $pair.Item2) }'
           Replace = 'else { }' }
        @{ Name = "aliases-not-read"
           Find = 'ForEach-Object { $_.PositionalArguments } |'
           Replace = 'ForEach-Object { @() } |' }
        @{ Name = "sustained-text-accepted"
           Find = 'else { [void]$findings.Add("''sustained'' must be `$true or `$false") }'
           Replace = 'else { $info["sustained"] = $true }' }
        @{ Name = "sustained-defaults-true"
           Find = 'if (-not $info.Contains("sustained")) { $info["sustained"] = $false }'
           Replace = 'if (-not $info.Contains("sustained")) { $info["sustained"] = $true }' }
    )
}
