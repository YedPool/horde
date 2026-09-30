# HostNames.ps1 - the ratchet for decision D12: nothing outside a port's own folder names that port.
#
# Development tooling, not part of the engine. It answers one question: does any file outside a
# port's own folder name that port - a terminal in hosts/<name>/, an agent harness in agents/<name>/ -
# where the port's allowlist does not say it may?
#
# TWO FAMILIES OF PORT, ONE RULE. D12 was written for terminals. The engine-settings design of
# 2026-09-30 (section 9, build step E1) applies the same seam to the agent harness - the CLI process a
# session runs - and the founder's decision of the same day says core never names an engine. A harness
# is therefore a port exactly as a host is: its folder is agents/<name>/, with the same names.txt,
# allowlist.txt and growth.txt, read by the same code below. Everything this header says of a "host"
# holds for a harness; the word is kept where it was, and a finding names the port by its folder
# ("hosts/<name>" or "agents/<name>"), so a host and a harness that share a folder name stay apart.
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
#   growth.txt, one per line:     <path> | <old> -> <new> | <YYYY-MM-DD> | <why the list must grow>
#   Blank lines and lines beginning with # are ignored in all three.
#
# WHAT COUNTS. A name is matched as a case-insensitive substring. A file's count is the number of
# MENTIONS - every occurrence of every one of the host's names in its text - plus one if its path
# names the host. Mentions, not lines: a second mention added to a line that already had one is a new
# mention (review of PR 21). An allowlisted count must be EXACT: more mentions than listed is a new
# mention; fewer is an entry that allows more than is needed, and it must be lowered.
#
# SHRINK-ONLY NEEDS AN OLD LIST TO COMPARE WITH. An exact count keeps a file in step with its own
# entry, but both are edited in the same tree, so the review of PR 21 raised a count together with
# the mention, added a file with its own entry, and deleted a name, each with 0 findings. There is no
# CI, so Test-HordeHostShrink compares each host's lists with origin/main: no new entry, no higher
# count, no name or host folder removed. With no git, no .git or no origin/main it returns a reason
# instead, which the suite prints as [SKIP]; a host new on the branch is reported, not compared.
#
# GROWTH IS RECORDED, NOT FORBIDDEN. Refusing every increase with no override was a deadlock: a
# branch that genuinely needs a new mention could never pass until the entry was already on main,
# and nothing but merging a failing branch could put it there. So an increase - a new path (old
# count 0) or a higher count - passes when hosts/<name>/growth.txt has a line for exactly that path,
# that old count and that new count, dated, with a reason of at least four distinct words. That line
# is what the reviewer agrees to. Only lines added since origin/main count: a line already on main
# recorded an increase that was merged, and letting it permit the same increase again would let a
# mention be removed and later restored with no review. growth.txt is append-only against
# origin/main - its lines there must still open the file, in order and unchanged - so the record of
# what was agreed cannot be rewritten. A line that matches no current difference is history, not a
# finding. There is no growth path for names.txt: a name is never removed.
#
# SWAPPING ONE MENTION FOR ANOTHER IS STILL INVISIBLE. The count is a number per file, so deleting a
# mention and adding a different one in the same file - a comment's citation traded for a call to the
# terminal - leaves it unchanged. The ratchet catches growth, not substitution; a reviewer reading the
# diff of an allowlisted file is what catches that. KNOWN LIMITATION, recorded in the review of PR 34
# and not fixed there: the harness allowlists made this larger, because they hold files with dozens of
# mentions each (core/Identity.ps1 names one harness 72 times), and a new mention traded for a deleted
# one in such a file is one line among many in its diff. Counting per line or per mention context
# would close it; until then it is review's to catch.
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
# The families of port, each a top-level folder holding one folder per port. A third family is a line
# here, not a copy of the scan. Order is only the order findings are reported in.
$script:HordePortFamilies = @("hosts", "agents")
$script:HordeHostNamesProseTypes = @(".md", ".html")
$script:HordeHostNameMinLength = 4

function Read-HordeHostTable {
    # The non-comment lines of names.txt or allowlist.txt, split on "|" and trimmed, with their line
    # numbers. With core.autocrlf on, a checked-out file has CRLF endings; the Trim below removes the
    # CR each line keeps after the split on LF. A separate CR strip would be dead code that no test
    # could fail on, so there is none.
    param([string]$Path)
    return , (Split-HordeHostTable -Text ([System.IO.File]::ReadAllText($Path)))
}

function Split-HordeHostTable {
    # Read-HordeHostTable's parser, on text already in hand - the working tree's file, or the same
    # file as origin/main holds it. One parser for both, so the two are never read differently.
    param([string]$Text)
    $rows = New-Object System.Collections.ArrayList
    $n = 0
    foreach ($raw in ($Text -split "`n")) {
        $n++
        $t = $raw.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        [void]$rows.Add([pscustomobject]@{ line = $n; cells = @($t -split "\|" | ForEach-Object { $_.Trim() }) })
    }
    return , $rows
}

function Get-HordeHostNameSet {
    # The names a names.txt declares, lower-cased (a name is matched ignoring case), from its well-
    # formed lines. A malformed line is Test-HordeHostNames's to report, not this one's.
    param([string]$Text)
    $set = @{}
    foreach ($r in (Split-HordeHostTable -Text $Text)) { if ($r.cells.Count -eq 2) { $set[$r.cells[0].ToLowerInvariant()] = $r.cells[0] } }
    return $set
}

function ConvertTo-HordeAllowPath {
    # An allowlist path as the scan writes paths: forward slashes, no leading slash. One function, so
    # the working tree's list and origin/main's are read the same way.
    param([string]$Path)
    return ($Path -replace '\\', '/').TrimStart('/')
}

function Get-HordeAllowMap {
    # path (forward slashes, lower-cased) -> { path; count } from an allowlist's well-formed lines.
    param([string]$Text)
    $map = @{}
    foreach ($r in (Split-HordeHostTable -Text $Text)) {
        if ($r.cells.Count -ne 3) { continue }
        $c = 0
        if (-not [int]::TryParse($r.cells[1], [ref]$c)) { continue }
        $p = ConvertTo-HordeAllowPath $r.cells[0]
        $map[$p.ToLowerInvariant()] = [pscustomobject]@{ path = $p; count = $c }
    }
    return $map
}

function Test-HordeHostShrink {
    # Have any host's lists grown since origin/main? Returns { skip; findings; newHosts }.
    #
    # WHY. The exact count in allowlist.txt stops a file from naming its host more often than its entry
    # says, but the entry is edited in the same working tree: the review of PR 21 raised a count with
    # the mention it allowed, added a new file with its own entry, and deleted a name from names.txt,
    # and each gave 0 findings. There is no CI to hold the old list, so origin/main is the old list:
    #   - no allowlist path that origin/main does not list may appear, and no count may be higher
    #     than origin/main's, UNLESS a growth.txt line added since origin/main records exactly that
    #     path, old count (0 for a new path) and new count - the header says why;
    #   - growth.txt's lines on origin/main must still open the file, in order and unchanged;
    #   - no name origin/main's names.txt declares may be missing, and no host folder may vanish.
    # A port whose names.txt is not on origin/main at all is NEW: its folder ("agents/<name>") is listed
    # in newHosts and not compared, because its first pull request is where its lists are agreed.
    #
    # skip is non-empty, and says why, when there is nothing to compare with - no git, no .git at the
    # root (tools/Mutate.ps1's copies), or no such ref. The caller must print it: an unmeasured
    # comparison is never a pass.
    param([string]$RepoRoot, [string]$Ref = "origin/main")
    $out = [pscustomobject]@{ skip = ""; findings = (New-Object System.Collections.ArrayList); newHosts = (New-Object System.Collections.ArrayList) }
    function Add-Finding { param([string]$HostName, [string]$Where, [string]$Problem)
        [void]$out.findings.Add([pscustomobject]@{ host = $HostName; path = $Where; problem = $Problem }) }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $out.skip = "git is not on PATH"; return $out }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) { $out.skip = "no .git at " + $RepoRoot + " - not a git checkout"; return $out }
    # --quiet: a missing ref exits 1 and prints nothing, so no stderr needs redirecting (and under
    # PowerShell 5.1 a native command's stderr must not be, CONTRIBUTING rule 12).
    $null = & git -C $RepoRoot rev-parse --verify --quiet ($Ref + "^{commit}")
    if ($LASTEXITCODE -ne 0) { $out.skip = $Ref + " does not exist in this checkout - run git fetch origin main to compare"; return $out }
    $onRef = @{}
    foreach ($p in @(& git -C $RepoRoot ls-tree -r --name-only $Ref -- @($script:HordePortFamilies))) { $onRef[$p] = $true }
    if ($LASTEXITCODE -ne 0) { $out.skip = "git ls-tree " + $Ref + " failed with exit code " + $LASTEXITCODE; return $out }

    # Keyed by the port's folder, "hosts/<name>" or "agents/<name>", never by the bare name: a harness
    # and a host may share a name, and each is compared with its own lists only.
    $here = @{}
    foreach ($fam in $script:HordePortFamilies) {
        $famDir = Join-Path $RepoRoot $fam
        if (Test-Path -LiteralPath $famDir -PathType Container) { foreach ($h in @(Get-ChildItem -LiteralPath $famDir -Directory)) { $here[$fam + "/" + $h.Name] = $h.FullName } }
    }
    # A PORT FOLDER THAT IS GONE takes its whole check with it, so it is the largest removal of all.
    foreach ($p in @($onRef.Keys)) {
        if ($p -match '^([^/]+/[^/]+)/names\.txt$' -and -not $here.ContainsKey($Matches[1])) {
            Add-Finding $Matches[1] $Matches[1] ("is on " + $Ref + " and gone here - deleting its folder switches its check off")
        }
    }
    foreach ($own in @($here.Keys | Sort-Object)) {
        $hn = $own
        if (-not $onRef.ContainsKey($own + "/names.txt")) { [void]$out.newHosts.Add($own); continue }
        $oldNames = Get-HordeHostNameSet -Text ((@(& git -C $RepoRoot show ($Ref + ":" + $own + "/names.txt"))) -join "`n")
        $newNames = @{}
        $np = Join-Path $here[$own] "names.txt"
        if (Test-Path -LiteralPath $np -PathType Leaf) { $newNames = Get-HordeHostNameSet -Text ([System.IO.File]::ReadAllText($np)) }
        foreach ($k in @($oldNames.Keys | Sort-Object)) {
            if (-not $newNames.ContainsKey($k)) { Add-Finding $hn ($own + "/names.txt") ("the name '" + $oldNames[$k] + "' is declared on " + $Ref + " and missing here - a name may not be removed") }
        }
        $growth = Get-HordeGrowthPermits -RepoRoot $RepoRoot -Ref $Ref -Own $own -HostDir $here[$own] -OnRef $onRef
        foreach ($g in $growth.problems) { Add-Finding $hn $g.path $g.problem }
        $oldAllow = @{}
        if ($onRef.ContainsKey($own + "/allowlist.txt")) { $oldAllow = Get-HordeAllowMap -Text ((@(& git -C $RepoRoot show ($Ref + ":" + $own + "/allowlist.txt"))) -join "`n") }
        $newAllow = @{}
        $ap = Join-Path $here[$own] "allowlist.txt"
        if (Test-Path -LiteralPath $ap -PathType Leaf) { $newAllow = Get-HordeAllowMap -Text ([System.IO.File]::ReadAllText($ap)) }
        foreach ($k in @($newAllow.Keys | Sort-Object)) {
            $e = $newAllow[$k]
            $was = 0
            if ($oldAllow.ContainsKey($k)) { $was = $oldAllow[$k].count }
            if ($e.count -le $was) { continue }
            if ($growth.permits.ContainsKey($k + "|" + $was + "|" + $e.count)) { continue }
            $record = " without a line added to " + $own + "/growth.txt recording '" + $e.path + " | " + $was + " -> " + $e.count + " | <date> | <reason>'"
            if ($was -eq 0) { Add-Finding $hn $e.path ("is in " + $own + "/allowlist.txt but not on " + $Ref + " - an entry may not be added" + $record) }
            else { Add-Finding $hn $e.path ("is allowed " + $e.count + " mention(s) here and " + $was + " on " + $Ref + " - a count may not rise" + $record) }
        }
    }
    return $out
}

function Get-HordeGrowthPermits {
    # What a host's growth.txt permits, and what is wrong with it: { permits; problems }. permits is a
    # set of "path|old|new" keys from the lines added since the ref ONLY; problems
    # lists { path; problem } for a ref line gone or changed here and for a malformed added line.
    # The header says why each rule exists.
    # Own is the port's folder, "hosts/<name>" or "agents/<name>": each port's growth is recorded, and
    # reviewed, in its own growth.txt, so a line in a host's file permits nothing for a harness.
    param([string]$RepoRoot, [string]$Ref, [string]$Own, [string]$HostDir, [hashtable]$OnRef)
    $out = [pscustomobject]@{ permits = @{}; problems = (New-Object System.Collections.ArrayList) }
    $rel = $Own + "/growth.txt"
    $old = New-Object System.Collections.ArrayList
    if ($OnRef.ContainsKey($rel)) { $old = Split-HordeHostTable -Text ((@(& git -C $RepoRoot show ($Ref + ":" + $rel))) -join "`n") }
    $new = New-Object System.Collections.ArrayList
    $gp = Join-Path $HostDir "growth.txt"
    if (Test-Path -LiteralPath $gp -PathType Leaf) { $new = Read-HordeHostTable -Path $gp }
    # APPEND-ONLY: the ref's lines must still open the file, in order. The cells are compared, so the
    # spacing around a "|" is not a change; any other edit, a removal or an insertion above them is.
    # One problem, at the first difference: every line after it has shifted and would repeat it.
    for ($i = 0; $i -lt $old.Count; $i++) {
        $was = $old[$i].cells -join " | "
        if ($i -ge $new.Count -or ($new[$i].cells -join " | ") -cne $was) {
            [void]$out.problems.Add([pscustomobject]@{ path = $rel; problem = ("the line '" + $was + "' is on " + $Ref + " and removed or changed here - growth.txt is append-only; add new lines at its end") })
            break
        }
    }
    for ($i = $old.Count; $i -lt $new.Count; $i++) {
        $r = $new[$i]
        $where = $rel + ":" + $r.line
        $bad = ""
        $p = ConvertTo-HordeAllowPath $r.cells[0]
        $from = -1; $to = -1; $d = [datetime]::MinValue
        if ($r.cells.Count -eq 4 -and $r.cells[1] -match '^(\d{1,9})\s*->\s*(\d{1,9})$') { $from = [int]$Matches[1]; $to = [int]$Matches[2] }
        if ($r.cells.Count -ne 4) { $bad = "a growth line is <path> | <old> -> <new> | <YYYY-MM-DD> | <why the list must grow>" }
        elseif ($from -lt 0) { $bad = "the counts for " + $p + " must read <old> -> <new>, two whole numbers" }
        elseif ($to -le $from) { $bad = "the line for " + $p + " records " + $from + " -> " + $to + ", which is not an increase - a decrease needs no record" }
        elseif (-not [datetime]::TryParseExact($r.cells[2], "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { $bad = "the date for " + $p + " must be a real date written YYYY-MM-DD" }
        elseif ((Get-HordeDistinctWordCount $r.cells[3]) -lt 4) { $bad = $p + " needs a reason of at least a sentence for its growth" }
        if ($bad) { [void]$out.problems.Add([pscustomobject]@{ path = $where; problem = $bad }); continue }
        # Not lower-cased: a PowerShell hashtable compares keys ignoring case already, and the mutation
        # that removed a ToLowerInvariant here survived because it changed nothing.
        $out.permits[$p + "|" + $from + "|" + $to] = $true
    }
    return $out
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
    # compared ignoring case, as the filesystem compares names: -contains ignores case by itself.
    param([string]$Rel)
    if (-not (Test-HordeUnderFolder -Rel $Rel -Folders @($script:HordeHostNamesProseFolder))) { return $false }
    return ($script:HordeHostNamesProseTypes -contains [System.IO.Path]::GetExtension($Rel))
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

    # Every port of every family, each held to its own lists. A port's folder is exempt for that port
    # only; another port's folder - of either family - is scanned like core.
    $hostDirs = New-Object System.Collections.ArrayList
    foreach ($fam in $script:HordePortFamilies) {
        $famDir = Join-Path $RepoRoot $fam
        if (Test-Path -LiteralPath $famDir -PathType Container) {
            foreach ($d in @(Get-ChildItem -LiteralPath $famDir -Directory)) { [void]$hostDirs.Add([pscustomobject]@{ own = ($fam + "/" + $d.Name); dir = $d }) }
        }
    }
    foreach ($port in $hostDirs) {
        $h = $port.dir
        $own = $port.own
        $hn = $own
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
                $p = ConvertTo-HordeAllowPath $r.cells[0]
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
