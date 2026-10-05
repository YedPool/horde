# ON EVERY INPUT THE LINK SUITES USE, DOES THE LINK WALK ANSWER AS THE CODE IT REPLACED?
#
# test/test-link-walk.ps1 compares the new walk and writer with the old (test/fixtures/link-walk/
# reference.ps1) on a corpus of its own. This suite takes the inputs from the suites themselves: the
# fuzz corpus of test-link-protocol, the refusals of test-link-contracts, the overlay's documents, and
# (once remote plan step R12a is on main) the node's answers. It copies the repository to a temporary
# folder, appends to that copy's remote/Contract.ps1 and remote/Protocol.ps1 a block that wraps each replaced
# function (Test-HordeLinkValue, Test-HordeLinkFrame, Test-HordeProtocolLimits, ConvertTo-HordeWireText)
# so every call also runs the old one on the same arguments and writes any difference to a log, and
# runs each suite there. The wrapped call still returns the new answer, so each suite must pass as it
# does unwrapped. The working tree is never touched.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

# The suites that call the replaced functions. test-journal, test-clock and test-transport-port load the
# link code but call none of them (measured 2026-10-02: no call logged), and the transports carry text
# only, so the local transport's suites would compare nothing either.
$suites = @("test\test-link-protocol.ps1", "test\test-link-contracts.ps1", "test\test-overlay.ps1")
# test-node-serve-capacity is left out: its one 256-session frame takes the old code minutes.
foreach ($s in @("test\test-node-serve.ps1")) { if (Test-Path -LiteralPath (Join-Path $root $s)) { $suites += $s } }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-walk-diff-" + [guid]::NewGuid().ToString("N"))
$copy = Join-Path $work "horde"
$log = Join-Path $work "diff.log"

# The block appended to each copied file. It captures the function the file just defined, then
# replaces it with a wrapper; a file dot-sourced again defines the real one again first, so the
# wrapper never wraps itself.
function Read-Shared {
    # A file another process may still hold open (a suite's grandchild inherits its output handle), read
    # without asking for it alone.
    param([string]$Path)
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try { $sr = New-Object System.IO.StreamReader($fs); return $sr.ReadToEnd() } finally { $fs.Dispose() }
}
function Read-Lines { param([string]$Path) return @((Read-Shared $Path) -split "`r?`n" | Where-Object { $_ -ne "" }) }

$wrapTemplate = @'

# ---- appended by test/test-link-walk-suites.ps1: compare with the replaced code on every call ----
. (Join-Path (Split-Path -Parent $PSScriptRoot) "test\fixtures\link-walk\reference.ps1")
function Get-HordeWalkDiffOutcome {
    # Bound is the wrapper's own PSBoundParameters: splatted by name, so each function gets exactly the
    # arguments the caller gave, and its own defaults for the rest.
    param([scriptblock]$Call, [hashtable]$Bound)
    try { $r = @(& $Call @Bound); return @(("ANSWER " + $r.Count + ":`n" + ($r -join "`n")), $r, $null) }
    catch { return @(("THROW: " + $_.Exception.Message), $null, $_) }
}
function Write-HordeWalkDiff {
    param([string]$Name, [string]$New, [string]$Old)
    $line = "CALL " + $Name
    if (-not [string]::Equals($New, $Old, [System.StringComparison]::Ordinal)) { $line = "DIFF " + $Name + " new=" + ($New -replace "[`r`n]+", " | ") + " old=" + ($Old -replace "[`r`n]+", " | ") }
    [System.IO.File]::AppendAllText($env:HORDE_WALK_DIFF_LOG, $line + "`r`n")
}
'@
$wrapOne = @'
${script:HordeWalkDiffNew_NAME} = ${function:NAME}
function NAME {
    PARAMS
    $n = Get-HordeWalkDiffOutcome -Call ${script:HordeWalkDiffNew_NAME} -Bound $PSBoundParameters
    if ($PSBoundParameters.ContainsKey("Walk")) {
        # Test-HordeLinkValue given a kept record (-Walk) has no counterpart in the old code, which took
        # the schema itself: its caller, Test-HordeLinkFrame, is compared whole instead.
        [System.IO.File]::AppendAllText($env:HORDE_WALK_DIFF_LOG, "SKIP NAME`r`n")
    } else {
        $o = Get-HordeWalkDiffOutcome -Call ${function:NAMEReference} -Bound $PSBoundParameters
        Write-HordeWalkDiff -Name "NAME" -New $n[0] -Old $o[0]
    }
    if ($null -ne $n[2]) { throw $n[2] }
    return $n[1]
}
'@

try {
    New-Item -ItemType Directory -Path $copy | Out-Null
    # Tracked files and new ones not yet committed, so the suite also checks a working tree mid-change.
    foreach ($f in @(& git -C $root ls-files --cached --others --exclude-standard)) {
        $src = Join-Path $root $f
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }
        $dst = Join-Path $copy $f
        $dir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst
    }
    Check (Test-Path -LiteralPath (Join-Path $copy "remote\Contract.ps1")) "CONTROL: the repository is copied, remote/ included"
    $plan = @{ "remote\Contract.ps1" = @("Test-HordeLinkValue", "Test-HordeLinkFrame"); "remote\Protocol.ps1" = @("Test-HordeProtocolLimits", "ConvertTo-HordeWireText") }
    foreach ($file in @($plan.Keys)) {
        $text = $wrapTemplate
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $copy $file), [ref]$null, [ref]$null)
        foreach ($name in $plan[$file]) {
            # The wrapper takes the real function's own parameters, read from its source.
            $def = $ast.Find({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -ceq $name }, $true)
            $params = $def.Body.ParamBlock.Extent.Text
            $text += "`r`n" + $wrapOne.Replace("PARAMS", $params).Replace("NAME", $name)
        }
        [System.IO.File]::AppendAllText((Join-Path $copy $file), $text)
    }
    $env:HORDE_WALK_DIFF_LOG = $log
    [System.IO.File]::WriteAllText($log, "")
    $empty = Join-Path $work "empty-stdin.txt"
    [System.IO.File]::WriteAllText($empty, "")
    foreach ($s in $suites) {
        $before = @(Read-Lines $log).Count
        $out = Join-Path $work ((Split-Path -Leaf $s) + ".out")
        $p = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $copy $s)) -RedirectStandardOutput $out -RedirectStandardError ($out + ".err") -RedirectStandardInput $empty -NoNewWindow -PassThru
        $null = $p.Handle
        $p.WaitForExit()
        $text = Read-Shared $out
        $lines = @(Read-Lines $log)
        $mine = @()
        if ($lines.Count -gt $before) { $mine = @($lines[$before..($lines.Count - 1)]) }
        $calls = @($mine | Where-Object { $_ -like "CALL *" -or $_ -like "DIFF *" }).Count
        $diffs = @($mine | Where-Object { $_ -like "DIFF *" })
        $banner = [regex]::Match($text, '(?m)^==== .* ====\s*$').Value.Trim()
        Check ($p.ExitCode -eq 0 -and $banner -ne "" -and $banner -notlike "*FAILURE*") ("$s passes with every call compared (exit " + $p.ExitCode + ": " + $banner + ")")
        if ($p.ExitCode -ne 0) {
            $why = @($text -split "`r?`n" | Where-Object { $_ -like "*[[]FAIL]*" -or $_ -like "*[[]ERROR]*" } | Select-Object -First 3)
            $why += @(Read-Lines ($out + ".err") | Select-Object -First 3)
            foreach ($w in $why) { Write-Host ("         " + $w) -ForegroundColor DarkYellow }
        }
        foreach ($d in @($diffs | Select-Object -First 5)) { Write-Host ("         " + $d.Substring(0, [Math]::Min(600, $d.Length))) -ForegroundColor DarkYellow }
        Check ($calls -gt 0 -and $diffs.Count -eq 0) ("$s : " + $calls + " calls compared, " + $diffs.Count + " differ")
    }
    $all = @(Read-Lines $log)
    foreach ($name in @("Test-HordeLinkValue", "Test-HordeLinkFrame", "Test-HordeProtocolLimits", "ConvertTo-HordeWireText")) {
        $n = @($all | Where-Object { $_ -ceq ("CALL " + $name) -or $_ -clike ("DIFF " + $name + " *") }).Count
        # Test-HordeLinkValue is compared where it is called with a schema of its own (the contract
        # documents); everywhere else it is part of Test-HordeLinkFrame, compared whole.
        $least = 20
        if ($name -ceq "Test-HordeLinkValue") { $least = 3 }
        Check ($n -ge $least) ("CONTROL: " + $name + " was compared " + $n + " times across the suites")
    }
} finally {
    Remove-Item Env:\HORDE_WALK_DIFF_LOG -ErrorAction SilentlyContinue
    if ((Split-Path -Leaf $work) -match '^horde-walk-diff-[0-9a-f]{32}$') { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

Complete-HordeSuite -Success "every link suite passes with each call of the new walk and writer compared against the code they replaced, and none differs"
