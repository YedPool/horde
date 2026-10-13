# test/lib/SuiteFiles.ps1 - the one list of where Horde's test suites live, so that the gate, and
# test/test-suite.ps1's check of how every suite is built, read the same list.
#
# WHY. A suite in a folder the gate does not look in is never run, and a suite nobody runs is worse
# than none: it reads as coverage. transports/local/test/test-local.ps1 (plan step R4) was that suite
# - beside its transport, as hosts/<name>/test/ suites are, and outside the test/test-*.ps1 glob the
# gate used (review of PR #42, 2026-09-30). So the folders are listed once, here, and
# Get-HordeStraySuiteFiles fails any test-*.ps1 outside them.
#
# THE GATE runs every file Get-HordeSuiteFiles returns:
#   test/test-*.ps1
#   hosts/*/test/test-*.ps1         a host's own suites (D12)
#   transports/*/test/test-*.ps1    a transport's own suites (remote design, decision 10)
#   agents/*/test/test-*.ps1        an agent harness's own suites (engines plan, E1)
#   messengers/*/test/test-*.ps1    a messenger's own suites (remote plan R21; review of #102). Its
#                                   test/Fixture.ps1 is not a suite: only test-*.ps1 is run.
#   surfaces/*/test/test-*.ps1      a surface's own suites (decisions design 2026-10-06, decision 2)
#   relays/*/test/test-*.ps1        a relay's own suites (relay PR 8a: the hosted relay's Worker suite
#                                   lives beside it, so only its folder names the host). Its
#                                   test/Fixture.ps1 is not a suite: only test-*.ps1 is run.
#
# NOT SUITES: anything under test/fixtures/. Those files are inputs that suites read or run as
# fixtures - test/fixtures/ledger holds test-*.ps1 files on purpose, as the trees a ledger cites.

$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test", "messengers/*/test", "surfaces/*/test", "relays/*/test")
$script:HordeSuiteDataFolder = "test/fixtures"

# MACHINE-BOUND SUITES: the gate runs them, but only on a machine with the founder's interactive logon,
# never on the remote test box (CONTRIBUTING 15, rule 5). Each is here because it was measured failing
# there and passing here, or says so in its own header. Listed once, in the repository (issue #89).
# Today only test/test-suite.ps1 reads it; the batch scripts and the remote gate do not yet.
$script:HordeMachineBoundSuites = [ordered]@{
    "transports/local/test/test-local.ps1" = "the local pipe and integrity levels; its Administrators-owned case runs only from an elevated token launched from PowerShell, and the suite exits 3 when it skips that case (issue #89)"
    "transports/local/test/test-node-serve-local.ps1" = "the real local pipe, from an interactive logon (its header)"
    "transports/local/test/test-hub-serve-local.ps1" = "the real local pipe, from an interactive logon (its header)"
    "transports/ssh/test/test-sshd-local.ps1" = "this machine's own server for the transport, run as the suite's own child on 127.0.0.1 (remote plan R16)"
    "transports/local/test/test-hub-act-local.ps1" = "the real local pipe, from an interactive logon (its header)"
    "transports/ssh/test/test-listen-local.ps1" = "horde listen runs this machine's own server for the transport as the suite's child on 127.0.0.1, and the hub's end is the real local pipe (remote plan R17a)"
    "transports/ssh/test/test-mesh-act-local.ps1" = "horde listen runs this machine's own server for the transport as the suite's child on 127.0.0.1, and horde hub serve -Listen takes the node's link on the real local pipe (mesh v1, remote plan R19 over R17c)"
    "test/test-transport-conformance.ps1" = "its [local] cases: on the always-on box its 27 [local] checks fail on main 54d97b3 exactly as on #85, and pass here (2026-10-05)"
    "test/test-window-follow.ps1" = "two real windows, one of another process, and what Windows tells the taskbar: an interactive logon (its header); with no interactive desktop it follows nothing and exits 3"
    "test/test-services-window.ps1" = "a real window of the suite's own child, asked to close: an interactive logon (its header); with no desktop it checks only what needs no window and exits 3"
    "surfaces/webview2/test/test-webview2-window.ps1" = "opens a real window drawn by the web engine, which needs the engine installed and an interactive logon (its header)"
}

function Get-HordeMachineBoundSuites {
    # The machine-bound suites, as { path; why }, paths relative to the repository with forward slashes.
    return @($script:HordeMachineBoundSuites.Keys | ForEach-Object { [pscustomobject]@{ path = $_; why = $script:HordeMachineBoundSuites[$_] } })
}

function Get-HordeSuiteFiles {
    # Every suite the gate runs, as FileInfo.
    param([Parameter(Mandatory = $true)][string]$Root)
    $out = New-Object System.Collections.ArrayList
    foreach ($pattern in $script:HordeSuiteFolders) {
        $parts = $pattern -split "/"
        $dirs = @(Get-Item -LiteralPath $Root)
        foreach ($p in $parts) {
            $next = @()
            foreach ($d in $dirs) {
                if ($p -eq "*") { $next += @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue) }
                else { $c = Join-Path $d.FullName $p; if (Test-Path -LiteralPath $c -PathType Container) { $next += @(Get-Item -LiteralPath $c) } }
            }
            $dirs = $next
        }
        foreach ($d in $dirs) {
            # -Filter alone also matches test-x.ps1x on Windows (8.3 names); the extension is checked exactly.
            foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter "test-*.ps1" -File | Where-Object { $_.Extension -ceq ".ps1" })) { [void]$out.Add($f) }
        }
    }
    # In the order of the folder list, then of each folder listing: the gate runs them in this order.
    return @($out)
}

function Get-HordeStraySuiteFiles {
    # Every test-*.ps1 under -Root that the gate would not run, outside .git and test/fixtures/, as
    # paths relative to -Root with forward slashes. Empty means no suite is invisible.
    param([Parameter(Mandatory = $true)][string]$Root)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $known = @{}
    foreach ($f in @(Get-HordeSuiteFiles -Root $Root)) { $known[$f.FullName.ToLowerInvariant()] = $true }
    $stray = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $rootFull -Filter "test-*.ps1" -File -Recurse -Force | Where-Object { $_.Extension -ceq ".ps1" })) {
        $rel = ($f.FullName.Substring($rootFull.Length).TrimStart('\', '/')) -replace '\\', '/'
        if ($rel -like ".git/*" -or $rel -like ($script:HordeSuiteDataFolder + "/*")) { continue }
        if (-not $known.ContainsKey($f.FullName.ToLowerInvariant())) { [void]$stray.Add($rel) }
    }
    $arr = [string[]]$stray.ToArray(); [Array]::Sort($arr, [System.StringComparer]::Ordinal)
    return @($arr)
}

# THE MUTATION SPECS: every *.psd1 under any folder named "mutations", at any depth, outside .git and
# test/fixtures/. One rule, read by test/test-mutation-specs.ps1 (every find string applies) and by
# tools/Mutate.ps1 -Changed (which mutants a change selects), so the two cannot disagree about what a
# spec is. Each had its own search before, and -Changed missed specs the guard checked: a spec in a
# subfolder of mutations/, and any mutations folder but the four suite folders' (review of PRs #62
# and #63, 2026-10-02).
function Get-HordeMutationSpecFiles {
    # Every spec under -Root, as FileInfo, in ordinal order of its path relative to -Root.
    param([Parameter(Mandatory = $true)][string]$Root)
    $specRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $found = New-Object System.Collections.ArrayList
    foreach ($sf in @(Get-ChildItem -LiteralPath $specRoot -Filter "*.psd1" -File -Recurse -Force | Where-Object { $_.Extension -ceq ".psd1" })) {
        $specRel = $sf.FullName.Substring($specRoot.Length + 1).Replace('\', '/')
        if ($specRel.StartsWith(".git/") -or $specRel.StartsWith($script:HordeSuiteDataFolder + "/")) { continue }
        # A folder named exactly "mutations" somewhere between -Root and the file.
        $folders = @($specRel.Split('/') | Select-Object -SkipLast 1)
        if ($folders -cnotcontains "mutations") { continue }
        [void]$found.Add([pscustomobject]@{ rel = $specRel; file = $sf })
    }
    $sorted = @($found.ToArray())
    [Array]::Sort([string[]]@($sorted | ForEach-Object { $_.rel }), [object[]]$sorted, [System.StringComparer]::Ordinal)
    return @($sorted | ForEach-Object { $_.file })
}

# A SUITE MUST NOT CHANGE WHAT OTHER PROCESSES OF THE USER SEE, AND A DRIVE LETTER IS SEEN BY ALL OF
# THEM. Until 2026-10-13 two suites made real drive letters, one aimed at a host that does not exist.
# A letter lives in the user's logon session, not in the process that made it: while it stood, a fresh
# powershell of any other session printed "Attempting to perform the InitializeDefaultDrives operation
# on the 'FileSystem' provider failed" and took 1.4 s to start where 0.2 is usual (measured that day,
# 7 of 8 starts), another lane's command-line suite failed on the line, and every mutation run
# repeated it hundreds of times. So no test file makes a drive letter: the code asks its questions of
# a drive through one function each (core/PathText.ps1), and a suite answers them itself.
# ONE FILE IS LET BY, because one question can only be asked of Windows: what it says of a letter
# that stands for a folder. That file makes its letter over a folder that exists on this machine's
# own drive, which every other process can reach, and says so where it does.
# WHAT THIS SEES, in the text of every .ps1 file in a folder that holds a suite, and below it: the
# name DefineDosDevice outside a comment; a command named subst, or net with use after it, or
# New-SmbMapping, or New-PSDrive with -Persist; the name MapNetworkDrive outside a comment; and a
# quoted text that is itself such a command line (for cmd.exe).
# WHAT IT DOES NOT SEE: a command whose name is put together when the suite runs, and a program
# of another language that a suite starts. A POWERSHELL DRIVE WITHOUT -Persist IS NOT A DRIVE LETTER:
# it is the process's own, and no other process sees it.
$script:HordeDriveLetterFile = "test/test-path-text.ps1"

function Get-HordeDriveLetterMakersIn {
    # What in the text of one PowerShell file makes a drive letter other processes would see: the
    # words for each thing found, in the order found, and nothing when there is none.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    # MOST FILES HOLD NONE OF THE WORDS, and are not parsed: parsing every test file took this
    # guard's suite from 8 s to 23 (measured 2026-10-13). A file that holds a word is read properly.
    if ($Text -notmatch '(?i)DosDevice|subst|net1?(?:\.exe)?["'']?\s+["'']?use|SmbMapping|-Persist|NetworkDrive') { return @() }
    $tokens = $null; $problems = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$problems)
    $found = New-Object System.Collections.ArrayList
    $say = { param([string]$What) if ($found -cnotcontains $What) { [void]$found.Add($What) } }
    # The two names are put together here, so that this file, which is a test file too, does not
    # hold what it looks for.
    $systemCall = "Define" + "DosDevice"
    $scriptingCall = "Map" + "NetworkDrive"
    foreach ($token in @($tokens)) {
        if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) { continue }
        if ($token.Text.IndexOf($systemCall, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { & $say $systemCall }
        if ($token.Text.IndexOf($scriptingCall, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { & $say $scriptingCall }
        # A quoted command line, as one handed to cmd.exe: the program's name and then a drive
        # letter, a switch or the start of a value - which the words "a subst drive" are not.
        if ($token -is [System.Management.Automation.Language.StringToken]) {
            if ($token.Text -match '(?<![A-Za-z0-9_.-])subst(?:\.exe)?["'']?\s+(?:[A-Za-z]:|/[Dd]\b|["''$(])') { & $say "subst" }
            if ($token.Text -match '(?<![A-Za-z0-9_.-])net1?(?:\.exe)?["'']?\s+use\s+(?:[A-Za-z*]:|/|\\\\|["''$(])') { & $say "net use" }
        }
    }
    foreach ($command in @($tree.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))) {
        $name = "" + $command.GetCommandName()
        if ($name -eq "") { continue }
        $leaf = ($name -split '[\\/]')[-1]
        $rest = @($command.CommandElements | Select-Object -Skip 1 | ForEach-Object { "" + $_.Extent.Text })
        if ($leaf -match '\Asubst(?:\.exe)?\z') { & $say "subst" }
        if ($leaf -match '\Anet1?(?:\.exe)?\z' -and @($rest | Where-Object { $_ -match '\A["'']?use["'']?\z' }).Count -gt 0) { & $say "net use" }
        if ($leaf -match '\ANew-SmbMapping\z') { & $say "New-SmbMapping" }
        if ($leaf -match '\ANew-PSDrive\z' -and @($rest | Where-Object { $_ -match '\A-Persist' }).Count -gt 0) { & $say "New-PSDrive -Persist" }
    }
    return @($found.ToArray())
}

function Get-HordeDriveLetterMakers {
    # Every test file under -Root that makes a drive letter, but for the one file that may, as
    # { file; what }: file relative to -Root with forward slashes, what the words for what was found.
    # Empty means no suite changes what other processes see. Every .ps1 file in a folder that holds a
    # suite is read, and every one below such a folder: a helper, a fixture and a racer are run by
    # suites too.
    param([Parameter(Mandatory = $true)][string]$Root)
    $base = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $folders = New-Object System.Collections.ArrayList
    foreach ($suite in @(Get-HordeSuiteFiles -Root $Root)) { if ($folders -notcontains $suite.DirectoryName) { [void]$folders.Add($suite.DirectoryName) } }
    $seen = @{}
    $makers = New-Object System.Collections.ArrayList
    foreach ($folder in $folders) {
        foreach ($script in @(Get-ChildItem -LiteralPath $folder -Filter "*.ps1" -File -Recurse -Force | Where-Object { $_.Extension -ceq ".ps1" })) {
            if ($seen.ContainsKey($script.FullName.ToLowerInvariant())) { continue }
            $seen[$script.FullName.ToLowerInvariant()] = $true
            $rel = $script.FullName.Substring($base.Length + 1).Replace('\', '/')
            if ($rel -ceq $script:HordeDriveLetterFile) { continue }
            $what = @(Get-HordeDriveLetterMakersIn -Text ([System.IO.File]::ReadAllText($script.FullName)))
            if ($what.Count -gt 0) { [void]$makers.Add([pscustomobject]@{ file = $rel; what = ($what -join ", ") }) }
        }
    }
    return @($makers.ToArray() | Sort-Object -Property file)
}
