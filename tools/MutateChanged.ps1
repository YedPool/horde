# MutateChanged.ps1 - which mutants a change could have made the suites miss: the selection behind
# tools\Mutate.ps1 -Changed <base-ref>. Dot-sourced by tools\Mutate.ps1; no side effects on load.
#
# WHY. A review round that reruns every mutation spec reruns hundreds of mutants on lines the round
# never touched (the founder's decision of 2026-10-02: each review round tests only what changed, and
# the full specs run once per PR, on its final head). So a round runs only the mutants whose find
# string sits in a line the diff added or modified.
#
# WHAT IS SELECTED, and why each rule leans towards running:
#   - A mutant whose find string sits on a line the diff added or modified, in a file the diff touched.
#     The diff is `git diff -U0` from the merge-base of the base and HEAD to the WORKING TREE, because
#     tools\Mutate.ps1 mutates a copy of the working tree, so the lines must be counted in that tree.
#   - A pure deletion has no new line to point at, yet it changes the code on both sides of the gap;
#     the line before the gap and the line after it count as modified.
#   - An untracked file is new in every line.
#   - FAIL SAFE: a mutant whose find string is not in its target, or is there more than once, or whose
#     target file is missing, is RUN, whatever the diff. It cannot be placed, so it cannot be shown to
#     be unchanged; and running it makes tools\Mutate.ps1 report it as "did not apply", which fails.
#   - A multi-line find string is run too: tools\Mutate.ps1 refuses it, so it fails the run, as it
#     would fail the full one (review of PR #63).
#   - EVERY MUTANT OF A SPEC WHOSE FILE CHANGED is run: a new or edited entry has never run in that
#     form, and an edited Environment or PassCodes changes what every run of the spec means - a
#     narrowed HORDE_SECTIONS reselected nothing when only entries were compared (review of PR #63,
#     probe P4).
#
# THE DIFF IS READ THE SAME WAY WHATEVER THE USER'S GIT CONFIG SAYS. diff.noprefix, diff.mnemonicPrefix
# and diff.srcPrefix/dstPrefix change the a/ and b/ this parser reads; with the first two set, every
# header failed to parse, an edited mutant line read as "0 files changed" and was skipped with exit 0
# (review of PR #63, probes P9 and P10). So git diff is given its prefixes, colour, external-diff and
# relative settings explicitly, and a diff that is not empty but does not parse whole is an error
# (Get-HordeDiffParseProblem), never "the diff is empty".
# NOT SELECTED: a change to a suite alone, or to test\lib, does not reselect the mutants of the code
# it tests. A suite edited to catch less is found by the full specs run once per PR on the merge
# result (CONTRIBUTING, "Test levels and merging"); that run, not this selection, is the merge gate.
#
# ZERO IS NOT A PASS when it should not be zero. A diff that touches a mutation target yet selects no
# mutant means the change has no mutant on any line it touched: Get-HordeSelectionVerdict says so and
# fails, and the author adds mutants or runs the full specs. An empty diff, or one that touches no
# target, selects none and says so.

function ConvertTo-HordeDiffKey {
    # One spelling for a repository path, whichever tool wrote it: forward slashes, no leading "./",
    # lower case (the file system is case-insensitive here, and a spec writes "tools\X.ps1").
    param([string]$Path)
    $p = ($Path.Trim() -replace '\\', '/')
    if ($p.StartsWith('./')) { $p = $p.Substring(2) }
    return $p.ToLowerInvariant()
}

function ConvertFrom-HordeDiffZero {
    # Parse `git diff -U0` output. Returns a hashtable: diff key of every file the diff names ->
    # HashSet[int] of the lines the CURRENT file has that the diff added or modified. A file that was
    # deleted, or only changed mode, is present with an empty set: it was touched.
    param([AllowEmptyString()][string]$Text)
    $files = @{}
    $cur = $null
    foreach ($ln in ($Text -split "`r?`n")) {
        $hdr = [regex]::Match($ln, '^diff --git "?a/.*?"? "?b/(.*?)"?$')
        if ($hdr.Success) {
            $cur = ConvertTo-HordeDiffKey $hdr.Groups[1].Value
            if (-not $files.ContainsKey($cur)) { $files[$cur] = New-Object 'System.Collections.Generic.HashSet[int]' }
            continue
        }
        if ($ln.StartsWith('+++ ')) {
            # The new name, when the header's split was unclear (a name with a space). A deleted file
            # has /dev/null here; its key stays the one the header gave.
            $p = $ln.Substring(4).TrimEnd("`t").Trim('"')
            if ($p -ne '/dev/null' -and $p.StartsWith('b/')) {
                $cur = ConvertTo-HordeDiffKey $p.Substring(2)
                if (-not $files.ContainsKey($cur)) { $files[$cur] = New-Object 'System.Collections.Generic.HashSet[int]' }
            }
            continue
        }
        $m = [regex]::Match($ln, '^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@')
        if ($m.Success -and $null -ne $cur) {
            $start = [int]$m.Groups[1].Value
            # "+c" with no count is ONE line, not zero.
            $count = 1
            if ($m.Groups[2].Success) { $count = [int]$m.Groups[2].Value }
            if ($count -eq 0) {
                # A pure deletion after line $start: the lines on both sides of the gap count.
                [void]$files[$cur].Add($start); [void]$files[$cur].Add($start + 1)
            } else {
                for ($i = $start; $i -lt $start + $count; $i++) { [void]$files[$cur].Add($i) }
            }
        }
    }
    return $files
}

function Get-HordeDiffParseProblem {
    # "" when every file the diff text names was parsed; otherwise why not. A diff that is not empty
    # but parses to less than it names must never read as "unchanged".
    param([AllowEmptyString()][string]$Text, [hashtable]$Changed)
    if (-not $Text.Trim()) { return "" }
    $headers = @(($Text -split "`r?`n") | Where-Object { $_.StartsWith("diff --git ") }).Count
    if ($headers -eq 0) { return "the diff is not empty, yet has no 'diff --git' header: parsed 0 files" }
    $parsed = @(($Text -split "`r?`n") | Where-Object { $_ -match '^diff --git "?a/.*?"? "?b/(.*?)"?$' }).Count
    if ($parsed -ne $headers -or $Changed.Count -eq 0) { return ("the diff names " + $headers + " file(s) but only " + $parsed + " parsed with a/ and b/ prefixes - refusing to read it as unchanged") }
    return ""
}

function Add-HordeWholeFile {
    # An untracked file: every one of its lines is new.
    param([hashtable]$Changed, [string]$Path, [int]$LineCount)
    $k = ConvertTo-HordeDiffKey $Path
    if (-not $Changed.ContainsKey($k)) { $Changed[$k] = New-Object 'System.Collections.Generic.HashSet[int]' }
    for ($i = 1; $i -le [Math]::Max(1, $LineCount); $i++) { [void]$Changed[$k].Add($i) }
}

function Find-HordeMutantLine {
    # Where a find string sits in its target's text: { status; line; count }. status is "located"
    # (exactly once, line is 1-based), "missing" (no target text, or not found) or "ambiguous".
    # A find string never spans lines (tools\Mutate.ps1 refuses one that does), so one line holds it.
    param($Text, [string]$Find)
    if ($Find -match "[\r\n]") { return [pscustomobject]@{ status = "multiline"; line = 0; count = 0 } }
    if ($null -eq $Text) { return [pscustomobject]@{ status = "missing"; line = 0; count = 0 } }
    $n = 0; $first = -1; $i = 0
    if ($Find.Length -gt 0) {
        while (($i = $Text.IndexOf($Find, $i, [System.StringComparison]::Ordinal)) -ge 0) {
            if ($first -lt 0) { $first = $i }
            $n++; $i += $Find.Length
        }
    }
    if ($n -eq 0) { return [pscustomobject]@{ status = "missing"; line = 0; count = 0 } }
    if ($n -gt 1) { return [pscustomobject]@{ status = "ambiguous"; line = 0; count = $n } }
    $line = 1
    for ($j = 0; $j -lt $first; $j++) { if ($Text[$j] -eq "`n") { $line++ } }
    return [pscustomobject]@{ status = "located"; line = $line; count = 1 }
}

function Select-HordeChangedMutants {
    # One row per mutant of every spec: { spec; name; target; line; selected; reason }.
    # -Specs: objects { spec (repo-relative path); data (the spec hashtable); text (the target's text,
    # or $null when the file is missing); specChanged (the diff touched the spec file itself) }.
    # -Changed: from ConvertFrom-HordeDiffZero.
    param([object[]]$Specs, [hashtable]$Changed)
    $rows = New-Object System.Collections.ArrayList
    foreach ($sp in @($Specs)) {
        $tk = ConvertTo-HordeDiffKey "$($sp.data.Target)"
        $touched = $Changed.ContainsKey($tk)
        foreach ($m in @($sp.data.Mutations)) {
            $loc = Find-HordeMutantLine -Text $sp.text -Find "$($m.Find)"
            $sel = $false; $why = ""
            if ($loc.status -eq "missing") {
                $sel = $true; $why = "find string not found in " + $sp.data.Target + " - run, because it cannot be placed (fail safe)"
            } elseif ($loc.status -eq "multiline") {
                $sel = $true; $why = "find string spans lines, which tools\Mutate.ps1 refuses - run, so the refusal is reported (fail safe)"
            } elseif ($loc.status -eq "ambiguous") {
                $sel = $true; $why = "find string occurs " + $loc.count + " times in " + $sp.data.Target + " - run, because it cannot be placed (fail safe)"
            } elseif ($touched -and $Changed[$tk].Contains([int]$loc.line)) {
                $sel = $true; $why = "line " + $loc.line + " of " + $sp.data.Target + " is added or modified"
            } elseif ($sp.specChanged) {
                $sel = $true; $why = "its spec file changed - every mutant of it runs (entries, Environment or PassCodes may differ)"
            } elseif ($touched) {
                $why = "line " + $loc.line + " of " + $sp.data.Target + " is unchanged"
            } else {
                $why = $sp.data.Target + " is not in the diff"
            }
            [void]$rows.Add([pscustomobject]@{ spec = $sp.spec; name = "$($m.Name)"; target = "$($sp.data.Target)"; line = $loc.line; selected = $sel; reason = $why })
        }
    }
    return @($rows)
}

function Get-HordeSelectionVerdict {
    # Is this selection an acceptable answer? { ok; message }. Zero selected is acceptable only when
    # the diff is empty or touches no mutation target.
    param([object[]]$Rows, [hashtable]$Changed)
    $selected = @($Rows | Where-Object { $_.selected })
    if ($selected.Count -gt 0) {
        return [pscustomobject]@{ ok = $true; message = ("selected " + $selected.Count + " of " + @($Rows).Count + " mutants") }
    }
    if ($Changed.Count -eq 0) {
        return [pscustomobject]@{ ok = $true; message = ("selected none of " + @($Rows).Count + " mutants: the diff is empty") }
    }
    $hit = @(@($Rows | ForEach-Object { $_.target }) | Sort-Object -Unique | Where-Object { $Changed.ContainsKey((ConvertTo-HordeDiffKey $_)) })
    if ($hit.Count -gt 0) {
        return [pscustomobject]@{ ok = $false; message = ("selected none, yet the diff touches the mutation target(s) " + ($hit -join ", ") + ": no mutant lies on a line it added or modified. Add mutants for the change, or run the full specs - zero is not a pass here") }
    }
    return [pscustomobject]@{ ok = $true; message = ("selected none of " + @($Rows).Count + " mutants: the diff touches no mutation target") }
}

function Get-HordeMutationSpecFiles {
    # Every mutation spec: <suite folder>/mutations/*.psd1, for each suite folder of
    # test\lib\SuiteFiles.ps1 ($script:HordeSuiteFolders), as repo-relative paths with backslashes.
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string[]]$Folders)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $out = New-Object System.Collections.ArrayList
    foreach ($pattern in $Folders) {
        $dirs = @(Get-Item -LiteralPath $rootFull)
        foreach ($p in @(($pattern -split "/") + "mutations")) {
            $next = @()
            foreach ($d in $dirs) {
                if ($p -eq "*") { $next += @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue) }
                else { $c = Join-Path $d.FullName $p; if (Test-Path -LiteralPath $c -PathType Container) { $next += @(Get-Item -LiteralPath $c) } }
            }
            $dirs = $next
        }
        foreach ($d in $dirs) {
            foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter "*.psd1" -File | Where-Object { $_.Extension -ceq ".psd1" })) {
                [void]$out.Add($f.FullName.Substring($rootFull.Length).TrimStart('\', '/'))
            }
        }
    }
    return @($out)
}

function Invoke-HordeGit {
    # git's stdout as one string, and its exit code. Not 2>&1 (PowerShell 5.1); its stderr reaches the
    # console as it is.
    param([string]$Repo, [string[]]$GitArgs)
    $lines = @(& git -C $Repo -c core.quotepath=off @GitArgs)
    return [pscustomobject]@{ code = $LASTEXITCODE; out = (($lines | ForEach-Object { "$_" }) -join "`n") }
}

function Get-HordeChangedLines {
    # The lines the working tree has that the diff from merge-base(<Base>, HEAD) added or modified,
    # untracked files included. { ok; error; mergeBase; changed }.
    param([string]$Repo, [string]$Base)
    $mb = Invoke-HordeGit -Repo $Repo -GitArgs @("merge-base", $Base, "HEAD")
    if ($mb.code -ne 0 -or -not $mb.out.Trim()) { return [pscustomobject]@{ ok = $false; error = ("cannot find the merge-base of '" + $Base + "' and HEAD"); mergeBase = ""; changed = @{} } }
    $sha = $mb.out.Trim()
    # Prefixes, colour, external diff and relative paths are given explicitly, and the config that sets
    # them is overridden too, so no user or repository setting changes what is parsed (header above).
    $d = Invoke-HordeGit -Repo $Repo -GitArgs @("-c", "diff.noprefix=false", "-c", "diff.mnemonicPrefix=false", "-c", "color.ui=false", "-c", "color.diff=false", "-c", "diff.relative=false",
        "diff", "-U0", "--no-renames", "--no-color", "--no-ext-diff", "--no-relative", "--src-prefix=a/", "--dst-prefix=b/", $sha, "--")
    if ($d.code -ne 0) { return [pscustomobject]@{ ok = $false; error = ("git diff against " + $sha + " failed"); mergeBase = $sha; changed = @{} } }
    $changed = ConvertFrom-HordeDiffZero -Text $d.out
    $why = Get-HordeDiffParseProblem -Text $d.out -Changed $changed
    if ($why) { return [pscustomobject]@{ ok = $false; error = $why; mergeBase = $sha; changed = @{} } }
    $u = Invoke-HordeGit -Repo $Repo -GitArgs @("ls-files", "--others", "--exclude-standard")
    if ($u.code -ne 0) { return [pscustomobject]@{ ok = $false; error = "git ls-files failed"; mergeBase = $sha; changed = @{} } }
    foreach ($rel in @($u.out -split "`n" | Where-Object { $_.Trim() })) {
        $full = Join-Path $Repo $rel
        $n = 1
        if (Test-Path -LiteralPath $full -PathType Leaf) { $n = @([System.IO.File]::ReadAllLines($full)).Count }
        Add-HordeWholeFile -Changed $changed -Path $rel -LineCount $n
    }
    return [pscustomobject]@{ ok = $true; error = ""; mergeBase = $sha; changed = $changed }
}
