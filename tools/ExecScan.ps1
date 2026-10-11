# ExecScan.ps1 - can a PowerShell file start a program, a shell or a script? An allowlist on every axis
# of the file's syntax tree.
#
# Development tooling, not part of the engine. test/test-exec-scan.ps1 runs it over every file in
# remote/, because the link protocol is never a remote shell (remote-sessions design section 6): the
# verb table cannot express one, and this proves the code beside the table does not hold one either.
#
# WHY EVERY AXIS IS AN ALLOWLIST. The first scan was a list of banned command names; the review of PR
# #40 (2026-10-01) wrote 27 ways to run something and it caught 3. The second allowlisted commands but
# kept lists of banned METHODS and TYPES, and the verification of the same day got past it seven more
# ways: [Microsoft.VisualBasic.Interaction]::Shell, ([wmiclass]'Win32_Process').InvokeMethod,
# $global:ExecutionContext...ExpandString, a script block made through GetType and CreateDelegate and
# handed to ForEach-Object -Process:$sb, script blocks given to Select-Object, Sort-Object and an
# Add-Member ScriptMethod, and core's Invoke-HordeRead, which runs the block it is given. A banned list
# loses to every name it did not think of. So each axis below admits only what remote/ was measured to
# need (its syntax trees, 2026-10-02), and everything else is a finding:
#
#   1. COMMANDS: a cmdlet of $HordeExecCmdlets, a function defined in the scanned files, or one of the
#      core/ functions of $HordeExecCoreFunctions - not every core function: Invoke-HordeRead runs the
#      block it is given. A command with no literal name, a call with &, a module-qualified name, and
#      any dot-sourcing but the loader line at the top of the file are findings. A function may not
#      take the name of an allowlisted cmdlet or core function.
#   2. ARGUMENTS of the cmdlets that would run a script block or a member name: ForEach-Object and
#      Where-Object take a literal script block (positional, -Process or -FilterScript) and nothing
#      else; Select-Object, Sort-Object and Measure-Object take parameters and literal names, never a
#      script block, a hashtable (a calculated property is a script block) or a variable; Add-Member
#      takes only -NotePropertyName, -NotePropertyValue, -InputObject, -Force and -PassThru; New-Object
#      takes a literal type from $HordeExecNewTypes and -ArgumentList.
#   3. SCRIPT BLOCKS: a { } may stand only as an argument of ForEach-Object or Where-Object, where its
#      body is scanned like the rest. Anywhere else - a variable, an attribute, any other command - is a
#      finding. With no literal block to hand on, no [scriptblock] type, no GetType and no
#      $ExecutionContext, remote/ has no way to hold a script block at all.
#   4. TYPES: every [type] - a literal, a cast, a parameter type, a static call - is one of
#      $HordeExecTypes. Attributes are one of $HordeExecAttributes. Class definitions and using
#      statements are findings.
#   5. STATIC MEMBERS: [Type]::Member only as listed for that type in $HordeExecStatic.
#   6. INSTANCE METHODS: the type of a value is not known from its syntax, so a method call on one may
#      use only a name in $HordeExecInstanceMethods, each harmless on any type it could be. GetType,
#      and every Invoke*, Create*, Start*, Run*, Exec* and Expand*, are not on it. A member named by an
#      expression ($o.$m()) is a finding.
#   7. VARIABLES: plain names, or the script: scope. Any other scope or drive (global:, using:, env:,
#      function:, variable:), and $ExecutionContext, $Host, $MyInvocation and $PSCmdlet in any form,
#      are findings.
#   8. PROPERTY READS are data, and remote/ reads arbitrary field names of parsed JSON, so they cannot
#      be a list of names. LEAVING THEM OPEN IS SAFE ONLY BECAUSE NO SCRIPT BLOCK CAN BE HELD: no
#      literal script block outside ForEach-Object and Where-Object (rule 3), no [scriptblock] type
#      (rule 4), no GetType (rule 6) and no $ExecutionContext (rule 7). Without a script block there is
#      no ScriptProperty to add and no hostile getter to reach. If any of those four ever loosens, this
#      rule must become a list too; test/mutations/exec-scan.psd1 re-allows [scriptblock] and the suite
#      must fail, so the argument stays enforced. The properties that lead to the engine itself
#      ($HordeExecProperties: InvokeCommand, Assembly, Runspace, SessionState, ScriptBlock, Module) are
#      findings all the same, a second line behind rule 7.
#
# The control is test/fixtures/link/shell-control.ps1, one function per way to run something, each
# line naming the finding it must get; test/fixtures/link/shell-clean.ps1, written the way remote/ is
# written, must have none. test/mutations/exec-scan.psd1 switches off each rule.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

# Rule 1. The cmdlets remote/ calls, measured, plus the read-only pipeline cmdlets beside them.
$script:HordeExecCmdlets = @("Join-Path", "Split-Path", "New-Object", "Where-Object", "ForEach-Object", "Sort-Object",
    "Select-Object", "Measure-Object", "Add-Member", "ConvertTo-Json", "ConvertFrom-Json", "Get-Date",
    # remote/Journal.ps1 (plan step R3) keeps its records as files in a folder it is given. THIS SCAN
    # IS ABOUT STARTING A PROCESS OR REACHING THE ENGINE, NOT ABOUT DISK: the journal must read, write
    # and list its own files. Get-ChildItem lists the journal folder (its high-water marks and records);
    # New-TimeSpan is arithmetic on times.
    "Get-ChildItem", "New-TimeSpan")
# Rule 1. The core/ functions remote/ calls, measured. None takes or runs a script block.
$script:HordeExecCoreFunctions = @("Get-HordeSchema", "Test-HordeSchema", "Read-HordeSchemaFile",
    # core/Tristate.ps1's constructors and converters, which the journal answers in. Each takes plain
    # values; Invoke-HordeRead, in the same file, takes a script block and is NOT here.
    "New-HordeKnown", "New-HordeAbsent", "New-HordeUnknown", "ConvertTo-HordeAnswerRecord", "ConvertFrom-HordeAnswerRecord",
    # Limit-HordeAge (remote plan R6, remote/Clock.ps1): ages a remote answer by the hub's receive time.
    # It takes an answer, a TTL and a time - plain values - and returns an answer; it calls
    # Assert-HordeAnswer and the constructors above, and runs nothing it is given. Its -Now defaults
    # to Get-Date (already allowed); remote/Clock.ps1 always passes a UTC -Now. Added 2026-10-02.
    "Limit-HordeAge",
    # The link walk (remote/Contract.ps1, fix/link-writer-speed) reads each schema node once into a
    # record and must read it exactly as Test-HordeSchema does: Get-HordeSchemaNode and
    # Assert-HordeSchema are the reads Test-HordeSchema itself makes (they take a schema and return its
    # checked keywords and compiled pattern, or throw), and Test-HordeSchemaType, Test-HordeSchemaIsNumber
    # and Compare-HordeSchemaNumber are the type and minimum checks it applies, called for the rare value
    # the walk does not check inline. Each takes plain values and runs nothing it is given. Added 2026-10-02.
    "Get-HordeSchemaNode", "Assert-HordeSchema", "Test-HordeSchemaType", "Test-HordeSchemaIsNumber", "Compare-HordeSchemaNumber")
# Rule 1. The core files remote/ may dot-source: the ones defining the functions above.
$script:HordeExecCoreFiles = @("Schema.ps1", "Tristate.ps1")

# Rule 2. The types New-Object may make.
$script:HordeExecNewTypes = @("System.Collections.ArrayList", "System.Collections.Stack", "System.Collections.Generic.List[string]",
    "System.Text.StringBuilder", "byte[]",
    # The journal's file access: a FileStream opens one journal file to read or to create (CreateNew,
    # WriteThrough), a StreamReader reads it, UTF8Encoding (no BOM) spells its text, and a datetime is
    # rebuilt from a high-water mark's ticks. None of them runs anything.
    "System.IO.FileStream", "System.IO.StreamReader", "System.Text.UTF8Encoding", "datetime",
    # The link walk's records (remote/Contract.ps1): property names to records, by exact name and
    # without case, as core/Schema.ps1 and PowerShell's member lookup match them. A dictionary of data.
    "System.Collections.Generic.Dictionary[string,object]")

# Rule 4. The types that may be named, lower case, without a leading "system.". An array of one is
# allowed as the type itself is.
$script:HordeExecTypes = @("string", "int", "long", "bool", "byte", "sbyte", "char", "int16", "uint16", "uint32", "uint64",
    "decimal", "double", "single", "datetime", "guid", "regex", "math", "array", "hashtable", "ordered", "pscustomobject",
    "management.automation.pscustomobject", "void", "switch", "ref", "collections.idictionary", "collections.ilist",
    "globalization.cultureinfo", "globalization.datetimestyles", "stringcomparison", "stringcomparer", "text.encoding",
    # io.stream: allowed only because the one stream remote/ holds is the link's own pipe, handed to
    # New-HordeFrameReader by the transport; remote/ never opens a stream itself.
    "io.stream",
    # remote/Journal.ps1's own files (see $HordeExecCmdlets): File and Directory for the static members
    # listed in $HordeExecStatic (Delete, CreateDirectory) and nothing else; the enums a FileStream is
    # opened with; the exceptions a failed open is told apart by; SHA-256 for a request's argsHash;
    # DateTimeKind for UTC times; Int32 and Int64 are int and long by their CLR names.
    "io.file", "io.directory", "io.filemode", "io.fileaccess", "io.fileshare", "io.fileoptions", "io.ioexception",
    "io.filenotfoundexception", "io.directorynotfoundexception", "security.cryptography.sha256", "datetimekind",
    "int32", "int64", "io.fileattributes", "io.path",
    # collections.ienumerable: the link's answer rules (remote/Contract.ps1, Test-HordeLinkAnswer) ask
    # whether a member is something PowerShell would unroll on return, to keep the old reading of it
    # (issue #77). An interface named in a type test; nothing is made or run with it.
    "collections.ienumerable")
$script:HordeExecAttributes = @("Parameter", "CmdletBinding")

# Rule 5. Per type (named as in $HordeExecTypes), the static members that may be read or called.
$script:HordeExecStatic = @{
    "datetime" = @("TryParseExact", "MinValue", "UtcNow", "TryParse")
    "decimal" = @("Truncate")
    "double" = @("IsNaN", "IsInfinity")
    "datetimekind" = @("Utc", "Unspecified")
    # The journal's files (see $HordeExecTypes): delete one of its own files, create its own folder.
    # GetAttributes: the journal reads a path's attributes to refuse a junction or a symbolic link
    # before it writes or deletes there (Resolve-HordeJournalPath).
    "io.file" = @("Delete", "GetAttributes")
    "io.fileattributes" = @("ReparsePoint")
    # Path arithmetic only, to confine every journal path to its root: nothing here touches a file.
    "io.path" = @("GetFullPath", "Combine", "GetDirectoryName", "IsPathRooted")
    "io.directory" = @("CreateDirectory")
    "io.filemode" = @("Open", "CreateNew")
    "io.fileaccess" = @("Read", "Write")
    "io.fileshare" = @("Read", "None")
    "io.fileoptions" = @("WriteThrough")
    # A factory for the hash algorithm, not a script block or a process: SHA256.Create returns a hasher.
    "security.cryptography.sha256" = @("Create")
    "regex" = @("Match", "Replace", "Split", "IsMatch")
    "string" = @("Equals")
    "globalization.cultureinfo" = @("InvariantCulture")
    "globalization.datetimestyles" = @("AdjustToUniversal", "AssumeUniversal", "RoundtripKind")
    # OrdinalIgnoreCase: the journal compares a resolved folder with its root as Windows does, without case.
    "stringcomparison" = @("Ordinal", "OrdinalIgnoreCase")
    # OrdinalIgnoreCase: the link walk finds a property's schema without case, as Get-HordeLinkProp's
    # .PSObject.Properties lookup did (remote/Contract.ps1, Get-HordeLinkWalkRecord).
    "stringcomparer" = @("Ordinal", "OrdinalIgnoreCase")
    "array" = @("Copy", "IndexOf", "Sort")
    "char" = @("IsHighSurrogate", "IsLowSurrogate")
    "guid" = @("NewGuid")
    "math" = @("Min", "Max", "Floor", "Abs")
    # GetEncoding: allowed only because it decodes the link's own pipe (Latin-1, one character per byte,
    # to find a byte outside printable ASCII in a received frame); it names an encoding and opens nothing.
    "text.encoding" = @("GetEncoding", "ASCII")
}

# Rule 6. Instance methods remote/ calls, measured, each one that reads, formats or adds to a
# collection whatever type it lands on.
$script:HordeExecInstanceMethods = @("ToString", "Trim", "Split", "Contains", "StartsWith", "EndsWith", "Substring", "IndexOf",
    "Replace", "Add", "ContainsKey", "Pop", "Push", "ToArray", "ToLowerInvariant", "Append", "ToCharArray", "ToUniversalTime",
    "GetBytes", "GetString",
    # Read: allowed only because the stream it reads is the link's own pipe (Read-HordeFrameLine reads
    # the transport's stream into a bounded buffer); remote/ holds no other stream to read.
    "Read",
    # The journal's own files: write and flush a record, read one back, close what was opened; trim a
    # number's trailing zeros; hash the canonical arguments.
    "Write", "Flush", "ReadToEnd", "Dispose", "TrimEnd", "ComputeHash", "IndexOfAny",
    # IsMatch: the link walk matches a string with the Regex core/Schema.ps1 compiled for the schema's
    # pattern (Get-HordeSchemaNode), as Test-HordeSchema does; it matches text and runs nothing.
    "IsMatch")

# Rule 7. Variables refused whatever their scope.
$script:HordeExecVariables = @("ExecutionContext", "Host", "MyInvocation", "PSCmdlet")
# Rule 8.
$script:HordeExecProperties = @("InvokeCommand", "Assembly", "Runspace", "SessionState", "ScriptBlock", "Module")

function ConvertTo-HordeExecTypeKey {
    # A type name as the lists above spell it: lower case, no leading "system.", no array brackets.
    param([string]$Name)
    $n = $Name.Trim().ToLowerInvariant()
    while ($n.EndsWith("[]")) { $n = $n.Substring(0, $n.Length - 2) }
    if ($n.StartsWith("system.")) { $n = $n.Substring(7) }
    return $n
}

function Get-HordeExecFunctionNames {
    # Every function defined in the .ps1 files under each folder in Roots, recursively: the functions
    # remote/ defines for itself. core/ is NOT read this way; its callable functions are listed above.
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
    # Is this dot-sourcing the one allowed form, at the top of the file?
    #   . (Join-Path $PSScriptRoot "<File>.ps1")   or   . (Join-Path (Split-Path -Parent $PSScriptRoot) "core\<File>.ps1")
    # where a core file is one of $HordeExecCoreFiles: the core files whose functions remote/ may call.
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
    if ($leaf.Value.StartsWith("core\")) { return ($script:HordeExecCoreFiles -ccontains $leaf.Value.Substring(5)) }
    return [regex]::IsMatch($leaf.Value, '\A[A-Za-z][A-Za-z0-9]*\.ps1\z')
}

function Get-HordeExecArgFindings {
    # Rule 2: the arguments of the cmdlets that could run a script block or a member name.
    param($Command, [string]$Name, [string]$At)
    $out = New-Object System.Collections.ArrayList
    $els = @($Command.CommandElements)
    $blocksOnly = ($Name -ceq "ForEach-Object" -or $Name -ceq "Where-Object")
    $namesOnly = ($Name -ceq "Select-Object" -or $Name -ceq "Sort-Object" -or $Name -ceq "Measure-Object")
    for ($i = 1; $i -lt $els.Count; $i++) {
        $el = $els[$i]
        if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
            $pn = $el.ParameterName
            $bound = $el.Argument
            if ($blocksOnly) {
                if (@("Process", "FilterScript") -notcontains $pn) { [void]$out.Add($At + $Name + " -" + $pn + ": only a literal script block may be given") }
                elseif ($null -ne $bound -and $bound -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { [void]$out.Add($At + $Name + " -" + $pn + ":" + $bound.Extent.Text + ": only a literal script block may be given") }
            } elseif ($namesOnly) {
                if ($null -ne $bound -and ($bound -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or $bound -is [System.Management.Automation.Language.HashtableAst])) { [void]$out.Add($At + $Name + " -" + $pn + " given a script block or a calculated property") }
            } elseif ($Name -ceq "Add-Member") {
                if (@("NotePropertyName", "NotePropertyValue", "InputObject", "Force", "PassThru") -notcontains $pn) { [void]$out.Add($At + "Add-Member -" + $pn + ": only a note property may be added") }
            } elseif ($Name -ceq "New-Object") {
                if (@("TypeName", "ArgumentList") -notcontains $pn) { [void]$out.Add($At + "New-Object -" + $pn + ": only -TypeName and -ArgumentList") }
            }
            continue
        }
        $prev = $null
        if ($i -gt 1 -and $els[$i - 1] -is [System.Management.Automation.Language.CommandParameterAst] -and $null -eq $els[$i - 1].Argument) { $prev = $els[$i - 1].ParameterName }
        if ($blocksOnly) {
            if ($el -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { [void]$out.Add($At + $Name + " given " + $el.Extent.Text + ": only a literal script block may be given") }
        } elseif ($namesOnly) {
            $isCount = (@("First", "Last", "Skip") -contains $prev)
            if ($el -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -or $el -is [System.Management.Automation.Language.HashtableAst]) { [void]$out.Add($At + $Name + " given a script block or a calculated property") }
            elseif (-not $isCount -and $el -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { [void]$out.Add($At + $Name + " given " + $el.Extent.Text + ": only literal property names") }
        } elseif ($Name -ceq "Add-Member") {
            if (@("NotePropertyName", "NotePropertyValue", "InputObject") -notcontains $prev) { [void]$out.Add($At + "Add-Member given " + $el.Extent.Text + " by position: only a named note property") }
        }
    }
    if ($Name -ceq "New-Object") {
        $typeArg = $null
        for ($i = 1; $i -lt $els.Count; $i++) {
            $el = $els[$i]
            if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($el.ParameterName -ceq "TypeName" -and $i + 1 -lt $els.Count) { $typeArg = $els[$i + 1]; $i++ }
                elseif ($el.ParameterName -ceq "ArgumentList") { $i++ }
                continue
            }
            if ($null -eq $typeArg) { $typeArg = $el }
        }
        if ($null -eq $typeArg -or $typeArg -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { [void]$out.Add($At + "New-Object of a type that is not a literal name") }
        elseif ($script:HordeExecNewTypes -notcontains $typeArg.Value) { [void]$out.Add($At + "New-Object " + $typeArg.Value + " is not a type New-Object may make here") }
    }
    return @($out)
}

function Get-HordeExecFindings {
    # Every way Path could start a program, a shell or a script, as "line N: what". Empty means none.
    # Known is the set of functions the scanned code defines for itself (Get-HordeExecFunctionNames
    # over remote/); the file's own functions and $HordeExecCoreFunctions are added to it.
    param([Parameter(Mandatory = $true)][string]$Path, $Known = $null)
    $tokens = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
    $out = New-Object System.Collections.ArrayList
    # A file that does not parse cannot be judged: its tree is partial, so silence would mean nothing.
    foreach ($e in @($errs)) { if ($null -ne $e) { [void]$out.Add("line " + $e.Extent.StartLineNumber + ": does not parse: " + $e.Message) } }
    $funcs = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $Known) { foreach ($k in $Known) { [void]$funcs.Add($k) } }
    foreach ($k in $script:HordeExecCoreFunctions) { [void]$funcs.Add($k) }
    foreach ($d in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
        if ($script:HordeExecCmdlets -contains $d.Name -or $script:HordeExecCoreFunctions -contains $d.Name) {
            [void]$out.Add("line " + $d.Extent.StartLineNumber + ": a function named " + $d.Name + " would shadow a command this check allows")
        }
        [void]$funcs.Add($d.Name)
    }
    # Rule 4: no classes, no using statements, attributes from the list.
    foreach ($n in @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.TypeDefinitionAst] -or $x -is [System.Management.Automation.Language.UsingStatementAst] }, $true))) {
        [void]$out.Add("line " + $n.Extent.StartLineNumber + ": a class or a using statement")
    }
    foreach ($a in @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.AttributeAst] }, $true))) {
        if ($script:HordeExecAttributes -notcontains $a.TypeName.FullName) { [void]$out.Add("line " + $a.Extent.StartLineNumber + ": the attribute [" + $a.TypeName.FullName + "()] is not one of " + ($script:HordeExecAttributes -join ", ")) }
    }
    # Rule 1 and rule 2.
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
        if ($script:HordeExecCmdlets -cnotcontains $name -and -not $funcs.Contains($name)) { [void]$out.Add($at + $name + " is not an allowlisted cmdlet or a function this code may call"); continue }
        foreach ($f in @(Get-HordeExecArgFindings -Command $c -Name $name -At $at)) { [void]$out.Add($f) }
    }
    # Rule 3: a script block only as an argument of ForEach-Object or Where-Object.
    foreach ($b in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true))) {
        $holder = $b.Parent
        if ($holder -is [System.Management.Automation.Language.CommandParameterAst]) { $holder = $holder.Parent }
        $ok = ($holder -is [System.Management.Automation.Language.CommandAst] -and @("ForEach-Object", "Where-Object") -ccontains $holder.GetCommandName() -and $holder.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Unknown)
        if (-not $ok) { [void]$out.Add("line " + $b.Extent.StartLineNumber + ": a script block that is not the body of ForEach-Object or Where-Object") }
    }
    # Rule 4: every type named.
    foreach ($t in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TypeExpressionAst] -or $n -is [System.Management.Automation.Language.TypeConstraintAst] }, $true))) {
        if ($script:HordeExecTypes -notcontains (ConvertTo-HordeExecTypeKey $t.TypeName.FullName)) { [void]$out.Add("line " + $t.Extent.StartLineNumber + ": the type [" + $t.TypeName.FullName + "] is not one this code may name") }
    }
    # Rules 5, 6 and 8: members.
    foreach ($m in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] }, $true))) {
        $at = "line " + $m.Extent.StartLineNumber + ": "
        if ($m.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { [void]$out.Add($at + "a member named by an expression (" + $m.Member.Extent.Text + "), which no allowlist can read"); continue }
        $member = $m.Member.Value
        $isCall = ($m -is [System.Management.Automation.Language.InvokeMemberExpressionAst])
        if ($m.Static) {
            if ($m.Expression -isnot [System.Management.Automation.Language.TypeExpressionAst]) { [void]$out.Add($at + "a static member ::" + $member + " of something that is not a type literal"); continue }
            $key = ConvertTo-HordeExecTypeKey $m.Expression.TypeName.FullName
            $allowedStatic = @()
            if ($script:HordeExecStatic.ContainsKey($key)) { $allowedStatic = @($script:HordeExecStatic[$key]) }
            if ($allowedStatic -cnotcontains $member) { [void]$out.Add($at + "[" + $m.Expression.TypeName.FullName + "]::" + $member + " is not a static member this code may use") }
        } elseif ($isCall) {
            if ($script:HordeExecInstanceMethods -cnotcontains $member) { [void]$out.Add($at + "the method " + $member + " is not one this code may call") }
        } elseif ($script:HordeExecProperties -contains $member) {
            [void]$out.Add($at + "the property " + $member + ", which leads to the engine")
        }
    }
    # Rule 7: variables.
    foreach ($v in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true))) {
        $at = "line " + $v.Extent.StartLineNumber + ": "
        $vp = $v.VariablePath
        $bare = $vp.UserPath
        $colon = $bare.IndexOf(":")
        if ($colon -ge 0) { $bare = $bare.Substring($colon + 1) }
        if ($script:HordeExecVariables -contains $bare) { [void]$out.Add($at + "`$" + $vp.UserPath + ", which reaches the engine"); continue }
        if (-not ($vp.IsUnqualified -or $vp.IsScript)) { [void]$out.Add($at + "`$" + $vp.UserPath + ": only plain variables and the script: scope") }
    }
    return @($out)
}

# THE RELAY PROFILE (relay design 2026-10-09, PR 1). relay/ reads text from an untrusted relay, so it is
# held to the same promise as remote/ - it starts no program and no shell, and runs no script block it
# is given - under a WIDER allowlist of what it may name: the cryptography types it needs, measured from
# relay/'s syntax trees on 2026-10-09. Nothing above changes for remote/: Get-HordeExecRelayFindings
# adds these lists for the one call and puts the remote lists back after it, whatever happens.
#
# WHY EACH WIDENING IS SAFE, axis by axis:
#   - TYPES, NEW-OBJECT TYPES AND STATIC MEMBERS: .NET cryptography (ECDsa, ECDiffieHellman, their Cng
#     forms, CngKey and its enums, ECParameters, ECPoint, ECCurve, HMACSHA256, AesGcm,
#     RandomNumberGenerator, HashAlgorithmName), Convert's base64 and hex members, and relay's own
#     compiled HordeRelayGcmV1. None starts a process or reaches the engine. [type] is allowed for one
#     use - "<name>" -as [type], to ask whether a type is loaded - and has no static member on the list.
#     [object] is a parameter type.
#   - INSTANCE METHODS: the key operations (SignData, VerifyData, DeriveKeyFromHmac, ImportParameters,
#     ExportParameters), AesGcm's Encrypt and Decrypt, and Delete (a CNG key's). On a type the scan
#     cannot see, Encrypt, Decrypt and Delete could reach a FileInfo - disk, which this scan is not
#     about (see $HordeExecCmdlets) - and none of them starts anything.
#   - ATTRIBUTES: AllowEmptyCollection, AllowEmptyString and AllowNull, which relax parameter binding
#     and run nothing.
#   - CORE: core/JsonText.ps1's Find-HordeJsonDuplicateKey, which reads text and runs nothing.
#   - THE JOURNAL (relay/Journal.ps1, relay PR 2), measured from its syntax tree on 2026-10-09. It keeps
#     its records as files under Horde's home, as remote/Journal.ps1 does, so the same reasoning holds:
#     this scan is about starting a process or reaching the engine, not about disk. Get-HordeHome
#     (core/Home.ps1) reads where the home is; New-HordeModuleSettings and Get-HordeModuleSettings
#     (core/ModuleSettings.ps1) declare and read its settings file, data checked against a table;
#     Move-HordeFileNewDurable (core/FileAtomic.ps1) gives a record its name. Each takes plain values
#     and runs nothing it is given. Start-Sleep waits between tries of a stream's lock. FileShare.Delete
#     lets a writer's temporary file be renamed while it is held open, and FileOptions.DeleteOnClose
#     removes a dead writer's leftover only if nobody holds it (decisions/Store.ps1's sweep).
#     Directory.EnumerateFileSystemEntries, Path.GetFileName and FileAttributes.Directory list a stream
#     folder without Get-ChildItem, which under 5.1 calls a folder named like a device (con, nul) not
#     found (review of the journal, finding 1).
#   - ADD-TYPE, THE ONE COMPILE. relay/ needs AES-GCM on .NET Framework, which has none, so
#     relay/BackendCng.ps1 compiles relay/Gcm.cs. Add-Type is admitted in exactly one form,
#       Add-Type -Path (Join-Path $PSScriptRoot "<Name>.cs")
#     a literal neighbour C# file, reviewed like any other source in the folder. Any other use - source
#     from a variable or a string (-TypeDefinition, -MemberDefinition), a path built from anything but
#     $PSScriptRoot and a literal name, a parent folder, an assembly by name, any further parameter - is
#     a finding (Get-HordeExecAddTypeFindings), checked by test/fixtures/relay/exec-control.ps1.
#   Nothing here lets relay/ hold a script block, so rule 8 (property reads stay open) still holds.
$script:HordeExecRelayAllow = @{
    Cmdlets = @("Add-Type", "Start-Sleep")
    CoreFunctions = @("Find-HordeJsonDuplicateKey", "Get-HordeHome", "New-HordeModuleSettings", "Get-HordeModuleSettings", "Move-HordeFileNewDurable")
    CoreFiles = @("JsonText.ps1", "Home.ps1", "ModuleSettings.ps1", "FileAtomic.ps1")
    Attributes = @("AllowEmptyCollection", "AllowEmptyString", "AllowNull")
    NewTypes = @("System.Security.Cryptography.AesGcm", "System.Security.Cryptography.CngKeyCreationParameters",
        "System.Security.Cryptography.CngProvider", "System.Security.Cryptography.ECDiffieHellmanCng", "System.Security.Cryptography.ECDsaCng",
        "System.Security.Cryptography.ECParameters", "System.Security.Cryptography.ECPoint", "System.Security.Cryptography.HMACSHA256")
    Types = @("object", "type", "convert", "horderelaygcmv1",
        "security.cryptography.cngalgorithm", "security.cryptography.cngalgorithmgroup", "security.cryptography.cngexportpolicies",
        "security.cryptography.cngkey", "security.cryptography.cngkeycreationoptions", "security.cryptography.cngkeyopenoptions",
        "security.cryptography.cryptographicexception", "security.cryptography.eccurve", "security.cryptography.ecdiffiehellman",
        "security.cryptography.ecdsa", "security.cryptography.hashalgorithmname", "security.cryptography.randomnumbergenerator")
    Static = @{
        "horderelaygcmv1" = @("Seal", "Open")
        "io.fileshare" = @("Delete")
        "io.fileoptions" = @("DeleteOnClose")
        "io.directory" = @("EnumerateFileSystemEntries")
        "io.path" = @("GetFileName")
        "io.fileattributes" = @("Directory")
        "long" = @("MaxValue")
        "array" = @("Clear")
        "math" = @("Ceiling")
        "convert" = @("ToBase64String", "FromBase64String", "ToByte")
        "text.encoding" = @("UTF8")
        "security.cryptography.cngalgorithm" = @("ECDsaP256", "ECDiffieHellmanP256")
        "security.cryptography.cngalgorithmgroup" = @("ECDsa", "ECDiffieHellman")
        "security.cryptography.cngexportpolicies" = @("None")
        "security.cryptography.cngkey" = @("Create", "Exists", "Open")
        "security.cryptography.cngkeycreationoptions" = @("MachineKey")
        "security.cryptography.cngkeyopenoptions" = @("MachineKey", "None")
        "security.cryptography.eccurve" = @("CreateFromFriendlyName")
        "security.cryptography.ecdiffiehellman" = @("Create")
        "security.cryptography.ecdsa" = @("Create")
        "security.cryptography.hashalgorithmname" = @("SHA256")
        "security.cryptography.randomnumbergenerator" = @("Create")
    }
    InstanceMethods = @("SignData", "VerifyData", "DeriveKeyFromHmac", "ImportParameters", "ExportParameters", "Encrypt", "Decrypt", "Delete")
}

function Get-HordeExecAddTypeFindings {
    # Every Add-Type in Path that is not exactly Add-Type -Path (Join-Path $PSScriptRoot "<Name>.cs").
    param([Parameter(Mandatory = $true)][string]$Path)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $out = New-Object System.Collections.ArrayList
    foreach ($c in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ieq "Add-Type" }, $true))) {
        $at = "line " + $c.Extent.StartLineNumber + ": "
        $els = @($c.CommandElements)
        $formOk = ($els.Count -eq 3 -and $els[1] -is [System.Management.Automation.Language.CommandParameterAst] -and $els[1].ParameterName -ceq "Path" -and $null -eq $els[1].Argument -and
            $els[2] -is [System.Management.Automation.Language.ParenExpressionAst])
        if ($formOk) {
            $inner = $els[2].Pipeline
            $formOk = ($inner -is [System.Management.Automation.Language.PipelineAst] -and $inner.PipelineElements.Count -eq 1)
            if ($formOk) {
                $join = $inner.PipelineElements[0]
                $formOk = ($join -is [System.Management.Automation.Language.CommandAst] -and $join.GetCommandName() -ceq "Join-Path" -and $join.CommandElements.Count -eq 3 -and
                    $join.CommandElements[1].Extent.Text -ceq '$PSScriptRoot' -and $join.CommandElements[2] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    [regex]::IsMatch($join.CommandElements[2].Value, '\A[A-Za-z][A-Za-z0-9]*\.cs\z'))
            }
        }
        if (-not $formOk) { [void]$out.Add($at + "Add-Type other than -Path (Join-Path `$PSScriptRoot `"<Name>.cs`"): only a literal neighbour C# file may be compiled") }
    }
    return @($out)
}

function Get-HordeExecRelayFindings {
    # Get-HordeExecFindings under the relay profile, plus the Add-Type form check. The remote lists are
    # restored before this returns, even when the scan throws.
    param([Parameter(Mandatory = $true)][string]$Path, $Known = $null)
    $saved = @{ c = $script:HordeExecCmdlets; f = $script:HordeExecCoreFunctions; cf = $script:HordeExecCoreFiles; a = $script:HordeExecAttributes
        n = $script:HordeExecNewTypes; t = $script:HordeExecTypes; s = $script:HordeExecStatic; m = $script:HordeExecInstanceMethods }
    $allow = $script:HordeExecRelayAllow
    try {
        $script:HordeExecCmdlets = @($saved.c) + @($allow.Cmdlets)
        $script:HordeExecCoreFunctions = @($saved.f) + @($allow.CoreFunctions)
        $script:HordeExecCoreFiles = @($saved.cf) + @($allow.CoreFiles)
        $script:HordeExecAttributes = @($saved.a) + @($allow.Attributes)
        $script:HordeExecNewTypes = @($saved.n) + @($allow.NewTypes)
        $script:HordeExecTypes = @($saved.t) + @($allow.Types)
        $static = @{}
        foreach ($k in @($saved.s.Keys)) { $static[$k] = @($saved.s[$k]) }
        foreach ($k in @($allow.Static.Keys)) {
            $have = @()
            if ($static.ContainsKey($k)) { $have = @($static[$k]) }
            $static[$k] = $have + @($allow.Static[$k])
        }
        $script:HordeExecStatic = $static
        $script:HordeExecInstanceMethods = @($saved.m) + @($allow.InstanceMethods)
        $found = @(Get-HordeExecFindings -Path $Path -Known $Known)
    } finally {
        $script:HordeExecCmdlets = $saved.c; $script:HordeExecCoreFunctions = $saved.f; $script:HordeExecCoreFiles = $saved.cf; $script:HordeExecAttributes = $saved.a
        $script:HordeExecNewTypes = $saved.n; $script:HordeExecTypes = $saved.t; $script:HordeExecStatic = $saved.s; $script:HordeExecInstanceMethods = $saved.m
    }
    return @($found + @(Get-HordeExecAddTypeFindings -Path $Path))
}
