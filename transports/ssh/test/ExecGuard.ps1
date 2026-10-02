# ExecGuard.ps1 - what the ssh adapter's code may run, as an allowlist on its syntax tree. Not a suite:
# transports/ssh/test/test-ssh.ps1 dot-sources it and holds the adapter to it.
#
# WHY AN ALLOWLIST. tools/ExecScan.ps1 scans remote/ only; transports/ has no scan policy yet (Horde
# #53). The first guard here listed the ways to start a program it had thought of, and the review of
# PR #68 (2026-10-02) appended 12 forms to Transport.ps1 that it passed, 12 of 12: a bare ssh.exe
# command, cmd.exe /c, the aliases start and saps, a quoted or a variable member name, a COM Run, a
# dot-invoked or Invoke()d script block, Invoke-Command, $ExecutionContext.InvokeCommand, and an alias
# to the start function. So, as ExecScan does for remote/, every axis is a list of what the adapter
# was measured to use (2026-10-02), and anything else is a finding:
#   - a command is a function the folder defines or one of a few cmdlets, named literally, never a
#     path or a program (no "." in the name), never called with &, and dot-sourced only by the two
#     loader lines at the top of Transport.ps1;
#   - a method is named literally, bare, and is one of the methods measured; Start only as
#     [System.Diagnostics.Process]::Start, exactly once in the folder, inside Start-HordeSshProcess,
#     and that function is called exactly once, by Open, with the System32 path;
#   - a type literal, and a New-Object type, is one of the types measured, and New-Object takes no
#     -ComObject;
#   - no member is named by an expression, and the engine is reached by no variable or property.
# ROUND 2 OF THE REVIEW (2026-10-02) found five more, and the guard now also holds that:
#   - a command is compared ignoring case, as PowerShell does: start-hordesshprocess is the start
#     function, and counts as a second caller;
#   - no using statement and no #requires, either of which loads code before the file runs;
#   - no assignment to an automatic variable ($PSScriptRoot, $ExecutionContext and the rest), to an
#     environment variable, or to the executable's constant once it is set;
#   - the one ProcessStartInfo is made in one canonical expression from $env:SystemRoot and that
#     constant, and none of the start's sensitive properties (FileName, Arguments, Verb, ...) is
#     assigned anywhere: the program to start is fixed where it is named.
# The folder's test/ subfolder is not read: tests start stand-in children on purpose.

$script:HordeSshGuardCmdlets = @("Join-Path", "Split-Path", "Test-Path", "New-Object", "Register-HordeTransport", "New-HordeUnknown", "New-HordeKnown", "Get-HordeHome")
$script:HordeSshGuardLoaders = @('. (Join-Path $PSScriptRoot "Argv.ps1")', '. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")')
$script:HordeSshGuardMethods = @("Add", "AddMilliseconds", "Append", "Ceiling", "Close", "ConnectAsync", "Copy", "Dispose", "EndsWith", "GetProcessById", "GetStream", "GetString", "IndexOf",
    "IsMatch", "Kill", "Match", "Max", "Min", "ReadAllBytes", "ReadAllText", "ReadAsync", "Replace", "Split", "StartsWith", "Substring", "ToArray",
    "ToCharArray", "ToString", "Trim", "TrimEnd", "Wait", "WaitAny", "WaitForExit", "WriteAsync")
$script:HordeSshGuardTypes = @("array", "bool", "byte", "byte[]", "char", "datetime", "int", "long", "math", "pscustomobject", "regex", "string", "string[]",
    "system.collections.generic.list[byte]", "system.diagnostics.process", "system.io.file", "system.io.fileaccess", "system.net.sockets.socketerror",
    "system.net.sockets.socketexception", "system.stringcomparison", "system.text.encoding", "system.threading.tasks.task",
    "system.threading.tasks.task[]", "void")
$script:HordeSshGuardNewTypes = @("System.Diagnostics.ProcessStartInfo", "System.IO.FileStream", "byte[]", "System.Net.Sockets.TcpClient", "System.Text.StringBuilder",
    "System.Collections.Generic.List[byte]")
# Variables that ARE the engine, and properties that lead to it, as tools/ExecScan.ps1 lists them. A
# property named Host on the adapter's own endpoint object is data, so the two lists are kept apart.
$script:HordeSshGuardEngineVariables = @("ExecutionContext", "Host", "PSCmdlet")
$script:HordeSshGuardEngineProperties = @("InvokeCommand", "InvokeProvider", "SessionState", "Runspace", "Module", "ScriptBlock")
# PowerShell's automatic variables (about_Automatic_Variables), none of which the adapter may assign.
# $null is left out: $null = <expression> is the discard idiom and assigns nothing.
$script:HordeSshGuardAutomatic = @("_", "args", "ConsoleFileName", "Error", "Event", "EventArgs", "EventSubscriber", "ExecutionContext", "false", "foreach",
    "HOME", "Host", "input", "LASTEXITCODE", "Matches", "MyInvocation", "NestedPromptLevel", "PID", "PROFILE", "PSBoundParameters", "PSCmdlet",
    "PSCommandPath", "PSCulture", "PSDebugContext", "PSHOME", "PSItem", "PSScriptRoot", "PSSenderInfo", "PSUICulture", "PSVersionTable", "PWD", "Sender",
    "ShellId", "StackTrace", "switch", "this", "true")
# StartInfo's properties that choose what runs, as whom, or where; none may be assigned anywhere.
$script:HordeSshGuardStartProps = @("FileName", "Arguments", "WorkingDirectory", "Verb", "UserName", "Password", "PasswordInClearText", "Domain",
    "LoadUserProfile", "EnvironmentVariables", "Environment", "StartInfo")
# The one way the start is set up, and the one way it is called.
$script:HordeSshGuardStartSetup = 'New-Object System.Diagnostics.ProcessStartInfo -ArgumentList @((Join-Path $env:SystemRoot $script:HordeSshExeRelative), $Arguments)'
$script:HordeSshGuardStartCall = 'Start-HordeSshProcess -Arguments (Join-HordeSshCommandLine -Argv (Get-HordeSshArgv -Endpoint $ep -Paths $paths))'
$script:HordeSshGuardExeConstant = '$script:HordeSshExeRelative = "System32\OpenSSH\ssh.exe"' 

function Get-HordeSshExecFindings {
    # Every finding for the .ps1 files directly in -Dir, as "<file>:<line>: what". Empty means the
    # adapter runs only what the lists above allow, and starts exactly one program, the sanctioned way.
    param([Parameter(Mandatory = $true)][string]$Dir)
    $out = New-Object System.Collections.ArrayList
    $files = @(Get-ChildItem -LiteralPath $Dir -Filter "*.ps1" -File)
    $parsed = @()
    $defined = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $files) {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
        foreach ($e in @($errs)) { if ($null -ne $e) { [void]$out.Add($f.Name + ":" + $e.Extent.StartLineNumber + ": does not parse: " + $e.Message) } }
        if ($null -ne $ast.ScriptRequirements) { [void]$out.Add($f.Name + ":1: a #requires statement, which loads what it names before the file runs") }
        foreach ($d in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) { [void]$defined.Add($d.Name) }
        $parsed += [pscustomobject]@{ name = $f.Name; ast = $ast }
    }
    $starts = New-Object System.Collections.ArrayList
    $callers = New-Object System.Collections.ArrayList
    $setups = New-Object System.Collections.ArrayList
    $exeSets = New-Object System.Collections.ArrayList
    foreach ($p in $parsed) {
        $ast = $p.ast
        function Add-At { param($Node, [string]$What) [void]$out.Add($p.name + ":" + $Node.Extent.StartLineNumber + ": " + $What) }
        foreach ($c in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
            $name = $c.GetCommandName()
            if ($c.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) {
                if ($script:HordeSshGuardLoaders -cnotcontains $c.Parent.Extent.Text.Trim()) { Add-At $c "dot-sourcing other than the two loader lines" }
                continue
            }
            if ($c.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand) { Add-At $c "a call with &, which runs whatever it is given"; continue }
            if ($null -eq $name) { Add-At $c "a command with no literal name"; continue }
            if ($name.Contains(".") -or $name.Contains("\") -or $name.Contains("/")) { Add-At $c ("'" + $name + "' names a program or a path"); continue }
            if (-not $defined.Contains($name) -and $script:HordeSshGuardCmdlets -cnotcontains $name) { Add-At $c ("'" + $name + "' is neither a function this folder defines nor an allowlisted cmdlet"); continue }
            if ($name -ieq "Start-HordeSshProcess") { [void]$callers.Add($c) }
            if ($name -ieq "New-Object" -and $c.Extent.Text -match 'ProcessStartInfo') {
                $fn = $c; while ($null -ne $fn -and $fn -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $fn = $fn.Parent }
                if ($c.Extent.Text -ceq $script:HordeSshGuardStartSetup -and $null -ne $fn -and $fn.Name -ceq "Start-HordeSshProcess") { [void]$setups.Add($c) }
                else { Add-At $c "a ProcessStartInfo made other than by the one canonical expression in Start-HordeSshProcess" }
            }
            if ($name -ieq "New-Object") {
                $els = @($c.CommandElements)
                $typeArg = $null
                for ($i = 1; $i -lt $els.Count; $i++) {
                    $el = $els[$i]
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                        if (@("TypeName", "ArgumentList") -cnotcontains $el.ParameterName) { Add-At $c ("New-Object -" + $el.ParameterName + ": only -TypeName and -ArgumentList") }
                        if ($el.ParameterName -ceq "TypeName" -and $i + 1 -lt $els.Count) { $typeArg = $els[$i + 1]; $i++ }
                        elseif ($el.ParameterName -ceq "ArgumentList") { $i++ }
                        continue
                    }
                    if ($null -eq $typeArg) { $typeArg = $el }
                }
                if ($null -eq $typeArg -or $typeArg -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { Add-At $c "New-Object of a type that is not a literal name" }
                elseif ($script:HordeSshGuardNewTypes -cnotcontains $typeArg.Value) { Add-At $c ("New-Object " + $typeArg.Value + " is not a type the adapter makes") }
            }
        }
        foreach ($m in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] }, $true))) {
            $member = $m.Member
            $isCall = ($m -is [System.Management.Automation.Language.InvokeMemberExpressionAst])
            if ($member -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $member.StringConstantType -ne [System.Management.Automation.Language.StringConstantType]::BareWord) {
                Add-At $m ("a member named by an expression or a quoted string (" + $member.Extent.Text + ")"); continue
            }
            $mn = $member.Value
            if ($script:HordeSshGuardEngineProperties -contains $mn) { Add-At $m ("the member " + $mn + ", which leads to the engine"); continue }
            if (-not $isCall) { continue }
            if ($mn -ceq "Start") {
                $fn = $m; while ($null -ne $fn -and $fn -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $fn = $fn.Parent }
                if ($m.Static -and $m.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and $m.Expression.TypeName.FullName -ceq "System.Diagnostics.Process" -and $null -ne $fn -and $fn.Name -ceq "Start-HordeSshProcess") { [void]$starts.Add($m) }
                else { Add-At $m "a Start other than [System.Diagnostics.Process]::Start in Start-HordeSshProcess" }
                continue
            }
            if ($script:HordeSshGuardMethods -cnotcontains $mn) { Add-At $m ("the method " + $mn + " is not one the adapter calls") }
        }
        foreach ($u in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.UsingStatementAst] }, $true))) { Add-At $u "a using statement, which can load code before the file runs" }
        foreach ($a in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
            $left = $a.Left
            if ($left -is [System.Management.Automation.Language.ConvertExpressionAst]) { $left = $left.Child }
            if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $vp = $left.VariablePath
                $bare = $vp.UserPath
                $colon = $bare.IndexOf(":")
                if ($colon -ge 0) { $bare = $bare.Substring($colon + 1) }
                if ($vp.DriveName -ieq "env") { Add-At $a ("an assignment to the environment variable " + $vp.UserPath); continue }
                if ($script:HordeSshGuardAutomatic -contains $bare) { Add-At $a ("an assignment to the automatic variable $" + $bare); continue }
                if ($bare -ieq "HordeSshExeRelative") {
                    if ($a.Extent.Text -ceq $script:HordeSshGuardExeConstant -and $a.Parent.Parent -is [System.Management.Automation.Language.ScriptBlockAst]) { [void]$exeSets.Add($a) }
                    else { Add-At $a "the executable's constant set other than once, at the top, to System32\OpenSSH\ssh.exe" }
                }
            } elseif ($left -is [System.Management.Automation.Language.MemberExpressionAst]) {
                $lm = $left.Member
                if ($lm -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { Add-At $a "an assignment to a member named by an expression"; continue }
                if ($script:HordeSshGuardStartProps -contains $lm.Value) { Add-At $a ("an assignment to " + $lm.Value + ", which chooses what a started program is") }
            }
        }
        foreach ($t in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TypeExpressionAst] -or $n -is [System.Management.Automation.Language.TypeConstraintAst] }, $true))) {
            if ($script:HordeSshGuardTypes -cnotcontains $t.TypeName.FullName.ToLowerInvariant()) { Add-At $t ("the type [" + $t.TypeName.FullName + "] is not one the adapter names") }
        }
        foreach ($v in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true))) {
            $bare = $v.VariablePath.UserPath
            $colon = $bare.IndexOf(":")
            if ($colon -ge 0) { $bare = $bare.Substring($colon + 1) }
            if ($script:HordeSshGuardEngineVariables -contains $bare) { Add-At $v ("`$" + $v.VariablePath.UserPath + ", which reaches the engine") }
        }
    }
    if ($starts.Count -ne 1) { [void]$out.Add("the folder starts a program " + $starts.Count + " time(s) the sanctioned way; exactly once is allowed") }
    if ($callers.Count -ne 1) { [void]$out.Add("Start-HordeSshProcess is called " + $callers.Count + " time(s) in the folder, in any casing; exactly once, by Open, is allowed") }
    elseif ($callers[0].Extent.Text -cne $script:HordeSshGuardStartCall) { [void]$out.Add("Start-HordeSshProcess is called other than with Open's argv, built from data") }
    if ($setups.Count -ne 1) { [void]$out.Add("the start is set up " + $setups.Count + " time(s) by the canonical expression; exactly once is allowed") }
    if ($exeSets.Count -ne 1) { [void]$out.Add("the executable's constant is set " + $exeSets.Count + " time(s); exactly once, at the top, is allowed") }
    return @($out)
}
