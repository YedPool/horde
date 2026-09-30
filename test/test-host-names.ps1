# DOES ANY FILE OUTSIDE A HOST'S FOLDER NAME THAT HOST? (decision D12)
#
# tools/HostNames.ps1 reads each host's hosts/<name>/names.txt and allowlist.txt and scans every other
# file. This suite first proves the scan refuses what it must, on throwaway repositories whose one
# host is invented - "zorbterm" - so that nothing in this file names a real terminal and the ratchet
# never has to except itself. Then it runs the scan on this repository.
#
# EXACTLY ONE FINDING per refusal, not merely the right one among several, as in test/test-ledger.ps1:
# a case failing for three reasons at once would otherwise pass for the wrong one.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "tools\HostNames.ps1")

$fake = Join-Path $env:TEMP ("horde-hostnames-" + [guid]::NewGuid().ToString("N").Substring(0, 8))

function Says { param($F, [string]$Text) return (@($F | Where-Object { $_.problem -like "*$Text*" }).Count -gt 0) }
function Show { param($F) foreach ($x in @($F)) { Write-Host ("         got: " + $x.host + " " + $x.path + " - " + $x.problem) -ForegroundColor Red } }

function Write-FakeFile {
    param([string]$Rel, [string]$Text)
    $p = Join-Path $script:repo $Rel
    New-Item -ItemType Directory -Force (Split-Path -Parent $p) | Out-Null
    [System.IO.File]::WriteAllText($p, $Text)
}

function New-FakeRepo {
    # A repository with one host, zorbterm, which is named in its own folder and in one allowlisted
    # file, on exactly two lines. Every case starts from it and changes one thing.
    param([string]$Name)
    $script:repo = Join-Path $fake $Name
    Write-FakeFile "hosts/zorbterm/names.txt" ("# what identifies the invented host`n" +
        "zorbterm | the invented terminal this suite polices in place of a real one`n" +
        "zorb-sock | the invented terminal's socket file name, which does not contain its name`n")
    Write-FakeFile "hosts/zorbterm/allowlist.txt" ("# exceptions`n" +
        "docs/rules.md | 2 | the rules describe how tests isolate the invented terminal`n")
    Write-FakeFile "hosts/zorbterm/adapter.ps1" "# the Zorbterm adapter, which may name its own host as often as it likes`n"
    Write-FakeFile "docs/rules.md" "Run tests in a separate Zorbterm.`nNever aim at the zorb-sock you work in.`nNothing else here.`n"
    Write-FakeFile "core/engine.ps1" "# sessions, slots and capabilities`n"
    return $script:repo
}

function Scan {
    param([string]$Name, [scriptblock]$Change)
    $r = New-FakeRepo $Name
    & $Change
    return @(Test-HordeHostNames -RepoRoot $r)
}

function Refuses {
    param([string]$Name, [scriptblock]$Change, [string]$Text, [string]$What)
    $f = @(Scan $Name $Change)
    $ok = ((Says $f $Text) -and $f.Count -eq 1)
    Check $ok $What
    if (-not $ok) { Show $f }
}

function Passes {
    param([string]$Name, [scriptblock]$Change, [string]$What)
    $f = @(Scan $Name $Change)
    Check ($f.Count -eq 0) $What
    if ($f.Count -gt 0) { Show $f }
}

try {
    Write-Host ""
    Write-Host "--- CONTROL: a repository that keeps its host in its folder passes ---" -ForegroundColor Cyan

    # The host's own adapter names it, and so does the allowlisted file, exactly as often as listed.
    Passes "clean" { } "a host named only in its own folder and in its allowlisted file, as often as listed, passes"

    Write-Host ""
    Write-Host "--- a new mention outside the host's folder is refused ---" -ForegroundColor Cyan

    Refuses "leak" { Write-FakeFile "core/leak.ps1" "function Start-ZORBTERM { }`n" } "is not in hosts/zorbterm/allowlist.txt" "a new file in core that names the host is refused, whatever its case"
    Refuses "leak-second-name" { Write-FakeFile "core/sock.ps1" "`$s = 'zorb-sock-12'`n" } "is not in hosts/zorbterm/allowlist.txt" "every name the host declares is checked, not only the first"
    Refuses "leak-path" { Write-FakeFile "test/fixtures/host-zorbterm.json" "{}`n" } "is not in hosts/zorbterm/allowlist.txt" "a file whose PATH names the host is refused, though its content does not"
    Refuses "leak-other-host" {
        Write-FakeFile "hosts/other/names.txt" "otherterm | a second invented terminal, so that one host can be caught naming another`n"
        Write-FakeFile "hosts/other/adapter.ps1" "# borrowed from zorbterm`n"
    } "hosts/zorbterm/allowlist.txt" "another host's folder naming this host is refused - only the host's own folder is exempt"
    Refuses "grown" { Write-FakeFile "docs/rules.md" "Run tests in a separate Zorbterm.`nNever aim at the zorb-sock you work in.`nZorbterm again.`n" } "a new mention" "an allowlisted file that gains a mention is refused"

    Write-Host ""
    Write-Host "--- the allowlist can only shrink ---" -ForegroundColor Cyan

    Refuses "shrunk" { Write-FakeFile "docs/rules.md" "Run tests in a separate Zorbterm.`nNothing else here.`n" } "lower it to 1" "an entry allowing more lines than the file needs is refused, and says what to lower it to"
    Refuses "clean-entry" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/allowlist.txt") -Value "core/engine.ps1 | 1 | an entry nobody needs, for a file that names nothing" } "no longer names the host" "an entry for a file that names nothing is refused"
    Refuses "missing-entry" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/allowlist.txt") -Value "core/gone.ps1 | 1 | an entry for a file that is not there at all" } "does not exist" "an entry for a file that does not exist is refused"
    Refuses "own-folder-entry" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/allowlist.txt") -Value "hosts/zorbterm/adapter.ps1 | 1 | the host's own file, which the scan never reads" } "excluded from the scan by rule" "an entry inside the host's own folder is refused as not needed"
    Refuses "planning-entry" {
        Write-FakeFile "planning/history.md" "The old Zorbterm fleet.`n"
        Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/allowlist.txt") -Value "planning/history.md | 1 | a planning record, which the scan never reads"
    } "excluded from the scan by rule" "an entry inside planning/ is refused as not needed"
    Refuses "duplicate" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/allowlist.txt") -Value "docs/rules.md | 2 | the same entry written a second time over" } "listed twice" "an entry listed twice is refused"
    # TWO findings, on purpose, for an entry that is itself malformed: the entry is refused, and so
    # the file it tried to allow is then reported as not allowlisted. Both are asserted, and nothing else.
    function RefusesEntry {
        param([string]$Name, [string]$Line, [string]$Text, [string]$What)
        $f = @(Scan $Name { Write-FakeFile "hosts/zorbterm/allowlist.txt" ($Line + "`n") })
        $ok = ((Says $f $Text) -and (Says $f "is not in hosts/zorbterm/allowlist.txt") -and $f.Count -eq 2)
        Check $ok $What
        if (-not $ok) { Show $f }
    }
    RefusesEntry "no-reason" "docs/rules.md | 2 | ok ok ok ok" "needs a reason" "an entry whose reason is one word repeated is refused, and its file is then reported"
    RefusesEntry "bad-count" "docs/rules.md | two | the rules describe how tests isolate the invented terminal" "must be a whole number" "a line count that is not a number is refused, and its file is then reported"
    RefusesEntry "zero-count" "docs/rules.md | 0 | the rules describe how tests isolate the invented terminal" "must be a whole number" "a line count of zero is refused - an entry allowing nothing is not needed"
    Refuses "bad-shape" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/allowlist.txt") -Value "core/engine.ps1 with no separators at all" } "an allowlist line is" "an allowlist line without its three parts is refused"

    Write-Host ""
    Write-Host "--- a host must say what identifies it ---" -ForegroundColor Cyan

    Refuses "no-names" { Write-FakeFile "hosts/bare/adapter.ps1" "# a host folder with no names.txt`n" } "declares no names.txt" "a host folder with no names.txt is refused - it could not be checked"
    Refuses "short-name" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/names.txt") -Value "zb | a name far too short to identify anything at all" } "shorter than 4" "a name shorter than four characters is refused"
    Refuses "name-no-reason" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/names.txt") -Value "zorbix | zorbix" } "needs a reason" "a name with no real reason is refused"
    Refuses "name-bad-shape" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/names.txt") -Value "zorbix" } "a name line is" "a name line without its reason is refused"
    Refuses "no-usable-name" { Write-FakeFile "hosts/zorbterm/names.txt" "# nothing but comments`n" } "lists no usable name" "a names.txt with no names is refused, not read as nothing to check"

    Write-Host ""
    Write-Host "--- what is not scanned, and how lines are counted ---" -ForegroundColor Cyan

    Passes "planning" { Write-FakeFile "planning/ledger/old-fleet.md" "The Zorbterm fleet and its zorb-sock.`n" } "planning/ is not scanned: plans and ledgers describe the old system by rule"
    Passes "git" { Write-FakeFile ".git/config" "[remote] zorbterm`n" } ".git/ is not scanned"
    Passes "git-file" { Write-FakeFile ".git" "gitdir: C:/code/zorbterm-worktrees/x/.git`n" } "nor is a worktree's .git file, which holds a path that can name anything"
    # MENTIONS, NOT LINES. The review of PR 21 appended "; zorbterm cli spawn" to a line that already
    # named the host, and a count of lines did not move. Each occurrence of each name counts.
    Refuses "same-line" { Write-FakeFile "docs/rules.md" "Run tests in a separate Zorbterm, never the zorbterm you work in.`nNever aim at the zorb-sock you work in.`n" } "3 mention(s); the allowlist allows 2 - a new mention" "a second mention on a line that already names the host is a new mention"
    Passes "two-names-one-line" { Write-FakeFile "docs/rules.md" "Run tests in a separate Zorbterm and its own zorb-sock.`nNothing else here.`n" } "two names on one line count as two mentions, not one line"
    Passes "moved-mention" { Write-FakeFile "docs/rules.md" "Nothing here.`nRun tests in a separate Zorbterm, never the zorb-sock you work in.`n" } "the same mentions on fewer lines are the same count"
    Passes "crlf" { Write-FakeFile "hosts/zorbterm/allowlist.txt" "# exceptions`r`ndocs/rules.md | 2 | the rules describe how tests isolate the invented terminal`r`n" } "an allowlist with CRLF line endings is read the same"
    Passes "backslash" { Write-FakeFile "hosts/zorbterm/allowlist.txt" "docs\rules.md | 2 | the rules describe how tests isolate the invented terminal`n" } "an allowlist path written with backslashes names the same file"
} finally {
    Remove-Item -Recurse -Force -LiteralPath $fake -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "--- this repository ---" -ForegroundColor Cyan

# CONTROL: each real host's names are armed. Its own names.txt is copied into a throwaway repository
# with one file that uses the host's first name; the scan must refuse that file. Without this, a
# names.txt that matched nothing would make the real run below pass by seeing nothing.
$realHosts = @(Get-ChildItem -LiteralPath (Join-Path $root "hosts") -Directory -ErrorAction SilentlyContinue)
Check ($realHosts.Count -ge 1) ("CONTROL: this repository has at least one host to check (" + $realHosts.Count + ")")
foreach ($h in $realHosts) {
    $np = Join-Path $h.FullName "names.txt"
    $first = (Read-HordeHostTable -Path $np)[0]
    $script:repo = Join-Path $env:TEMP ("horde-hostnames-arm-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    try {
        Write-FakeFile ("hosts/" + $h.Name + "/names.txt") ([System.IO.File]::ReadAllText($np))
        Write-FakeFile "core/planted.ps1" ("# " + $first.cells[0] + "`n")
        $armed = @(Test-HordeHostNames -RepoRoot $script:repo)
        Check ((Says $armed "is not in hosts/") -and $armed.Count -eq 1) ("CONTROL: host '" + $h.Name + "' - its first declared name, planted in core/, is caught")
        if ($armed.Count -ne 1) { Show $armed }
    } finally {
        Remove-Item -Recurse -Force -LiteralPath $script:repo -ErrorAction SilentlyContinue
    }
}

$real = @(Test-HordeHostNames -RepoRoot $root)
Check ($real.Count -eq 0) "no file outside a host's folder names that host, beyond what its allowlist lists exactly"
Show $real

Complete-HordeSuite -Success "nothing outside hosts/<name>/ names a host it may not"
