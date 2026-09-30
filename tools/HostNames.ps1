# HostNames.ps1 - the ratchet for decision D12: nothing outside hosts/<name>/ names that host.
#
# Development tooling, not part of the engine. It answers one question: does any file outside a
# host's own folder name that host - a terminal - where the host's allowlist does not say it may?
#
# WHY A RATCHET AND NOT A RULE ALONE. D12 (planning/migration-plan.html) says the engine, the schemas
# and the read model speak of sessions, slots and capabilities, never of a particular terminal, so
# that a second host is a new adapter and not an engine change. The first host was the only host for
# the whole life of the systems Horde replaces, and its name is in comments, fixtures and data today.
# A rule with no check would erode one reasonable-looking mention at a time. So each existing mention
# is listed, with its reason and its exact number of mentions, and the list may only get shorter.
#
# THE DATA IS THE HOST'S. Each host declares what identifies it in hosts/<name>/names.txt, and its
# exceptions in hosts/<name>/allowlist.txt. This file and its suite name no terminal at all, so the
# ratchet does not have to except itself, and a new host brings its own names without touching it.
#
#   names.txt, one per line:      <name> | <why it identifies this host>
#   allowlist.txt, one per line:  <path> | <mentions> | <why this file may name the host>
#   Blank lines and lines beginning with # are ignored in both.
#
# WHAT COUNTS. A name is matched as a case-insensitive substring. A file's count is the number of
# MENTIONS - every occurrence of every one of the host's names in its text - plus one if its path
# names the host. Mentions, not lines: a second mention added to a line that already had one is a new
# mention (review of PR 21). An allowlisted count must be EXACT: more mentions than listed is a new
# mention; fewer is an entry that allows more than is needed, and it must be lowered. That second
# half is what makes the list shrink-only.
#
# SWAPPING ONE MENTION FOR ANOTHER IS STILL INVISIBLE. The count is a number per file, so deleting a
# mention and adding a different one in the same file - a comment's citation traded for a call to the
# terminal - leaves it unchanged. The ratchet catches growth, not substitution; a reviewer reading the
# diff of an allowlisted file is what catches that.
#
# WHAT IS NOT SCANNED, by rule:
#   - hosts/<name>/ itself: the one place the host's name belongs.
#   - the .md and .html files under planning/: plans, ledgers and handoffs are prose records of the
#     system being replaced and of the migration away from it. They cannot be accurate without naming
#     the terminal, and D12 governs the code and the contracts, not the history. Listing them would
#     make every plan edit an allowlist edit and protect nothing. ONLY PROSE: the first version
#     skipped planning/ whatever the file, and the review of PR 21 hid a script there that core
#     dot-sourced. Any other file under planning/ is a finding of its own, and is scanned as well.
#   - .git/: not the repository's content.
# Other hosts' folders ARE scanned: hosts/vscode naming another terminal would be the same leak.
#
# EVERY SCANNED BYTE IS PRINTABLE ASCII (tab, LF, CR, 0x20-0x7E), host folders included: CONTRIBUTING
# rule 13 already requires it, and it is what lets a byte-for-byte substring search stand for "names
# the host". Without it the review of PR 21 hid a name behind a look-alike Cyrillic letter and behind
# UTF-16 with no byte order mark (a NUL after every letter); both read as nothing. Both are refused now.
#
# WHAT THE SCAN STILL CANNOT SEE, so that nobody reads a pass as more than it is:
#   - A NAME BUILT AT RUN TIME: two string halves joined, or an environment variable's name assembled
#     from pieces. The scan matches text, not what the code computes.
#   - A NAME SPLIT ACROSS LINES: half at the end of one line of a here-string, half on the next.
#   - PATHS LONGER THAN 260 CHARACTERS: untested. The review's attempt to plant one failed in its own
#     setup ("Illegal characters in path"), so whether Get-ChildItem under PowerShell 5.1 lists such a
#     file is not known.
#   - SUBSTITUTION inside an allowlisted file (see WHAT COUNTS above).
#
# THE DISK, NOT GIT. The scan reads the working tree (see Get-HordeRepoFiles for why), so what fails
# locally and what a pull request holds can differ: a local file that is untracked or ignored and
# names a host fails the suite on that machine only, and a committed file deleted from the working
# tree passes there. No .gitignore exists and no suite leaves files in the tree - `git status
# --ignored --short` printed nothing on 2026-09-30 after every suite had run - so today the two agree.
# A tool that starts leaving artefacts in the tree should write them outside it, or bring a .gitignore
# and teach this scan to honour it.

$script:HordeHostNamesProseFolder = "planning"
$script:HordeHostNamesProseTypes = @(".md", ".html")
$script:HordeHostNameMinLength = 4

function Read-HordeHostTable {
    # The non-comment lines of names.txt or allowlist.txt, split on "|" and trimmed, with their line
    # numbers. With core.autocrlf on, a checked-out file has CRLF endings; the Trim below removes the
    # CR each line keeps after the split on LF. A separate CR strip would be dead code that no test
    # could fail on, so there is none.
    param([string]$Path)
    $rows = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($raw in ([System.IO.File]::ReadAllText($Path) -split "`n")) {
        $n++
        $t = $raw.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        [void]$rows.Add([pscustomobject]@{ line = $n; cells = @($t -split "\|" | ForEach-Object { $_.Trim() }) })
    }
    return , $rows
}

function Get-HordeDistinctWordCount {
    # "a a a a" is four words and no reason. The ledger gate measures a reason the same way.
    param([string]$Text)
    return @(@("$Text" -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }) | Sort-Object -Unique).Count
}

function Test-HordeUnderFolder {
    # Is the forward-slash relative path inside one of the folders? Compared ignoring case, because
    # the filesystem does.
    param([string]$Rel, [string[]]$Folders)
    foreach ($x in $Folders) {
        if ($Rel.StartsWith($x.TrimEnd('/') + "/", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Test-HordePlanningProse {
    # Is the forward-slash relative path a .md or .html file under planning/? The extension is
    # compared ignoring case, as the filesystem compares names.
    param([string]$Rel)
    if (-not (Test-HordeUnderFolder -Rel $Rel -Folders @($script:HordeHostNamesProseFolder))) { return $false }
    return ($script:HordeHostNamesProseTypes -contains ([System.IO.Path]::GetExtension($Rel).ToLowerInvariant()))
}

function Get-HordeFirstNonAsciiByte {
    # The offset of the file's first byte that is not printable ASCII - tab, LF, CR and 0x20-0x7E are
    # allowed - or -1 if there is none. The bytes are decoded as ISO-8859-1, which maps each byte to
    # the character with the same number, so a regex can look at bytes without a loop over them.
    param([string]$Full)
    $bytes = [System.IO.File]::ReadAllBytes($Full)
    $m = [regex]::Match([System.Text.Encoding]::GetEncoding(28591).GetString($bytes), '[^\t\n\r\x20-\x7E]')
    if ($m.Success) { return $m.Index }
    return -1
}

function Get-HordeRepoFiles {
    # Every file under the root except .git/ and the given folders, as forward-slash paths relative
    # to the root. The filesystem, not `git ls-files`: tools/Mutate.ps1 runs suites in a copy with no
    # .git, and a file not yet added is exactly the one a ratchet must see.
    param([string]$RepoRoot, [string[]]$Skip)
    $rootFull = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $out = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
        # .git IS A FILE IN A WORKTREE, holding the path of the main repository, and that path can
        # name anything: the worktree this ratchet was written in had the terminal's name in its
        # folder name, and the first count reported .git as a mention. Skipped as a file as well.
        if ($rel -eq ".git" -or (Test-HordeUnderFolder -Rel $rel -Folders (@(".git") + $Skip))) { continue }
        if (Test-HordePlanningProse -Rel $rel) { continue }
        [void]$out.Add([pscustomobject]@{ rel = $rel; full = $f.FullName })
    }
    return , $out
}

function Get-HordeNameMentionCount {
    # How many times the file names the host: every occurrence of every name in its text, plus one if
    # its path names the host. Occurrences, not lines - the review of PR 21 appended a second mention
    # to a line that already had one, and a count of lines did not move. Occurrences of one name do
    # not overlap ("aa" is in "aaa" once), and a name inside another name is counted for each.
    # Every file is read as text. Any file that is not printable ASCII is refused on its own by
    # Test-HordeHostNames, so the text read here is the bytes on disk, one character each.
    param([string]$Full, [string]$Rel, [string[]]$Names)
    $count = 0
    foreach ($nm in $Names) { if ($Rel.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $count = 1; break } }
    $text = [System.IO.File]::ReadAllText($Full)
    foreach ($nm in $Names) {
        $at = $text.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase)
        while ($at -ge 0) {
            $count++
            $at = $text.IndexOf($nm, $at + $nm.Length, [System.StringComparison]::OrdinalIgnoreCase)
        }
    }
    return $count
}

function Test-HordeHostNames {
    # Returns one object per problem found, { host; path; problem }. An empty result means every host
    # is named only where its allowlist says, exactly as often as it says. Wrap the call in @():
    # the findings are returned unrolled, like Test-HordeLedger's, so one finding arrives bare. (The
    # first version returned the list as one object, and every result then had a Count of 1 - the
    # clean control caught it.)
    param([string]$RepoRoot)
    $found = New-Object System.Collections.ArrayList
    function Add-Finding { param([string]$HostName, [string]$Where, [string]$Problem)
        [void]$found.Add([pscustomobject]@{ host = $HostName; path = $Where; problem = $Problem }) }

    # ANYTHING BUT PROSE UNDER planning/ is refused, once for the repository and whatever it names:
    # only prose is exempt from the scan, so only prose may live there.
    # Get-HordeRepoFiles already leaves the prose out, so whatever it returns under planning/ is not.
    foreach ($f in (Get-HordeRepoFiles -RepoRoot $RepoRoot -Skip @())) {
        if (Test-HordeUnderFolder -Rel $f.rel -Folders @($script:HordeHostNamesProseFolder)) {
            Add-Finding "(repository)" $f.rel "is under planning/, where only .md and .html are allowed and skipped - move it out of planning/"
        }
        # EVERY BYTE PRINTABLE ASCII, host folders included (CONTRIBUTING rule 13 has no exemption).
        # The name scan reads bytes as text, so a name written with a look-alike letter, or in UTF-16
        # without a byte order mark (a NUL after every letter), was invisible to it - the review of
        # PR 21 measured both. Refusing every other byte closes both holes, and a BOM with them.
        $bad = Get-HordeFirstNonAsciiByte -Full $f.full
        if ($bad -ge 0) {
            Add-Finding "(repository)" $f.rel ("has a byte that is not printable ASCII at offset " + $bad + " - source files are ASCII (CONTRIBUTING rule 13), and a name hidden in such bytes is invisible to this scan")
        }
    }

    $hostsDir = Join-Path $RepoRoot "hosts"
    $hostDirs = @()
    if (Test-Path -LiteralPath $hostsDir -PathType Container) { $hostDirs = @(Get-ChildItem -LiteralPath $hostsDir -Directory) }
    foreach ($h in $hostDirs) {
        $hn = $h.Name
        $own = "hosts/" + $hn
        $namesPath = Join-Path $h.FullName "names.txt"
        # A HOST THAT DECLARES NO NAMES CANNOT BE POLICED, so it is a finding, not a pass.
        if (-not (Test-Path -LiteralPath $namesPath -PathType Leaf)) {
            Add-Finding $hn $own "declares no names.txt, so nothing can check that it stays in its folder"; continue
        }
        $names = New-Object System.Collections.ArrayList
        foreach ($r in (Read-HordeHostTable -Path $namesPath)) {
            $where = $own + "/names.txt:" + $r.line
            if ($r.cells.Count -ne 2) { Add-Finding $hn $where "a name line is <name> | <why it identifies this host>"; continue }
            $nm = $r.cells[0]
            # A SHORT NAME MATCHES EVERYWHERE, and a ratchet that fires on every file gets allowlisted
            # into meaning nothing.
            if ($nm.Length -lt $script:HordeHostNameMinLength) { Add-Finding $hn $where ("the name '" + $nm + "' is shorter than " + $script:HordeHostNameMinLength + " characters and would match almost anything"); continue }
            if ((Get-HordeDistinctWordCount $r.cells[1]) -lt 4) { Add-Finding $hn $where ("the name '" + $nm + "' needs a reason of at least a sentence"); continue }
            [void]$names.Add($nm)
        }
        if ($names.Count -eq 0) { Add-Finding $hn ($own + "/names.txt") "lists no usable name, so nothing is checked"; continue }

        $skip = @($own)
        $allowed = @{}
        $allowPath = Join-Path $h.FullName "allowlist.txt"
        if (Test-Path -LiteralPath $allowPath -PathType Leaf) {
            foreach ($r in (Read-HordeHostTable -Path $allowPath)) {
                $where = $own + "/allowlist.txt:" + $r.line
                if ($r.cells.Count -ne 3) { Add-Finding $hn $where "an allowlist line is <path> | <mentions> | <why this file may name the host>"; continue }
                $p = ($r.cells[0] -replace '\\', '/').TrimStart('/')
                $allowCount = 0
                if (-not [int]::TryParse($r.cells[1], [ref]$allowCount) -or $allowCount -lt 1) { Add-Finding $hn $where ("the mention count for " + $p + " must be a whole number of at least 1"); continue }
                if ((Get-HordeDistinctWordCount $r.cells[2]) -lt 4) { Add-Finding $hn $where ($p + " needs a reason of at least a sentence"); continue }
                $key = $p.ToLowerInvariant()
                if ($allowed.ContainsKey($key)) { Add-Finding $hn $where ($p + " is listed twice"); continue }
                # AN ENTRY FOR A PATH THE SCAN NEVER READS allows nothing, and would sit there forever.
                if ((Test-HordeUnderFolder -Rel $p -Folders $skip) -or (Test-HordePlanningProse -Rel $p)) { Add-Finding $hn $where ($p + " is excluded from the scan by rule, so the entry is not needed"); continue }
                $allowed[$key] = [pscustomobject]@{ path = $p; count = $allowCount }
            }
        }

        $seen = @{}
        foreach ($f in (Get-HordeRepoFiles -RepoRoot $RepoRoot -Skip $skip)) {
            $c = Get-HordeNameMentionCount -Full $f.full -Rel $f.rel -Names $names
            $key = $f.rel.ToLowerInvariant()
            $a = $allowed[$key]
            if ($a) { $seen[$key] = $c }
            if ($c -eq 0) { continue }
            if (-not $a) { Add-Finding $hn $f.rel ("has " + $c + " mention(s) of the host and is not in " + $own + "/allowlist.txt"); continue }
            if ($c -gt $a.count) { Add-Finding $hn $f.rel ("has " + $c + " mention(s); the allowlist allows " + $a.count + " - a new mention") }
            elseif ($c -lt $a.count) { Add-Finding $hn $f.rel ("has only " + $c + " mention(s); the allowlist allows " + $a.count + " - lower it to " + $c) }
        }
        # LISTED, BUT NAMING THE HOST NOWHERE, OR NOT THERE AT ALL: the entry allows what nothing needs.
        foreach ($k in @($allowed.Keys)) {
            if (-not $seen.ContainsKey($k)) { Add-Finding $hn $allowed[$k].path ("is listed in " + $own + "/allowlist.txt but does not exist - remove the entry") }
            elseif ($seen[$k] -eq 0) { Add-Finding $hn $allowed[$k].path ("no longer names the host - remove its entry from " + $own + "/allowlist.txt") }
        }
    }
    return $found
}
