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
    "test/test-transport-conformance.ps1" = "its [local] cases: on the always-on box its 27 [local] checks fail on main 54d97b3 exactly as on #85, and pass here (2026-10-05)"
    "test/test-window-follow.ps1" = "two real windows, one of another process, and what Windows tells the taskbar: an interactive logon (its header); with no interactive desktop it follows nothing and exits 3"
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
