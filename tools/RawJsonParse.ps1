# RawJsonParse.ps1 - which shipped files still call ConvertFrom-Json themselves?
#
# Development tooling, not part of the engine. test/test-json-parse-allowlist.ps1 runs it.
#
# WHY. PowerShell 7's ConvertFrom-Json reads a date-shaped string as a [datetime]; 5.1 never does
# (issue #274, measured 2026-10-14 on 7.6.6). core/JsonText.ps1's ConvertFrom-HordeJson is the one
# parse that keeps every string a string under both. A file that calls ConvertFrom-Json itself is
# exposed again the day it runs under 7, so every such call outside core/JsonText.ps1 is a finding.
#
# THE ALLOWLIST IS CLOSED (T-0323, 2026-10-20). core/json-parse-allowlist.txt once listed the files that
# still parsed raw, and only shrank; the last entry left in that change. The file stays, with no entries,
# because a missing list is itself a finding, and an entry in it is a finding too: there is no exception
# to ask for, a reader uses ConvertFrom-HordeJson.
#
# WHAT COUNTS. A command named ConvertFrom-Json in the file's PARSE (a CommandAst), with or without its
# module prefix - not a mention in a comment or a string. A file that does not parse is a finding, so it
# can never pass by being unreadable.
# NOT COUNTED: a direct .NET JSON call ([System.Text.Json...]) is not a command, so this lint does not see it. The one exception is the old .NET serializer class, scanned apart (Get-HordeSerializerUse, T-0323) with no allowlist.
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

function Get-HordeSerializerUse {
    # path (forward slashes) -> number of code tokens naming .NET's JavaScriptSerializer, for every shipped
    # file but the seam. T-0323: that class throws on every call under PowerShell 7 on .NET 10, and its
    # callers' catch-and-skip hid it; core/JsonText.ps1's ConvertFrom-HordeJsonObject is the one reader. No
    # allowlist: the count must be zero. A comment is not code, and the name is split below so this file
    # does not trip its own scan.
    param([Parameter(Mandatory = $true)][string]$Root)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $name = "JavaScript" + "Serializer"
    $counts = @{}
    foreach ($rel in @(Get-HordeShippedScriptFiles -Root $rootFull)) {
        if ($rel -ieq $script:HordeJsonSeamFile) { continue }
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $rootFull $rel), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { continue }
        $n = @($tokens | Where-Object { $_.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment -and $_.Text.Contains($name) }).Count
        if ($n -gt 0) { $counts[$rel] = $n }
    }
    return $counts
}

function Test-HordeRawJsonParse {
    # Findings { path; problem } for the repository at -Root. The allowlist is CLOSED (no entries), so every
    # raw call is a finding; -AllowlistPath names a copy of the list to read instead of the repository's own.
    param([Parameter(Mandatory = $true)][string]$Root, [string]$AllowlistPath = "")
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($AllowlistPath -eq "") { $AllowlistPath = Join-Path $rootFull $script:HordeJsonAllowlistFile }
    $out = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $AllowlistPath -PathType Leaf)) {
        [void]$out.Add([pscustomobject]@{ path = $script:HordeJsonAllowlistFile; problem = "the allowlist is missing" })
    } else {
        $lineNo = 0
        foreach ($line in @([System.IO.File]::ReadAllLines($AllowlistPath))) {
            $lineNo++
            $t = $line.Trim()
            if ($t -eq "" -or $t.StartsWith("#")) { continue }
            [void]$out.Add([pscustomobject]@{ path = $script:HordeJsonAllowlistFile; problem = ("line " + $lineNo + " is an entry, and the allowlist is closed: parse with ConvertFrom-HordeJson, never list a raw call") })
        }
    }
    $counts = Get-HordeRawJsonParseCounts -Root $rootFull
    foreach ($rel in @($counts.Keys | Sort-Object)) {
        $n = $counts[$rel]
        if ($n -lt 0) { [void]$out.Add([pscustomobject]@{ path = $rel; problem = "does not parse, so its calls cannot be counted" }); continue }
        [void]$out.Add([pscustomobject]@{ path = $rel; problem = ("calls ConvertFrom-Json " + $n + " time(s): parse with ConvertFrom-HordeJson (core/JsonText.ps1)") })
    }
    $ser = Get-HordeSerializerUse -Root $rootFull
    foreach ($rel in @($ser.Keys | Sort-Object)) { [void]$out.Add([pscustomobject]@{ path = $rel; problem = ("names the .NET serializer " + $ser[$rel] + " time(s), which throws under PowerShell 7: parse with ConvertFrom-HordeJsonObject (core/JsonText.ps1)") }) }
    return $out.ToArray()
}
