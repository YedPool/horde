# ExecGuard.ps1 - what the ssh adapter's code may run, as an allowlist on its syntax tree. Not a suite:
# transports/ssh/test/test-ssh.ps1 dot-sources it and holds the adapter to it.
#
# THREAT MODEL (decided 2026-10-02, after three review rounds of PR #68). This is a LINT against Horde's
# own code drifting - a contributor's edit or an AI agent's - toward starting something it should not.
# It is NOT a security boundary against a hostile author: no static scan of PowerShell can be sound (a
# name built at run time, reflection, a string handed to the engine), and a hostile author can edit this
# file too. So it closes broad, cheap classes and does not chase one-off forms:
#   - a defined function never shadows a command: every function the folder defines is at the top
#     level, defined once, and named <Verb>-HordeSsh<Noun>, which no cmdlet, built-in function or
#     alias is (round 3: a nested "function Join-Path" in the start function ran cmd.exe);
#   - no assignment through the function:, alias: or variable: drive (round 3: ${function:...} = {}
#     replaced the argv builder);
#   - the program is named without resolving any command: [ProcessStartInfo]::new with
#     [System.IO.Path]::Combine([System.Environment]::SystemDirectory, ...), so neither a shadowed cmdlet
#     nor $env:SystemRoot can change it;
#   - Add-Type only in Native.ps1, with its C# pinned by SHA-256, since C# is not read here.
# DATA IS BY DESIGN: the endpoint ($ep) and the paths ($paths) flow from Open into argv - data in, argv
# out. They are not code and are not policed here; Get-HordeSshArgv re-checks every field it is given
# against the same patterns that parsed it, and Test-HordeSshSafePath every path.
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
#
# A SECOND SANCTIONED START (remote plan R17b, coordinator's approval of 2026-10-06): enrolment makes
# keys with the System32 ssh-keygen.exe. It is held exactly as the first: one [Process]::Start, inside
# New-HordeSshKey in Enroll.ps1 and nowhere else; one canonical setup naming ssh-keygen.exe from the
# system directory; and its argv assigned once, in one pinned expression, so no caller's flag reaches
# it. Anything else that starts a program, anywhere in the folder, is a finding as before.
#
# A THIRD SANCTIONED START (remote plan R17a, coordinator's approval of 2026-10-07): the hub's listener
# runs the System32 sshd.exe as `horde listen`'s child. Held the same way: one [Process]::Start, inside
# Start-HordeSshServer in Listen.ps1 and nowhere else; one canonical setup naming sshd.exe from the
# system directory; and its argv assigned once, in one pinned expression: -D -e -f and the
# configuration Listen.ps1 wrote under Horde's home.

$script:HordeSshGuardCmdlets = @("Move-HordeFileAtomic", "Join-Path", "Split-Path", "Test-Path", "New-Object", "Register-HordeTransport", "New-HordeUnknown", "New-HordeKnown", "Get-HordeHome", "Add-Type",
    # Enroll.ps1 (R17b): its own files under Horde's home, the key's ACL, and its registration.
    "Remove-Item", "Move-Item", "Set-Acl", "Get-Acl", "Where-Object", "ForEach-Object", "Register-HordeEnrollment",
    # Listen.ps1 (R17a): its registration.
    "Register-HordeListener",
    # Listen.ps1, mesh v1 (2026-10-11): the port's rule for which address the hub may listen on, applied again.
    "Get-HordeListenAddressKind")
$script:HordeSshGuardLoaders = @('. (Join-Path $PSScriptRoot "Argv.ps1")', '. (Join-Path $PSScriptRoot "Files.ps1")', '. (Join-Path $PSScriptRoot "Attach.ps1")', '. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\FileAtomic.ps1")', '. (Join-Path $PSScriptRoot "Native.ps1")', '. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "core\Home.ps1")')
# Every function the folder defines (header): no cmdlet, built-in function or alias has this shape.
$script:HordeSshGuardFunctionName = '\A[A-Z][A-Za-z]+-HordeSsh[A-Za-z]+\z'
# Add-Type: only here, and only this source (SHA-256 of the C# with line endings as LF).
$script:HordeSshGuardNativeFile = "Native.ps1"
# Re-pinned 2026-10-07 (issue #147, item 1): LimitProcessMemory added, the listener job's per-process memory cap.
# Re-pinned 2026-10-11 (mesh v1, issue #147 item 2): LimitProcessMemory became LimitListenerJob, which also
# caps the job's memory as a whole and how many processes it may run.
$script:HordeSshGuardNativeSha = "D4647A9BD504D220A357027B336397F478022F81335C5BD9820F87A772094229"
$script:HordeSshGuardMethods = @("GetRandomFileName", "Add", "AddMilliseconds", "Append", "Ceiling", "Close", "ConnectAsync", "Contains", "Copy", "Dispose", "EndsWith", "GetProcessById", "GetStream", "GetString", "IndexOf",
    "IsMatch", "Kill", "Match", "Max", "Min", "Assign", "Combine", "NewKillOnCloseJob", "ReadAllBytes", "ReadAllText", "ReadAsync", "Replace", "Split", "StartsWith", "Substring", "ToArray",
    "ToCharArray", "ToString", "Trim", "TrimEnd", "Wait", "WaitAny", "WaitForExit", "WriteAsync",
    # Enroll.ps1 (R17b), measured 2026-10-06: paths, its own files, the key's ACL, the key's fingerprint
    # and the expiry date. None runs anything.
    "GetFullPath", "GetCurrent", "SetAccessRuleProtection", "SetOwner", "AddAccessRule", "GetAccessRules", "IsPathRooted", "ReadToEndAsync",
    "FromBase64String", "ComputeHash", "Create", "ToBase64String", "ReadAllLines", "WriteAllText", "CreateDirectory", "AddDays",
    # Listen.ps1 (R17a), measured 2026-10-07: its configuration file, the user's name, sshd's start time.
    "ToLowerInvariant", "WriteAllLines", "ToUniversalTime",
    # Listen.ps1, issue #147 items 1 and 2: the listener job's memory caps and process count (Native.ps1).
    "LimitListenerJob",
    # Enroll.ps1, issue #144 item 3 (2026-10-11): an enrolment's expiry read as sshd reads it. None runs anything.
    "ParseExact", "ToLocalTime",
    # Files.ps1, issue #123 (2026-10-11): who owns and may write the link's files and their folders.
    "GetOwner", "Equals",
    # Listen.ps1, mesh v1 (2026-10-11): the address it binds and checks it answers on.
    "Parse",
    # Transport.ps1, the first live mesh link (2026-10-11): the fd state an ssh session handed this process,
    # taken out of ssh.exe's environment. It narrows what the start passes on and runs nothing.
    "Remove")
$script:HordeSshGuardTypes = @("array", "bool", "byte", "byte[]", "char", "datetime", "int", "long", "math", "pscustomobject", "regex", "string", "string[]",
    "system.collections.generic.list[byte]", "system.diagnostics.process", "system.diagnostics.processstartinfo", "system.io.file", "system.io.fileaccess",
    "system.io.path", "system.environment", "hordesshnative", "hordesshjob", "system.management.automation.pstypename", "system.net.sockets.socketerror",
    "system.net.sockets.socketexception", "system.stringcomparison", "system.text.encoding", "system.threading.tasks.task",
    "system.threading.tasks.task[]", "void",
    # Enroll.ps1 (R17b), measured 2026-10-06.
    "system.security.principal.windowsidentity", "system.security.principal.securityidentifier", "system.convert",
    "system.security.cryptography.sha256", "system.io.directory", "switch", "system.globalization.cultureinfo",
    # Listen.ps1, issue #144 item 3 (2026-10-11): the hub's register, handed over as a table of device and key.
    "hashtable",
    # Listen.ps1, mesh v1 (2026-10-11): the address it binds.
    "system.net.ipaddress")
$script:HordeSshGuardNewTypes = @("System.Diagnostics.ProcessStartInfo", "System.IO.FileStream", "byte[]", "System.Net.Sockets.TcpClient", "System.Text.StringBuilder",
    "System.Collections.Generic.List[byte]",
    # Enroll.ps1 (R17b): the key's ACL, and a list of lines.
    "System.Security.AccessControl.FileSecurity", "System.Security.AccessControl.FileSystemAccessRule", "System.Collections.ArrayList")
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
$script:HordeSshGuardStartSetup = '[System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh.exe"), $Arguments)'
$script:HordeSshGuardStartCall = 'Start-HordeSshProcess -Arguments (Join-HordeSshCommandLine -Argv (Get-HordeSshArgv -Endpoint $ep -Paths $paths)) -Job $job'
# The second start (header): where it may be, how it is set up, and its one fixed argv.
$script:HordeSshGuardKeygenFile = "Enroll.ps1"
$script:HordeSshGuardKeygenFunction = "New-HordeSshKey"
$script:HordeSshGuardKeygenSetup = '[System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "ssh-keygen.exe"), $keygenArgs)'
$script:HordeSshGuardKeygenArgv = '$keygenArgs = Join-HordeSshCommandLine -Argv @("-q", "-t", "ed25519", "-N", "", "-C", "horde", "-f", $full)' 
# The third start (header): where it may be, how it is set up, and its one fixed argv.
$script:HordeSshGuardServerFile = "Listen.ps1"
$script:HordeSshGuardServerFunction = "Start-HordeSshServer"
$script:HordeSshGuardServerSetup = '[System.Diagnostics.ProcessStartInfo]::new([System.IO.Path]::Combine([System.Environment]::SystemDirectory, "OpenSSH", "sshd.exe"), $serverArgs)'
$script:HordeSshGuardServerArgv = '$serverArgs = Join-HordeSshCommandLine -Argv @("-D", "-e", "-f", $Config)'

function Get-HordeSshExecFindings {
    # Every finding for the .ps1 files directly in -Dir, as "<file>:<line>: what". Empty means the
    # adapter runs only what the lists above allow, and starts exactly one program, the sanctioned way.
    param([Parameter(Mandatory = $true)][string]$Dir)
    $out = New-Object System.Collections.ArrayList
    $files = @(Get-ChildItem -LiteralPath $Dir -Filter "*.ps1" -File)
    $parsed = @()
    $seenNames = @{}
    $defined = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $files) {
        $tokens = $null; $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errs)
        foreach ($e in @($errs)) { if ($null -ne $e) { [void]$out.Add($f.Name + ":" + $e.Extent.StartLineNumber + ": does not parse: " + $e.Message) } }
        if ($null -ne $ast.ScriptRequirements) { [void]$out.Add($f.Name + ":1: a #requires statement, which loads what it names before the file runs") }
        foreach ($d in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
            [void]$defined.Add($d.Name)
            $at = $f.Name + ":" + $d.Extent.StartLineNumber + ": "
            # TOP LEVEL, ONCE, AND NAMED SO IT SHADOWS NOTHING (header).
            if (-not ($d.Parent -is [System.Management.Automation.Language.NamedBlockAst] -and $null -eq $d.Parent.Parent.Parent)) { [void]$out.Add($at + "the function " + $d.Name + " is defined inside something else, where it shadows a command of the same name") }
            if (-not [regex]::IsMatch($d.Name, $script:HordeSshGuardFunctionName)) { [void]$out.Add($at + "the function " + $d.Name + " is not named <Verb>-HordeSsh<Noun>, so it could shadow a cmdlet, a function or an alias") }
            if ($seenNames.ContainsKey($d.Name.ToLowerInvariant())) { [void]$out.Add($at + "the function " + $d.Name + " is defined a second time, replacing the first") }
            $seenNames[$d.Name.ToLowerInvariant()] = $true
        }
        $parsed += [pscustomobject]@{ name = $f.Name; ast = $ast }
    }
    $starts = New-Object System.Collections.ArrayList
    $callers = New-Object System.Collections.ArrayList
    $setups = New-Object System.Collections.ArrayList
    $keygenStarts = New-Object System.Collections.ArrayList
    $keygenSetups = New-Object System.Collections.ArrayList
    $keygenArgvs = New-Object System.Collections.ArrayList
    $serverStarts = New-Object System.Collections.ArrayList
    $serverSetups = New-Object System.Collections.ArrayList
    $serverArgvs = New-Object System.Collections.ArrayList
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
            if ($name -ieq "New-Object" -and $c.Extent.Text -match 'ProcessStartInfo') { Add-At $c "a ProcessStartInfo made with New-Object: only the one canonical ::new in Start-HordeSshProcess" }
            if ($name -ieq "Add-Type") {
                $src = $null
                for ($i = 1; $i -lt $c.CommandElements.Count; $i++) {
                    $el = $c.CommandElements[$i]
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst] -and $el.ParameterName -ceq "TypeDefinition" -and $i + 1 -lt $c.CommandElements.Count) { $src = $c.CommandElements[$i + 1] }
                }
                if ($p.name -cne $script:HordeSshGuardNativeFile) { Add-At $c "Add-Type outside Native.ps1" }
                elseif ($src -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { Add-At $c "Add-Type of a source that is not one literal string" }
                else {
                    $sha = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($src.Value.Replace("`r`n", "`n")))).Replace("-", "")
                    if ($sha -cne $script:HordeSshGuardNativeSha) { Add-At $c ("Add-Type of C# that is not the pinned source (SHA-256 " + $sha + "); a reviewer changes the pin with the code") }
                }
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
            if ($mn -ceq "new") {
                $fn = $m; while ($null -ne $fn -and $fn -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $fn = $fn.Parent }
                $assign = $m.Parent
                $isPsi = ($m.Static -and $m.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and $m.Expression.TypeName.FullName -ceq "System.Diagnostics.ProcessStartInfo" -and $null -ne $fn)
                if ($isPsi -and $m.Extent.Text -ceq $script:HordeSshGuardStartSetup -and $fn.Name -ceq "Start-HordeSshProcess") { [void]$setups.Add($m) }
                elseif ($isPsi -and $m.Extent.Text -ceq $script:HordeSshGuardKeygenSetup -and $fn.Name -ceq $script:HordeSshGuardKeygenFunction -and $p.name -ceq $script:HordeSshGuardKeygenFile) { [void]$keygenSetups.Add($m) }
                elseif ($isPsi -and $m.Extent.Text -ceq $script:HordeSshGuardServerSetup -and $fn.Name -ceq $script:HordeSshGuardServerFunction -and $p.name -ceq $script:HordeSshGuardServerFile) { [void]$serverSetups.Add($m) }
                else { Add-At $m "a ::new other than the canonical ProcessStartInfo in Start-HordeSshProcess, New-HordeSshKey or Start-HordeSshServer" }
                continue
            }
            if ($mn -ceq "Start") {
                $fn = $m; while ($null -ne $fn -and $fn -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $fn = $fn.Parent }
                $isProc = ($m.Static -and $m.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and $m.Expression.TypeName.FullName -ceq "System.Diagnostics.Process" -and $null -ne $fn)
                if ($isProc -and $fn.Name -ceq "Start-HordeSshProcess") { [void]$starts.Add($m) }
                elseif ($isProc -and $fn.Name -ceq $script:HordeSshGuardKeygenFunction -and $p.name -ceq $script:HordeSshGuardKeygenFile) { [void]$keygenStarts.Add($m) }
                elseif ($isProc -and $fn.Name -ceq $script:HordeSshGuardServerFunction -and $p.name -ceq $script:HordeSshGuardServerFile) { [void]$serverStarts.Add($m) }
                else { Add-At $m "a Start other than [System.Diagnostics.Process]::Start in Start-HordeSshProcess, New-HordeSshKey or Start-HordeSshServer" }
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
                # The drive from the path's own text: ${variable:x} parses with no DriveName (measured).
                $drive = ""
                if ($vp.UserPath.Contains(":")) { $drive = $vp.UserPath.Substring(0, $vp.UserPath.IndexOf(":")) }
                if (@("function", "alias", "variable") -contains $drive) { Add-At $a ("an assignment through the " + $drive + ": drive, which replaces a command or a variable by name"); continue }
                if ($script:HordeSshGuardAutomatic -contains $bare) { Add-At $a ("an assignment to the automatic variable $" + $bare); continue }
                if ($bare -ieq "keygenArgs") { [void]$keygenArgvs.Add($a) }
                if ($bare -ieq "serverArgs") { [void]$serverArgvs.Add($a) }
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
    # The second start is optional - a copy of the folder without Enroll.ps1 has none - but never more
    # than one, and only with its pinned setup and argv.
    if ($keygenStarts.Count -gt 1) { [void]$out.Add("New-HordeSshKey starts a program " + $keygenStarts.Count + " times; at most once is allowed") }
    if ($keygenStarts.Count -ne $keygenSetups.Count) { [void]$out.Add("New-HordeSshKey starts a program " + $keygenStarts.Count + " time(s) but sets up ssh-keygen.exe the canonical way " + $keygenSetups.Count + " time(s)") }
    if ($keygenStarts.Count -eq 1) {
        if ($keygenArgvs.Count -ne 1) { [void]$out.Add("ssh-keygen's argv is assigned " + $keygenArgvs.Count + " time(s); exactly once, in the pinned expression, is allowed") }
        elseif ($keygenArgvs[0].Extent.Text -cne $script:HordeSshGuardKeygenArgv) { [void]$out.Add("ssh-keygen's argv is not the pinned one: no caller's flag may reach it (" + $keygenArgvs[0].Extent.Text + ")") }
    }
    # The third start, the same way: optional, at most once, only with its pinned setup and argv.
    if ($serverStarts.Count -gt 1) { [void]$out.Add("Start-HordeSshServer starts a program " + $serverStarts.Count + " times; at most once is allowed") }
    if ($serverStarts.Count -ne $serverSetups.Count) { [void]$out.Add("Start-HordeSshServer starts a program " + $serverStarts.Count + " time(s) but sets up sshd.exe the canonical way " + $serverSetups.Count + " time(s)") }
    if ($serverStarts.Count -eq 1) {
        if ($serverArgvs.Count -ne 1) { [void]$out.Add("sshd's argv is assigned " + $serverArgvs.Count + " time(s); exactly once, in the pinned expression, is allowed") }
        elseif ($serverArgvs[0].Extent.Text -cne $script:HordeSshGuardServerArgv) { [void]$out.Add("sshd's argv is not the pinned one: no caller's flag may reach it (" + $serverArgvs[0].Extent.Text + ")") }
    }
    return @($out)
}
