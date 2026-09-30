# Ledger.ps1 - checks knowledge ledgers. The format is in planning/ledger/README.md.
#
# This is development tooling, not part of the engine. It answers one question: has every lesson
# the old systems learned about a module been dealt with - tested, carried, or dropped for a stated
# reason - before that module replaces anything?

$script:HordeLedgerSources = @("comments", "history", "pull requests", "docs", "tests")
$script:HordeLedgerDispositions = @("test", "comment", "dropped")

function Get-HordeLedgerFiles {
    # Every ledger in a folder. README.md and files beginning with "_" are documentation or
    # templates, not ledgers, and are skipped.
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $Dir -Filter *.md -File |
        Where-Object { $_.Name -ne "README.md" -and -not $_.Name.StartsWith("_") })
}

function Read-HordeLedgerText {
    # CR IS STRIPPED BEFORE ANY PARSING. With core.autocrlf on, a checked-out file has CRLF line
    # endings, and a pattern anchored at the end of a line silently stops matching the moment a
    # stray \r sits in front of the \n. That exact failure produced two wrong answers in one day on
    # the system this repository replaces, one of which nearly "corrected" a correct quotation.
    param([string]$Path)
    return ((Get-Content -LiteralPath $Path -Raw) -replace "`r", "")
}

function Resolve-HordeLedgerTarget {
    # Where a `where:` path really points, and whether it may be used. Returns { full; rel; problem }.
    #
    # THREE HOLES AN INDEPENDENT REVIEW FOUND, all closed here, all from one mistake - trusting
    # Test-Path to mean "a readable file":
    # - a DIRECTORY passes Test-Path, then fails to read, and that failure was swallowed, so the entry
    #   passed with no finding at all. Only a leaf file is accepted now.
    # - ".." climbed out of the repository. The resolved path must stay inside it.
    # - "." passed as a comment's file. It is a directory, so it is refused like any other.
    param([string]$RepoRoot, [string]$Rel)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $rootFull = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath((Join-Path $rootFull $Rel))
    # $relOut, NOT $rel. PowerShell variable names ignore case, so a local called $rel silently
    # OVERWROTE the $Rel parameter - and every message below then quoted a computed path instead of
    # what the ledger wrote; for "." it printed nothing at all. Found by the re-review.
    $relOut = ($full.Substring([Math]::Min($full.Length, $rootFull.Length)).TrimStart('\', '/')) -replace '\\', '/'
    if (-not $full.StartsWith($rootFull + $sep, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ full = $full; rel = $relOut; problem = "points outside the repository: $Rel" }
    }
    # NO LINKS ON THE WAY IN. The check above is lexical - GetFullPath never follows a link - so a
    # junction or symlink under test/ could reach anything on the machine while looking inside the
    # repository. Every component that exists is checked; git can commit a symlink, and a checkout
    # that allows them makes it real.
    $cur = $full
    while ($cur.Length -gt $rootFull.Length) {
        $item = Get-Item -LiteralPath $cur -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
            return [pscustomobject]@{ full = $full; rel = $relOut; problem = "passes through a link (junction or symlink), which may lead outside the repository: $Rel" }
        }
        $cur = Split-Path -Parent $cur
    }
    if (Test-Path -LiteralPath $full -PathType Container) {
        return [pscustomobject]@{ full = $full; rel = $relOut; problem = "names a directory, which is not a file: $Rel" }
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        return [pscustomobject]@{ full = $full; rel = $relOut; problem = "names a file that does not exist: $Rel" }
    }
    return [pscustomobject]@{ full = $full; rel = $relOut; problem = "" }
}

function Get-HordeWordCount {
    # Words, or DISTINCT words - the second exists because "a a a a" is four words and no sentence.
    param([string]$Text, [switch]$Distinct)
    $w = @("$Text" -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    if ($Distinct) { $w = @($w | Sort-Object -Unique) }
    return $w.Count
}

function Read-HordeTargetText {
    # A target file's text, CR stripped, or throws. The caller turns a throw into a finding, so a
    # read that fails can never quietly count as a pass - which is exactly how the directory hole
    # worked: the read failed, the check threw, and ErrorActionPreference=Continue swallowed it.
    param([string]$Full)
    $raw = Get-Content -LiteralPath $Full -Raw -ErrorAction Stop
    if ($null -eq $raw) { return "" }
    return ($raw -replace "`r", "")
}

function Test-HordeLedger {
    # Returns one object per problem found. An empty result means the ledger passed.
    #
    # $RepoRoot is where `where:` paths are resolved, and nothing outside it may be named. It is a
    # parameter so the gate can be pointed at fixtures with their own layout, which is how its own
    # controls work.
    param([string]$Path, [string]$RepoRoot)

    $name = Split-Path -Leaf $Path
    # A LIST, NOT AN ARRAY, and local to this call. A nested function can call methods on its
    # parent's variables but cannot reassign them, so `+=` on an array from inside Add-Finding would
    # silently build a new local copy and lose every finding.
    $found = New-Object System.Collections.ArrayList
    function Add-Finding { param([string]$Entry, [string]$Problem)
        [void]$found.Add([pscustomobject]@{ ledger = $name; entry = $Entry; problem = $Problem }) }

    # [string] AND a null check, because a zero-byte file gives Get-Content -Raw nothing at all, and
    # the first version then invented a phantom "unnumbered" entry instead of saying it was empty.
    [string]$text = Read-HordeLedgerText -Path $Path
    if ($null -eq $text) { $text = "" }

    # THE HEADER IS EVERYTHING BEFORE THE FIRST ENTRY, and only the header is searched for it. The
    # first version searched the whole file, so the five sources could be claimed inside an entry.
    $parts = [regex]::Split($text, "(?m)^### ")
    $header = $parts[0]
    $blocks = @($parts | Select-Object -Skip 1)

    foreach ($s in $script:HordeLedgerSources) {
        $pattern = "(?m)^-\s*" + [regex]::Escape($s) + ":\s*searched\s*$"
        if ($header -notmatch $pattern) { Add-Finding -Entry "(header)" -Problem "source '$s' is not marked searched" }
    }
    if ($header -notmatch "(?m)^module:\s*\S") { Add-Finding -Entry "(header)" -Problem "no module: line" }
    if ($header -notmatch "(?m)^replaces:\s*\S") { Add-Finding -Entry "(header)" -Problem "no replaces: line - a ledger says what it replaces" }
    if ($blocks.Count -eq 0) { Add-Finding -Entry "(ledger)" -Problem "no entries - a ledger with nothing in it records nothing" }

    $seen = @{}
    foreach ($b in $blocks) {
        $firstLine = ($b -split "`n")[0].Trim()
        $id = ""
        if ($firstLine -match "^(L-\d+)\b") { $id = $Matches[1] } else { $id = "(unnumbered: $firstLine)" }
        if ($id -like "L-*") {
            if ($seen.ContainsKey($id)) { Add-Finding -Entry $id -Problem "duplicate entry id" }
            $seen[$id] = $true
        } else {
            Add-Finding -Entry $id -Problem "entry heading must begin with L-<number>"
        }

        $source = ""; $disp = @(); $where = ""; $reason = ""
        foreach ($line in ($b -split "`n")) {
            if ($line -match "^-\s*source:\s*(.*)$")      { $source = $Matches[1].Trim() }
            if ($line -match "^-\s*disposition:\s*(.*)$") { $disp += $Matches[1].Trim() }
            if ($line -match "^-\s*where:\s*(.*)$")       { $where = $Matches[1].Trim() }
            if ($line -match "^-\s*reason:\s*(.*)$")      { $reason = $Matches[1].Trim() }
        }

        if (-not $source) { Add-Finding -Entry $id -Problem "no source - a lesson that cannot be traced cannot be re-examined" }

        if ($disp.Count -eq 0) { Add-Finding -Entry $id -Problem "no disposition - nobody dealt with this"; continue }
        if ($disp.Count -gt 1) { Add-Finding -Entry $id -Problem "more than one disposition"; continue }
        $d = "$($disp[0])".ToLowerInvariant()
        if ($script:HordeLedgerDispositions -notcontains $d) { Add-Finding -Entry $id -Problem "unknown disposition '$d'"; continue }

        # `break` below leaves the switch only, which is the intent; the foreach carries on to the
        # next entry. (An independent review checked this and confirmed it.)
        switch ($d) {
            "test" {
                if ($where -notmatch '^(?<file>[^:]+?)\s*::\s*"(?<text>[^"]+)"\s*$') {
                    Add-Finding -Entry $id -Problem "test disposition needs where: <file> :: `"<assertion text>`""
                    break
                }
                $wantFile = $Matches["file"].Trim(); $assertion = $Matches["text"]
                $t = Resolve-HordeLedgerTarget -RepoRoot $RepoRoot -Rel $wantFile
                if ($t.problem) { Add-Finding -Entry $id -Problem $t.problem; break }
                # A TEST, not any file. The first version accepted the ledger itself - its own where:
                # line contains the quoted text - so an entry could certify itself.
                if ($t.rel -notmatch '^test/.+\.ps1$') { Add-Finding -Entry $id -Problem "must name a test script under test/, not $($t.rel)"; break }
                # ENOUGH TEXT TO MEAN SOMETHING. "e" appears in every file.
                if ((Get-HordeWordCount -Text $assertion) -lt 3) { Add-Finding -Entry $id -Problem "the assertion must be at least three words, or it matches almost anything"; break }
                $body = $null
                try { $body = Read-HordeTargetText -Full $t.full } catch { Add-Finding -Entry $id -Problem "cannot read $($t.rel): $($_.Exception.Message)"; break }
                # AS A QUOTED STRING, ON A LINE OF CODE - the form a test's name takes. Two looser
                # versions were each broken in review: plain text matched a comment, and a quoted
                # string still matched a COMMENT that quotes a test that has since been deleted -
                # which is exactly the rot this gate exists to catch.
                $quoted = '"' + $assertion + '"'
                $code = (($body -split "`n") | Where-Object { -not $_.TrimStart().StartsWith("#") }) -join "`n"
                if ($code.Contains($quoted)) { break }
                if ($body.Contains($quoted)) { Add-Finding -Entry $id -Problem "the quoted text appears only in a comment in $($t.rel) - the assertion it names may have been deleted" }
                elseif ($body.Contains($assertion)) { Add-Finding -Entry $id -Problem "the text is in $($t.rel) but not as a quoted string, so it is not an assertion's name" }
                else { Add-Finding -Entry $id -Problem "test file exists but does not contain the assertion `"$assertion`"" }
            }
            "comment" {
                # THE LESSON ITSELF MUST BE FINDABLE. The first version checked only that a file
                # existed - "." passed - so nothing verified that the lesson was carried anywhere.
                if ($where -notmatch '^(?<file>[^:]+?)\s*::\s*"(?<text>[^"]+)"\s*$') {
                    Add-Finding -Entry $id -Problem "comment disposition needs where: <file> :: `"<phrase from the comment>`""
                    break
                }
                $wantFile = $Matches["file"].Trim(); $phrase = $Matches["text"]
                $t = Resolve-HordeLedgerTarget -RepoRoot $RepoRoot -Rel $wantFile
                if ($t.problem) { Add-Finding -Entry $id -Problem $t.problem; break }
                # THE LEDGER ITSELF, compared by full path, so it holds wherever the ledger lives - the
                # planning/ledger/ rule below only covers ledgers kept in the usual place.
                if ([string]::Equals($t.full, [System.IO.Path]::GetFullPath($Path), [System.StringComparison]::OrdinalIgnoreCase)) {
                    Add-Finding -Entry $id -Problem "names the ledger itself as the place the lesson is carried"; break
                }
                if ($t.rel -match '^planning/ledger/') { Add-Finding -Entry $id -Problem "a lesson cannot be carried in a ledger, which is where it is being claimed"; break }
                if ((Get-HordeWordCount -Text $phrase) -lt 3) { Add-Finding -Entry $id -Problem "the phrase must be at least three words, or it matches almost anything"; break }
                $body = $null
                try { $body = Read-HordeTargetText -Full $t.full } catch { Add-Finding -Entry $id -Problem "cannot read $($t.rel): $($_.Exception.Message)"; break }
                if (-not $body.Contains($phrase)) { Add-Finding -Entry $id -Problem "$($t.rel) does not contain the phrase `"$phrase`"" }
            }
            "dropped" {
                # A sentence is measured as at least four DISTINCT words: enough to stop "n/a" and
                # "a a a a", not so strict that a short, true reason is refused.
                if ((Get-HordeWordCount -Text $reason -Distinct) -lt 4) {
                    Add-Finding -Entry $id -Problem "dropped needs a reason of at least a sentence"
                }
            }
        }
    }
    return @($found)
}
