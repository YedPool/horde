# ExecScan.ps1 - does a PowerShell file start a program, a shell or a script? An allowlist, read from
# the file's syntax tree.
#
# Development tooling, not part of the engine. test/test-link-contracts.ps1 runs it over every file in
# remote/, because the link protocol is never a remote shell (remote-sessions design section 6): the
# verb table cannot express one, and this proves the code beside the table does not hold one either.
#
# WHY AN ALLOWLIST. The first version of this check was a list of banned command names. The review of
# PR #40 (2026-10-01) wrote 27 ways to run something and the list caught 3: a module-qualified name, an
# alias made on the spot, a COM object, a .NET process, a runspace, a WMI or CIM method, a background
# job, compiled C#, a native program called by name, a member called through a variable. A name list
# loses to every spelling it did not think of; an allowlist loses only to what it admits. So:
#
#   1. EVERY COMMAND IS ONE WE NAMED. A command's name must be a cmdlet in $HordeExecCmdlets or a
#      function defined in core/ or remote/ (or in the file itself). Anything else - a native program
#      (git, notepad.exe), a cmdlet nobody reviewed - is a finding. A module-qualified name
#      (Module\Cmdlet) is a finding: it reaches past a function of the same name.
#   2. A COMMAND WITH NO NAME IS A FINDING: `& $x`, `& { }`, `. $x`, `.("ie" + "x")`. The one form of
#      dot-sourcing allowed is the one every file here uses to load its neighbours, at the top of the
#      file: . (Join-Path $PSScriptRoot "<File>.ps1") or . (Join-Path (Split-Path -Parent $PSScriptRoot)
#      "core\<File>.ps1"), the file name a literal.
#   3. SOME CMDLETS ARE REFUSED EVEN IF SOMEONE ADDS THEM TO THE ALLOWLIST ($HordeExecDenied): aliases
#      made at run time, jobs, compiled code, WMI and CIM methods, and the cmdlets that run a string.
#      A function may not take one of their names either, or it would shadow the check.
#   4. FOREACH-OBJECT AND WHERE-OBJECT TAKE A SCRIPT BLOCK AND NOTHING ELSE: `$sb | ForEach-Object
#      Invoke` calls a method by name, so a bare word there is a finding.
#   5. A METHOD CALLED BY ONE OF THE NAMES THAT RUN THINGS ($HordeExecMembers) is a finding, on any
#      object; so is a method or property named by a variable or expression ([Process]::$m(...)), which
#      no allowlist can read.
#   6. A TYPE THAT RUNS THINGS ($HordeExecTypes) is a finding wherever it is named - [Diagnostics.Process]
#      as a cast, a static call or a parameter type - and so is New-Object of it, New-Object -ComObject,
#      and New-Object of a type that is not a literal.
#   7. $ExecutionContext is a finding wherever it is read: it is the engine's own command invoker.
#
# The control is test/fixtures/link/shell-control.ps1, one function per way to run something; every one
# must be found, and test/fixtures/link/shell-clean.ps1, written the way remote/ is written, must not.
# test/mutations/exec-scan.psd1 switches off each rule above and the suite must notice.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

# The cmdlets remote/ may call. It is what remote/Contract.ps1 and remote/Protocol.ps1 use, measured
# from their syntax trees on 2026-10-01, plus the read-only pipeline cmdlets beside them. None starts
# anything. A cmdlet is added here by review, with the reason in the pull request.
$script:HordeExecCmdlets = @("Join-Path", "Split-Path", "New-Object", "Where-Object", "ForEach-Object", "Sort-Object",
    "Select-Object", "Measure-Object", "Add-Member", "ConvertTo-Json", "ConvertFrom-Json", "Get-Date")

# Refused outright, allowlisted or not, and never a function's name. Lower case; matched without case.
$script:HordeExecDenied = @("invoke-expression", "iex", "invoke-command", "icm", "invoke-item", "ii", "start-process",
    "saps", "start", "start-job", "sajb", "start-threadjob", "receive-job", "add-type", "set-alias", "sal", "new-alias",
    "nal", "import-alias", "invoke-cimmethod", "invoke-wmimethod", "register-objectevent", "register-wmievent",
    "register-cimindicationevent", "register-engineevent", "new-pssession", "enter-pssession", "import-module",
    "ipmo", "new-module", "nmo", "set-item", "si", "new-item", "ni", "get-command", "gcm", "invoke-restmethod",
    "invoke-webrequest")

# A method called by one of these names runs code or starts a process, whatever the object.
$script:HordeExecMembers = @("invoke", "invokereturnasis", "invokewithcontext", "invokescript", "invokecommand",
    "begininvoke", "start", "run", "exec", "shellexecute", "create", "createinstance", "newscriptblock",
    "addscript", "addcommand", "gettypefromprogid", "gettypefromclsid", "createprocess")

# A type that runs code or starts a process. Matched without case against the type's name as written,
# and against any name ending in one of these after a dot, so Process, Diagnostics.Process and
# System.Diagnostics.Process are one type.
$script:HordeExecTypes = @("diagnostics.process", "diagnostics.processstartinfo", "process", "processstartinfo",
    "powershell", "management.automation.powershell", "scriptblock", "management.automation.scriptblock",
    "activator", "runspacefactory", "management.automation.runspaces.runspacefactory", "wscript.shell",
    "shell.application", "type")

function Test-HordeExecTypeName {
    # Is Name one of $HordeExecTypes? [type] is in the list for [type]::GetTypeFromProgID; a parameter
    # typed [type] has no use in remote/ either.
    param([string]$Name)
    $n = $Name.Trim().ToLowerInvariant()
    foreach ($t in $script:HordeExecTypes) {
        if ($n -ceq $t -or $n.EndsWith("." + $t)) { return $true }
    }
    return $false
}

function Get-HordeExecFunctionNames {
    # Every function defined in the .ps1 files under each folder in Roots, recursively.
    param([string[]]$Roots)
    $names = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $Roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $r -Filter "*.ps1" -Recurse -File)) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            foreach ($d in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) { [void]$names.Add($d.Name) }
        }
    }
    return $names
}

function Test-HordeExecLoaderDot {
    # Is this dot-sourcing the one allowed form, at the top of the file? See rule 2 above.
    param($Command)
    if ($Command.Parent -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }
    $p = $Command.Parent.Parent
    if ($p -isnot [System.Management.Automation.Language.NamedBlockAst]) { return $false }
    if ($p.Parent -isnot [System.Management.Automation.Language.ScriptBlockAst] -or $null -ne $p.Parent.Parent) { return $false }
    if ($Command.CommandElements.Count -ne 1) { return $false }
    $paren = $Command.CommandElements[0]
    if ($paren -isnot [System.Management.Automation.Language.ParenExpressionAst]) { return $false }
    $inner = $paren.Pipeline
    if ($inner -isnot [System.Management.Automation.Language.PipelineAst] -or $inner.PipelineElements.Count -ne 1) { return $false }
    $join = $inner.PipelineElements[0]
    if ($join -isnot [System.Management.Automation.Language.CommandAst] -or $join.GetCommandName() -cne "Join-Path" -or $join.CommandElements.Count -ne 3) { return $false }
    $base = $join.CommandElements[1].Extent.Text
    $leaf = $join.CommandElements[2]
    if (@('$PSScriptRoot', '(Split-Path -Parent $PSScriptRoot)') -cnotcontains $base) { return $false }
    if ($leaf -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $false }
    return [regex]::IsMatch($leaf.Value, '\A((core|remote)\\)?[A-Za-z][A-Za-z0-9]*\.ps1\z')
}

function Get-HordeExecFindings {
    # Every way Path could start a program, a shell or a script, as "line N: what". Empty means none.
    # Known is the set of function names a command may call besides the allowlisted cmdlets
    # (Get-HordeExecFunctionNames over core/ and remote/); the file's own functions are added to it.
    param([Parameter(Mandatory = $true)][string]$Path, $Known = $null)
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
    $out = New-Object System.Collections.ArrayList
    # A file that does not parse cannot be judged: its tree is partial, so silence would mean nothing.
    foreach ($e in @($errs)) { if ($null -ne $e) { [void]$out.Add("line " + $e.Extent.StartLineNumber + ": does not parse: " + $e.Message) } }
    $funcs = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $Known) { foreach ($k in $Known) { [void]$funcs.Add($k) } }
    foreach ($d in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
        [void]$funcs.Add($d.Name)
        if ($script:HordeExecDenied -contains $d.Name.ToLowerInvariant() -or $script:HordeExecCmdlets -contains $d.Name) {
            [void]$out.Add("line " + $d.Extent.StartLineNumber + ": a function named " + $d.Name + " would shadow a cmdlet this check judges")
        }
    }
    $allowed = $script:HordeExecCmdlets
    foreach ($c in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
        $at = "line " + $c.Extent.StartLineNumber + ": "
        $name = $c.GetCommandName()
        if ($c.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) {
            if (-not (Test-HordeExecLoaderDot $c)) { [void]$out.Add($at + "dot-sourcing something other than a neighbour file by its literal name") }
            continue
        }
        if ($c.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand) { [void]$out.Add($at + "a call with &, which runs whatever it is given"); continue }
        if ($null -eq $name) { [void]$out.Add($at + "a command with no literal name"); continue }
        if ($name.Contains("\") -or $name.Contains("/")) { [void]$out.Add($at + $name + " is module-qualified or a path"); continue }
        if ($script:HordeExecDenied -contains $name.ToLowerInvariant()) { [void]$out.Add($at + $name + " is refused: it runs code, makes an alias, a job or a type, or calls a method of the system"); continue }
        if ($allowed -cnotcontains $name -and -not $funcs.Contains($name)) { [void]$out.Add($at + $name + " is not an allowlisted cmdlet or a function of core/ or remote/ (a native program, or a cmdlet nobody reviewed)"); continue }
        if ($name -ceq "ForEach-Object" -or $name -ceq "Where-Object") {
            for ($i = 1; $i -lt $c.CommandElements.Count; $i++) {
                $el = $c.CommandElements[$i]
                if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                    if (@("Process", "Begin", "End", "FilterScript") -notcontains $el.ParameterName) { [void]$out.Add($at + $name + " -" + $el.ParameterName + ": only a script block may be given") }
                } elseif ($el -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                    [void]$out.Add($at + $name + " given " + $el.Extent.Text + ": only a script block may be given, a name calls a method")
                }
            }
        }
        if ($name -ceq "New-Object") {
            $typeArg = $null
            for ($i = 1; $i -lt $c.CommandElements.Count; $i++) {
                $el = $c.CommandElements[$i]
                if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                    if ($el.ParameterName -like "Com*") { [void]$out.Add($at + "New-Object -ComObject: no COM object is needed here") }
                    elseif ($el.ParameterName -like "T*" -and $i + 1 -lt $c.CommandElements.Count) { $typeArg = $c.CommandElements[$i + 1]; $i++ }
                    elseif ($el.ParameterName -like "A*" -or $el.ParameterName -like "P*") { $i++ }
                    continue
                }
                if ($null -eq $typeArg) { $typeArg = $el }
            }
            if ($null -eq $typeArg -or $typeArg -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { [void]$out.Add($at + "New-Object of a type that is not a literal name") }
            elseif (Test-HordeExecTypeName $typeArg.Value) { [void]$out.Add($at + "New-Object " + $typeArg.Value + ", a type that runs things") }
        }
    }
    foreach ($m in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] }, $true))) {
        $at = "line " + $m.Extent.StartLineNumber + ": "
        if ($m.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { [void]$out.Add($at + "a member named by an expression (" + $m.Member.Extent.Text + "), which no allowlist can read"); continue }
        if ($m -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $script:HordeExecMembers -contains "$($m.Member.Value)".ToLowerInvariant()) {
            [void]$out.Add($at + "the method " + $m.Member.Value + ", which runs code or starts a process")
        }
    }
    foreach ($t in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TypeExpressionAst] -or $n -is [System.Management.Automation.Language.TypeConstraintAst] }, $true))) {
        if (Test-HordeExecTypeName $t.TypeName.FullName) { [void]$out.Add("line " + $t.Extent.StartLineNumber + ": the type [" + $t.TypeName.FullName + "], which runs code or starts a process") }
    }
    foreach ($v in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true))) {
        if ($v.VariablePath.UserPath -eq "ExecutionContext") { [void]$out.Add("line " + $v.Extent.StartLineNumber + ": `$ExecutionContext, the engine's own command invoker") }
    }
    return @($out)
}
