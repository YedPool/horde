# ParamShadow.ps1 - does any shipped code assign to a typed parameter under another casing?
#
# Development tooling, not part of the engine. test/test-param-shadow.ps1 runs it.
#
# WHY. PowerShell's variable names ignore case, so $transport and $Transport are one variable. In a
# block with a [string]$Transport parameter, `$transport = $tr.value` does not make a new variable: it
# writes into the parameter, and the [string] type turns the transport object into its text. That broke
# `horde node serve` on PR #111 (2026-10-07): R17b added -Transport to cli/commands/node.ps1, whose
# serve code already held the local transport in $transport, and the listener got a string ("transport
# does not accept links"). test-cli does not start serve, so only the machine-bound end-to-end saw it.
#
# THE FORM, measured over shipped code on 2026-10-07: five assignments to a parameter under another
# casing. Four were deliberate normalizations of UNTYPED parameters ($rows = @($Rows)), which convert
# nothing; one was the typed case above. So the rule is the typed case: an assignment, under a casing
# that differs, to a parameter of the same block that carries a type other than object or an array of
# them. Written in the parameter's own casing, an assignment is plainly meant and is not counted.
#
# HOW. Each file is parsed, never run (tools/FunctionNames.ps1's list of shipped files). An assignment
# belongs to the nearest enclosing function or script block that has a param block.

. (Join-Path $PSScriptRoot "FunctionNames.ps1")

# Types that convert nothing on assignment.
$script:HordeParamShadowLooseTypes = @("object", "object[]", "system.object", "system.object[]", "array", "psobject", "system.management.automation.psobject")

function Find-HordeParamShadows {
    # Findings in one script's text: "<line>: $<assigned> writes into parameter [<type>]$<Param>".
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$errs)
    $out = New-Object System.Collections.ArrayList
    foreach ($sb in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ScriptBlockAst] -and $null -ne $n.ParamBlock }, $true))) {
        $typed = @{}
        foreach ($p in @($sb.ParamBlock.Parameters)) {
            $tc = @($p.Attributes | Where-Object { $_ -is [System.Management.Automation.Language.TypeConstraintAst] })
            if ($tc.Count -eq 0) { continue }
            $tn = $tc[0].TypeName.FullName
            if ($script:HordeParamShadowLooseTypes -contains $tn.ToLowerInvariant()) { continue }
            $typed[$p.Name.VariablePath.UserPath] = $tn
        }
        if ($typed.Count -eq 0) { continue }
        foreach ($a in @($sb.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
            # Only this block's own assignments: a nested block with its own params is judged by itself.
            $owner = $a.Parent
            while ($null -ne $owner -and -not ($owner -is [System.Management.Automation.Language.ScriptBlockAst] -and $null -ne $owner.ParamBlock)) { $owner = $owner.Parent }
            if ($owner -ne $sb) { continue }
            $left = $a.Left
            if ($left -is [System.Management.Automation.Language.ConvertExpressionAst]) { $left = $left.Child }
            if ($left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            $v = $left.VariablePath.UserPath
            foreach ($k in @($typed.Keys)) {
                if ($v -ieq $k -and $v -cne $k) { [void]$out.Add(("" + $a.Extent.StartLineNumber + ": `$" + $v + " writes into parameter [" + $typed[$k] + "]`$" + $k)) }
            }
        }
    }
    return $out.ToArray()
}

function Find-HordeShippedParamShadows {
    # Every finding in shipped code under -Root, as "<file>:<finding>".
    param([Parameter(Mandatory = $true)][string]$Root)
    $out = New-Object System.Collections.ArrayList
    foreach ($rel in @(Get-HordeShippedScriptFiles -Root $Root)) {
        $text = [System.IO.File]::ReadAllText((Join-Path $Root $rel))
        foreach ($f in @(Find-HordeParamShadows -Text $text)) { [void]$out.Add($rel + ":" + $f) }
    }
    return $out.ToArray()
}
