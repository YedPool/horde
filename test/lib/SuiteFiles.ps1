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
#
# NOT SUITES: anything under test/fixtures/. Those files are inputs that suites read or run as
# fixtures - test/fixtures/ledger holds test-*.ps1 files on purpose, as the trees a ledger cites.

$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test")
$script:HordeSuiteDataFolder = "test/fixtures"

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
