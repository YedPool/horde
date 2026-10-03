# FunctionNames.ps1 - is any function name defined twice in the code that ships?
#
# Development tooling, not part of the engine. test/test-function-names.ps1 runs it.
#
# WHY. PowerShell gives a name to whichever definition was loaded last, and says nothing. On
# 2026-10-02 core/PermissionLevels.ps1 (remote R0, PR #55) defined Find-HordeJsonDuplicateKey, a name
# core/Ownership.ps1 already used for a scanner that answers differently: a list of findings, keys
# compared ignoring case, against the first repeated key compared exactly. Nothing loaded both files
# yet. The first caller that did - the agent descriptor of engines E2 reads the permission levels and
# the ownership table - would have run one scanner while its author tested the other.
#
# HOW. Each file is PARSED, never run: running every file in one session shows only the definition
# that won, never that there were two. A definition counts when it is at the top of its file, where
# dot-sourcing makes it the caller's. A function defined inside another function lives only while that
# function runs (tools/HostNames.ps1 and tools/Ledger.ps1 each define a local Add-Finding), so it is
# not a collision and is not counted - unless its name carries global: or script:, which puts it in a
# shared scope. Names are compared ignoring case and without a scope prefix (function script:X and
# function X are one name), as PowerShell resolves them.
#
# THE OTHER WAYS TO DEFINE A NAME are counted too when the name is written literally: Set-Item and
# New-Item on function:X, and Set-Alias and New-Alias X - an alias is resolved before a function, so
# an alias X hides function X. A name built at run time cannot be seen by a parse; none of these forms
# is used in shipped code (grep, 2026-10-02), and the review of this guard listed them as its limit.
#
# WHAT SHIPS: every .ps1 under core/, remote/, transports/, tools/, cli/, hosts/ and agents/, and
# horde.ps1, except anything in a folder named test. A suite may override a core function on purpose
# (test/test-identity.ps1 replaces Get-HordeProcessTable with a tripwire), and each suite runs in its
# own process.

$script:HordeShippedCodeFolders = @("core", "remote", "transports", "tools", "cli", "hosts", "agents")
$script:HordeShippedCodeFiles = @("horde.ps1")

function Get-HordeShippedScriptFiles {
    # Every shipped .ps1 under -Root, as paths relative to it with forward slashes.
    param([Parameter(Mandatory = $true)][string]$Root)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $out = New-Object System.Collections.ArrayList
    foreach ($f in $script:HordeShippedCodeFiles) { if (Test-Path -LiteralPath (Join-Path $rootFull $f) -PathType Leaf) { [void]$out.Add($f) } }
    foreach ($d in $script:HordeShippedCodeFolders) {
        $dir = Join-Path $rootFull $d
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter "*.ps1" | Where-Object { $_.Extension -ieq ".ps1" })) {
            $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
            if (@($rel -split '/') -contains "test") { continue }
            [void]$out.Add($rel)
        }
    }
    return $out.ToArray()
}

function Get-HordeTopFunctionDefinitions {
    # The functions defined at the top of each file, { name; file; line }. A file that does not parse
    # is reported as a definition named "<parse error>", so it can never pass by being unreadable.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string[]]$Files)
    $out = New-Object System.Collections.ArrayList
    foreach ($rel in $Files) {
        $full = Join-Path $Root $rel
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { [void]$out.Add([pscustomobject]@{ name = "<parse error>"; file = $rel; line = $errors[0].Extent.StartLineNumber }); continue }
        $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($d in $defs) {
            # A class method is not a command: its body parses as a FunctionDefinitionAst under a
            # FunctionMemberAst, and no call by name can reach it (batch 5, 2026-10-03: core/Metrics.ps1's
            # HordeRecordOrderComparer.Compare was counted, and the load check found no command Compare).
            if ($d.Parent -is [System.Management.Automation.Language.FunctionMemberAst]) { continue }
            $nested = $false
            $p = $d.Parent
            while ($null -ne $p) { if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $nested = $true; break }; $p = $p.Parent }
            if ($nested -and $d.Name -notmatch '^(global|script):') { continue }
            [void]$out.Add([pscustomobject]@{ name = $d.Name; file = $rel; line = $d.Extent.StartLineNumber })
        }
        $cmds = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($c in $cmds) {
            $nm = "$($c.GetCommandName())"
            $kind = ""
            if (@("Set-Item", "New-Item", "si", "ni") -contains $nm) { $kind = "item" }
            elseif (@("Set-Alias", "New-Alias", "sal", "nal") -contains $nm) { $kind = "alias" }
            if ($kind -eq "") { continue }
            foreach ($e in @($c.CommandElements | Select-Object -Skip 1)) {
                if ($e -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { continue }
                $v = "$($e.Value)"
                if ($kind -eq "item") {
                    if ($v -match '^function:\\?(.+)$') { [void]$out.Add([pscustomobject]@{ name = $Matches[1]; file = $rel; line = $c.Extent.StartLineNumber }) }
                    continue
                }
                [void]$out.Add([pscustomobject]@{ name = $v; file = $rel; line = $c.Extent.StartLineNumber })
                break
            }
        }
    }
    return $out.ToArray()
}

function Find-HordeDuplicateFunctions {
    # Each name defined more than once, ignoring case, with every place it is defined.
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()]$Definitions)
    # Keyed exactly, so the lower-casing below is what makes the comparison ignore case: a plain @{}
    # ignores case already, and would hide a break of that line (mutation run of 2026-10-02).
    $byName = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
    foreach ($d in @($Definitions)) {
        $k = ("$($d.name)" -replace '^(global|script|local|private):', '').ToLowerInvariant()
        if (-not $byName.ContainsKey($k)) { $byName[$k] = New-Object System.Collections.ArrayList }
        [void]$byName[$k].Add($d)
    }
    $out = New-Object System.Collections.ArrayList
    foreach ($k in @($byName.Keys | Sort-Object)) {
        if ($byName[$k].Count -gt 1) {
            [void]$out.Add([pscustomobject]@{ name = $byName[$k][0].name; places = @($byName[$k] | ForEach-Object { $_.file + ":" + $_.line }) })
        }
    }
    return $out.ToArray()
}
