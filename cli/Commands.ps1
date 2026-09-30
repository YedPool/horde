# The command registry: every file in cli\commands is one command, and it declares itself.
#
# WHY ONE FILE PER COMMAND, DISCOVERED, and not a table beside a dispatcher. wezfleet closed a bug
# class with a central table (YedPool/wezfleet a6d6ff1): a switch branch in `case` form that was
# unreachable, a param with no trailing comma that left two flags undeclared, and 27 commands
# dispatched while the help advertised 16. A table fixed the drift between help and dispatch, but it
# is still a second place to edit. Here there is no second place: the file IS the declaration, the
# dispatcher names no command, and help is generated from the files.
#
# A COMMAND FILE ONLY DECLARES. It is exactly one statement - `$HordeCommand = @{ ... }` with
# constant name, group, usage and summary and a `run` script block - checked on the syntax tree
# BEFORE anything in it runs. So listing the commands, or printing help, executes no command code,
# and a file that does work at load time is refused rather than run.

Set-StrictMode -Off

# Groups, in display order. A command naming a group not listed here is refused, so help can never
# silently drop one.
$script:HordeCommandGroups = [ordered]@{
    about = "about horde"
}

$script:HordeCommandKeys = @("name", "group", "usage", "summary")

function Get-HordeRoot { return (Split-Path -Parent $PSScriptRoot) }

function Get-HordeCommandDir { return (Join-Path $PSScriptRoot "commands") }

function Get-HordeConstantString {
    # The string a hashtable value is, if it is a plain constant; otherwise $null.
    param($ValueAst)
    $v = $ValueAst
    if ($v -is [System.Management.Automation.Language.PipelineAst] -and @($v.PipelineElements).Count -eq 1) { $v = $v.PipelineElements[0] }
    if ($v -is [System.Management.Automation.Language.CommandExpressionAst]) { $v = $v.Expression }
    if ($v -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $v.Value }
    return $null
}

function Get-HordeRunProblem {
    # Why a hashtable value is not an acceptable `run` block, or $null if it is.
    #
    # IT MUST BE AN ADVANCED SCRIPT BLOCK - [CmdletBinding()] on its param block. Measured 2026-09-29
    # on PowerShell 5.1: a plain script block handed `-Bogus` puts it in $args and runs as if nothing
    # were wrong; an advanced one throws a binding error, which the dispatcher turns into exit 2 and the
    # usage line. A mistyped flag must never be silently ignored - the old system's `-AllowCloseWindow`
    # was unreachable for several commits for the same reason, in a different form.
    param($ValueAst)
    $v = $ValueAst
    if ($v -is [System.Management.Automation.Language.PipelineAst] -and @($v.PipelineElements).Count -eq 1) { $v = $v.PipelineElements[0] }
    if ($v -is [System.Management.Automation.Language.CommandExpressionAst]) { $v = $v.Expression }
    if ($v -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return "'run' is not a literal script block" }
    $pb = $v.ScriptBlock.ParamBlock
    if (-not $pb -or @($pb.Attributes | Where-Object { $_.TypeName.Name -eq "CmdletBinding" }).Count -eq 0) {
        return "'run' has no [CmdletBinding()] param block, so a mistyped argument would be silently ignored"
    }
    return $null
}

function Read-HordeCommandAst {
    # Parse a command file and return { info; findings }. info is $null when there are findings.
    # Nothing in the file is executed.
    param([string]$Path)
    $findings = New-Object System.Collections.ArrayList
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        [void]$findings.Add("does not parse: " + $errors[0].Message)
        return [pscustomobject]@{ info = $null; findings = @($findings) }
    }
    # Traps is $null when there are none, and @($null).Count is 1 - so it is tested for null first.
    if ($ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock -or ($null -ne $ast.EndBlock.Traps -and $ast.EndBlock.Traps.Count -gt 0)) {
        [void]$findings.Add("has a param, begin or process block; a command file only declares `$HordeCommand")
    }
    $stmts = @($ast.EndBlock.Statements)
    if ($stmts.Count -ne 1) {
        [void]$findings.Add("has " + $stmts.Count + " top-level statements; it must have exactly one, `$HordeCommand = @{ ... }")
        return [pscustomobject]@{ info = $null; findings = @($findings) }
    }
    $s = $stmts[0]
    $table = $null
    if ($s -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $s.Operator -eq [System.Management.Automation.Language.TokenKind]::Equals -and
        $s.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $s.Left.VariablePath.UserPath -eq "HordeCommand" -and
        $s.Right -is [System.Management.Automation.Language.CommandExpressionAst] -and
        $s.Right.Expression -is [System.Management.Automation.Language.HashtableAst]) { $table = $s.Right.Expression }
    if (-not $table) {
        [void]$findings.Add("its one statement is not `$HordeCommand = @{ ... }")
        return [pscustomobject]@{ info = $null; findings = @($findings) }
    }
    $info = [ordered]@{ path = $Path }
    $hasRun = $false
    foreach ($pair in $table.KeyValuePairs) {
        $key = "$($pair.Item1.Extent.Text)".Trim('"', "'")
        if ($key -eq "run") {
            $hasRun = $true
            $why = Get-HordeRunProblem -ValueAst $pair.Item2
            if ($why) { [void]$findings.Add($why) }
            continue
        }
        if ($script:HordeCommandKeys -notcontains $key) { [void]$findings.Add("declares an unknown key '" + $key + "'"); continue }
        $text = Get-HordeConstantString -ValueAst $pair.Item2
        if ($null -eq $text) { [void]$findings.Add("'" + $key + "' is not a constant string, so it cannot be read without running the file") }
        else { $info[$key] = $text }
    }
    if (-not $hasRun) { [void]$findings.Add("has no 'run' script block") }
    foreach ($k in $script:HordeCommandKeys) {
        if (-not $info.Contains($k) -or "$($info[$k])".Trim() -eq "") { [void]$findings.Add("has no " + $k) }
    }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ($info.Contains("name") -and "$($info["name"])" -cne $base) {
        [void]$findings.Add("declares name '" + $info["name"] + "' but the file is " + $base + ".ps1; the file name is the command name")
    }
    if ($info.Contains("name") -and "$($info["name"])" -cnotmatch '^[a-z][a-z0-9-]*$') {
        [void]$findings.Add("name '" + $info["name"] + "' is not lowercase letters, digits and hyphens")
    }
    if ($info.Contains("group") -and -not $script:HordeCommandGroups.Contains("$($info["group"])")) {
        [void]$findings.Add("names group '" + $info["group"] + "', which help does not list")
    }
    if ($info.Contains("usage") -and $info.Contains("name") -and
        "$($info["usage"])" -ne "$($info["name"])" -and -not "$($info["usage"])".StartsWith("$($info["name"]) ")) {
        [void]$findings.Add("usage does not start with its own name")
    }
    if ($findings.Count -gt 0) { return [pscustomobject]@{ info = $null; findings = @($findings) } }
    return [pscustomobject]@{ info = [pscustomobject]$info; findings = @() }
}

function Get-HordeCommands {
    # Every command file in Dir, read without running any of them. Returns { commands; findings },
    # where each finding names its file. A broken file is a finding, never silently skipped.
    param([string]$Dir = (Get-HordeCommandDir))
    $commands = New-Object System.Collections.ArrayList
    $findings = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter *.ps1 -File | Sort-Object Name)) {
        $r = Read-HordeCommandAst -Path $f.FullName
        if ($r.info) { [void]$commands.Add($r.info) }
        foreach ($x in $r.findings) { [void]$findings.Add($f.Name + ": " + $x) }
    }
    return [pscustomobject]@{ commands = @($commands); findings = @($findings) }
}

function Get-HordeCommandFile {
    # The file for one command name, or $null. The name is checked BEFORE it touches a path, so
    # "..\something" cannot reach a file outside the commands folder.
    param([string]$Name, [string]$Dir = (Get-HordeCommandDir))
    if ($Name -cnotmatch '^[a-z][a-z0-9-]*$') { return $null }
    $p = Join-Path $Dir ($Name + ".ps1")
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
    return $p
}

function Import-HordeCommand {
    # Validate a command file, then load it and return its declaration. Validation comes first, so
    # a file that would do work on load is refused before it runs.
    param([string]$Path)
    $r = Read-HordeCommandAst -Path $Path
    if (-not $r.info) { throw ("not a valid command file: " + (Split-Path -Leaf $Path) + ": " + ($r.findings -join "; ")) }
    $HordeCommand = $null
    . $Path
    return $HordeCommand
}

function Format-HordeHelp {
    # Help, GENERATED from the command files. Returns lines; the caller decides where they go.
    param([string]$Dir = (Get-HordeCommandDir))
    $all = Get-HordeCommands -Dir $Dir
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("usage: horde <command> [arguments]")
    foreach ($g in $script:HordeCommandGroups.Keys) {
        $rows = @($all.commands | Where-Object { $_.group -eq $g } | Sort-Object name)
        if ($rows.Count -eq 0) { continue }
        [void]$lines.Add("")
        [void]$lines.Add("  " + $script:HordeCommandGroups[$g])
        foreach ($c in $rows) {
            [void]$lines.Add("    horde " + $c.usage)
            [void]$lines.Add("        " + $c.summary)
        }
    }
    if (@($all.findings).Count -gt 0) {
        [void]$lines.Add("")
        [void]$lines.Add("  broken command files (not listed above):")
        foreach ($x in $all.findings) { [void]$lines.Add("    " + $x) }
    }
    return @($lines)
}
