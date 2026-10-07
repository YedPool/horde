# CoreLoad.ps1 - does each core file, loaded ALONE, define every Horde function it calls?
#
# Development tooling, not part of the engine. test/test-core-load.ps1 runs it.
#
# WHY. A core file is dot-sourced by whatever needs it, and PowerShell resolves a call when it runs, not
# when the file loads. So a file that calls a function defined in a file it never loads works for as long
# as something else happened to load that file first, and fails the day it is loaded on its own. Review
# of #109, 2026-10-06: core/NodePolicy.ps1 called Assert-HordeAsciiBytes, which lived in
# core/AgentDescriptor.ps1, a file NodePolicy never loads; loaded alone, Get-HordeNodePolicy answered
# unknown ("not recognized") for every valid policy, and every suite passed because each loaded the
# descriptor file first.
#
# HOW. Each file is loaded on its own in a fresh runspace, and the functions defined there afterwards
# are listed: the file's own and those of every file it loads, at any depth. Its calls are read from
# its parse (tools/FunctionNames.ps1's walk): every command named in it that some shipped file defines
# at its top. A call to such a function that the runspace does not define is a finding. A file that
# throws while loading is a finding too, so it can never pass by not loading.
#
# THE LIMIT. A name built at run time is not seen by a parse, and a call to a function a caller is
# expected to define (a callback by name) would be reported; none is in core today.

. (Join-Path $PSScriptRoot "FunctionNames.ps1")

function Find-HordeUnloadedCalls {
    # Every call, in the .ps1 files directly under <Root>\<Folder>, to a Horde function that the file
    # does not define or load: { file; name; line }. A file that fails to load is reported with the
    # name "<load error>" and the error in line's place.
    param([Parameter(Mandatory = $true)][string]$Root, [string]$Folder = "core")
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $known = @{}
    foreach ($d in @(Get-HordeTopFunctionDefinitions -Root $rootFull -Files @(Get-HordeShippedScriptFiles -Root $rootFull))) { $known[("" + $d.name).ToLowerInvariant()] = $true }
    $out = New-Object System.Collections.ArrayList
    $dir = Join-Path $rootFull $Folder
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter "*.ps1" | Sort-Object Name)) {
        $rel = $Folder + "/" + $f.Name
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { [void]$out.Add([pscustomobject]@{ file = $rel; name = "<parse error>"; line = $errors[0].Extent.StartLineNumber }); continue }
        $calls = @{}
        foreach ($c in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
            $nm = "" + $c.GetCommandName()
            if ($nm -eq "" -or -not $known.ContainsKey($nm.ToLowerInvariant())) { continue }
            if (-not $calls.ContainsKey($nm.ToLowerInvariant())) { $calls[$nm.ToLowerInvariant()] = [pscustomobject]@{ name = $nm; line = $c.Extent.StartLineNumber } }
        }
        $ps = [PowerShell]::Create()
        try {
            [void]$ps.AddScript(". '" + $f.FullName.Replace("'", "''") + "'; @(Get-Command -CommandType Function | ForEach-Object { `$_.Name })")
            $names = $null
            try { $names = @($ps.Invoke()) } catch { [void]$out.Add([pscustomobject]@{ file = $rel; name = "<load error>"; line = $_.Exception.Message }); continue }
            if ($ps.Streams.Error.Count -gt 0) { [void]$out.Add([pscustomobject]@{ file = $rel; name = "<load error>"; line = ("" + $ps.Streams.Error[0]) }); continue }
            $have = @{}
            foreach ($n in $names) { $have[("" + $n).ToLowerInvariant()] = $true }
            foreach ($k in @($calls.Keys | Sort-Object)) {
                if (-not $have.ContainsKey($k)) { [void]$out.Add([pscustomobject]@{ file = $rel; name = $calls[$k].name; line = $calls[$k].line }) }
            }
        } finally { $ps.Dispose() }
    }
    return $out.ToArray()
}
