# StartSites.ps1 - where can the code of a port family start something, and is each place on its list?
#
# Development tooling, not part of the engine. test/test-start-sites.ps1 runs it over messengers/.
#
# WHY (remote plan R21, slice 3b, merge condition 2; review of #102). The wezfleet messenger is the first
# messenger that starts a program. tools/ExecScan.ps1 holds remote/ to starting nothing at all; a
# messenger must start one thing, so the rule here is not "none" but "exactly the listed ones": every
# place a file under messengers/ could start a program, run a script block or load code is a START SITE,
# and each must match a line of messengers/start-sites.txt by its file, its function, its kind and its
# exact text. A second process start, a start of another program, a changed program path, or a site that
# moved to another function is a site the list does not have, and is refused. A listed site that is no
# longer there is refused too, so the list cannot keep a stale permission for a later edit to reuse.
#
# THREAT MODEL, as the remote transport's own exec guard states it: a lint against Horde's own code drifting
# toward starting something it should not, not a boundary against a hostile author - no static scan of
# PowerShell is sound against one. It closes the broad, cheap forms:
#   call     a command run with & (a script block, a path, a string)
#   dot      a file or script block dot-sourced
#   command  a command that starts or evaluates something by name (Start-Process, Invoke-Expression,
#            Invoke-Command, a job, a shell, a PowerShell), or any command named like a program or a
#            path (a name holding . \ / or :)
#   method   a call of a method that starts, invokes or compiles (Start, Invoke, Create, ...), or of a
#            method named by an expression ($o.$name())
#   type     a type that leads to a process, a script block or the engine ([System.Diagnostics.Process],
#            [scriptblock], [powershell], [wmiclass], [activator], ...); a static call on one is the
#            whole call, so [ProcessStartInfo]::new(<program>, ...) carries its program in its text
# A folder named test is not read: tests start stand-in children on purpose.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

$script:HordeStartSiteCommands = @("start-process", "saps", "start", "invoke-expression", "iex", "invoke-command", "icm", "invoke-item", "ii",
    "start-job", "sajb", "start-threadjob", "receive-job", "cmd", "powershell", "pwsh", "bash", "wsl", "invoke-wmimethod", "invoke-cimmethod")
$script:HordeStartSiteMethods = @("start", "invoke", "invokescript", "invokereturnasis", "invokewithcontext", "begininvoke", "create", "createdelegate",
    "invokemethod", "invokemember", "shellexecute", "run", "exec", "addscript", "addcommand", "newscriptblock", "expandstring", "getnewclosure")
$script:HordeStartSiteTypes = @("system.diagnostics.process", "diagnostics.process", "system.diagnostics.processstartinfo", "diagnostics.processstartinfo",
    "scriptblock", "system.management.automation.scriptblock", "powershell", "system.management.automation.powershell", "runspacefactory",
    "system.management.automation.runspaces.runspacefactory", "wmiclass", "wmi", "wmisearcher", "activator", "system.activator", "type", "system.type",
    "appdomain", "system.appdomain", "reflection.assembly", "system.reflection.assembly")
$script:HordeStartSiteKinds = @("call", "dot", "command", "method", "type")

function Get-HordeStartSiteFiles {
    # Every .ps1 under -Folder of -Root, outside any folder named test, as paths relative to -Root with
    # forward slashes.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Folder)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $dir = Join-Path $rootFull $Folder
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @() }
    $out = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter "*.ps1" | Where-Object { $_.Extension -ieq ".ps1" })) {
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
        if (@($rel -split '/') -contains "test") { continue }
        [void]$out.Add($rel)
    }
    $arr = [string[]]$out.ToArray(); [Array]::Sort($arr, [System.StringComparer]::Ordinal)
    return @($arr)
}

function Get-HordeStartSiteFunction {
    # The name of the function an AST node is inside, or "(top)".
    param($Node)
    $p = $Node.Parent
    while ($null -ne $p) {
        if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $p.Name }
        $p = $p.Parent
    }
    return "(top)"
}

function Get-HordeStartSites {
    # Every start site in the files of -Folder, as { file; function; kind; text }, text being the exact
    # source of the site with runs of white space made one space. A file that does not parse is one site
    # of kind "parse", which no list line can match.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Folder)
    $out = New-Object System.Collections.ArrayList
    foreach ($rel in @(Get-HordeStartSiteFiles -Root $Root -Folder $Folder)) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $rel), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { [void]$out.Add([pscustomobject]@{ file = $rel; function = "(top)"; kind = "parse"; text = "the file does not parse" }); continue }
        $add = {
            param($Node, [string]$Kind, [string]$Text)
            [void]$out.Add([pscustomobject]@{ file = $rel; function = (Get-HordeStartSiteFunction $Node); kind = $Kind; text = (($Text -replace '\s+', ' ').Trim()) })
        }
        foreach ($c in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
            $first = $c.CommandElements[0]
            if ($c.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand) { & $add $c "call" $c.Extent.Text; continue }
            if ($c.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) { & $add $c "dot" $c.Extent.Text; continue }
            $name = $c.GetCommandName()
            if ($null -eq $name) { & $add $c "command" $c.Extent.Text; continue }
            if ($script:HordeStartSiteCommands -contains $name.ToLowerInvariant() -or $name -match '[.\\/:]') { & $add $c "command" $c.Extent.Text }
        }
        foreach ($mc in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true))) {
            if ($mc.Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { & $add $mc "method" $mc.Extent.Text; continue }
            if ($script:HordeStartSiteMethods -contains $mc.Member.Value.ToLowerInvariant()) { & $add $mc "method" $mc.Extent.Text }
        }
        foreach ($t in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TypeExpressionAst] -or $n -is [System.Management.Automation.Language.TypeConstraintAst] }, $true))) {
            if ($script:HordeStartSiteTypes -notcontains $t.TypeName.FullName.ToLowerInvariant()) { continue }
            # A static call on the type is the site as a whole, its arguments included: the program a
            # ProcessStartInfo is made for is part of the text a list line must match.
            $site = $t
            if ($t.Parent -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and [object]::ReferenceEquals($t.Parent.Expression, $t)) { $site = $t.Parent }
            & $add $t "type" $site.Extent.Text
        }
        foreach ($nb in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ieq "New-Object" }, $true))) {
            $typeArg = @($nb.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] }) | Select-Object -First 1
            if ($null -ne $typeArg -and $script:HordeStartSiteTypes -contains "$($typeArg.Value)".ToLowerInvariant()) { & $add $nb "type" $nb.Extent.Text }
        }
    }
    return @($out)
}

function Read-HordeStartSiteList {
    # The lines of a start-sites list as { file; function; kind; text; line }, and the problems of the
    # malformed ones. A line is: file | function | kind | text | why. The text is the last-but-one cell,
    # so a site's own text may hold a |.
    param([Parameter(Mandatory = $true)][string]$Path)
    $entries = New-Object System.Collections.ArrayList
    $problems = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($line in @([System.IO.File]::ReadAllLines($Path))) {
        $n++
        if ($line.Trim() -eq "" -or $line.TrimStart().StartsWith("#")) { continue }
        $cells = @($line -split '\|' | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 5) { [void]$problems.Add("line " + $n + " is not 'file | function | kind | text | why'"); continue }
        $why = $cells[$cells.Count - 1]
        $text = (@($cells[3..($cells.Count - 2)]) -join " | ")
        if ($script:HordeStartSiteKinds -cnotcontains $cells[2]) { [void]$problems.Add("line " + $n + " has the kind '" + $cells[2] + "', not one of " + ($script:HordeStartSiteKinds -join ", ")); continue }
        if ($why -eq "") { [void]$problems.Add("line " + $n + " does not say why the site may be there"); continue }
        [void]$entries.Add([pscustomobject]@{ file = $cells[0]; function = $cells[1]; kind = $cells[2]; text = $text; line = $n })
    }
    return [pscustomobject]@{ entries = @($entries); problems = @($problems) }
}

function Test-HordeStartSites {
    # Findings for -Folder of -Root against the list at -List (relative to -Root): every site not on the
    # list, every list line no site matches, and every malformed list line. Each line allows ONE site.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Folder, [Parameter(Mandatory = $true)][string]$List)
    $listPath = Join-Path $Root $List
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) { return @($List + " is missing: no start site in " + $Folder + "/ is allowed without it") }
    $read = Read-HordeStartSiteList -Path $listPath
    $out = New-Object System.Collections.ArrayList
    foreach ($p in $read.problems) { [void]$out.Add($List + ": " + $p) }
    $used = @{}
    foreach ($s in @(Get-HordeStartSites -Root $Root -Folder $Folder)) {
        $hit = $null
        foreach ($e in $read.entries) {
            if ($used.ContainsKey($e.line)) { continue }
            if ($e.file -ceq $s.file -and $e.function -ceq $s.function -and $e.kind -ceq $s.kind -and $e.text -ceq $s.text) { $hit = $e; break }
        }
        if ($null -eq $hit) { [void]$out.Add($s.file + " (" + $s.function + ") has a " + $s.kind + " start site that " + $List + " does not list: " + $s.text); continue }
        $used[$hit.line] = $true
    }
    foreach ($e in $read.entries) {
        if (-not $used.ContainsKey($e.line)) { [void]$out.Add($List + " line " + $e.line + " lists a " + $e.kind + " site in " + $e.file + " (" + $e.function + ") that is not there: " + $e.text) }
    }
    return @($out)
}
