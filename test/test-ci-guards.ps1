# DOES THE CI GUARD RUNNER RUN EVERY LISTED GUARD IN BOTH SHELLS AND CALL GREEN ONLY WHAT PROVED IT?
#
# tools/CiGuards.ps1 is the one step of .github/workflows/guards.yml. NOTHING HERE REACHES GITHUB. This
# suite runs the real script, as its own process under Windows PowerShell 5.1 and under PowerShell 7,
# against a small tree of its own in temp: a copy of core/GuardList.ps1, a test\guards.txt, and stand-in
# guards that go green, red, exit 0 with no banner, exit 0 with a failures banner, and report the shell
# and PSModulePath they were started with. Read from the outside:
#   - every listed guard runs in 5.1 AND in 7 (a stand-in writes a marker line naming the shell);
#   - green is exit 0 AND a closing banner that is not a failures banner (CONTRIBUTING 15 rule 7);
#   - one red guard does not stop the others, and makes the exit code 1;
#   - the guard list is the only list: a guard added to the file runs with no other edit;
#   - a missing list, a bad line, a guard named but not in the tree, and -Only a guard not listed are red;
#   - 5.1 is given the machine PSModulePath, 7 none.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
Set-StrictMode -Version Latest

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("horde-ci-guards-" + [guid]::NewGuid().ToString("N").Substring(0, 10))
[void][System.IO.Directory]::CreateDirectory($work)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$script51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$script7 = Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe"

$green = '$s = $PSVersionTable.PSVersion.Major; Write-Output ("ran in shell " + $s); Write-Output "  [PASS] stand-in"; Write-Output "==== stand-in green ===="; exit 0'
$red = 'Write-Output "  [FAIL] stand-in red"; Write-Output ""; Write-Output "==== 1 FAILURE(S) ===="; exit 1'
$nobanner = 'Write-Output "  [PASS] stand-in, cut short"; exit 0'
$failbanner = 'Write-Output "==== 2 FAILURE(S) ===="; exit 0'
$modules = '$s = $PSVersionTable.PSVersion.Major; Write-Output ("shell " + $s + " modules=" + $env:PSModulePath); Write-Output "==== modules ===="; exit 0'

function New-Tree {
    # A tree with core/GuardList.ps1 (the real one) and test\guards.txt = $Lines, and the stand-in guards in $Files.
    param([string]$Name, [AllowNull()]$Lines, [hashtable]$Files)
    $t = Join-Path $work $Name
    [void][System.IO.Directory]::CreateDirectory((Join-Path $t "core"))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $t "test"))
    Copy-Item -LiteralPath (Join-Path $root "core\GuardList.ps1") -Destination (Join-Path $t "core\GuardList.ps1")
    if ($null -ne $Lines) { [System.IO.File]::WriteAllText((Join-Path $t "test\guards.txt"), $Lines, $utf8) }
    foreach ($k in $Files.Keys) { [System.IO.File]::WriteAllText((Join-Path $t ("test\" + $k)), $Files[$k], $utf8) }
    return $t
}

function Invoke-Runner {
    # tools\CiGuards.ps1 as its own process under $Exe: { code; out }.
    param([string]$Exe, [string]$Tree, [string[]]$More = @(), [string]$PoisonModulePath = "")
    $log = Join-Path $Tree "logs"
    $words = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $root "tools\CiGuards.ps1"), "-Root", $Tree, "-LogFolder", $log) + $More
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (@($words | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    if ($psi.EnvironmentVariables.ContainsKey("GITHUB_STEP_SUMMARY")) { $psi.EnvironmentVariables.Remove("GITHUB_STEP_SUMMARY") }
    $psi.EnvironmentVariables["GITHUB_STEP_SUMMARY"] = (Join-Path $Tree "summary.md")
    # A PSModulePath the runner was started with, that no guard child may inherit.
    if ($PoisonModulePath -ne "") { $psi.EnvironmentVariables["PSModulePath"] = $PoisonModulePath }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(240000)) { try { $p.Kill() } catch { } ; return [pscustomobject]@{ code = -1; out = "timed out" } }
    $p.WaitForExit()
    $r = [pscustomobject]@{ code = $p.ExitCode; out = ($o.Result + $e.Result) }
    $p.Dispose()
    return $r
}

foreach ($shell in @($script51, $script7)) {
    if (-not [System.IO.File]::Exists($shell)) { Check $false ("the shell " + $shell + " is on this machine, to run the CI runner under it"); continue }
    $label = if ($shell -ceq $script51) { "5.1" } else { "7" }
    Write-Host ("== the runner under PowerShell " + $label)

    $t = New-Tree -Name ("all-green-" + $label) -Lines "# list`ntest/test-a.ps1`ntest/test-b.ps1`n" -Files @{ "test-a.ps1" = $green; "test-b.ps1" = $green }
    $r = Invoke-Runner -Exe $shell -Tree $t
    Check ($r.code -eq 0 -and $r.out -clike "*every guard is green in both shells (4 runs)*") ("two listed guards, each in two shells, all green: exit 0 after 4 runs (" + $r.code + ")")
    Check ($r.out -clike "*ran in shell 5*" -and $r.out -clike "*ran in shell 7*") "  the stand-ins really ran in 5.1 and in 7"
    Check ([regex]::Matches($r.out, '\[GREEN\] test-[ab] in (Windows PowerShell 5\.1|PowerShell 7)').Count -eq 4) "  and each of the four runs is reported green"
    Check ([System.IO.File]::Exists((Join-Path $t "logs\test-a.5.1.log")) -and [System.IO.File]::Exists((Join-Path $t "logs\test-b.7.log"))) "  and each run's output is kept in a log"
    Check ([System.IO.File]::ReadAllText((Join-Path $t "summary.md")) -clike "*| test-a | Windows PowerShell 5.1 | 0 | ==== stand-in green ==== | green |*") "  and the step summary has a table of the runs"

    $t = New-Tree -Name ("one-red-" + $label) -Lines "test/test-r.ps1`ntest/test-a.ps1`n" -Files @{ "test-r.ps1" = $red; "test-a.ps1" = $green }
    $r = Invoke-Runner -Exe $shell -Tree $t
    Check ($r.code -eq 1 -and $r.out -clike "*[[]RED] test-r in Windows PowerShell 5.1*" -and $r.out -clike "*[[]GREEN] test-a in PowerShell 7*") "a red guard makes exit 1, and the guard after it still ran"
    Check ($r.out -clike "*::error::not green: test-r (Windows PowerShell 5.1), test-r (PowerShell 7)*") "  and the error names the guard and the shell"

    $t = New-Tree -Name ("nobanner-" + $label) -Lines "test/test-n.ps1`n" -Files @{ "test-n.ps1" = $nobanner }
    $r = Invoke-Runner -Exe $shell -Tree $t
    Check ($r.code -eq 1 -and $r.out -clike "*[[]RED] test-n in Windows PowerShell 5.1 (exit 0, no closing banner: NOT RUN)*") "exit 0 with no closing banner is NOT RUN, never green"

    $t = New-Tree -Name ("failbanner-" + $label) -Lines "test/test-f.ps1`n" -Files @{ "test-f.ps1" = $failbanner }
    $r = Invoke-Runner -Exe $shell -Tree $t
    Check ($r.code -eq 1 -and $r.out -clike "*[[]RED] test-f in PowerShell 7 (exit 0, ==== 2 FAILURE(S) ====)*") "exit 0 under a failures banner is not green"

    $t = New-Tree -Name ("new-line-" + $label) -Lines "test/test-a.ps1`n" -Files @{ "test-a.ps1" = $green; "test-z.ps1" = $red }
    $r = Invoke-Runner -Exe $shell -Tree $t
    Check ($r.code -eq 0 -and $r.out -cnotlike "*test-z*") "a guard that is in the folder but not in the list does not run"
    [System.IO.File]::AppendAllText((Join-Path $t "test\guards.txt"), "test/test-z.ps1`n", $utf8)
    $r = Invoke-Runner -Exe $shell -Tree $t
    Check ($r.code -eq 1 -and $r.out -clike "*[[]RED] test-z in Windows PowerShell 5.1*") "one added line to the list is the only edit needed to run a new guard"

    $t = New-Tree -Name ("only-" + $label) -Lines "test/test-a.ps1`ntest/test-r.ps1`n" -Files @{ "test-a.ps1" = $green; "test-r.ps1" = $red }
    $r = Invoke-Runner -Exe $shell -Tree $t -More @("-Only", "test\test-a.ps1")
    Check ($r.code -eq 0 -and $r.out -cnotlike "*test-r*") "-Only runs one listed guard"
    $r = Invoke-Runner -Exe $shell -Tree $t -More @("-Only", "test\test-q.ps1")
    Check ($r.code -eq 1 -and $r.out -clike "*-Only test\test-q.ps1 is not in test\guards.txt*") "-Only a guard that is not listed is refused"

    $t = New-Tree -Name ("nolist-" + $label) -Lines $null -Files @{ "test-a.ps1" = $green }
    $r = Invoke-Runner -Exe $shell -Tree $t
    Check ($r.code -eq 1 -and $r.out -clike "*::error::test\guards.txt is not there*") "no guard list: exit 1, never a green run of nothing"
    $t = New-Tree -Name ("badline-" + $label) -Lines "test/test-a.ps1`nrm -rf /`n" -Files @{ "test-a.ps1" = $green }
    $r = Invoke-Runner -Exe $shell -Tree $t
    Check ($r.code -eq 1 -and $r.out -clike "*::error::line 2 of test\guards.txt is not a guard script*" -and $r.out -cnotlike "*ran in shell*") "a bad line refuses the whole list: no guard runs"
    $t = New-Tree -Name ("missing-" + $label) -Lines "test/test-a.ps1`ntest/test-gone.ps1`n" -Files @{ "test-a.ps1" = $green }
    $r = Invoke-Runner -Exe $shell -Tree $t
    Check ($r.code -eq 1 -and $r.out -clike "*[[]RED] test-gone in PowerShell 7 (exit -1*" -and $r.out -clike "*the guard test\test-gone.ps1 is not in the checkout*") "a listed guard that is not in the checkout is red, never skipped"

    $t = New-Tree -Name ("modules-" + $label) -Lines "test/test-m.ps1`n" -Files @{ "test-m.ps1" = $modules }
    $r = Invoke-Runner -Exe $shell -Tree $t -PoisonModulePath "C:\horde-ci-probe\poison"
    $machine = [Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
    $seven = [regex]::Match($r.out, 'shell 7 modules=([^\r\n]*)').Groups[1].Value
    $five = [regex]::Match($r.out, 'shell 5 modules=([^\r\n]*)').Groups[1].Value
    if ("" + $machine -ne "") { Check ($five -clike ("*" + ($machine -split ";")[0] + "*")) "5.1 is started with the machine PSModulePath" }
    Check ($seven -ilike "*PowerShell\7\Modules*" -and $seven -cnotlike "*horde-ci-probe*") "7 builds its own PSModulePath: its own modules folder is in it and the runner's is not passed on"
    Check ($five -cnotlike "*horde-ci-probe*" -and $five -ne "") "5.1 is not handed the runner's PSModulePath either"
}

Write-Host "== the workflow holds no list of its own"
$wf = [System.IO.File]::ReadAllText((Join-Path $root ".github\workflows\guards.yml"))
$wfCode = @($wf -split "\r?\n" | Where-Object { $_.Trim() -ne "" -and -not $_.TrimStart().StartsWith("#") }) -join "`n"
Check ($wfCode -clike "*tools\CiGuards.ps1*") "the workflow calls tools\CiGuards.ps1"
Check ($wfCode -cnotmatch 'test-[a-z-]+\.ps1' -and $wfCode -cnotmatch 'test\\test-') "  and names no guard itself: the list is test\guards.txt alone"
Check ($wfCode -clike "*shell: powershell*" -and $wfCode -clike "*persist-credentials: false*" -and $wfCode -clike "*permissions:*contents: read*") "  and keeps its read-only token, no saved credentials, and 5.1 as the step shell"
Check ($wfCode -cnotmatch 'required|branch protection') "  and does not make itself a required check"

try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Write-Host ("  (the suite's temp folder stays: " + $work + ")") }
Complete-HordeSuite -Success "the CI runner runs every listed guard in both shells and calls green only exit 0 with a closing banner"
