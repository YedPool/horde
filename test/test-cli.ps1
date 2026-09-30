# DOES THE HORDE COMMAND LINE DECLARE EVERY COMMAND ONCE, AND BIND EVERY ARGUMENT IT IS GIVEN?
#
# The bug class this guards, from the system Horde replaces (YedPool/wezfleet a6d6ff1): a command
# that dispatched and was missing from help, a flag that was undeclared and so unreachable, and a
# dispatch branch that could never be reached. And two traps measured while building this: arguments
# forwarded through a ValueFromRemainingArguments param lose their switch meaning, and a plain script
# block silently accepts any flag it does not know.
#
# The dispatcher is run as a real separate process, both the way a script runs it (-File) and the way
# a person types it at a prompt, because the two bind arguments differently.

$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "cli\Commands.ps1")

$fails = @()
# A condition must be exactly true or false; anything else fails loudly. A helper that returned an
# array alongside $false once made a "must throw" check pass when nothing threw (see test-isolation.ps1).
function Check { param($Cond, [string]$What)
    if ($Cond -isnot [bool]) { Write-Host "  [FAIL] $What (the check's condition was not true or false)" -ForegroundColor Red; $script:fails += $What; return }
    if ($Cond) { Write-Host "  [PASS] $What" -ForegroundColor DarkGray }
    else { Write-Host "  [FAIL] $What" -ForegroundColor Red; $script:fails += $What } }

function Invoke-Horde {
    # Run horde as its own process. Returns { code; out; err } with the two streams kept apart.
    # Not `2>&1`: on PowerShell 5.1 that turns a native command's stderr into an error record.
    param([string]$Root, [string[]]$Arguments, [switch]$AsTyped)
    $script = Join-Path $Root "horde.ps1"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    if ($AsTyped) {
        $quoted = @($Arguments | ForEach-Object { if ($_ -match '^-') { $_ } else { "'" + ($_ -replace "'", "''") + "'" } }) -join " "
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& '" + $script + "' " + $quoted + "; exit `$LASTEXITCODE`""
    } else {
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"" + $script + "`" " + (($Arguments | ForEach-Object { "`"" + $_ + "`"" }) -join " ")
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ code = $p.ExitCode; out = $out; err = $err }
}

Write-Host ""
Write-Host "--- a command file only declares, and is read without being run ---" -ForegroundColor Cyan

$marker = Join-Path $env:TEMP "horde-cli-side-effect-marker.txt"
Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
$good = Get-HordeCommands -Dir (Join-Path $root "test\fixtures\cli\good")
Check (@($good.commands).Count -eq 1 -and @($good.findings).Count -eq 0) "a well-formed command file is read with no findings"
Check ($good.commands[0].usage -eq "alpha [-Loud]") "and its usage is read from the file without running it"

$bad = Get-HordeCommands -Dir (Join-Path $root "test\fixtures\cli\bad")
function HasFinding { param([string]$File, [string]$Like)
    return (@($bad.findings | Where-Object { $_ -like ($File + ":*") -and $_ -like ("*" + $Like + "*") }).Count -gt 0) }
Check (@($bad.commands).Count -eq 0) "no malformed command file is listed as a command"
Check (HasFinding "side-effect.ps1" "top-level statements") "a command file that does work at load time is refused"
Check (HasFinding "computed.ps1" "not a constant string") "a declaration that must be computed to be read is refused"
Check (HasFinding "misnamed.ps1" "the file name is the command name") "a command whose declared name is not its file name is refused"
Check (HasFinding "ungrouped.ps1" "which help does not list") "a command in a group help does not list is refused, so help cannot drop it"
Check (HasFinding "plain-run.ps1" "CmdletBinding") "a run block that would silently accept any flag is refused"
Check (HasFinding "no-summary.ps1" "has no summary") "a command with no summary is refused"
Check (HasFinding "no-summary.ps1" "unknown key") "and so is a key the registry does not know"
Check (HasFinding "wrong-usage.ps1" "usage does not start with its own name") "a usage line for a different command is refused"
Check ((Test-HordeCommandName -Name "version") -eq $true) "CONTROL: a plain command name is well-formed"
Check ((Test-HordeCommandName -Name "version`n") -eq $false) "a command name with a trailing newline is not well-formed"
Check (-not (Test-Path -LiteralPath $marker)) "listing the commands ran none of their code"
Check ((@(Format-HordeHelp -Dir (Join-Path $root "test\fixtures\cli\bad")) -join "`n") -like "*broken command files*") "help names broken command files instead of silently leaving them out"
$refused = $false
try { [void](Import-HordeCommand -Path (Join-Path $root "test\fixtures\cli\bad\side-effect.ps1")) } catch { $refused = $true }
Check $refused "loading a malformed command file is refused"
Check (-not (Test-Path -LiteralPath $marker)) "and refused before any of it ran"

Write-Host ""
Write-Host "--- the real commands, and the help generated from them ---" -ForegroundColor Cyan

$real = Get-HordeCommands
Check (@($real.findings).Count -eq 0) ("every shipped command file is well-formed" + $(if (@($real.findings).Count) { ": " + ($real.findings -join "; ") } else { "" }))
Check (@($real.commands | Where-Object { $_.name -eq "version" }).Count -eq 1) "CONTROL: the registry really finds the shipped commands"
$helpText = @(Format-HordeHelp)
foreach ($c in $real.commands) {
    Check (@($helpText | Where-Object { $_ -eq ("    horde " + $c.usage) }).Count -eq 1) ("help lists '" + $c.name + "' exactly once")
}

# The dispatcher names no command, so it never needs editing to add one - apart from "help", which
# is where a bare `horde` goes.
$tokens = $null; $errors = $null
$disp = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root "horde.ps1"), [ref]$tokens, [ref]$errors)
$literals = @($disp.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
$named = @($real.commands | Where-Object { $_.name -ne "help" -and $literals -contains $_.name })
Check ($named.Count -eq 0) "the dispatcher names no command, so adding one never means editing it"
Check ($null -eq $disp.ParamBlock) "the dispatcher has no param block - the one that would strip switches from forwarded arguments"

Write-Host ""
Write-Host "--- the dispatcher, run as a real process ---" -ForegroundColor Cyan

$version = "$(Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1)".Trim()
$r = Invoke-Horde -Root $root -Arguments @()
Check ($r.code -eq 0 -and $r.out -like "usage: horde*") "horde with no arguments prints help and exits 0"
$r = Invoke-Horde -Root $root -Arguments @("--help")
Check ($r.code -eq 0 -and $r.out -like "usage: horde*") "horde --help prints help"
$r = Invoke-Horde -Root $root -Arguments @("version")
Check ($r.code -eq 0 -and $r.out -like ("horde " + $version + "*")) "horde version prints the version from the VERSION file"
$r = Invoke-Horde -Root $root -Arguments @("version", "-Json")
$j = $null; try { $j = $r.out | ConvertFrom-Json } catch { }
Check ($r.code -eq 0 -and $j -and $j.version -eq $version) "horde version -Json prints the same version as JSON"
$r = Invoke-Horde -Root $root -Arguments @("no-such-command")
Check ($r.code -eq 2 -and $r.err -like "*unknown command 'no-such-command'*") "an unknown command exits 2 and says so"
$r = Invoke-Horde -Root $root -Arguments @("version", "-Bogus")
Check ($r.code -eq 2 -and $r.err -like "*usage: horde version*") "a flag the command does not take exits 2 with its usage, never silently ignored"
# "..\Commands" is aimed at a file that EXISTS - cli\Commands.ps1, one folder up from cli\commands -
# so this fails if the name check is removed. The first version aimed at "..\cli\Commands", which is
# missing either way, and could not fail (review of PR #12).
Check (Test-Path -LiteralPath (Join-Path $root "cli\Commands.ps1") -PathType Leaf) "CONTROL: the file a path-shaped name would reach really exists"
$r = Invoke-Horde -Root $root -Arguments @("..\Commands")
Check ($r.code -eq 2 -and $r.err -like "*unknown command*") "a command name that is a path reaches no file"

# A STAND-IN ROOT with two extra commands, so forwarding and failure can be tested without shipping
# test commands: the real dispatcher and registry, copied, with fixture commands beside them.
$tmp = Join-Path $env:TEMP ("horde-cli-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $tmp "cli\commands") | Out-Null
Copy-Item -LiteralPath (Join-Path $root "horde.ps1") -Destination $tmp
Copy-Item -LiteralPath (Join-Path $root "VERSION") -Destination $tmp
Copy-Item -Path (Join-Path $root "cli\*.ps1") -Destination (Join-Path $tmp "cli")
Copy-Item -LiteralPath (Join-Path $root "cli\commands\help.ps1") -Destination (Join-Path $tmp "cli\commands")
Copy-Item -Path (Join-Path $root "test\fixtures\cli\extra\*.ps1") -Destination (Join-Path $tmp "cli\commands")
# Two files that look like commands and are not. zeta.ps1x is matched by `Get-ChildItem -Filter *.ps1`
# through its 8.3 short name (ZETA~1.PS1), measured 2026-09-29 in %TEMP%. nul.ps1 is a reserved
# device name: it can only be created through a \?\ path, and was listed by help while `horde nul`
# said "unknown command" (review of PR #12, finding 4). It cannot be committed as a fixture - a
# checkout on Windows could not write it - so it is made here from zeta's declaration.
$standInCommands = Join-Path $tmp "cli\commands"
$longPrefix = [string][char]92 + [char]92 + "?" + [char]92
Copy-Item -LiteralPath (Join-Path $root "test\fixtures\cli\lookalike\zeta.ps1x") -Destination $standInCommands
$nulPath = $longPrefix + (Join-Path $standInCommands "nul.ps1")
[System.IO.File]::WriteAllText($nulPath, ([System.IO.File]::ReadAllText((Join-Path $standInCommands "zeta.ps1x")) -replace "zeta", "nul"))
try {
    Write-Host ""
    Write-Host "--- help and dispatch find the same files ---" -ForegroundColor Cyan
    Check ([System.IO.File]::Exists($nulPath)) "CONTROL: a command file named nul.ps1 really exists"
    $listed = Get-HordeCommands -Dir $standInCommands
    $listedNames = @($listed.commands | ForEach-Object { $_.name })
    if (@(Get-ChildItem -LiteralPath $standInCommands -Filter *.ps1 -File | Where-Object { $_.Name -eq "zeta.ps1x" }).Count -eq 1) {
        Check $true "CONTROL: on this volume, -Filter *.ps1 really matches zeta.ps1x"
        Check ($listedNames -notcontains "zeta") "a .ps1x file is not listed as a command, though -Filter *.ps1 matches it"
    } else {
        Write-Host "  [SKIP] this volume makes no 8.3 short names, so the .ps1x look-alike cannot be tested here" -ForegroundColor Yellow
    }
    Check ($listedNames -notcontains "nul") "a command file with a reserved device name is not listed"
    Check (@($listed.findings | Where-Object { $_ -like "nul.ps1:*reserved*" }).Count -eq 1) "and it is named as a broken command file instead"
    $h = Invoke-Horde -Root $tmp -Arguments @("help")
    Check ($h.code -eq 0 -and $h.out -like "*    horde echo-args*") "CONTROL: help in the stand-in root lists its commands"
    $r = Invoke-Horde -Root $tmp -Arguments @("nul")
    Check ($h.out -notlike "*    horde nul*" -and $r.code -eq 2) "help does not list a command that dispatch cannot reach"
    $unreached = @($listedNames | Where-Object { -not ((Get-Command Find-HordeCommand -ErrorAction SilentlyContinue) -and (Find-HordeCommand -Name $_ -Dir $standInCommands).command) })
    Check ($listedNames.Count -gt 0 -and $unreached.Count -eq 0) ("dispatch finds every command that help lists" + $(if ($unreached.Count) { ": not " + ($unreached -join ", ") } else { "" }))

    foreach ($typed in @($false, $true)) {
        $how = "from a script"; if ($typed) { $how = "typed at a prompt" }
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "abc", "-Json", "-Count", "5") -AsTyped:$typed
        Check ($r.out.Trim() -eq "target=[abc] json=True count=5") ("a switch, a named value and a positional all reach the command, " + $how + " (got: " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    $r = Invoke-Horde -Root $tmp -Arguments @("boom")
    Check ($r.code -eq 1 -and $r.err -like "*boom failed on purpose*") "a command that fails exits 1 and says why"
}
finally {
    # nul.ps1 first, through the same \?\ path that made it: an ordinary path names the device.
    if ([System.IO.File]::Exists($nulPath)) { [System.IO.File]::Delete($nulPath) }
    if ((Split-Path -Leaf $tmp) -match '^horde-cli-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $tmp)) "the stand-in root was removed"

Write-Host ""
if ($fails.Count) {
    Write-Host "==== $($fails.Count) FAILURE(S) ====" -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "==== every command is declared once, and every argument reaches it ====" -ForegroundColor Green
exit 0
