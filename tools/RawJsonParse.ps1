# RawJsonParse.ps1 - which shipped files still call ConvertFrom-Json themselves?
#
# Development tooling, not part of the engine. test/test-json-parse-allowlist.ps1 runs it.
#
# WHY. PowerShell 7's ConvertFrom-Json reads a date-shaped string as a [datetime]; 5.1 never does
# (issue #274, measured 2026-10-14 on 7.6.6). core/JsonText.ps1's ConvertFrom-HordeJson is the one
# parse that keeps every string a string under both. A file that calls ConvertFrom-Json itself is
# exposed again the day it runs under 7, so every such call outside core/JsonText.ps1 is a finding
# unless core/json-parse-allowlist.txt lists its file with the exact number of calls.
#
# THE LIST ONLY SHRINKS, as hosts/<name>/allowlist.txt does for test/test-host-names.ps1. The count is
# EXACT: a file with more calls than listed is a finding (a new raw parse), and so is a file with FEWER
# (the entry allows more than the file needs: lower it, or delete the line). A listed file that is gone
# is a finding. So a file moved to the seam must leave the list in the same change, and a new raw call
# can only arrive through a visible, reviewed edit of the list.
#
# WHAT COUNTS. A command named ConvertFrom-Json in the file's PARSE (a CommandAst), with or without its
# module prefix - not a mention in a comment or a string. A file that does not parse is a finding, so it
# can never pass by being unreadable.
# NOT COUNTED: a direct .NET JSON call ([System.Text.Json...], JavaScriptSerializer) is not a command, so this lint does not see it.
#
# WHAT IS SCANNED: the shipped files (tools/FunctionNames.ps1, Get-HordeShippedScriptFiles), which
# leaves out every folder named test. That exclusion is deliberate: a suite reads the answers of the
# code under test with its own parse, so that a fault in the seam cannot also blind the reader
# (test/test-decisions-shells.ps1). core/JsonText.ps1 itself is the seam and is not scanned.

. (Join-Path $PSScriptRoot "FunctionNames.ps1")

$script:HordeJsonSeamFile = "core/JsonText.ps1"
$script:HordeJsonAllowlistFile = "core/json-parse-allowlist.txt"

function Get-HordeRawJsonParseCounts {
    # path (forward slashes) -> number of raw ConvertFrom-Json calls, for every shipped file but the seam
    # that has at least one; a file that does not parse maps to -1.
    param([Parameter(Mandatory = $true)][string]$Root)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $counts = @{}
    foreach ($rel in @(Get-HordeShippedScriptFiles -Root $rootFull)) {
        if ($rel -ieq $script:HordeJsonSeamFile) { continue }
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $rootFull $rel), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { $counts[$rel] = -1; continue }
        $n = @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] -and ("" + $x.GetCommandName()) -match '(\A|\\)ConvertFrom-Json\z' }, $true)).Count
        if ($n -gt 0) { $counts[$rel] = $n }
    }
    return $counts
}

function Test-HordeRawJsonParse {
    # Findings { path; problem } for the repository at -Root against its allowlist (or -AllowlistPath).
    param([Parameter(Mandatory = $true)][string]$Root, [string]$AllowlistPath = "")
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($AllowlistPath -eq "") { $AllowlistPath = Join-Path $rootFull $script:HordeJsonAllowlistFile }
    $out = New-Object System.Collections.ArrayList
    $allowed = @{}
    if (-not (Test-Path -LiteralPath $AllowlistPath -PathType Leaf)) {
        [void]$out.Add([pscustomobject]@{ path = $script:HordeJsonAllowlistFile; problem = "the allowlist is missing" })
    } else {
        $lineNo = 0
        foreach ($line in @([System.IO.File]::ReadAllLines($AllowlistPath))) {
            $lineNo++
            $t = $line.Trim()
            if ($t -eq "" -or $t.StartsWith("#")) { continue }
            $parts = @($t -split '\|' | ForEach-Object { $_.Trim() })
            if ($parts.Count -ne 3 -or $parts[0] -eq "" -or $parts[1] -notmatch '\A[1-9]\d{0,3}\z' -or $parts[2] -eq "") {
                [void]$out.Add([pscustomobject]@{ path = $script:HordeJsonAllowlistFile; problem = ("line " + $lineNo + " is not <path> | <calls, 1 or more> | <why>") }); continue
            }
            $p = $parts[0] -replace '\\', '/'
            if ($allowed.ContainsKey($p.ToLowerInvariant())) { [void]$out.Add([pscustomobject]@{ path = $p; problem = ("is listed twice (line " + $lineNo + ")") }); continue }
            $allowed[$p.ToLowerInvariant()] = [pscustomobject]@{ path = $p; count = [int]$parts[1] }
        }
    }
    $counts = Get-HordeRawJsonParseCounts -Root $rootFull
    foreach ($rel in @($counts.Keys | Sort-Object)) {
        $n = $counts[$rel]
        if ($n -lt 0) { [void]$out.Add([pscustomobject]@{ path = $rel; problem = "does not parse, so its calls cannot be counted" }); continue }
        $entry = $allowed[$rel.ToLowerInvariant()]
        if ($null -eq $entry) { [void]$out.Add([pscustomobject]@{ path = $rel; problem = ("calls ConvertFrom-Json " + $n + " time(s) and is not on the allowlist: parse with ConvertFrom-HordeJson (core/JsonText.ps1)") }); continue }
        if ($n -gt $entry.count) { [void]$out.Add([pscustomobject]@{ path = $rel; problem = ("calls ConvertFrom-Json " + $n + " time(s), more than the " + $entry.count + " listed: a new raw parse; use ConvertFrom-HordeJson") }) }
        elseif ($n -lt $entry.count) { [void]$out.Add([pscustomobject]@{ path = $rel; problem = ("calls ConvertFrom-Json " + $n + " time(s), fewer than the " + $entry.count + " listed: lower the entry, so the list only shrinks") }) }
    }
    foreach ($k in @($allowed.Keys | Sort-Object)) {
        $e = $allowed[$k]
        $found = $false
        foreach ($rel in $counts.Keys) { if ($rel.ToLowerInvariant() -ceq $k) { $found = $true; break } }
        if (-not $found) { [void]$out.Add([pscustomobject]@{ path = $e.path; problem = "is listed but has no raw ConvertFrom-Json call (or is gone, or is not shipped): delete the line, so the list only shrinks" }) }
    }
    return $out.ToArray()
}
