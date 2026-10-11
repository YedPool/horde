# CAN ANYTHING IN remote/ OR relay/ START A PROGRAM OR A SHELL?
#
# Plan step R1 (planning/execution-plan-remote.md) implies it: the link is an allowlisted command
# protocol, never a remote shell, so the code beside the verb table must not hold one either.
# tools/ExecScan.ps1 reads every file's syntax tree against an allowlist on every axis; this suite
# proves it refuses each of the forms in test/fixtures/link/shell-control.ps1 for its own reason,
# passes a file written the way remote/ is, and finds nothing in remote/ itself.
#
# SECTION II holds relay/ (relay design 2026-10-09) to the same promise under the wider relay profile
# of tools/ExecScan.ps1: every form of the remote control file is still refused under it, the one
# admitted Add-Type form is the only compile, and test/fixtures/relay/exec-control.ps1 names each
# other form's refusal.
#
# WHY A SUITE OF ITS OWN. These checks were section I of test/test-link-contracts.ps1. The exec-scan
# mutation spec reruns its suite once per mutant, and a mutant of tools/ExecScan.ps1 can change only
# this section; measured 2026-10-02 on the always-on box, the whole suite took 59.6 s and this section
# 2.0 s of it, so the spec's 41 mutants spent about 40 minutes re-proving the verb table and timed out
# at 30. Moved verbatim: every check, its text and its count are the same.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }

$fx = Join-Path $here "fixtures\link"

function Says {
    # Is there a finding containing Text? A boolean, never the matching items.
    param($Findings, [string]$Text)
    # Contains, not -like: a path such as $.repos[0] holds brackets, which -like reads as a pattern.
    return (@($Findings | Where-Object { "$_".Contains($Text) }).Count -gt 0)
}
function Show { param($Findings) foreach ($f in @($Findings)) { Write-Host ("         finding: " + $f) -ForegroundColor DarkYellow } }
Write-Host ""
Write-Host "--- I. nothing in remote/ can start a program or a shell ---" -ForegroundColor Cyan

# The verb table cannot express a shell; this proves the code beside it does not hold one either.
# remote/ calls core and the adapters, which run what they run; it never starts anything itself.
# tools/ExecScan.ps1 reads each file's syntax tree against an ALLOWLIST on every axis, because the
# banned-name list it replaced caught 3 of the 27 ways to run something that the review
# of PR #40 wrote (2026-10-01), and its second version, which still kept lists of banned methods and
# types, let 7 of the verification's forms through. Every axis is now an allowlist (tools/ExecScan.ps1).
. (Join-Path $root "tools\ExecScan.ps1")
$known = Get-HordeExecFunctionNames -Roots @(Join-Path $root "remote")
Check ($known.Contains("Test-HordeLinkFrame") -and -not $known.Contains("Invoke-HordeRead")) "CONTROL: the functions remote/ defines are read, and core's are not: only the listed core functions may be called, never Invoke-HordeRead, which runs the block it is given"

function Get-LineFindings {
    param($Findings, [int]$Line)
    return @($Findings | Where-Object { "$_".StartsWith("line " + $Line + ": ") })
}
$ctlPath = Join-Path $fx "shell-control.ps1"
$ctl = @(Get-HordeExecFindings -Path $ctlPath -Known $known)
$ctlAst = [System.Management.Automation.Language.Parser]::ParseFile($ctlPath, [ref]$null, [ref]$null)
$forms = @($ctlAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
Check ($forms.Count -eq 94) ("CONTROL: the control file holds 94 forms - the review's 27, the first scan's 9, the verification's 13, 44 that each isolate one rule, and a class method (found " + $forms.Count + ")")
foreach ($form in $forms) {
    $hits = @(Get-LineFindings $ctl $form.Extent.StartLineNumber)
    Check ($hits.Count -ge 1) ("CONTROL: the form " + $form.Name + " is refused")
}
# Each form's own reason, so a rule switched off is seen even where another rule also catches the form.
$expectCount = 0
$lineNo = 0
foreach ($text in [System.IO.File]::ReadAllLines($ctlPath)) {
    $lineNo++
    $m = [regex]::Match($text, '#\s*expect:\s*(.+?)\s*$')
    if (-not $m.Success -or $text.TrimStart().StartsWith("#")) { continue }
    $expectCount++
    $want = $m.Groups[1].Value
    $hits = @(Get-LineFindings $ctl $lineNo)
    Check (@($hits | Where-Object { "$_".Contains($want) }).Count -ge 1) ("CONTROL: line " + $lineNo + " is refused because: " + $want)
    if (@($hits | Where-Object { "$_".Contains($want) }).Count -eq 0) { Show $hits }
}
Check ($expectCount -eq 99) ("CONTROL: 99 lines of the control file name their reason (found " + $expectCount + ")")
$clean = @(Get-HordeExecFindings -Path (Join-Path $fx "shell-clean.ps1") -Known $known)
Check ($clean.Count -eq 0) "CONTROL: a file written the way remote/ is written - its loader lines, allowlisted cmdlets, core functions, .NET types that start nothing - has no finding"; Show $clean
$broken = @(Get-HordeExecFindings -Path (Join-Path $fx "shell-unparsed.ps1") -Known $known)
Check (Says $broken "does not parse") "a file that does not parse is a finding, never silence"
$remoteFiles = @(Get-ChildItem -LiteralPath (Join-Path $root "remote") -Filter "*.ps1" -Recurse)
Check ($remoteFiles.Count -ge 1) "there is code in remote/ to check"
foreach ($file in $remoteFiles) {
    $got = @(Get-HordeExecFindings -Path $file.FullName -Known $known)
    Check ($got.Count -eq 0) ("remote/" + $file.Name + " starts no program and no shell"); Show $got
}

Write-Host ""
Write-Host "--- II. nothing in relay/ can start a program or a shell, under its wider profile ---" -ForegroundColor Cyan

# relay/ reads text from an untrusted relay, so it is held to the same promise as remote/, under the
# relay profile of tools/ExecScan.ps1: the cryptography types it needs, and one form of Add-Type.
$rfx = Join-Path $here "fixtures\relay"
$relayKnown = Get-HordeExecFunctionNames -Roots @(Join-Path $root "relay")
Check ($relayKnown.Contains("Read-HordeRelayEnvelope") -and -not $relayKnown.Contains("Test-HordeLinkFrame")) "CONTROL: the functions relay/ defines are read, and remote's are not"
$before = ($script:HordeExecCmdlets -join ",") + "|" + ($script:HordeExecTypes -join ",") + "|" + ($script:HordeExecInstanceMethods -join ",") + "|" + (@($script:HordeExecStatic.Keys | Sort-Object) -join ",") + "|" + ($script:HordeExecStatic["array"] -join ",")
$rctlPath = Join-Path $rfx "exec-control.ps1"
$rctl = @(Get-HordeExecRelayFindings -Path $rctlPath -Known $relayKnown)
$after = ($script:HordeExecCmdlets -join ",") + "|" + ($script:HordeExecTypes -join ",") + "|" + ($script:HordeExecInstanceMethods -join ",") + "|" + (@($script:HordeExecStatic.Keys | Sort-Object) -join ",") + "|" + ($script:HordeExecStatic["array"] -join ",")
Check ($before -ceq $after -and $script:HordeExecCmdlets -cnotcontains "Add-Type") "after a relay scan the remote lists are exactly as they were"
$rLines = 0
$lineNo = 0
foreach ($text in [System.IO.File]::ReadAllLines($rctlPath)) {
    $lineNo++
    $m = [regex]::Match($text, '#\s*expect:\s*(.+?)\s*$')
    if (-not $m.Success -or $text.TrimStart().StartsWith("#")) { continue }
    $rLines++
    $hits = @(Get-LineFindings $rctl $lineNo)
    Check (@($hits | Where-Object { "$_".Contains($m.Groups[1].Value) }).Count -ge 1) ("CONTROL: relay control line " + $lineNo + " is refused because: " + $m.Groups[1].Value)
    if (@($hits | Where-Object { "$_".Contains($m.Groups[1].Value) }).Count -eq 0) { Show $hits }
}
Check ($rLines -eq 12) ("CONTROL: 12 lines of the relay control file name their reason (found " + $rLines + ")")
$rclean = @(Get-HordeExecRelayFindings -Path (Join-Path $rfx "exec-clean.ps1") -Known $relayKnown)
Check ($rclean.Count -eq 0) "CONTROL: a file written the way relay/ is written has no finding under the relay profile"; Show $rclean
$rcleanRemote = @(Get-HordeExecFindings -Path (Join-Path $rfx "exec-clean.ps1") -Known $relayKnown)
Check ((Says $rcleanRemote "Add-Type is not an allowlisted cmdlet") -and (Says $rcleanRemote "ECDsa")) "and the remote profile still refuses that same file: the widening is relay's alone"
# The profile widens what may be NAMED; every way to run something must still be refused under it.
$ctlRelay = @(Get-HordeExecRelayFindings -Path $ctlPath -Known $known)
$missed = @($forms | Where-Object { @(Get-LineFindings $ctlRelay $_.Extent.StartLineNumber).Count -eq 0 } | ForEach-Object { $_.Name })
Check ($missed.Count -eq 0) ("every one of the " + $forms.Count + " forms of the remote control file is still refused under the relay profile (" + ($missed -join ", ") + ")")
$relayFiles = @(Get-ChildItem -LiteralPath (Join-Path $root "relay") -Filter "*.ps1" -Recurse)
Check ($relayFiles.Count -ge 8) ("there is code in relay/ to check (" + $relayFiles.Count + " files)")
foreach ($file in $relayFiles) {
    $got = @(Get-HordeExecRelayFindings -Path $file.FullName -Known $relayKnown)
    Check ($got.Count -eq 0) ("relay/" + $file.Name + " starts no program and no shell"); Show $got
}
Check (@($relayFiles | Where-Object { [System.IO.File]::ReadAllText($_.FullName).Contains("Add-Type") } | ForEach-Object { $_.Name }) -join "," -ceq "BackendCng.ps1") "exactly one relay file compiles anything: BackendCng.ps1"

Complete-HordeSuite -Success "nothing in remote/ or relay/ can start a program, a shell or a script, and every way to is refused for its own reason"
