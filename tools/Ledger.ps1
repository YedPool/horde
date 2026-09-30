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

function Test-HordeLedger {
    # Returns one object per problem found. An empty result means the ledger passed.
    #
    # $RepoRoot is where the `where:` paths of test and comment dispositions are resolved. It is a
    # parameter rather than assumed so the gate can be pointed at fixtures with their own layout -
    # which is how its own controls work.
    param([string]$Path, [string]$RepoRoot)

    $name = Split-Path -Leaf $Path
    # A LIST, NOT AN ARRAY, and local to this call. A nested function can call methods on its
    # parent's variables but cannot reassign them, so `+=` on an array from inside Add-Finding would
    # silently build a new local copy and lose every finding. Keeping it local also means two calls
    # can never see each other's results.
    $found = New-Object System.Collections.ArrayList
    function Add-Finding { param([string]$Entry, [string]$Problem)
        [void]$found.Add([pscustomobject]@{ ledger = $name; entry = $Entry; problem = $Problem }) }

    $text = Read-HordeLedgerText -Path $Path

    # --- the header: all five sources must have been searched --------------------------------
    foreach ($s in $script:HordeLedgerSources) {
        $pattern = "(?m)^-\s*" + [regex]::Escape($s) + ":\s*searched\s*$"
        if ($text -notmatch $pattern) { Add-Finding -Entry "(header)" -Problem "source '$s' is not marked searched" }
    }
    if ($text -notmatch "(?m)^module:\s*\S") { Add-Finding -Entry "(header)" -Problem "no module: line" }

    # --- the entries -------------------------------------------------------------------------
    $blocks = [regex]::Split($text, "(?m)^### ") | Select-Object -Skip 1
    if (@($blocks).Count -eq 0) { Add-Finding -Entry "(ledger)" -Problem "no entries - a ledger with nothing in it records nothing" }

    $seen = @{}
    foreach ($b in @($blocks)) {
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

        if (@($disp).Count -eq 0) { Add-Finding -Entry $id -Problem "no disposition - nobody dealt with this"; continue }
        if (@($disp).Count -gt 1) { Add-Finding -Entry $id -Problem "more than one disposition"; continue }
        $d = "$($disp[0])".ToLowerInvariant()
        if ($script:HordeLedgerDispositions -notcontains $d) { Add-Finding -Entry $id -Problem "unknown disposition '$d'"; continue }

        switch ($d) {
            "test" {
                # THE CHECK THAT MAKES THE GATE REAL. Without it, writing "test" beside every entry
                # would pass while enforcing nothing. The named file must exist AND contain the quoted
                # assertion text.
                if ($where -notmatch '^(?<file>[^:]+?)\s*::\s*"(?<text>[^"]+)"\s*$') {
                    Add-Finding -Entry $id -Problem "test disposition needs where: <file> :: `"<assertion text>`""
                    break
                }
                $file = Join-Path $RepoRoot $Matches["file"].Trim()
                $assertion = $Matches["text"]
                if (-not (Test-Path -LiteralPath $file)) { Add-Finding -Entry $id -Problem "names a test file that does not exist: $($Matches['file'].Trim())"; break }
                $body = Read-HordeLedgerText -Path $file
                if (-not $body.Contains($assertion)) { Add-Finding -Entry $id -Problem "test file exists but does not contain the assertion `"$assertion`"" }
            }
            "comment" {
                if (-not $where) { Add-Finding -Entry $id -Problem "comment disposition needs where: <file>"; break }
                $file = Join-Path $RepoRoot (($where -split "\s*::\s*")[0].Trim())
                if (-not (Test-Path -LiteralPath $file)) { Add-Finding -Entry $id -Problem "names a file that does not exist: $where" }
            }
            "dropped" {
                # "A sentence" is measured loosely as at least four words: enough to stop a bare
                # "n/a", not so strict that a short, true reason is refused.
                if (@($reason -split "\s+" | Where-Object { $_ }).Count -lt 4) {
                    Add-Finding -Entry $id -Problem "dropped needs a reason of at least a sentence"
                }
            }
        }
    }
    return @($found)
}
