# HostNames.ps1 - the ratchet for decision D12: nothing outside a port's own folder names that port.
#
# Development tooling, not part of the engine. It answers one question: does any file outside a
# port's own folder name that port - a terminal in hosts/<name>/, an agent harness in agents/<name>/,
# a transport in transports/<name>/ - where the port's allowlist does not say it may?
#
# THREE FAMILIES OF PORT, ONE RULE. (The third, transports/, came with remote plan step R5; see
# $script:HordePortFamilies.) D12 was written for terminals. The engine-settings design of
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
#                             or: <name> | <kind> | <why it identifies this host>
#   allowlist.txt, one per line:  <path> | <mentions> | <why this file may name the host>
#                             or: <path> | import | <why> (THE ONE CROSS-HOST IMPORT, below)
#   growth.txt, one per line:     <path> | <old> -> <new> | <YYYY-MM-DD> | <why the list must grow>
#   Blank lines and lines beginning with # are ignored in all three.
#
# KINDS OF NAME. A name line may say what kind of knowledge the name is, from a closed list: name (the
# default, and what a two-part line is), processImage, or path. The lifecycle plan
# (planning/execution-plan-lifecycle.md, step 5 and section 2.6) brings engine knowledge core must
# never hold - each harness's process images, and the path fragments of its transcripts, rollouts,
# control files and task output - and declares it here, in the harness's own names.txt, so this scan
# catches it anywhere else. Every kind is a name to the scan and counts as a mention like any other.
# The kind is what lets a later rule ask for one kind alone: core matches no processImage at all
# (Test-HordeProcessImages). A kind outside the list is refused, matched exactly, never guessed at.
#
# CORE MATCHES NO PROCESS IMAGE (Test-HordeProcessImages). The lifecycle plan, section 2.6: core
# matches no image name; the orphan classes are defined by structure, and which processes are a
# harness's is its adapter's to answer. The ratchet cannot hold that alone - a file its allowlist
# covers may name the harness any way it likes, an image included - so a processImage has a rule of
# its own, with no allowlist and no growth record: outside every port's folder and outside test/, no
# file may match one, by its text or its path. test/ is exempt because tests of the old readers carry
# process tables as data (on 2026-10-02 one projection fixture held 13 image mentions and the identity
# suite 34). The rule was measured against main at c3938b8, where three legacy readers of Phases 0 to 2
# already matched an image. They are listed in tools/process-image-legacy.txt, each with its EXACT
# number of matches (review of PR #57, A1 and A3): a file that gains a match is refused, one with
# fewer than listed must lower its count, and one with none must leave. Against origin/main a new
# entry or a raised count is refused outright - there is no growth record for this list, which exists
# only to shrink to nothing as engines A4 moves those reads behind the AgentPort. A name whose kind is
# processImage on origin/main may not become another kind (A2), which would take it out of this rule.
# WHAT IS MATCHED: each image as written and as an escaped regular expression ("x\.exe", A4).
# WHAT A TEXT SCAN CANNOT SEE, so a pass is not read as more: an image built from pieces ('x' + '.exe',
# "$name.exe"), a looser pattern ("x.\.exe", "x.*"), and the harness's process name without its
# extension, which is the harness's name and so the ratchet's to count, not this rule's (A4, A5).
#
# THE ONE CROSS-HOST IMPORT (hosts plan step 5; hosts decision 3 of 2026-09-30). Two multiplexers
# share one command language, which lives in the first one's folder as Dialect.ps1; the second
# imports it rather than copying it. Other ports' folders are scanned, so without a rule of its own
# every importing file would be a leak. An allowlist entry whose count is the word import lets a file
# in ANOTHER port's folder OF THE SAME FAMILY name this port exactly once, and only in a line that
# dot-sources this port's Dialect.ps1; the port must have that file. The dialect hands out what an
# importer would otherwise spell - its environment variables, which contain the host's name and so
# collide with the substring match - as data (Get-HordeMuxDialectEnvNames), so nothing else in the
# importer needs to name the host. Inside another port's folder an import is the ONLY way in: a
# numbered entry there is refused, except for that port's own list files (names.txt, allowlist.txt,
# growth.txt), which name other ports' files by path (8 such entries on 2026-10-02). For the
# origin/main comparison an import entry counts 1, so adding one is growth like any other entry.
#
# WHAT COUNTS. A name is matched as a case-insensitive substring. A file's count is the number of
# MENTIONS - every occurrence of every one of the host's names in its text - plus one if its path
# names the host. Mentions, not lines: a second mention added to a line that already had one is a new
# mention (review of PR 21). An allowlisted count must be EXACT: more mentions than listed is a new
# mention; fewer is an entry that allows more than is needed, and it must be lowered.
# ONE PLACE IN THE TEXT, ONE MENTION. Where two declared names overlap - an image named after its
# harness holds the harness's name - the longer one is counted and the shorter is not counted again
# inside it. Counted once per name, declaring a harness's image that holds its name (lifecycle step 5)
# would have raised the count of every file that already names that image, with no new mention.
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
# THE ONE EXCEPTION IS A PINNED FILE (decisions design 2026-10-06, section 3.11; core/Fingerprints.ps1).
# An adapter that cannot be written without a program library commits it in its own folder beside a
# fingerprints.txt, one line per file with its SHA-256. A file such a list names is not read as text
# - it is not Horde's text, and nobody can change a byte of it without changing its line - and the scan
# instead fails when a listed file is missing or no longer has its fingerprint. Only inside a port's
# folder: a list anywhere else pins nothing and is a finding, and a binary no list names is refused as
# any other non-ASCII file is.
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

# The one reader of a fingerprint list, shared with the adapters that load pinned files.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "core\Fingerprints.ps1")

$script:HordeHostNamesProseFolder = "planning"
# The families of port, each a top-level folder holding one folder per port. A third family is a line
# here, not a copy of the scan. Order is only the order findings are reported in.
# THE THIRD FAMILY (remote plan step R5; the remote design's founder decision 10): nothing outside
# transports/<name>/ names a transport program or its options, so the second transport is a new folder
# and not an engine change. transports/Port.ps1, beside the transport folders, belongs to no transport
# and is scanned like core.
# THE FOURTH FAMILY (remote plan step R21, slice 3): nothing outside messengers/<name>/ names what
# identifies a messenger, so a second way of handing a message to a session is a new folder too.
# messengers/Port.ps1 belongs to no messenger, like transports/Port.ps1.
# THE FIFTH FAMILY (decisions design 2026-10-06, decision 2): nothing outside surfaces/<name>/ names
# what shows a page in a window, so a second way of showing one - another platform's window, a file,
# a remote view - is a new folder too. surfaces/Port.ps1 belongs to no surface.
$script:HordePortFamilies = @("hosts", "agents", "transports", "messengers", "surfaces")
$script:HordeHostNamesProseTypes = @(".md", ".html")
$script:HordeHostNameMinLength = 4
# The cross-host import (header, THE ONE CROSS-HOST IMPORT): the count cell that marks it, matched
# exactly, the one file it may dot-source, and the list files of a port that may name other ports.
$script:HordeImportCount = "import"
$script:HordeDialectFile = "Dialect.ps1"
$script:HordePortListFiles = @("names.txt", "allowlist.txt", "growth.txt")
# The closed list of kinds a name line may give (header, KINDS OF NAME). Matched exactly.
$script:HordePortNameKinds = @("name", "processImage", "path")
# The image rule's exemptions (header, CORE MATCHES NO PROCESS IMAGE). Folders skipped besides every
# port's own; and the file listing the legacy readers measured at c3938b8, which may still match an
# image, each exactly as often as listed, until their reads move behind the AgentPort. Neither may grow.
$script:HordeProcessImageExempt = @("test")
$script:HordeProcessImageLegacyFile = "tools/process-image-legacy.txt"

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
    # Two parts, or three with a kind: a kind line on origin/main is a name like any other, so deleting
    # one here is a removal the shrink check must see.
    foreach ($r in (Split-HordeHostTable -Text $Text)) { if ($r.cells.Count -eq 2 -or $r.cells.Count -eq 3) { $set[$r.cells[0].ToLowerInvariant()] = $r.cells[0] } }
    return $set
}

function Get-HordeHostNameKinds {
    # name (lower-cased) -> kind, from a names.txt text's well-formed lines: two parts is a name of kind
    # name, three gives its kind. The shrink check uses it to refuse a processImage demoted (header).
    param([string]$Text)
    $kinds = @{}
    foreach ($r in (Split-HordeHostTable -Text $Text)) {
        if ($r.cells.Count -eq 2) { $kinds[$r.cells[0].ToLowerInvariant()] = "name" }
        elseif ($r.cells.Count -eq 3) { $kinds[$r.cells[0].ToLowerInvariant()] = $r.cells[1] }
    }
    return $kinds
}

function ConvertTo-HordePortName {
    # One names.txt row as { name; kind; why; problem }. problem is empty for a usable name, and
    # otherwise says what is wrong, in the words the suite looks for. A two-part row is a name of kind
    # name; a three-part row gives its kind in the middle.
    param($Row)
    $out = [pscustomobject]@{ name = ""; kind = "name"; why = ""; problem = "" }
    if ($Row.cells.Count -eq 2) { $out.name = $Row.cells[0]; $out.why = $Row.cells[1] }
    elseif ($Row.cells.Count -eq 3) { $out.name = $Row.cells[0]; $out.kind = $Row.cells[1]; $out.why = $Row.cells[2] }
    else { $out.problem = "a name line is <name> | <why it identifies this host>, or <name> | <kind> | <why>"; return $out }
    # A SHORT NAME MATCHES EVERYWHERE, and a ratchet that fires on every file gets allowlisted
    # into meaning nothing.
    if ($out.name.Length -lt $script:HordeHostNameMinLength) { $out.problem = "the name '" + $out.name + "' is shorter than " + $script:HordeHostNameMinLength + " characters and would match almost anything"; return $out }
    # -cnotcontains: a miscased kind is refused, not read as the kind it resembles.
    if ($script:HordePortNameKinds -cnotcontains $out.kind) { $out.problem = "the kind '" + $out.kind + "' of the name '" + $out.name + "' is not one of " + ($script:HordePortNameKinds -join ", "); return $out }
    if ((Get-HordeDistinctWordCount $out.why) -lt 4) { $out.problem = "the name '" + $out.name + "' needs a reason of at least a sentence" }
    return $out
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
        # An import entry allows one mention, so it is compared as a count of 1 (header).
        if ($r.cells[1] -ceq $script:HordeImportCount) { $c = 1 }
        elseif (-not [int]::TryParse($r.cells[1], [ref]$c)) { continue }
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
        # A PROCESS IMAGE STAYS ONE (review of PR #57, A2): demoted to a path or a name it would leave
        # the image rule while the shrink check, keyed by name alone, saw nothing removed.
        if (Test-Path -LiteralPath $np -PathType Leaf) {
            $oldKinds = Get-HordeHostNameKinds -Text ((@(& git -C $RepoRoot show ($Ref + ":" + $own + "/names.txt"))) -join "`n")
            $newKinds = Get-HordeHostNameKinds -Text ([System.IO.File]::ReadAllText($np))
            foreach ($k in @($oldKinds.Keys | Sort-Object)) {
                if ($oldKinds[$k] -ceq "processImage" -and $newKinds.ContainsKey($k) -and $newKinds[$k] -cne "processImage") {
                    Add-Finding $hn ($own + "/names.txt") ("the name '" + $oldNames[$k] + "' is a processImage on origin/main and a " + $newKinds[$k] + " here - a process image may not be demoted, which would take it out of the image rule")
                }
            }
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
    # THE LEGACY IMAGE LIST ONLY SHRINKS (review of PR #57, A1): against the ref, no new entry and no
    # higher count, and no growth record admits either. A list the ref does not have is new on this
    # branch: reported, not compared, as a new port is.
    $lf = $script:HordeProcessImageLegacyFile
    $lp = Join-Path $RepoRoot $lf
    if (Test-Path -LiteralPath $lp -PathType Leaf) {
        # ls-tree prints nothing for a missing path and exits 0, so no stderr needs redirecting.
        if (@(& git -C $RepoRoot ls-tree --name-only $Ref -- $lf).Count -eq 0) { [void]$out.newHosts.Add($lf) }
        else {
            $oldLegacy = (Read-HordeImageLegacy -Text ((@(& git -C $RepoRoot show ($Ref + ":" + $lf))) -join "`n")).entries
            $newLegacy = (Read-HordeImageLegacy -Text ([System.IO.File]::ReadAllText($lp))).entries
            foreach ($k in @($newLegacy.Keys | Sort-Object)) {
                $e = $newLegacy[$k]
                if (-not $oldLegacy.ContainsKey($k)) { Add-Finding "(repository)" $e.path ("is in " + $lf + " but not on " + $Ref + " - the legacy list only shrinks, and no growth line admits an entry") }
                elseif ($e.count -gt $oldLegacy[$k].count) { Add-Finding "(repository)" $e.path ("is allowed " + $e.count + " process image match(es) here and " + $oldLegacy[$k].count + " on " + $Ref + " - a legacy count may not rise") }
            }
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

function Get-HordePortFolderOf {
    # The port folder ("hosts/<name>" or "agents/<name>") a forward-slash relative path lies in, or ""
    # when it lies in none.
    param([string]$Rel)
    foreach ($fam in $script:HordePortFamilies) {
        if ($Rel -match ('^(' + [regex]::Escape($fam) + '/[^/]+)/')) { return $Matches[1] }
    }
    return ""
}

function Test-HordePortListFile {
    # Is the path one of a port's own list files - names.txt, allowlist.txt or growth.txt directly in
    # its folder? Those name other ports' files by path, and a numbered entry for one stays allowed.
    param([string]$Rel)
    $port = Get-HordePortFolderOf -Rel $Rel
    if (-not $port) { return $false }
    $rest = $Rel.Substring($port.Length + 1)
    return ($script:HordePortListFiles -contains $rest)
}

function Test-HordeDialectImport {
    # Does the file have a line that dot-sources <Folder>/Dialect.ps1 and holds a mention of the port?
    # The caller has already seen the file name the port exactly once, so the one mention is that line.
    # THE WHOLE LINE IS THE IMPORT (review of PR #58, B1 and B2): "." and a space, then the dialect's
    # path as the one thing dot-sourced - a quoted path, or (Join-Path <variable> <quoted path>) - and
    # nothing after it but an optional comment. The path ends at Dialect.ps1, so a longer file name is
    # another file; and a path handed to a loader, or passed as an argument to another dot-sourced
    # file, is refused, because the loader could open any file of the host. A comment, an & call or a
    # string that merely names the file is not an import either.
    param([string]$Full, [string]$Folder, [string[]]$Names)
    $quoted = '(?:"(?<p>[^"]*)"|''(?<p>[^'']*)'')'
    $line = '^\s*\.\s+(?:' + $quoted + '|\(\s*Join-Path\s+\$[A-Za-z_][A-Za-z0-9_:]*\s+' + $quoted + '\s*\))\s*(?:#.*)?$'
    $path = '(?:^|[\\/])' + [regex]::Escape($Folder) + '[\\/]' + [regex]::Escape($script:HordeDialectFile) + '$'
    $ic = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    foreach ($text in ([System.IO.File]::ReadAllText($Full) -split "`n")) {
        $m = [regex]::Match($text.TrimEnd("`r"), $line, $ic)
        if (-not $m.Success) { continue }
        if (-not [regex]::IsMatch($m.Groups["p"].Value, $path, $ic)) { continue }
        if ((Get-HordeMentionSpans -Text $text -Names $Names).Count -ge 1) { return $true }
    }
    return $false
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
    $listing = @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force)
    # PINNED FILES ARE NOT TEXT (header, THE ONE EXCEPTION). Whatever a fingerprint list inside a port's
    # folder names, in that list's own folder, is left out of every text scan; Test-HordePinnedFiles
    # holds each to its fingerprint instead.
    $pinned = @{}
    foreach ($f in $listing) {
        if ($f.Name -cne (Get-HordeFingerprintListName)) { continue }
        $listRel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
        if (-not (Get-HordePortFolderOf -Rel $listRel)) { continue }
        foreach ($e in (Read-HordeFingerprintList -Path $f.FullName).entries) { $pinned[(Join-Path $f.DirectoryName $e.name).ToLowerInvariant()] = $true }
    }
    foreach ($f in $listing) {
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
        # .git IS A FILE IN A WORKTREE, holding the path of the main repository, and that path can
        # name anything: the worktree this ratchet was written in had the terminal's name in its
        # folder name, and the first count reported .git as a mention. Skipped as a file as well.
        if ($rel -eq ".git" -or (Test-HordeUnderFolder -Rel $rel -Folders (@(".git") + $Skip))) { continue }
        if (Test-HordePlanningProse -Rel $rel) { continue }
        if ($pinned.ContainsKey($f.FullName.ToLowerInvariant())) { continue }
        [void]$out.Add([pscustomobject]@{ rel = $rel; full = $f.FullName })
    }
    return , $out
}

function Test-HordePinnedFiles {
    # Every fingerprint list in the tree, held to its files (header, THE ONE EXCEPTION): one object per
    # problem, { host; path; problem }, unrolled, so wrap the call in @(). A list outside a port's folder
    # is a finding and pins nothing; inside one, a malformed line, a listed file that is missing and a
    # file that no longer has its fingerprint are each a finding.
    param([string]$RepoRoot)
    $found = New-Object System.Collections.ArrayList
    $rootFull = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    foreach ($f in @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force | Where-Object { $_.Name -ceq (Get-HordeFingerprintListName) })) {
        $rel = $f.FullName.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
        if (Test-HordeUnderFolder -Rel $rel -Folders @(".git")) { continue }
        if (-not (Get-HordePortFolderOf -Rel $rel)) {
            [void]$found.Add([pscustomobject]@{ host = "(repository)"; path = $rel; problem = "is a fingerprint list outside a port's folder, where it pins nothing - only an adapter, in its own folder, brings in a file that is not Horde's text" })
            continue
        }
        foreach ($x in (Test-HordeFingerprints -Folder $f.DirectoryName).findings) {
            [void]$found.Add([pscustomobject]@{ host = "(repository)"; path = $rel; problem = ("pinned file: " + $x) })
        }
    }
    return $found
}

function Get-HordeNameMentionCount {
    # How many times the file names the host: every place in its text where one of its names occurs,
    # plus one if its path names the host. Occurrences, not lines - the review of PR 21 appended a
    # second mention to a line that already had one, and a count of lines did not move. Occurrences of
    # one name do not overlap ("aa" is in "aaa" once), and where two names overlap the longer is
    # counted once (header, ONE PLACE IN THE TEXT, ONE MENTION).
    # Every file is read as text. Any file that is not printable ASCII is refused on its own by
    # Test-HordeHostNames, so the text read here is the bytes on disk, one character each.
    param([string]$Full, [string]$Rel, [string[]]$Names)
    $count = 0
    foreach ($nm in $Names) { if ($Rel.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $count = 1; break } }
    $text = [System.IO.File]::ReadAllText($Full)
    return ($count + (Get-HordeMentionSpans -Text $text -Names $Names).Count)
}

function Get-HordeMentionSpans {
    # The places in the text the names occupy, as { start; end; name }, none overlapping another.
    # Every occurrence of every name is found first; then, from the start of the text, each place is
    # taken unless it begins inside one already taken, and at one starting point the longest name is
    # taken. So an image named after its harness is one place, not the image and the name inside it.
    param([string]$Text, [string[]]$Names)
    $all = New-Object System.Collections.ArrayList
    foreach ($nm in $Names) {
        $at = $Text.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase)
        while ($at -ge 0) {
            [void]$all.Add([pscustomobject]@{ start = $at; end = $at + $nm.Length; name = $nm })
            $at = $Text.IndexOf($nm, $at + $nm.Length, [System.StringComparison]::OrdinalIgnoreCase)
        }
    }
    $kept = New-Object System.Collections.ArrayList
    $taken = 0
    foreach ($s in @($all | Sort-Object -Property @{ Expression = { $_.start }; Ascending = $true }, @{ Expression = { $_.end }; Descending = $true })) {
        if ($s.start -lt $taken) { continue }
        [void]$kept.Add($s)
        $taken = $s.end
    }
    return , $kept
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
    # THE FILES LEFT OUT OF THAT SCAN ARE HELD TO THEIR FINGERPRINTS instead (header, THE ONE EXCEPTION).
    foreach ($x in @(Test-HordePinnedFiles -RepoRoot $RepoRoot)) { Add-Finding $x.host $x.path $x.problem }

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
        $fam = $own.Split("/")[0]
        $hn = $own
        $namesPath = Join-Path $h.FullName "names.txt"
        # A HOST THAT DECLARES NO NAMES CANNOT BE POLICED, so it is a finding, not a pass.
        if (-not (Test-Path -LiteralPath $namesPath -PathType Leaf)) {
            Add-Finding $hn $own "declares no names.txt, so nothing can check that it stays in its folder"; continue
        }
        $names = New-Object System.Collections.ArrayList
        foreach ($r in (Read-HordeHostTable -Path $namesPath)) {
            $where = $own + "/names.txt:" + $r.line
            $pn = ConvertTo-HordePortName $r
            if ($pn.problem) { Add-Finding $hn $where $pn.problem; continue }
            [void]$names.Add($pn.name)
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
                $isImport = ($r.cells[1] -ceq $script:HordeImportCount)
                $allowCount = 1
                if (-not $isImport -and (-not [int]::TryParse($r.cells[1], [ref]$allowCount) -or $allowCount -lt 1)) { Add-Finding $hn $where ("the mention count for " + $p + " must be a whole number of at least 1, or the word " + $script:HordeImportCount); continue }
                if ((Get-HordeDistinctWordCount $r.cells[2]) -lt 4) { Add-Finding $hn $where ($p + " needs a reason of at least a sentence"); continue }
                $key = $p.ToLowerInvariant()
                if ($allowed.ContainsKey($key)) { Add-Finding $hn $where ($p + " is listed twice"); continue }
                # AN ENTRY FOR A PATH THE SCAN NEVER READS allows nothing, and would sit there forever.
                if ((Test-HordeUnderFolder -Rel $p -Folders $skip) -or (Test-HordePlanningProse -Rel $p)) { Add-Finding $hn $where ($p + " is excluded from the scan by rule, so the entry is not needed"); continue }
                # THE ONE CROSS-HOST IMPORT (header): only from another port of this family, only of a
                # Dialect.ps1 that exists; and inside another port's folder, the only way in.
                $otherPort = Get-HordePortFolderOf -Rel $p
                if ($isImport) {
                    if (-not $otherPort -or -not $otherPort.StartsWith($fam + "/")) { Add-Finding $hn $where ($p + " is not in another " + $fam + " port's folder - only another " + $fam + " port imports this port's " + $script:HordeDialectFile); continue }
                    if (-not (Test-Path -LiteralPath (Join-Path $h.FullName $script:HordeDialectFile) -PathType Leaf)) { Add-Finding $hn $where ($own + "/" + $script:HordeDialectFile + " does not exist, so " + $p + " has nothing to import"); continue }
                } elseif ($otherPort -and -not (Test-HordePortListFile -Rel $p)) {
                    Add-Finding $hn $where ($p + " is in another port's folder, which may name this port only through an import of its " + $script:HordeDialectFile + ": " + $p + " | " + $script:HordeImportCount + " | <why>"); continue
                }
                $allowed[$key] = [pscustomobject]@{ path = $p; count = $allowCount; import = $isImport }
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
            elseif ($a.import -and -not (Test-HordeDialectImport -Full $f.full -Folder $h.Name -Names $names)) { Add-Finding $hn $f.rel ("names the host once, but not in a line that dot-sources " + $own + "/" + $script:HordeDialectFile + " - an import entry allows that line and nothing else") }
        }
        # LISTED, BUT NAMING THE HOST NOWHERE, OR NOT THERE AT ALL: the entry allows what nothing needs.
        foreach ($k in @($allowed.Keys)) {
            if (-not $seen.ContainsKey($k)) { Add-Finding $hn $allowed[$k].path ("is listed in " + $own + "/allowlist.txt but does not exist - remove the entry") }
            elseif ($seen[$k] -eq 0) { Add-Finding $hn $allowed[$k].path ("no longer names the host - remove its entry from " + $own + "/allowlist.txt") }
        }
    }
    return $found
}

function Get-HordePortFolders {
    # Every port's folder that exists, as "<family>/<name>", forward slashes. Returned UNROLLED, so a
    # caller writes @(Get-HordePortFolders): a list returned as one object and wrapped in @() is one
    # element, and the image rule then skipped no port at all (measured on this step's first try).
    param([string]$RepoRoot)
    $out = New-Object System.Collections.ArrayList
    foreach ($fam in $script:HordePortFamilies) {
        $famDir = Join-Path $RepoRoot $fam
        if (Test-Path -LiteralPath $famDir -PathType Container) { foreach ($d in @(Get-ChildItem -LiteralPath $famDir -Directory)) { [void]$out.Add($fam + "/" + $d.Name) } }
    }
    return @($out)
}

function Get-HordePortNamesOfKind {
    # Every usable name of one kind that any port declares, as { own; name }, own being the port's
    # folder ("agents/<name>"). A malformed line is Test-HordeHostNames's to report, not this one's.
    param([string]$RepoRoot, [string]$Kind)
    $out = New-Object System.Collections.ArrayList
    foreach ($fam in $script:HordePortFamilies) {
        $famDir = Join-Path $RepoRoot $fam
        if (-not (Test-Path -LiteralPath $famDir -PathType Container)) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $famDir -Directory)) {
            $np = Join-Path $d.FullName "names.txt"
            if (-not (Test-Path -LiteralPath $np -PathType Leaf)) { continue }
            foreach ($r in (Read-HordeHostTable -Path $np)) {
                $pn = ConvertTo-HordePortName $r
                if (-not $pn.problem -and $pn.kind -ceq $Kind) { [void]$out.Add([pscustomobject]@{ own = ($fam + "/" + $d.Name); name = $pn.name }) }
            }
        }
    }
    return , $out
}

function Read-HordeImageLegacy {
    # tools/process-image-legacy.txt as { entries; problems }: entries maps a path (forward slashes,
    # lower-cased) to { path; count }; problems lists { line; problem } for a line that is malformed,
    # whose count is not a whole number of at least 1, whose reason is not a sentence, or that repeats
    # a path. A refused line excuses nothing.
    param([string]$Text)
    $out = [pscustomobject]@{ entries = @{}; problems = (New-Object System.Collections.ArrayList) }
    foreach ($r in (Split-HordeHostTable -Text $Text)) {
        $bad = ""
        $c = 0
        if ($r.cells.Count -ne 3) { $bad = "a legacy line is <path> | <process image matches> | <why this old reader may still match one>" }
        elseif (-not [int]::TryParse($r.cells[1], [ref]$c) -or $c -lt 1) { $bad = "the match count for " + $r.cells[0] + " must be a whole number of at least 1" }
        elseif ((Get-HordeDistinctWordCount $r.cells[2]) -lt 4) { $bad = $r.cells[0] + " needs a reason of at least a sentence" }
        else {
            $p = ConvertTo-HordeAllowPath $r.cells[0]
            $key = $p.ToLowerInvariant()
            if ($out.entries.ContainsKey($key)) { $bad = $p + " is listed twice" }
            else { $out.entries[$key] = [pscustomobject]@{ path = $p; count = $c } }
        }
        if ($bad) { [void]$out.problems.Add([pscustomobject]@{ line = $r.line; problem = $bad }) }
    }
    return $out
}

function Get-HordeImageMatches {
    # How many times a file matches the declared process images, and which: every occurrence of each
    # image in its text, as written and as an escaped regular expression (header, WHAT IS MATCHED),
    # plus one if its path names one. Returns { count; images }.
    param([string]$Text, [string]$Rel, $Images)
    $count = 0
    $hit = New-Object System.Collections.ArrayList
    foreach ($img in $Images) {
        $n = 0
        foreach ($form in @(@($img.name, [regex]::Escape($img.name)) | Select-Object -Unique)) {
            if ($Rel.IndexOf($form, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $n++ }
            $at = $Text.IndexOf($form, [System.StringComparison]::OrdinalIgnoreCase)
            while ($at -ge 0) {
                $n++
                $at = $Text.IndexOf($form, $at + $form.Length, [System.StringComparison]::OrdinalIgnoreCase)
            }
        }
        if ($n -gt 0) { $count += $n; [void]$hit.Add($img) }
    }
    return [pscustomobject]@{ count = $count; images = $hit }
}

function Test-HordeProcessImages {
    # Does any file outside every port's folder and outside test/ match a process image a port
    # declares, beyond the exact counts tools/process-image-legacy.txt lists? Returns one object per
    # problem, { host; path; problem }, unrolled as Test-HordeHostNames's are, so wrap the call in @().
    # The header says why the rule exists and why it has no allowlist.
    param([string]$RepoRoot)
    $found = New-Object System.Collections.ArrayList
    $images = Get-HordePortNamesOfKind -RepoRoot $RepoRoot -Kind "processImage"
    $lf = $script:HordeProcessImageLegacyFile
    $legacy = @{}
    $lp = Join-Path $RepoRoot $lf
    if (Test-Path -LiteralPath $lp -PathType Leaf) {
        $read = Read-HordeImageLegacy -Text ([System.IO.File]::ReadAllText($lp))
        $legacy = $read.entries
        foreach ($x in $read.problems) { [void]$found.Add([pscustomobject]@{ host = "(repository)"; path = ($lf + ":" + $x.line); problem = $x.problem }) }
    }
    $matched = @{}
    # PORT FOLDERS, NOT FAMILIES (step R5): a file directly under a family folder - transports/Port.ps1
    # - belongs to no port, so it is held to this rule like core.
    foreach ($f in (Get-HordeRepoFiles -RepoRoot $RepoRoot -Skip (@(Get-HordePortFolders -RepoRoot $RepoRoot) + @($script:HordeProcessImageExempt)))) {
        $m = Get-HordeImageMatches -Text ([System.IO.File]::ReadAllText($f.full)) -Rel $f.rel -Images $images
        if ($m.count -eq 0) { continue }
        $key = $f.rel.ToLowerInvariant()
        if ($legacy.ContainsKey($key)) {
            $matched[$key] = $m.count
            $allowedCount = $legacy[$key].count
            if ($m.count -gt $allowedCount) { [void]$found.Add([pscustomobject]@{ host = "(repository)"; path = $f.rel; problem = ("has " + $m.count + " process image match(es); " + $lf + " allows " + $allowedCount + " - a new match") }) }
            elseif ($m.count -lt $allowedCount) { [void]$found.Add([pscustomobject]@{ host = "(repository)"; path = $f.rel; problem = ("has only " + $m.count + " process image match(es); " + $lf + " allows " + $allowedCount + " - lower it to " + $m.count) }) }
            continue
        }
        $what = @($m.images | ForEach-Object { "'" + $_.name + "' of " + $_.own }) -join ", "
        [void]$found.Add([pscustomobject]@{ host = $m.images[0].own; path = $f.rel; problem = ("matches the process image " + $what + " - core matches no image name (lifecycle plan section 2.6): which processes are a harness's is its adapter's to answer, and no allowlist admits an image") })
    }
    # THE LEGACY LIST ONLY SHRINKS: an entry that excuses nothing is removed, so a later file at that
    # path cannot inherit an excuse it was never measured for.
    foreach ($k in @($legacy.Keys | Sort-Object)) {
        if (-not $matched.ContainsKey($k)) {
            [void]$found.Add([pscustomobject]@{ host = "(repository)"; path = $legacy[$k].path; problem = ("is listed in " + $lf + " but matches no process image - remove it from the list, which only shrinks") })
        }
    }
    return $found
}
