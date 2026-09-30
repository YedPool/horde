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
# is listed, with its reason and its exact number of lines, and the list may only get shorter.
#
# THE DATA IS THE HOST'S. Each host declares what identifies it in hosts/<name>/names.txt, and its
# exceptions in hosts/<name>/allowlist.txt. This file and its suite name no terminal at all, so the
# ratchet does not have to except itself, and a new host brings its own names without touching it.
#
#   names.txt, one per line:      <name> | <why it identifies this host>
#   allowlist.txt, one per line:  <path> | <lines> | <why this file may name the host>
#   Blank lines and lines beginning with # are ignored in both.
#
# WHAT COUNTS. A name is matched as a case-insensitive substring. A file's count is the number of its
# lines containing any of the host's names, plus one if its path does. An allowlisted count must be
# EXACT: more lines than listed is a new mention; fewer is an entry that allows more than is needed,
# and it must be lowered. That second half is what makes the list shrink-only.
#
# WHAT IS NOT SCANNED, by rule:
#   - hosts/<name>/ itself: the one place the host's name belongs.
#   - planning/: plans, ledgers and handoffs are prose records of the system being replaced and of
#     the migration away from it. They cannot be accurate without naming the terminal, and D12
#     governs the code and the contracts, not the history. Listing them would make every plan edit
#     an allowlist edit and protect nothing.
#   - .git/: not the repository's content.
# Other hosts' folders ARE scanned: hosts/vscode naming another terminal would be the same leak.

$script:HordeHostNamesExcluded = @("planning")
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
        [void]$out.Add([pscustomobject]@{ rel = $rel; full = $f.FullName })
    }
    return , $out
}

function Get-HordeNameLineCount {
    # How many lines of the file name any of the names, plus one if its path does. A line naming two
    # of them counts once. Every file is read as text: the repository holds no binary files, and a
    # binary one would be read as text too - a false mention can only make the check stricter.
    param([string]$Full, [string]$Rel, [string[]]$Names)
    $count = 0
    foreach ($nm in $Names) { if ($Rel.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $count = 1; break } }
    $text = [System.IO.File]::ReadAllText($Full)
    foreach ($ln in ($text -split "`n")) {
        foreach ($nm in $Names) {
            if ($ln.IndexOf($nm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $count++; break }
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

    $hostsDir = Join-Path $RepoRoot "hosts"
    if (-not (Test-Path -LiteralPath $hostsDir -PathType Container)) { return }
    foreach ($h in @(Get-ChildItem -LiteralPath $hostsDir -Directory)) {
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

        $skip = @($own) + $script:HordeHostNamesExcluded
        $allowed = @{}
        $allowPath = Join-Path $h.FullName "allowlist.txt"
        if (Test-Path -LiteralPath $allowPath -PathType Leaf) {
            foreach ($r in (Read-HordeHostTable -Path $allowPath)) {
                $where = $own + "/allowlist.txt:" + $r.line
                if ($r.cells.Count -ne 3) { Add-Finding $hn $where "an allowlist line is <path> | <lines> | <why this file may name the host>"; continue }
                $p = ($r.cells[0] -replace '\\', '/').TrimStart('/')
                $lines = 0
                if (-not [int]::TryParse($r.cells[1], [ref]$lines) -or $lines -lt 1) { Add-Finding $hn $where ("the line count for " + $p + " must be a whole number of at least 1"); continue }
                if ((Get-HordeDistinctWordCount $r.cells[2]) -lt 4) { Add-Finding $hn $where ($p + " needs a reason of at least a sentence"); continue }
                $key = $p.ToLowerInvariant()
                if ($allowed.ContainsKey($key)) { Add-Finding $hn $where ($p + " is listed twice"); continue }
                # AN ENTRY FOR A PATH THE SCAN NEVER READS allows nothing, and would sit there forever.
                if (Test-HordeUnderFolder -Rel $p -Folders $skip) { Add-Finding $hn $where ($p + " is excluded from the scan by rule, so the entry is not needed"); continue }
                $allowed[$key] = [pscustomobject]@{ path = $p; lines = $lines }
            }
        }

        $seen = @{}
        foreach ($f in (Get-HordeRepoFiles -RepoRoot $RepoRoot -Skip $skip)) {
            $c = Get-HordeNameLineCount -Full $f.full -Rel $f.rel -Names $names
            $key = $f.rel.ToLowerInvariant()
            $a = $allowed[$key]
            if ($a) { $seen[$key] = $c }
            if ($c -eq 0) { continue }
            if (-not $a) { Add-Finding $hn $f.rel ("names the host on " + $c + " line(s) and is not in " + $own + "/allowlist.txt"); continue }
            if ($c -gt $a.lines) { Add-Finding $hn $f.rel ("names the host on " + $c + " line(s); the allowlist allows " + $a.lines + " - a new mention") }
            elseif ($c -lt $a.lines) { Add-Finding $hn $f.rel ("names the host on only " + $c + " line(s); the allowlist allows " + $a.lines + " - lower it to " + $c) }
        }
        # LISTED, BUT NAMING THE HOST NOWHERE, OR NOT THERE AT ALL: the entry allows what nothing needs.
        foreach ($k in @($allowed.Keys)) {
            if (-not $seen.ContainsKey($k)) { Add-Finding $hn $allowed[$k].path ("is listed in " + $own + "/allowlist.txt but does not exist - remove the entry") }
            elseif ($seen[$k] -eq 0) { Add-Finding $hn $allowed[$k].path ("no longer names the host - remove its entry from " + $own + "/allowlist.txt") }
        }
    }
    return $found
}
