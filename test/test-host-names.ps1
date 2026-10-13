# DOES ANY FILE OUTSIDE A PORT'S FOLDER NAME THAT PORT? (decision D12, and CONTRIBUTING rule 14)
#
# tools/HostNames.ps1 reads each port's names.txt and allowlist.txt - every host in hosts/<name>/ and
# every harness in agents/<name>/ - and scans every other file. This suite first proves the scan
# refuses what it must, on throwaway repositories whose one host and one harness are invented -
# "zorbterm" and "zorbcode" - so that nothing in this file names a real terminal or a real harness and
# the ratchet never has to except itself. Then it runs the scan on this repository.
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
    # file, on exactly two lines; and one harness, zorbcode, named in its own folder and once in one
    # allowlisted file. Every case starts from it and changes one thing.
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
    Write-FakeFile "agents/zorbcode/names.txt" ("# what identifies the invented harness`n" +
        "zorbcode | the invented agent harness this suite polices in place of a real one`n")
    Write-FakeFile "agents/zorbcode/allowlist.txt" ("# exceptions`n" +
        "docs/agents.md | 1 | the agent guide says which harness the fleet starts by default`n")
    Write-FakeFile "agents/zorbcode/adapter.ps1" "# the Zorbcode adapter, which may name its own harness as often as it likes: zorbcode`n"
    Write-FakeFile "docs/agents.md" "Sessions start a zorbcode process.`nNothing else here.`n"
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
    Write-Host "--- a harness is a port too: agents/<name>/ is held to the same rule as hosts/<name>/ ---" -ForegroundColor Cyan

    # Rule 14 keeps each terminal in hosts/<name>/ so the next terminal is an adapter, not an engine
    # change. The engine-settings design (2026-09-30, section 9) applies the same seam to the agent
    # harness, and the founder's decision of that day says core never names an engine. So: the same
    # scan, the same lists and the same shrink-only comparison, over a second family of folders.
    Refuses "agent-leak" { Write-FakeFile "core/spawn.ps1" "& ZORBCODE --resume`n" } "is not in agents/zorbcode/allowlist.txt" "a new file in core that names a harness is refused, whatever its case"
    Refuses "agent-leak-path" { Write-FakeFile "test/fixtures/zorbcode-resume.json" "{}`n" } "is not in agents/zorbcode/allowlist.txt" "a file whose PATH names a harness is refused, though its content does not"
    Refuses "agent-grown" { Write-FakeFile "docs/agents.md" "Sessions start a zorbcode process.`nOr a second zorbcode.`n" } "a new mention" "a file allowlisted for a harness that gains a mention is refused"
    Refuses "agent-shrunk" { Write-FakeFile "docs/agents.md" "Nothing here.`n" } "no longer names the host" "a harness entry for a file that names it nowhere is refused"
    Refuses "agent-own-entry" { Add-Content -LiteralPath (Join-Path $script:repo "agents/zorbcode/allowlist.txt") -Value "agents/zorbcode/adapter.ps1 | 1 | the harness's own file, which the scan never reads" } "excluded from the scan by rule" "an entry inside the harness's own folder is refused as not needed"
    Refuses "agent-no-names" { Write-FakeFile "agents/bare/adapter.ps1" "# a harness folder with no names.txt`n" } "declares no names.txt" "a harness folder with no names.txt is refused - it could not be checked"
    Refuses "agent-names-host" { Write-FakeFile "agents/zorbcode/adapter.ps1" "# zorbcode, typed into a zorbterm pane`n" } "is not in hosts/zorbterm/allowlist.txt" "a harness's folder that names a host is refused - one port's folder does not excuse another port"
    Refuses "host-names-agent" { Write-FakeFile "hosts/zorbterm/adapter.ps1" "# zorbterm, running zorbcode`n" } "is not in agents/zorbcode/allowlist.txt" "a host's folder that names a harness is refused"
    Refuses "agent-names-agent" {
        Write-FakeFile "agents/other/names.txt" "othercode | a second invented harness, so that one harness can be caught naming another`n"
        Write-FakeFile "agents/other/adapter.ps1" "# borrowed from zorbcode`n"
    } "is not in agents/zorbcode/allowlist.txt" "another harness's folder that names this harness is refused"
    Refuses "agent-folder-named-like-host" {
        Write-FakeFile "agents/zorbterm/names.txt" "zorbcli | an invented harness whose folder has the same name as the invented host`n"
    } "is not in hosts/zorbterm/allowlist.txt" "a harness folder with a host's folder name does not exempt that host - a port is its family and its name"

    Write-Host ""
    Write-Host "--- what is not scanned, and how lines are counted ---" -ForegroundColor Cyan

    Passes "planning" { Write-FakeFile "planning/ledger/old-fleet.md" "The Zorbterm fleet and its zorb-sock.`n" } "a .md under planning/ is not scanned: plans and ledgers describe the old system by rule"
    Passes "planning-html" { Write-FakeFile "planning/Plan.HTML" "<p>The Zorbterm fleet.</p>`n" } "nor is a .html under planning/, whatever the case of its extension"
    # PROSE ONLY. The review of PR 21 put a script under planning/lib/, dot-sourced it from core, and
    # the scan never read it: planning/ was skipped whatever the file. Only prose is skipped now, and
    # any other file there is refused outright, so planning/ cannot hold code at all.
    Refuses "planning-code" { Write-FakeFile "planning/lib/spawn.ps1" "function Invoke-Spawn { }`n" } "only .md and .html" "a script under planning/ is refused, though it names nothing"
    function RefusesPlanningData {
        $f = @(Scan "planning-data" { Write-FakeFile "planning/host.json" "{ `"host`": `"zorbterm`" }`n" })
        $ok = ((Says $f "only .md and .html") -and (Says $f "is not in hosts/zorbterm/allowlist.txt") -and $f.Count -eq 2)
        Check $ok "a data file under planning/ is refused, and is scanned like any other file, so its mention is reported too"
        if (-not $ok) { Show $f }
    }
    RefusesPlanningData

    Write-Host ""
    Write-Host "--- every scanned byte is printable ASCII, so no name hides behind an encoding ---" -ForegroundColor Cyan

    # The review of PR 21 wrote the host's name with a Cyrillic letter, and as UTF-16 with no byte
    # order mark; the scan read both as text and found nothing. CONTRIBUTING rule 13 already says
    # source files are ASCII, so a byte outside printable ASCII (tab, CR and LF allowed) is refused.
    function Write-FakeBytes { param([string]$Rel, [byte[]]$Bytes)
        $p = Join-Path $script:repo $Rel
        New-Item -ItemType Directory -Force (Split-Path -Parent $p) | Out-Null
        [System.IO.File]::WriteAllBytes($p, $Bytes) }
    Refuses "lookalike" { Write-FakeBytes "core/h.ps1" ([System.Text.Encoding]::UTF8.GetBytes("# z" + [char]0x043E + "rbterm cli spawn`n")) } "not printable ASCII" "a name spelled with a look-alike letter is refused as non-ASCII"
    Refuses "utf16-no-bom" { Write-FakeBytes "core/u.ps1" ([System.Text.Encoding]::Unicode.GetBytes("zorbterm cli spawn`n")) } "not printable ASCII" "a file in UTF-16 with no byte order mark is refused - its NUL bytes are not printable ASCII"
    Refuses "utf8-bom" { Write-FakeBytes "core/b.ps1" ([byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::ASCII.GetBytes("# sessions`n"))) } "not printable ASCII" "a byte order mark is refused"
    Refuses "own-folder-non-ascii" { Write-FakeBytes "hosts/zorbterm/adapter.ps1" ([System.Text.Encoding]::UTF8.GetBytes("# caf" + [char]0x00E9 + "`n")) } "not printable ASCII" "the host's own folder is held to ASCII too - rule 13 has no exemption"
    Passes "ascii-whitespace" { Write-FakeFile "core/ws.ps1" "`tif (`$x) {`r`n`t`t`$y`r`n}`r`n" } "CONTROL: tabs, CR and LF are printable enough, and pass"
    Passes "planning-prose-non-ascii" { Write-FakeBytes "planning/notes.md" ([System.Text.Encoding]::UTF8.GetBytes("caf" + [char]0x00E9 + "`n")) } "prose under planning/ is not scanned, so a non-ASCII letter there is not this suite's to refuse"
    # A PINNED FILE IS THE ONE EXCEPTION (decisions design 2026-10-06, section 3.11): a program library an
    # adapter cannot be written without sits in the adapter's folder beside a fingerprints.txt giving its
    # SHA-256. It is not read as text; it is held to its fingerprint instead. Everything else about
    # the ASCII rule stands: a binary no list names, and a list outside a port's folder, are refused.
    $libBytes = [byte[]](0x4D, 0x5A, 0x00, 0xFF, 0x90, 0x00)
    $libHasher = [System.Security.Cryptography.SHA256]::Create()
    $libSha = -join ($libHasher.ComputeHash($libBytes) | ForEach-Object { $_.ToString("x2") })
    $libHasher.Dispose()
    $libLine = "zorb.dll | " + $libSha + " | the invented library the invented host cannot be written without`n"
    Passes "pinned" { Write-FakeBytes "hosts/zorbterm/lib/zorb.dll" $libBytes; Write-FakeFile "hosts/zorbterm/lib/fingerprints.txt" $libLine } "a binary in a port's folder that a fingerprint list beside it names, with its SHA-256, is not read as text and passes"
    Refuses "pinned-changed" { Write-FakeBytes "hosts/zorbterm/lib/zorb.dll" ([byte[]](0x4D, 0x5A, 0x00, 0xFF, 0x90, 0x01)); Write-FakeFile "hosts/zorbterm/lib/fingerprints.txt" $libLine } "does not match its fingerprint" "one changed byte in a pinned file is refused"
    Refuses "pinned-missing" { Write-FakeFile "hosts/zorbterm/lib/fingerprints.txt" $libLine } "is listed and is not there" "a listed file that is not there is refused"
    Refuses "pinned-unlisted" { Write-FakeBytes "hosts/zorbterm/lib/zorb.dll" $libBytes; Write-FakeFile "hosts/zorbterm/lib/fingerprints.txt" $libLine; Write-FakeBytes "hosts/zorbterm/lib/other.dll" $libBytes } "not printable ASCII" "a binary beside the list that the list does not name is refused like any other"
    Refuses "pinned-path" { Write-FakeBytes "hosts/zorbterm/lib/zorb.dll" $libBytes; Write-FakeFile "hosts/zorbterm/lib/fingerprints.txt" ($libLine + "..\..\..\core\engine.ps1 | " + $libSha + " | a line reaching out of the list's own folder`n") } "is not a plain file name" "a list line that names a path, not a file in its own folder, is refused"
    function RefusesPinnedOutsideAPort {
        $f = @(Scan "pinned-outside" { Write-FakeBytes "core/lib/zorb.dll" $libBytes; Write-FakeFile "core/lib/fingerprints.txt" $libLine })
        $ok = ((Says $f "outside a port's folder") -and (Says $f "not printable ASCII") -and $f.Count -eq 2)
        Check $ok "a fingerprint list outside a port's folder pins nothing: the list is refused, and the binary beside it is refused as non-ASCII"
        if (-not $ok) { Show $f }
    }
    RefusesPinnedOutsideAPort
    # ONLY A PROGRAM LIBRARY IS EVER LEFT UNREAD. A list names files by name alone, so a script could be
    # listed with its own fingerprint: the review of the surfaces pull request (2026-10-06) did that to
    # a .ps1 holding a look-alike letter, and the scan passed it. The control is the same script with
    # no list: whatever it is refused for then, it must still be refused for when a list names it.
    function RefusesPinnedScript {
        $scriptBytes = [System.Text.Encoding]::UTF8.GetBytes("# caf" + [char]0x00E9 + ": start a zorbcode process`n")
        $scriptHasher = [System.Security.Cryptography.SHA256]::Create()
        $scriptSha = -join ($scriptHasher.ComputeHash($scriptBytes) | ForEach-Object { $_.ToString("x2") })
        $scriptHasher.Dispose()
        $plain = @(Scan "script-unlisted" { Write-FakeBytes "hosts/zorbterm/lib/helper.ps1" $scriptBytes })
        Check ($plain.Count -ge 1 -and (Says $plain "not printable ASCII")) ("CONTROL: a script in a port's folder with a byte that is not ASCII is refused when no list names it (" + $plain.Count + " finding(s))")
        $listed = @(Scan "script-listed" { Write-FakeBytes "hosts/zorbterm/lib/helper.ps1" $scriptBytes; Write-FakeFile "hosts/zorbterm/lib/fingerprints.txt" ("helper.ps1 | " + $scriptSha + " | a script listed with its own fingerprint, to get it past the scan`n") })
        $kept = @($plain | Where-Object { $was = $_; @($listed | Where-Object { $_.path -ceq $was.path -and $_.problem -ceq $was.problem }).Count -eq 1 })
        $ok = ($kept.Count -eq $plain.Count)
        Check $ok "a fingerprint list cannot excuse a script: listed with its true fingerprint, it is still read as text and refused for everything it was refused for"
        if (-not $ok) { Show $listed }
        $named = ((Says $listed "is not a program library") -and $listed.Count -eq ($plain.Count + 1))
        Check $named "and the list is refused for naming it: only a program library is ever left unread"
        if (-not $named) { Show $listed }
        $both = @(Scan "script-beside-library" { Write-FakeBytes "hosts/zorbterm/lib/zorb.dll" $libBytes; Write-FakeBytes "hosts/zorbterm/lib/helper.ps1" $scriptBytes
            Write-FakeFile "hosts/zorbterm/lib/fingerprints.txt" ($libLine + "helper.ps1 | " + $scriptSha + " | a script listed beside a real library`n") })
        Check ((Says $both "not printable ASCII") -and (Says $both "is not a program library") -and -not (Says $both "zorb.dll")) "beside a real library the script is still refused, and the library is still left unread"
    }
    RefusesPinnedScript
    Passes "git"{ Write-FakeFile ".git/config" "[remote] zorbterm`n" } ".git/ is not scanned"
    Passes "git-file" { Write-FakeFile ".git" "gitdir: C:/code/zorbterm-worktrees/x/.git`n" } "nor is a worktree's .git file, which holds a path that can name anything"
    # MENTIONS, NOT LINES. The review of PR 21 appended "; zorbterm cli spawn" to a line that already
    # named the host, and a count of lines did not move. Each occurrence of each name counts.
    Refuses "same-line" { Write-FakeFile "docs/rules.md" "Run tests in a separate Zorbterm, never the zorbterm you work in.`nNever aim at the zorb-sock you work in.`n" } "3 mention(s); the allowlist allows 2 - a new mention" "a second mention on a line that already names the host is a new mention"
    Passes "two-names-one-line" { Write-FakeFile "docs/rules.md" "Run tests in a separate Zorbterm and its own zorb-sock.`nNothing else here.`n" } "two names on one line count as two mentions, not one line"
    Passes "moved-mention" { Write-FakeFile "docs/rules.md" "Nothing here.`nRun tests in a separate Zorbterm, never the zorb-sock you work in.`n" } "the same mentions on fewer lines are the same count"
    Passes "crlf" { Write-FakeFile "hosts/zorbterm/allowlist.txt" "# exceptions`r`ndocs/rules.md | 2 | the rules describe how tests isolate the invented terminal`r`n" } "an allowlist with CRLF line endings is read the same"
    Passes "backslash" { Write-FakeFile "hosts/zorbterm/allowlist.txt" "docs\rules.md | 2 | the rules describe how tests isolate the invented terminal`n" } "an allowlist path written with backslashes names the same file"
    Write-Host ""
    Write-Host "--- the lists can only shrink: compared with origin/main when the checkout has it ---" -ForegroundColor Cyan

    # The exact count alone does not make the list shrink-only. The review of PR 21 added a mention
    # and raised its count in the same edit, added a new file with its own entry, and deleted a name
    # from names.txt - each gave 0 findings, because the scan compares a file with its own list. With
    # no CI, the suite compares the lists with origin/main instead. Each case below is a throwaway
    # git repository whose origin/main is its first commit; the change is made after it.
    function Invoke-FakeGit {
        param([string[]]$GitArgs)
        $null = & git -C $script:repo -c core.autocrlf=false -c init.defaultBranch=main -c user.name=horde-test -c user.email=horde-test@example.invalid -c commit.gpgsign=false @GitArgs
        if ($LASTEXITCODE -ne 0) { throw ("git " + ($GitArgs -join " ") + " exited " + $LASTEXITCODE) }
    }
    function Shrink {
        param([string]$Name, [scriptblock]$Change)
        $null = New-FakeRepo $Name
        Invoke-FakeGit @("init", "-q")
        Invoke-FakeGit @("add", "-A")
        Invoke-FakeGit @("commit", "-q", "--no-verify", "-m", "baseline")
        Invoke-FakeGit @("update-ref", "refs/remotes/origin/main", "HEAD")
        & $Change
        return (Test-HordeHostShrink -RepoRoot $script:repo)
    }
    function ShrinkRefuses {
        param([string]$Name, [scriptblock]$Change, [string]$Text, [string]$What)
        $r = Shrink $Name $Change
        $f = @($r.findings)
        $ok = ($r.skip -eq "" -and (Says $f $Text) -and $f.Count -eq 1)
        Check $ok $What
        if (-not $ok) { Write-Host ("         skip: " + $r.skip) -ForegroundColor Red; Show $f }
    }
    function ShrinkPasses {
        param([string]$Name, [scriptblock]$Change, [string]$What)
        $r = Shrink $Name $Change
        $f = @($r.findings)
        $ok = ($r.skip -eq "" -and $f.Count -eq 0 -and @($r.newHosts).Count -eq 0)
        Check $ok $What
        if (-not $ok) { Write-Host ("         skip: " + $r.skip + "; new hosts: " + (@($r.newHosts) -join ", ")) -ForegroundColor Red; Show $f }
    }
    $allow = "hosts/zorbterm/allowlist.txt"
    ShrinkPasses "sh-same" { } "CONTROL: lists unchanged since origin/main pass"
    ShrinkPasses "sh-lowered" {
        Write-FakeFile "docs/rules.md" "Run tests in a separate Zorbterm.`n"
        Write-FakeFile $allow "docs/rules.md | 1 | the rules describe how tests isolate the invented terminal`n"
    } "a count lowered below origin/main's passes"
    ShrinkPasses "sh-removed" {
        Write-FakeFile "docs/rules.md" "Nothing here.`n"
        Write-FakeFile $allow "# nothing left to allow`n"
    } "an entry removed since origin/main passes"
    ShrinkPasses "sh-name-added" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbterm/names.txt") -Value "zorbctl | the invented terminal's command line tool, added after origin/main" } "a name added since origin/main passes - more names only check more"
    ShrinkRefuses "sh-raised" {
        Write-FakeFile "docs/rules.md" "Run tests in a separate Zorbterm.`nNever aim at the zorb-sock you work in.`nzorbterm cli spawn`n"
        Write-FakeFile $allow "docs/rules.md | 3 | the rules describe how tests isolate the invented terminal`n"
    } "may not rise" "a count raised together with the mention it allows is refused"
    ShrinkRefuses "sh-new-entry" {
        Write-FakeFile "core/engine.ps1" "function Start-Pane { zorbterm cli spawn }`n"
        Add-Content -LiteralPath (Join-Path $script:repo $allow) -Value "core/engine.ps1 | 1 | the engine spawns panes in the invented terminal directly"
    } "not on origin/main" "a new allowlist entry is refused, reason and all"
    ShrinkRefuses "sh-name-removed" { Write-FakeFile "hosts/zorbterm/names.txt" "zorbterm | the invented terminal this suite polices in place of a real one`n" } "zorb-sock" "a name deleted from names.txt since origin/main is refused, and named"
    ShrinkRefuses "sh-host-removed" {
        Write-FakeFile "hosts/other/names.txt" "otherterm | a second invented terminal, which this branch then deletes`n"
        Invoke-FakeGit @("add", "-A"); Invoke-FakeGit @("commit", "-q", "--no-verify", "-m", "other"); Invoke-FakeGit @("update-ref", "refs/remotes/origin/main", "HEAD")
        Remove-Item -Recurse -Force -LiteralPath (Join-Path $script:repo "hosts/other")
    } "deleting its folder" "a host folder on origin/main that is gone here is refused - deleting it would switch its check off"
    $nh = Shrink "sh-new-host" { Write-FakeFile "hosts/other/names.txt" "otherterm | a second invented terminal, new since origin/main`n" }
    Check ($nh.skip -eq "" -and @($nh.findings).Count -eq 0 -and (@($nh.newHosts) -join ",") -eq "hosts/other") "a host new since origin/main is reported as new, not compared - its pull request sets its baseline"
    # THE SAME COMPARISON FOR A HARNESS. Without it an agents/ allowlist would be exact but not
    # shrink-only: its count and the mention it allows could rise together in one edit.
    $agentAllow = "agents/zorbcode/allowlist.txt"
    $agentTwo = "Sessions start a zorbcode process.`nOr a second zorbcode.`n"
    $agentTwoEntry = "docs/agents.md | 2 | the agent guide says which harness the fleet starts by default`n"
    ShrinkRefuses "sh-agent-raised" { Write-FakeFile "docs/agents.md" $agentTwo; Write-FakeFile $agentAllow $agentTwoEntry } "may not rise" "a harness's count raised together with the mention it allows is refused"
    ShrinkRefuses "sh-agent-new-entry" {
        Write-FakeFile "core/spawn.ps1" "& zorbcode`n"
        Add-Content -LiteralPath (Join-Path $script:repo $agentAllow) -Value "core/spawn.ps1 | 1 | the engine starts the invented harness directly"
    } "not on origin/main" "a new entry in a harness's allowlist is refused, reason and all"
    ShrinkRefuses "sh-agent-name-removed" { Write-FakeFile "agents/zorbcode/names.txt" "zorbctl | an unrelated invented name, so the file still declares one`n" } "'zorbcode'" "a name deleted from a harness's names.txt since origin/main is refused, and named"
    ShrinkRefuses "sh-agent-removed" { Remove-Item -Recurse -Force -LiteralPath (Join-Path $script:repo "agents/zorbcode") } "deleting its folder" "a harness folder on origin/main that is gone here is refused - deleting it would switch its check off"
    ShrinkPasses "sh-agent-growth" {
        Write-FakeFile "docs/agents.md" $agentTwo; Write-FakeFile $agentAllow $agentTwoEntry
        Write-FakeFile "agents/zorbcode/growth.txt" "docs/agents.md | 1 -> 2 | 2026-09-30 | the guide now names the harness in a second example`n"
    } "a harness's raised count passes with a line in its own growth.txt"
    ShrinkRefuses "sh-agent-growth-wrong-port" {
        Write-FakeFile "docs/agents.md" $agentTwo; Write-FakeFile $agentAllow $agentTwoEntry
        Write-FakeFile "hosts/zorbterm/growth.txt" "docs/agents.md | 1 -> 2 | 2026-09-30 | the guide now names the harness in a second example`n"
    } "agents/zorbcode/growth.txt recording" "a harness's growth recorded in a host's growth.txt permits nothing - each port reviews its own growth"
    ShrinkRefuses "sh-agent-growth-append-only" {
        Write-FakeFile "agents/zorbcode/growth.txt" "docs/agents.md | 0 -> 1 | 2026-09-01 | the guide first named the harness it starts`n"
        Invoke-FakeGit @("add", "-A"); Invoke-FakeGit @("commit", "-q", "--no-verify", "-m", "main"); Invoke-FakeGit @("update-ref", "refs/remotes/origin/main", "HEAD")
        Write-FakeFile "agents/zorbcode/growth.txt" "# emptied`n"
    } "append-only" "a harness's growth.txt is read from origin/main at its own path, so a line removed from it is refused"
    $na = Shrink "sh-new-agent" { Write-FakeFile "agents/other/names.txt" "othercode | a second invented harness, new since origin/main`n" }
    Check ($na.skip -eq "" -and @($na.findings).Count -eq 0 -and (@($na.newHosts) -join ",") -eq "agents/other") "a harness new since origin/main is reported as new under its own port, not compared"
    $ng = Shrink "sh-no-git" { Remove-Item -Recurse -Force -LiteralPath (Join-Path $script:repo ".git") }
    Check ($ng.skip -like "*no .git*" -and @($ng.findings).Count -eq 0) "with no .git the comparison is skipped, and says why"
    $nr = Shrink "sh-no-ref" { Invoke-FakeGit @("update-ref", "-d", "refs/remotes/origin/main") }
    Check ($nr.skip -like "*origin/main does not exist*" -and @($nr.findings).Count -eq 0) "with no origin/main the comparison is skipped, and says why"
    Write-Host ""
    Write-Host "--- growth passes only with a matching line added to growth.txt, which is append-only ---" -ForegroundColor Cyan

    # Refusing every increase, with no override, deadlocked: a branch that needs a new mention could
    # never pass until the entry was already on main. A line in hosts/<name>/growth.txt recording
    # exactly the path, the old count and the new count is the override, and the thing the reviewer
    # agrees to. Each refusal below breaks exactly one part of that line; a malformed line is its own
    # finding, and the growth it failed to record is the second.
    function ShrinkRefusesAll {
        param([string]$Name, [scriptblock]$Change, [string[]]$Texts, [string]$What)
        $r = Shrink $Name $Change
        $f = @($r.findings)
        $ok = ($r.skip -eq "" -and $f.Count -eq $Texts.Count)
        foreach ($t in $Texts) { $ok = ($ok -and (Says $f $t)) }
        Check $ok $What
        if (-not $ok) { Write-Host ("         skip: " + $r.skip) -ForegroundColor Red; Show $f }
    }
    function Save-FakeMain {
        # Make what the change has written so far origin/main, so the case can then change it.
        Invoke-FakeGit @("add", "-A"); Invoke-FakeGit @("commit", "-q", "--no-verify", "-m", "main"); Invoke-FakeGit @("update-ref", "refs/remotes/origin/main", "HEAD")
    }
    $grow = "hosts/zorbterm/growth.txt"
    $why = "a third mention documents the spawn command of the invented terminal"
    $three = "Run tests in a separate Zorbterm.`nNever aim at the zorb-sock you work in.`nzorbterm cli spawn`n"
    function Raise-Rules {
        # docs/rules.md goes from 2 mentions to 3, and its entry with it.
        Write-FakeFile "docs/rules.md" $three
        Write-FakeFile $allow "docs/rules.md | 3 | the rules describe how tests isolate the invented terminal`n"
    }
    ShrinkPasses "gr-raised" { Raise-Rules; Write-FakeFile $grow ("# growth`ndocs/rules.md | 2 -> 3 | 2026-09-30 | " + $why + "`n") } "a raised count passes with a growth line for that path, that old count and that new count"
    ShrinkPasses "gr-new-entry" {
        Write-FakeFile "core/engine.ps1" "function Start-Pane { zorbterm cli spawn }`n"
        Add-Content -LiteralPath (Join-Path $script:repo $allow) -Value "core/engine.ps1 | 1 | the engine spawns panes in the invented terminal directly"
        Write-FakeFile $grow "core/engine.ps1 | 0 -> 1 | 2026-09-30 | the engine spawns panes in the invented terminal directly`n"
    } "a new entry passes with a growth line recording 0 -> its count"
    ShrinkPasses "gr-path-form" { Raise-Rules; Write-FakeFile $grow ("docs\Rules.MD | 2 -> 3 | 2026-09-30 | " + $why + "`r`n") } "a growth path is read as an allowlist path is: backslashes, any case, CRLF"
    ShrinkPasses "gr-history" { Write-FakeFile $grow ("docs/rules.md | 2 -> 3 | 2026-09-30 | " + $why + "`n") } "a growth line that matches no current difference is history, not a finding"
    ShrinkRefuses "gr-no-file" { Raise-Rules } "growth.txt recording 'docs/rules.md | 2 -> 3" "a raised count with no growth.txt is refused, and the line it needs is named"
    ShrinkRefuses "gr-other-path" { Raise-Rules; Write-FakeFile $grow ("core/engine.ps1 | 2 -> 3 | 2026-09-30 | " + $why + "`n") } "may not rise" "a growth line for another path does not permit the increase"
    ShrinkRefuses "gr-new-wrong" { Raise-Rules; Write-FakeFile $grow ("docs/rules.md | 2 -> 4 | 2026-09-30 | " + $why + "`n") } "may not rise" "a growth line whose new count is not the allowlist's is refused"
    ShrinkRefuses "gr-old-wrong" { Raise-Rules; Write-FakeFile $grow ("docs/rules.md | 1 -> 3 | 2026-09-30 | " + $why + "`n") } "may not rise" "a growth line whose old count is not origin/main's is refused"
    ShrinkRefuses "gr-new-entry-old-wrong" {
        Write-FakeFile "core/engine.ps1" "function Start-Pane { zorbterm cli spawn }`n"
        Add-Content -LiteralPath (Join-Path $script:repo $allow) -Value "core/engine.ps1 | 1 | the engine spawns panes in the invented terminal directly"
        Write-FakeFile $grow "core/engine.ps1 | 1 -> 2 | 2026-09-30 | the engine spawns panes in the invented terminal directly`n"
    } "an entry may not be added" "a new entry's growth line must start from 0"
    ShrinkRefusesAll "gr-short-reason" { Raise-Rules; Write-FakeFile $grow "docs/rules.md | 2 -> 3 | 2026-09-30 | more more more more`n" } @("reason of at least a sentence for its growth", "may not rise") "a growth line with fewer than four distinct words of reason is refused, and permits nothing"
    ShrinkRefusesAll "gr-shape" { Raise-Rules; Write-FakeFile $grow ("docs/rules.md | 2 -> 3 | " + $why + "`n") } @("a growth line is", "may not rise") "a growth line with no date cell is refused, and permits nothing"
    ShrinkRefusesAll "gr-arrow" { Raise-Rules; Write-FakeFile $grow ("docs/rules.md | 2 to 3 | 2026-09-30 | " + $why + "`n") } @("must read <old> -> <new>", "may not rise") "a growth line whose counts are not <old> -> <new> is refused, and permits nothing"
    ShrinkRefusesAll "gr-not-increase" { Raise-Rules; Write-FakeFile $grow ("docs/rules.md | 3 -> 3 | 2026-09-30 | " + $why + "`n") } @("not an increase", "may not rise") "a growth line that records no increase is refused"
    ShrinkRefusesAll "gr-bad-date" { Raise-Rules; Write-FakeFile $grow ("docs/rules.md | 2 -> 3 | 2026-13-40 | " + $why + "`n") } @("real date", "may not rise") "a growth line whose date is not a real date is refused, and permits nothing"
    ShrinkRefusesAll "gr-date-form" { Raise-Rules; Write-FakeFile $grow ("docs/rules.md | 2 -> 3 | 30-09-2026 | " + $why + "`n") } @("real date", "may not rise") "a growth line whose date is not written YYYY-MM-DD is refused, and permits nothing"
    $onMain = "docs/rules.md | 1 -> 2 | 2026-09-01 | the rules gained a second mention of the socket file`n"
    ShrinkPasses "gr-appended" { Write-FakeFile $grow $onMain; Save-FakeMain; Raise-Rules; Write-FakeFile $grow ($onMain + "docs/rules.md | 2 -> 3 | 2026-09-30 | " + $why + "`n") } "CONTROL: a growth line appended after origin/main's lines passes"
    ShrinkRefuses "gr-removed" { Write-FakeFile $grow $onMain; Save-FakeMain; Write-FakeFile $grow "# emptied`n" } "append-only" "a growth line on origin/main that is removed here is refused"
    ShrinkRefuses "gr-file-deleted" { Write-FakeFile $grow $onMain; Save-FakeMain; Remove-Item -LiteralPath (Join-Path $script:repo $grow) } "append-only" "a growth.txt on origin/main that is deleted here is refused"
    ShrinkRefuses "gr-edited" { Write-FakeFile $grow $onMain; Save-FakeMain; Write-FakeFile $grow "docs/rules.md | 1 -> 2 | 2026-09-01 | the rules gained a second mention of something`n" } "append-only" "a growth line on origin/main that is edited here is refused"
    ShrinkRefuses "gr-inserted" { Write-FakeFile $grow $onMain; Save-FakeMain; Write-FakeFile $grow ("core/engine.ps1 | 0 -> 1 | 2026-09-30 | the engine spawns panes in the invented terminal`n" + $onMain) } "append-only" "a growth line inserted above origin/main's lines is refused - new lines go at the end"
    ShrinkRefuses "gr-reused" {
        Write-FakeFile $grow "core/engine.ps1 | 0 -> 1 | 2026-09-01 | the engine once spawned panes in the invented terminal`n"; Save-FakeMain
        Write-FakeFile "core/engine.ps1" "function Start-Pane { zorbterm cli spawn }`n"
        Add-Content -LiteralPath (Join-Path $script:repo $allow) -Value "core/engine.ps1 | 1 | the engine spawns panes in the invented terminal directly"
    } "an entry may not be added" "a growth line already on origin/main permits nothing again - a removed mention cannot come back unreviewed"

    Write-Host ""
    Write-Host "--- a port declares the kind of each name: name, processImage or path (lifecycle plan step 5) ---" -ForegroundColor Cyan

    # The lifecycle plan (planning/execution-plan-lifecycle.md, step 5 and section 2.6) brings engine
    # knowledge core must never hold: each harness's process images and the path fragments of its
    # transcripts, rollouts, control files and task output. They are declared in the harness's own
    # names.txt, as names of a kind, so the ratchet catches them anywhere else. The invented image and
    # fragment below do not contain the harness's name, so only their own declaration can catch them.
    $zcImage = "zcrunner.exe | processImage | the invented harness's own process image, which does not contain its name"
    $zcPath = "zc-chatlog- | path | the invented harness's chat log file name prefix, which does not contain its name"
    function Add-ZorbcodeName { param([string]$Line) Add-Content -LiteralPath (Join-Path $script:repo "agents/zorbcode/names.txt") -Value $Line }
    Passes "kind-lines" { Add-ZorbcodeName $zcImage; Add-ZorbcodeName $zcPath } "CONTROL: a processImage line and a path line that nothing outside the folder uses pass"
    Passes "kind-name-explicit" { Add-ZorbcodeName "zorbcli | name | the invented harness's second command name, its kind written out" } "a line whose kind is written as name is read like a two-part line"
    Refuses "image-leak" { Add-ZorbcodeName $zcImage; Write-FakeFile "core/tree.ps1" "if (`$p.Name -eq 'ZCRUNNER.EXE') { }`n" } "is not in agents/zorbcode/allowlist.txt" "a planted process image name in core is caught, whatever its case"
    Refuses "path-leak" { Add-ZorbcodeName $zcPath; Write-FakeFile "core/follow.ps1" "Join-Path `$d 'zc-chatlog-*.jsonl'`n" } "is not in agents/zorbcode/allowlist.txt" "a planted transcript path fragment in core is caught"
    Refuses "bad-kind" { Add-ZorbcodeName "zcrunner.exe | image | the invented harness's own process image, which does not contain its name" } "is not one of name, processImage, path" "a kind outside the closed list is refused"
    Refuses "kind-case" { Add-ZorbcodeName "zcrunner.exe | processimage | the invented harness's own process image, which does not contain its name" } "is not one of name, processImage, path" "a kind is matched exactly, so a miscased kind is refused rather than guessed at"
    Refuses "kind-no-reason" { Add-ZorbcodeName "zcrunner.exe | processImage | zcrunner" } "needs a reason" "a kind line with no real reason is refused"
    Refuses "kind-short" { Add-ZorbcodeName "zc- | path | a fragment far too short to identify the invented harness" } "shorter than 4" "a kind line whose name is shorter than four characters is refused"
    Refuses "kind-bad-shape" { Add-ZorbcodeName "zcrunner.exe | processImage | its own image | an extra part" } "a name line is" "a name line with four parts is refused"
    # ONE MENTION, ONE COUNT. An image named after its harness - zorbcode.exe for zorbcode - holds the
    # harness's name inside it. Counted once per name it would be two mentions, and declaring an image
    # would raise every allowlist count that already covers it, with no new mention made.
    $exe = "zorbcode.exe | processImage | the invented harness's process image, which contains its name"
    Passes "contained-once" { Add-ZorbcodeName $exe; Write-FakeFile "docs/agents.md" "Sessions start a zorbcode.exe process.`nNothing else here.`n" } "a declared name inside a longer declared name is one mention, not two"
    Refuses "contained-apart" { Add-ZorbcodeName $exe; Write-FakeFile "docs/agents.md" "Sessions start a zorbcode.exe process, the zorbcode.`nNothing else here.`n" } "2 mention(s); the allowlist allows 1 - a new mention" "the shorter name on its own beside the longer one is still a second mention"
    Refuses "contained-repeated" { Add-ZorbcodeName $exe; Write-FakeFile "docs/agents.md" "Sessions start zorbcode.exe or zorbcode.exe.`nNothing else here.`n" } "2 mention(s); the allowlist allows 1 - a new mention" "each occurrence of the longer name is a mention of its own"
    # At one starting point the LONGEST name is taken. Which one wins only shows with a third name that
    # starts where the shortest ends: taken shortest-first, zorbcode and .exe.log would be two.
    Passes "contained-longest-first" { Add-ZorbcodeName $exe; Add-ZorbcodeName ".exe.log | path | an invented log file suffix that overlaps the invented image"; Write-FakeFile "docs/agents.md" "Sessions write zorbcode.exe.log.`nNothing else here.`n" } "at one starting point the longest declared name is the mention, and a name inside it is not counted again"
    Refuses "contained-inner" { Add-ZorbcodeName "bcode-ctl | path | an invented fragment that starts inside the harness's name"; Write-FakeFile "docs/agents.md" "Sessions start zorbcode-ctl and zorbcode.`nNothing else here.`n" } "2 mention(s); the allowlist allows 1 - a new mention" "two declared names that overlap without one containing the other are one mention there, and the next is counted"
    ShrinkRefuses "sh-image-removed" {
        Add-ZorbcodeName $zcImage; Save-FakeMain
        Write-FakeFile "agents/zorbcode/names.txt" "zorbcode | the invented agent harness this suite polices in place of a real one`n"
    } "'zcrunner.exe'" "a processImage name on origin/main that is deleted here is refused, and named - a kind line is a name"
    ShrinkPasses "sh-kind-written-out" {
        Write-FakeFile "agents/zorbcode/names.txt" "zorbcode | name | the invented agent harness this suite polices in place of a real one`n"
    } "a two-part name line rewritten with its kind written out is the same name, not a removal"

    Write-Host ""
    Write-Host "--- one allowlisted cross-host import: a host may dot-source another host's Dialect.ps1, once (hosts plan step 5) ---" -ForegroundColor Cyan

    # Hosts decision 3 (2026-09-30): the command language two multiplexers share lives in the first
    # one's folder, and the second imports it as a declared dependency rather than copying it. Other
    # hosts' folders are scanned, so without a rule of its own every file of the second host that uses
    # the language would be a leak - and its own scrub of the first one's environment variables too,
    # because those variables contain the first host's name. So: one allowlist entry, "<path> | import
    # | <reason>", lets a file in another host's folder name this host exactly once, in a line that
    # dot-sources this host's Dialect.ps1. The dialect hands out its variable names as data, so the
    # importer never spells them. Any other mention in that folder is refused. The invented hosts are
    # zorbmux, which owns the language, and zorbplex, which imports it.
    $importLine = ". (Join-Path `$PSScriptRoot '..\zorbmux\Dialect.ps1')"
    $importEntry = "hosts/zorbplex/Adapter.ps1 | import | the second multiplexer imports the shared command language"
    # THE TWO LISTS NAME EACH OTHER, as the real ports' lists do: an import entry names the importing
    # file by its path, so the importer's allowlist lists the other host's allowlist; that line names the
    # other host, so its allowlist lists the importer's back. The importer's count is the entry's one
    # mention plus that line's. -Entry "" writes the two list lines alone.
    function Write-DialectLists {
        param([string]$Entry)
        $mux = ""
        if ($Entry) { $mux = $Entry + "`n" }
        Write-FakeFile "hosts/zorbmux/allowlist.txt" ($mux + "hosts/zorbplex/allowlist.txt | 1 | the importing host's allowlist names this host's allowlist by its path`n")
        $n = 1; if ($Entry) { $n = 2 }
        Write-FakeFile "hosts/zorbplex/allowlist.txt" ("hosts/zorbmux/allowlist.txt | " + $n + " | the shared language's allowlist names the importing file and this allowlist by path`n")
    }
    function New-DialectRepo {
        param([string]$Name)
        $null = New-FakeRepo $Name
        Write-FakeFile "hosts/zorbmux/names.txt" "zorbmux | the invented multiplexer whose command language a second invented host shares`n"
        Write-FakeFile "hosts/zorbmux/Dialect.ps1" "function Get-HordeMuxDialectEnvNames { return @('ZORBMUX', 'ZORBMUX_PANE') }`n"
        Write-FakeFile "hosts/zorbplex/names.txt" "zorbplex | the invented second multiplexer, which imports the first one's dialect`n"
        Write-FakeFile "hosts/zorbplex/Adapter.ps1" ($importLine + "`n`$scrub = Get-HordeMuxDialectEnvNames`n")
        Write-DialectLists $importEntry
    }
    function DialectScan { param([string]$Name, [scriptblock]$Change) New-DialectRepo $Name; & $Change; return @(Test-HordeHostNames -RepoRoot $script:repo) }
    function DialectRefuses {
        param([string]$Name, [scriptblock]$Change, [string]$Text, [string]$What)
        $f = @(DialectScan $Name $Change)
        $ok = ((Says $f $Text) -and $f.Count -eq 1)
        Check $ok $What
        if (-not $ok) { Show $f }
    }
    function DialectPasses {
        param([string]$Name, [scriptblock]$Change, [string]$What)
        $f = @(DialectScan $Name $Change)
        Check ($f.Count -eq 0) $What
        if ($f.Count -gt 0) { Show $f }
    }
    # A REFUSED ENTRY ALSO REPORTS ITS FILE, as RefusesEntry above asserts: both findings, and nothing else.
    function DialectRefusesEntry {
        param([string]$Name, [scriptblock]$Change, [string]$Text, [string]$What)
        $f = @(DialectScan $Name $Change)
        $ok = ((Says $f $Text) -and (Says $f "is not in hosts/zorbmux/allowlist.txt") -and $f.Count -eq 2)
        Check $ok $What
        if (-not $ok) { Show $f }
    }
    DialectPasses "dialect-import" { } "a file in another host's folder that dot-sources this host's Dialect.ps1 once, under an import entry, passes"
    DialectPasses "dialect-import-crlf" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" ($importLine + "`r`n`$scrub = Get-HordeMuxDialectEnvNames`r`n") } "the import line is found the same with CRLF line endings"
    DialectPasses "dialect-import-slash" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" ". (Join-Path `$PSScriptRoot '../zorbmux/Dialect.ps1')`n" } "the import may use forward slashes"
    DialectRefuses "dialect-second-mention" { Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbplex/Adapter.ps1") -Value "`$p = `$env:ZORBMUX_PANE" } "2 mention(s); the allowlist allows 1 - a new mention" "a second mention beside the import is refused - the importer asks the dialect for the variable names"
    DialectRefuses "dialect-spells-env" { Write-FakeFile "hosts/zorbplex/Scrub.ps1" "Remove-Item Env:ZORBMUX_PANE`n" } "is not in hosts/zorbmux/allowlist.txt" "a file of the importing host that spells the dialect's variable itself is refused"
    DialectRefuses "dialect-other-file" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" ". (Join-Path `$PSScriptRoot '..\zorbmux\Transport.ps1')`n" } "dot-sources hosts/zorbmux/Dialect.ps1" "an import of a file other than Dialect.ps1 is refused"
    DialectRefuses "dialect-not-dot-sourced" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" "# the language is in ..\zorbmux\Dialect.ps1`n" } "dot-sources hosts/zorbmux/Dialect.ps1" "a mention that only names the dialect, in a comment, is not an import and is refused"
    # THE PATH IS THE DIALECT, AND THE LINE DOT-SOURCES IT DIRECTLY (review of PR #58, B1 and B2): a
    # longer file name that only begins with Dialect.ps1 is another file, and a dialect path handed to
    # a loader as an argument lets the loader open any file of the host.
    DialectRefuses "dialect-longer-name" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" ". (Join-Path `$PSScriptRoot '..\zorbmux\Dialect.ps1.private.ps1')`n" } "dot-sources hosts/zorbmux/Dialect.ps1" "a file whose name only begins with Dialect.ps1 is not the dialect"
    DialectRefuses "dialect-as-argument" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" ". (Invoke-Loader '..\zorbmux\Dialect.ps1')`n" } "dot-sources hosts/zorbmux/Dialect.ps1" "a dialect path passed to a loader is not an import"
    DialectRefuses "dialect-after-other-file" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" ". '..\zorbplex\Other.ps1' '..\zorbmux\Dialect.ps1'`n" } "dot-sources hosts/zorbmux/Dialect.ps1" "a line that dot-sources another file, with the dialect path as its argument, is not an import"
    DialectPasses "dialect-quoted-direct" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" (". `"`$PSScriptRoot\..\zorbmux\Dialect.ps1`"`n") } "the dialect dot-sourced as one quoted path passes"
    DialectPasses "dialect-trailing-comment" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" ($importLine + " # the shared command language`n") } "an import line may end in a comment"
    DialectRefuses "dialect-called" { Write-FakeFile "hosts/zorbplex/Adapter.ps1" "& (Join-Path `$PSScriptRoot '..\zorbmux\Dialect.ps1')`n" } "dot-sources hosts/zorbmux/Dialect.ps1" "a dialect run with & instead of dot-sourced is refused"
    DialectRefusesEntry "dialect-numbered-entry" {
        Write-FakeFile "hosts/zorbplex/Adapter.ps1" ($importLine + "`n`$p = `$env:ZORBMUX_PANE`n")
        Write-DialectLists "hosts/zorbplex/Adapter.ps1 | 2 | the second multiplexer imports the language and reads its pane variable"
    } "only through an import" "a numbered entry for a file in another host's folder is refused - an import is the one way in"
    DialectRefusesEntry "dialect-import-outside-port" {
        Write-FakeFile "core/engine.ps1" ($importLine + "`n")
        Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbmux/allowlist.txt") -Value "core/engine.ps1 | import | the engine borrows the multiplexer language directly"
    } "is not in another hosts port's folder" "an import entry for a file outside every host's folder is refused - core imports no host"
    DialectRefusesEntry "dialect-import-from-harness" {
        # A harness whose folder name is not its declared name, so the entry's path names no harness.
        Write-FakeFile "agents/plainh/names.txt" "plaincode | an invented harness whose folder name does not contain its declared name`n"
        Write-FakeFile "agents/plainh/adapter.ps1" ($importLine + "`n")
        Add-Content -LiteralPath (Join-Path $script:repo "hosts/zorbmux/allowlist.txt") -Value "agents/plainh/adapter.ps1 | import | the harness borrows the multiplexer language directly"
    } "is not in another hosts port's folder" "an import entry for a file in a harness's folder is refused - only another host imports a host's dialect"
    DialectRefusesEntry "dialect-import-case" { Write-DialectLists "hosts/zorbplex/Adapter.ps1 | Import | the second multiplexer imports the shared command language" } "or the word import" "the word import is matched exactly, so a miscased one is refused rather than guessed at"
    # THE MENTION MUST BE IN THE IMPORT LINE. Here the host's folder name is not one of its declared
    # names, so the import line names nothing, and the file's one mention is a variable spelled
    # elsewhere: an import line beside it must not excuse that.
    DialectRefuses "dialect-mention-elsewhere" {
        Write-FakeFile "hosts/zorbmux/names.txt" "zorbmuxd | the invented multiplexer's server name, which its folder name does not contain`n"
        Write-FakeFile "hosts/zorbplex/Adapter.ps1" ($importLine + "`n`$p = `$env:ZORBMUXD_PANE`n")
        # zorbmuxd is not in the path hosts/zorbmux/allowlist.txt, so that list needs no line back.
        Write-FakeFile "hosts/zorbmux/allowlist.txt" ($importEntry + "`n")
        Write-FakeFile "hosts/zorbplex/allowlist.txt" "hosts/zorbmux/allowlist.txt | 1 | the shared language's allowlist names the importing file by its path`n"
    } "dot-sources hosts/zorbmux/Dialect.ps1" "an import line that names nothing does not excuse the one mention made elsewhere in the file"
    DialectRefusesEntry "dialect-missing" { Remove-Item -LiteralPath (Join-Path $script:repo "hosts/zorbmux/Dialect.ps1") } "hosts/zorbmux/Dialect.ps1 does not exist" "an import entry for a host with no Dialect.ps1 is refused - there is nothing to import"
    DialectRefuses "dialect-import-names-path" {
        Remove-Item -LiteralPath (Join-Path $script:repo "hosts/zorbplex/Adapter.ps1")
        Write-FakeFile "hosts/zorbplex/zorbmux-shim.ps1" ($importLine + "`n")
        Write-DialectLists "hosts/zorbplex/zorbmux-shim.ps1 | import | the second multiplexer imports the shared command language"
    } "2 mention(s); the allowlist allows 1 - a new mention" "an importing file whose path also names the host has two mentions, and is refused"
    function Save-DialectMain {
        # zorbmux and zorbplex on origin/main, with no import yet: the branch then adds it.
        Write-FakeFile "hosts/zorbmux/names.txt" "zorbmux | the invented multiplexer whose command language a second invented host shares`n"
        Write-FakeFile "hosts/zorbmux/Dialect.ps1" "function Get-HordeMuxDialectEnvNames { return @('ZORBMUX', 'ZORBMUX_PANE') }`n"
        Write-FakeFile "hosts/zorbplex/names.txt" "zorbplex | the invented second multiplexer, which imports the first one's dialect`n"
        Write-DialectLists ""
        # The importer's count as it will be once the import names it: only the import entry is new.
        Write-FakeFile "hosts/zorbplex/allowlist.txt" "hosts/zorbmux/allowlist.txt | 2 | the shared language's allowlist names the importing file and this allowlist by path`n"
        Save-FakeMain
        Write-FakeFile "hosts/zorbplex/Adapter.ps1" ($importLine + "`n")
        Write-DialectLists $importEntry
    }
    ShrinkRefuses "sh-import-new" { Save-DialectMain } "not on origin/main" "a new import entry is growth like any new entry, and is refused without a growth line"
    ShrinkPasses "sh-import-growth" { Save-DialectMain; Write-FakeFile "hosts/zorbmux/growth.txt" "hosts/zorbplex/Adapter.ps1 | 0 -> 1 | 2026-10-02 | the second multiplexer imports the shared command language`n" } "a new import entry passes with a growth line recording 0 -> 1"

    Write-Host ""
    Write-Host "--- core matches no process image, not even where an allowlist lets a file name the harness ---" -ForegroundColor Cyan

    # Lifecycle plan section 2.6: "Core matches no image name"; which processes are a harness's is its
    # adapter's to answer. The ratchet alone cannot hold that: a file allowlisted for a harness may name
    # it any way it likes, an image included. So a processImage has a rule of its own with no allowlist:
    # outside every port's folder and outside test/, a file that matches one is refused, unless it is
    # one of the legacy readers the rule was measured against, listed with its exact number of matches
    # in tools/process-image-legacy.txt - a list that can only shrink (review of PR #57, A1 and A3).
    $legacyFile = "tools/process-image-legacy.txt"
    function Write-Legacy { param([string]$Lines) Write-FakeFile $legacyFile ("# legacy readers`n" + $Lines + "`n") }
    $oldEntry = "core/old.ps1 | 1 | an old reader that matched the invented image before the rule existed"
    function Images {
        param([string]$Name, [scriptblock]$Change)
        $null = New-FakeRepo $Name
        Add-ZorbcodeName $zcImage
        & $Change
        return @(Test-HordeProcessImages -RepoRoot $script:repo)
    }
    function ImagesRefuse {
        param([string]$Name, [scriptblock]$Change, [string]$Text, [string]$What)
        $f = @(Images $Name $Change)
        $ok = ((Says $f $Text) -and $f.Count -eq 1)
        Check $ok $What
        if (-not $ok) { Show $f }
    }
    function ImagesRefuseBoth {
        # A refused legacy entry excuses nothing, so its file is then reported too: both, and nothing else.
        param([string]$Name, [scriptblock]$Change, [string]$Text, [string]$What)
        $f = @(Images $Name $Change)
        $ok = ((Says $f $Text) -and (Says $f "matches the process image") -and $f.Count -eq 2)
        Check $ok $What
        if (-not $ok) { Show $f }
    }
    function ImagesPass {
        param([string]$Name, [scriptblock]$Change, [string]$What)
        $f = @(Images $Name $Change)
        Check ($f.Count -eq 0) $What
        if ($f.Count -gt 0) { Show $f }
    }
    ImagesPass "img-clean" { } "CONTROL: a repository whose process images stay in their harness's folder passes"
    ImagesRefuse "img-core" { Write-FakeFile "core/tree.ps1" "if (`$p.Name -eq 'ZCRUNNER.EXE') { }`n" } "matches the process image 'zcrunner.exe'" "a process image matched in core is refused, whatever its case"
    ImagesRefuse "img-engine" { Write-FakeFile "remote/node.ps1" "# zcrunner.exe`n" } "matches the process image" "an image matched in any engine folder, not only core/, is refused"
    ImagesRefuse "img-path" { Write-FakeFile "core/zcrunner.exe.json" "{}`n" } "matches the process image" "a file whose path names an image is refused, though its content does not"
    $allowImage = "core/tree.ps1 | 1 | the engine's process walk once named the invented harness's image"
    function Write-AllowlistedImage {
        Write-FakeFile "core/tree.ps1" "if (`$p.Name -eq 'zcrunner.exe') { }`n"
        Add-Content -LiteralPath (Join-Path $script:repo "agents/zorbcode/allowlist.txt") -Value $allowImage
    }
    ImagesRefuse "img-allowlisted" { Write-AllowlistedImage } "matches the process image" "an image in a file the harness's allowlist covers is still refused - an allowlist admits a mention, never an image"
    $null = New-FakeRepo "img-allowlisted-ratchet"; Add-ZorbcodeName $zcImage; Write-AllowlistedImage
    $ratchetOnly = @(Test-HordeHostNames -RepoRoot $script:repo)
    Check ($ratchetOnly.Count -eq 0) "CONTROL: the ratchet alone passes that allowlisted image, which is why images need a rule of their own"
    if ($ratchetOnly.Count -gt 0) { Show $ratchetOnly }
    ImagesPass "img-test" { Write-FakeFile "test/fixtures/processes.json" "[ { `"name`": `"zcrunner.exe`" } ]`n" } "a test's process table is not core: test/ is not checked by this rule"
    ImagesPass "img-own-folder" { Write-FakeFile "agents/zorbcode/Claims.ps1" "@('zcrunner.exe')`n" } "the harness's own folder may match its image - that is where the answer lives"
    ImagesPass "img-name-kind" { Write-FakeFile "core/spawn.ps1" "& zorbcode`n" } "a name of kind name is the ratchet's to judge, not this rule's"
    ImagesPass "img-path-kind" { Add-ZorbcodeName $zcPath; Write-FakeFile "core/follow.ps1" "'zc-chatlog-'`n" } "a name of kind path is the ratchet's to judge, not this rule's"
    ImagesPass "img-planning" { Write-FakeFile "planning/ledger/tree.md" "zcrunner.exe was matched by name`n" } "prose under planning/ is not scanned"
    # THE REGEX-ESCAPED FORM is the same image (review of PR #57, A4): a match written as a pattern.
    ImagesRefuse "img-escaped" { Write-FakeFile "core/tree.ps1" "if (`$p.Name -match '^zcrunner\.exe$') { }`n" } "matches the process image" "an image written as an escaped regular expression is matched too"
    ImagesPass "img-legacy" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe')`n"; Write-Legacy $oldEntry } "a listed legacy reader may still match an image, exactly as often as listed"
    ImagesPass "img-legacy-form" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe')`n"; Write-Legacy "Core\Old.ps1 | 1 | an old reader that matched the invented image before the rule existed" } "a legacy path is read as an allowlist path is: backslashes, any case"
    ImagesRefuse "img-legacy-other" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe')`n"; Write-FakeFile "core/new.ps1" "@('zcrunner.exe')`n"; Write-Legacy $oldEntry } "matches the process image" "a legacy entry excuses its own file and no other"
    # A COUNT, NOT A FILE (A3): the excuse covers the matches the file had, and no new one.
    ImagesRefuse "img-legacy-gains" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe', 'ZCRUNNER.EXE')`n"; Write-Legacy $oldEntry } "2 process image match(es); tools/process-image-legacy.txt allows 1 - a new match" "a legacy reader that gains an image match is refused - the excuse is a count, not a file"
    ImagesRefuse "img-legacy-gains-escaped" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe')`n`$re = 'zcrunner\.exe'`n"; Write-Legacy $oldEntry } "a new match" "an escaped form added to a legacy reader is a new match"
    ImagesRefuse "img-legacy-over" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe')`n"; Write-Legacy "core/old.ps1 | 2 | an old reader that matched the invented image before the rule existed" } "lower it to 1" "a legacy count above the file's matches must be lowered - it only shrinks"
    ImagesRefuse "img-legacy-stale" { Write-FakeFile "core/old.ps1" "# sessions`n"; Write-Legacy $oldEntry } "matches no process image" "a legacy reader that no longer matches an image must leave the list - it only shrinks"
    ImagesRefuse "img-legacy-gone" { Write-Legacy "core/gone.ps1 | 1 | a reader that has since been deleted from the tree" } "matches no process image" "a legacy reader that is gone must leave the list"
    ImagesRefuse "img-legacy-twice" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe')`n"; Write-Legacy ($oldEntry + "`n" + $oldEntry) } "listed twice" "a legacy entry listed twice is refused"
    ImagesRefuseBoth "img-legacy-bad-count" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe')`n"; Write-Legacy "core/old.ps1 | one | an old reader that matched the invented image before the rule existed" } "must be a whole number" "a legacy count that is not a whole number is refused, and its file is then reported"
    ImagesRefuseBoth "img-legacy-no-reason" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe')`n"; Write-Legacy "core/old.ps1 | 1 | old old old old" } "needs a reason" "a legacy entry without a real reason is refused, and its file is then reported"
    ImagesRefuseBoth "img-legacy-shape" { Write-FakeFile "core/old.ps1" "@('zcrunner.exe')`n"; Write-Legacy "core/old.ps1 | 1" } "a legacy line is" "a legacy line without its three parts is refused, and its file is then reported"

    # THE LEGACY LIST AGAINST origin/main (A1): an entry not there, or a count above its count, is
    # refused outright. There is no growth record for this list: it exists only to shrink to nothing.
    $legacyMore = "core/new.ps1 | 1 | a second reader added after the rule existed"
    ShrinkRefuses "sh-legacy-added" { Write-Legacy $oldEntry; Save-FakeMain; Write-Legacy ($oldEntry + "`n" + $legacyMore) } "not on origin/main" "a legacy entry added since origin/main is refused - the list only shrinks"
    ShrinkRefuses "sh-legacy-raised" { Write-Legacy $oldEntry; Save-FakeMain; Write-Legacy "core/old.ps1 | 2 | an old reader that matched the invented image before the rule existed" } "may not rise" "a legacy count raised since origin/main is refused"
    ShrinkRefuses "sh-legacy-growth-line" {
        Write-Legacy $oldEntry; Save-FakeMain; Write-Legacy ($oldEntry + "`n" + $legacyMore)
        Write-FakeFile "agents/zorbcode/growth.txt" "core/new.ps1 | 0 -> 1 | 2026-10-02 | a second reader added after the rule existed`n"
    } "not on origin/main" "a growth line admits no legacy entry"
    ShrinkPasses "sh-legacy-lowered" { Write-Legacy "core/old.ps1 | 2 | an old reader that matched the invented image before the rule existed"; Save-FakeMain; Write-Legacy $oldEntry } "a legacy count lowered since origin/main passes"
    ShrinkPasses "sh-legacy-emptied" { Write-Legacy $oldEntry; Save-FakeMain; Write-Legacy "# empty now" } "a legacy list emptied since origin/main passes"
    $nl = Shrink "sh-legacy-new" { Write-Legacy $oldEntry }
    Check ($nl.skip -eq "" -and @($nl.findings).Count -eq 0 -and (@($nl.newHosts) -join ",") -eq $legacyFile) "a legacy list that origin/main does not have is reported as new, not compared - its pull request sets its baseline"
    # A KIND MAY NOT BE DEMOTED (A2): an image turned into a path or a name leaves the image rule.
    ShrinkRefuses "sh-kind-demoted" {
        Add-ZorbcodeName $zcImage; Save-FakeMain
        Write-FakeFile "agents/zorbcode/names.txt" ("zorbcode | the invented agent harness this suite polices in place of a real one`n" + "zcrunner.exe | path | the invented harness's own process image, now said to be a path`n")
    } "processImage on origin/main" "a processImage on origin/main that is another kind here is refused - demoting it would take it out of the image rule"
    ShrinkPasses "sh-kind-promoted" {
        Add-ZorbcodeName $zcPath; Save-FakeMain
        Write-FakeFile "agents/zorbcode/names.txt" ("zorbcode | the invented agent harness this suite polices in place of a real one`n" + "zc-chatlog- | processImage | the invented fragment, now held to the stricter rule`n")
    } "a name promoted to processImage passes - the stricter rule only gains"

    Write-Host ""
    Write-Host "--- a transport is a port too: transports/<name>/ is the third family (remote plan step R5) ---" -ForegroundColor Cyan

    # Founder decision 10 of the remote design: nothing outside transports/<name>/ names a transport
    # program or its options, so the second transport is a new folder and not an engine change. The
    # same scan, the same lists and the same origin/main comparison, over a third family of folders.
    # The invented transport is zorblink; transports/Port.ps1 is the port, and belongs to no transport.
    function Add-Zorblink {
        Write-FakeFile "transports/zorblink/names.txt" "zorblink | the invented transport this suite polices in place of a real one`n"
        Write-FakeFile "transports/zorblink/Transport.ps1" "# the zorblink adapter, which may name its own transport: zorblink`n"
    }
    Passes "transport-clean" { Add-Zorblink } "CONTROL: a transport named only in its own folder passes"
    Refuses "transport-leak" { Add-Zorblink; Write-FakeFile "core/dial.ps1" "& ZORBLINK -T`n" } "is not in transports/zorblink/allowlist.txt" "a new file in core that names a transport is refused, whatever its case"
    Refuses "transport-port-file" { Add-Zorblink; Write-FakeFile "transports/Port.ps1" "# dispatches to zorblink`n" } "is not in transports/zorblink/allowlist.txt" "the port file beside the transport folders belongs to no transport, and is refused for naming one"
    Refuses "transport-no-names" { Write-FakeFile "transports/bare/Transport.ps1" "# a transport folder with no names.txt`n" } "declares no names.txt" "a transport folder with no names.txt is refused - it could not be checked"
    Refuses "transport-names-host" { Add-Zorblink; Write-FakeFile "transports/zorblink/Transport.ps1" "# zorblink, carrying a zorbterm pane`n" } "is not in hosts/zorbterm/allowlist.txt" "a transport's folder that names a host is refused"
    Refuses "host-names-transport" { Add-Zorblink; Write-FakeFile "hosts/zorbterm/adapter.ps1" "# zorbterm, reached over zorblink`n" } "is not in transports/zorblink/allowlist.txt" "a host's folder that names a transport is refused"
    ShrinkRefuses "sh-transport-removed" { Add-Zorblink; Save-FakeMain; Remove-Item -Recurse -Force -LiteralPath (Join-Path $script:repo "transports/zorblink") } "deleting its folder" "a transport folder on origin/main that is gone here is refused"
    $nt = Shrink "sh-new-transport" { Add-Zorblink }
    Check ($nt.skip -eq "" -and @($nt.findings).Count -eq 0 -and (@($nt.newHosts) -join ",") -eq "transports/zorblink") "a transport new since origin/main is reported as new under its own port, not compared"
    # THE IMAGE RULE SKIPS PORT FOLDERS, NOT FAMILIES: a file directly under transports/ - the port -
    # belongs to no transport, so it is held to the image rule like core.
    $null = New-FakeRepo "img-family-file"; Add-ZorbcodeName $zcImage; Add-Zorblink
    Write-FakeFile "transports/Port.ps1" "# if (`$p.Name -eq 'zcrunner.exe') { }`n"
    $famImg = @(Test-HordeProcessImages -RepoRoot $script:repo)
    Check ((Says $famImg "matches the process image") -and $famImg.Count -eq 1) "a file directly under a family folder, in no port's folder, is held to the image rule"
    if ($famImg.Count -ne 1) { Show $famImg }
    $null = New-FakeRepo "img-transport-own"; Add-ZorbcodeName $zcImage; Add-Zorblink
    Write-FakeFile "transports/zorblink/Transport.ps1" "# zorblink`n"
    Write-FakeFile "transports/zorblink/Image.ps1" "# zorblink checks no harness image`n"
    Check (@(Test-HordeProcessImages -RepoRoot $script:repo).Count -eq 0) "CONTROL: a transport's own folder that matches no image passes the image rule"
} finally {
    Remove-Item -Recurse -Force -LiteralPath $fake -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "--- this repository ---" -ForegroundColor Cyan

# CONTROL: each real port's names are armed - EVERY one of them, for every host and every harness. Its
# own names.txt is copied into a throwaway repository with one file that uses one declared name; the
# scan must refuse that file, once per name. Without this, a name that matched nothing would make the
# real run below pass by seeing nothing. (The first version planted only the first name.)
$realHosts = @(Get-ChildItem -LiteralPath (Join-Path $root "hosts") -Directory -ErrorAction SilentlyContinue)
Check ($realHosts.Count -ge 1) ("CONTROL: this repository has at least one host to check (" + $realHosts.Count + ")")
$realAgents = @(Get-ChildItem -LiteralPath (Join-Path $root "agents") -Directory -ErrorAction SilentlyContinue)
Check ($realAgents.Count -ge 1) ("CONTROL: this repository has at least one harness to check (" + $realAgents.Count + ")")
$realTransports = @(Get-ChildItem -LiteralPath (Join-Path $root "transports") -Directory -ErrorAction SilentlyContinue)
Check ($realTransports.Count -ge 1) ("CONTROL: this repository has at least one transport to check (" + $realTransports.Count + ")")
$realMessengers = @(Get-ChildItem -LiteralPath (Join-Path $root "messengers") -Directory -ErrorAction SilentlyContinue)
Check ($realMessengers.Count -ge 1) ("CONTROL: this repository has at least one messenger to check (" + $realMessengers.Count + ")")
$realSurfaces = @(Get-ChildItem -LiteralPath (Join-Path $root "surfaces") -Directory -ErrorAction SilentlyContinue)
Check ($realSurfaces.Count -ge 1) ("CONTROL: this repository has at least one surface to check (" + $realSurfaces.Count + ")")
$realRelays = @(Get-ChildItem -LiteralPath (Join-Path $root "relays") -Directory -ErrorAction SilentlyContinue)
Check ($realRelays.Count -ge 1) ("CONTROL: this repository has at least one relay to check (" + $realRelays.Count + ")")
$realWakers = @(Get-ChildItem -LiteralPath (Join-Path $root "wakers") -Directory -ErrorAction SilentlyContinue)
Check ($realWakers.Count -ge 1) ("CONTROL: this repository has at least one waker to check (" + $realWakers.Count + ")")
foreach ($h in @($realHosts + $realAgents + $realTransports + $realMessengers + $realSurfaces + $realRelays + $realWakers)) {
    $port = Split-Path -Leaf (Split-Path -Parent $h.FullName)
    $np = Join-Path $h.FullName "names.txt"
    # NOT WRAPPED IN @(). Read-HordeHostTable returns its list as ONE object (`return , $rows`), so
    # @() made a one-element array holding the whole list: the first run of this loop reported one
    # name for a host that declares three, and planted all three on one line.
    $declared = Read-HordeHostTable -Path $np
    Check ($declared.Count -ge 1) ("CONTROL: " + $port + "/" + $h.Name + " declares at least one name (" + $declared.Count + ")")
    foreach ($row in $declared) {
        $script:repo = Join-Path $env:TEMP ("horde-hostnames-arm-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
        try {
            Write-FakeFile ($port + "/" + $h.Name + "/names.txt") ([System.IO.File]::ReadAllText($np))
            Write-FakeFile "core/planted.ps1" ("# " + $row.cells[0] + "`n")
            $armed = @(Test-HordeHostNames -RepoRoot $script:repo)
            Check ((Says $armed ("is not in " + $port + "/" + $h.Name + "/allowlist.txt")) -and $armed.Count -eq 1) ("CONTROL: " + $port + "/" + $h.Name + " - its declared name '" + $row.cells[0] + "', planted in core/, is caught")
            if ($armed.Count -ne 1) { Show $armed }
        } finally {
            Remove-Item -Recurse -Force -LiteralPath $script:repo -ErrorAction SilentlyContinue
        }
    }
}

# EVERY DECLARED PROCESS IMAGE IS ARMED for the image rule too: planted in core/ of a throwaway
# repository holding only its port's names.txt, with no legacy reader listed, it must be refused.
# NOT WRAPPED IN @(): the list comes back as one object, as Read-HordeHostTable's does (see above).
$realImages = Get-HordePortNamesOfKind -RepoRoot $root -Kind "processImage"
Check ($realImages.Count -ge 1) ("CONTROL: at least one port declares a processImage, so the image rule below has something to look for (" + $realImages.Count + ")")
foreach ($img in $realImages) {
    $script:repo = Join-Path $env:TEMP ("horde-hostnames-img-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    try {
        Write-FakeFile ($img.own + "/names.txt") ([System.IO.File]::ReadAllText((Join-Path $root ($img.own + "/names.txt"))))
        Write-FakeFile "core/planted.ps1" ("# " + $img.name + "`n")
        $armed = @(Test-HordeProcessImages -RepoRoot $script:repo)
        Check ((Says $armed ("matches the process image '" + $img.name + "'")) -and $armed.Count -eq 1) ("CONTROL: " + $img.own + " - its declared process image '" + $img.name + "', planted in core/, is refused by the image rule")
        if ($armed.Count -ne 1) { Show $armed }
    } finally {
        Remove-Item -Recurse -Force -LiteralPath $script:repo -ErrorAction SilentlyContinue
    }
}
$realImageFindings = @(Test-HordeProcessImages -RepoRoot $root)
Check ($realImageFindings.Count -eq 0) "core matches no process image name, beyond the exact counts tools/process-image-legacy.txt lists"
Show $realImageFindings

$real = @(Test-HordeHostNames -RepoRoot $root)
Check ($real.Count -eq 0) "no file outside a port's folder names that port, beyond what its allowlist lists exactly"
Show $real

# NEVER A SILENT PASS. When this checkout cannot be compared with origin/main, or a host is new on
# this branch, the suite says so on a [SKIP] line: that part was not measured, and must not read as
# passed. tools/Mutate.ps1 runs suites in a copy with no .git, so there it is always skipped; the
# throwaway repositories above are what prove the comparison itself.
$shrink = Test-HordeHostShrink -RepoRoot $root
if ($shrink.skip) {
    Write-Host ("  [SKIP] the lists were not compared with origin/main: " + $shrink.skip) -ForegroundColor Yellow
} else {
    foreach ($n in @($shrink.newHosts)) {
        Write-Host ("  [SKIP] " + $n + " is not on origin/main, so its lists are not compared - its pull request sets their baseline") -ForegroundColor Yellow
    }
    Check (@($shrink.findings).Count -eq 0) "no port's lists grew since origin/main: no new entry, no raised count, no name removed"
    Show $shrink.findings
}

Complete-HordeSuite -Success "nothing outside hosts/<name>/ or agents/<name>/ names a port it may not"
