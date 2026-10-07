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

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
# The suite helper first, so an error while loading the registry is recorded like any other. It sets
# $ErrorActionPreference to Stop: every test below that expects an error says so with -ErrorAction or
# a try/catch (CONTRIBUTING 9).
. (Join-Path $root "test\lib\Suite.ps1")
trap { Register-HordeSuiteError $_; continue }
. (Join-Path $root "cli\Commands.ps1")

function Start-HordeProcess {
    # Run powershell.exe with these arguments. Returns { code; out; err } with the two streams kept
    # apart. Not `2>&1`: on PowerShell 5.1 that turns a native command's stderr into an error record.
    param([string]$PowerShellArguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = $PowerShellArguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    # THE TWO STREAMS ARE READ AT THE SAME TIME, never one to its end and then the other. A pipe holds
    # 4,096 bytes: a child that writes more than that to stderr waits for a reader, and a reader still
    # waiting for stdout to end waits for the child - for ever. Measured 2026-10-07: an unknown command
    # prints the whole help to stderr, the help reached 4,362 bytes, and this suite stood still for 23
    # minutes at that check; at 3,591 bytes it had passed.
    $errRead = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $err = $errRead.Result
    return [pscustomobject]@{ code = $p.ExitCode; out = $out; err = $err }
}

function Invoke-Horde {
    # Run horde as its own process, from a script (-File) or as typed at a prompt (-Command).
    # Typed, a word starting with "-" or "$" is left unquoted, so that PowerShell parses it as it
    # would at a prompt: -Json:$false and $null are syntax there, not text. Every other word is quoted.
    param([string]$Root, [string[]]$Arguments, [switch]$AsTyped)
    $script = Join-Path $Root "horde.ps1"
    if ($AsTyped) {
        $quoted = @($Arguments | ForEach-Object { if ($_ -match '^[-$]') { $_ } else { "'" + ($_ -replace "'", "''") + "'" } }) -join " "
        return (Start-HordeProcess -PowerShellArguments ("-NoProfile -ExecutionPolicy Bypass -Command `"& '" + $script + "' " + $quoted + "; exit `$LASTEXITCODE`""))
    }
    return (Start-HordeProcess -PowerShellArguments ("-NoProfile -ExecutionPolicy Bypass -File `"" + $script + "`" " + (($Arguments | ForEach-Object { "`"" + $_ + "`"" }) -join " ")))
}

function Invoke-HordeInProcess {
    # Run PowerShell code that calls horde IN-PROCESS - `& $horde ...` from inside a script, the way a
    # command or another script calls it - in a process of its own, so that horde's exit code and its
    # stderr are read as Invoke-Horde reads them. This is not typed mode: -Command parses one line of
    # text, while here a variable set earlier reaches horde as the object it holds, $null included.
    param([string]$Root, [string]$Code)
    $file = Join-Path $Root ("in-process-" + [guid]::NewGuid().ToString("N") + ".ps1")
    Set-Content -LiteralPath $file -Encoding Ascii -Value ('$horde = Join-Path $PSScriptRoot "horde.ps1"' + "`r`n" + $Code + "`r`nexit `$LASTEXITCODE")
    try { return (Start-HordeProcess -PowerShellArguments ("-NoProfile -ExecutionPolicy Bypass -File `"" + $file + "`"")) }
    finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
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
Check (HasFinding "quoted-key.ps1" "unknown key") "a key that spells another key inside its quotes is not taken for it"
Check (HasFinding "sustained-text.ps1" "'sustained' must be") "sustained given as text is refused: it is `$true or `$false"
Check ((Test-HordeCommandName -Name "version") -eq $true) "CONTROL: a plain command name is well-formed"
Check ((Test-HordeCommandName -Name "version`n") -eq $false) "a command name with a trailing newline is not well-formed"
Check (-not (Test-Path -LiteralPath $marker)) "listing the commands ran none of their code"
Check ((@(Format-HordeHelp -Dir (Join-Path $root "test\fixtures\cli\bad")) -join "`n") -like "*broken command files*") "help names broken command files instead of silently leaving them out"
$refused = $false
try { [void](Import-HordeCommand -Path (Join-Path $root "test\fixtures\cli\bad\side-effect.ps1")) } catch { $refused = $true }
Check $refused "loading a malformed command file is refused"
Check (-not (Test-Path -LiteralPath $marker)) "and refused before any of it ran"

# A REDIRECTION'S TARGET IS CODE, evaluated when the statement runs: `@{...} 2> $(...)` or
# `summary = "x" 2> $(...)` ran the $(...) at load, and passed validation (review of PR #12, finding 2).
# Each fixture here writes the marker if it is ever loaded.
foreach ($f in @("redirect-top", "redirect-value", "redirect-run")) {
    Check (HasFinding ($f + ".ps1") "redirection") ("a redirection in a declaration is refused: " + $f)
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    try { [void](Import-HordeCommand -Path (Join-Path $root ("test\fixtures\cli\bad\" + $f + ".ps1"))) } catch { }
    Check (-not (Test-Path -LiteralPath $marker)) ("and loading it runs none of it" + ": " + $f)
}
Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue

# `using module` and `#requires -Modules` import a module - running its code - when the file loads,
# and a dynamicparam block is a script body the one-statement check did not look at (review of PR #12,
# finding 3). using-module.ps1 imports test\fixtures\cli\modules\marker.psm1, which writes the marker.
Check (HasFinding "using-module.ps1" "using") "a command file with a using statement is refused"
Check (HasFinding "requires-module.ps1" "#requires") "a command file with a #requires line is refused"
Check (HasFinding "dynamicparam.ps1" "dynamicparam") "a command file with a dynamicparam block is refused"
foreach ($f in @("using-module", "requires-module", "dynamicparam")) {
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    try { [void](Import-HordeCommand -Path (Join-Path $root ("test\fixtures\cli\bad\" + $f + ".ps1"))) } catch { }
    Check (-not (Test-Path -LiteralPath $marker)) ("and loading it runs none of it" + ": " + $f)
}
Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "--- the real commands, and the help generated from them ---" -ForegroundColor Cyan

$real = Get-HordeCommands
Check (@($real.findings).Count -eq 0) ("every shipped command file is well-formed" + $(if (@($real.findings).Count) { ": " + ($real.findings -join "; ") } else { "" }))
Check (@($real.commands | Where-Object { $_.name -eq "version" }).Count -eq 1) "CONTROL: the registry really finds the shipped commands"
# SUSTAINED COMMANDS ARE OPTED OUT OF POWER THROTTLING, AND ONLY THEY (core/Platform.ps1). Throttling
# starts about 3 s into sustained work, and loading the type costs about 0.2 s, so a quick command
# pays nothing.
Check (@($real.commands | Where-Object { $_.name -eq "metrics" -and $_.sustained -eq $true }).Count -eq 1) "metrics declares itself sustained"
Check (@($real.commands | Where-Object { $_.name -eq "node" -and $_.sustained -eq $true }).Count -eq 1) "node declares itself sustained: node serve runs until stopped (review of PR #81, F2)"
Check (@($real.commands | Where-Object { $_.name -eq "version" -and $_.sustained -eq $false }).Count -eq 1) "version does not, and reads as not sustained"
$helpText = @(Format-HordeHelp)
$notOnce = @($real.commands | Where-Object { $u = "    horde " + $_.usage; @($helpText | Where-Object { $_ -eq $u }).Count -ne 1 } | ForEach-Object { $_.name })
Check ($notOnce.Count -eq 0) ("help lists every command exactly once" + $(if ($notOnce.Count) { ": not " + ($notOnce -join ", ") } else { "" }))

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
# so this fails if dispatch ever joins a typed name onto a path again, as its first version did. It
# does NOT fail if the name check in Find-HordeCommand is removed: a name is only ever compared with
# the names in the listing, which a path never equals (second review of PR #12, finding 7). The unit
# tests after it hold the name check itself.
Check (Test-Path -LiteralPath (Join-Path $root "cli\Commands.ps1") -PathType Leaf) "CONTROL: the file a path-shaped name would reach really exists"
$r = Invoke-Horde -Root $root -Arguments @("..\Commands")
Check ($r.code -eq 2 -and $r.err -like "*unknown command*") "a command name that is a path reaches no file"
$found = Find-HordeCommand -Name "..\Commands"
Check ($null -eq $found.command -and @($found.findings).Count -eq 0) "looking up a path-shaped name finds no command and no broken file"
# THE NAME CHECK IN Find-HordeCommand: only a well-formed name may claim a broken file's findings.
# A broken file whose own name is malformed (bad_name.ps1) is listed as a finding; looked up by that
# malformed name it must give nothing, as every other malformed name does - so `horde bad_name` is an
# unknown command (exit 2), never "its command file is broken" (exit 1). This fails if the
# Test-HordeCommandName call is removed from Find-HordeCommand (mutation-checked 2026-09-29).
$malformed = Join-Path $env:TEMP ("horde-cli-name-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $malformed | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $malformed "bad_name.ps1") -Value '$HordeCommand = @{ name = "bad_name"; group = "about"; usage = "bad_name"; summary = "a malformed name"; run = { [CmdletBinding()] param() } }'
    Check ((Test-HordeCommandName -Name "bad_name") -eq $false) "CONTROL: bad_name is not a well-formed command name"
    $all = Get-HordeCommands -Dir $malformed
    Check (@($all.findings | Where-Object { $_ -like "bad_name.ps1: *not lowercase*" }).Count -eq 1) "CONTROL: bad_name.ps1 is listed as a broken command file"
    $found = Find-HordeCommand -Name "bad_name" -Dir $malformed
    Check ($null -eq $found.command -and @($found.findings).Count -eq 0) "a malformed name claims no broken file's findings"
}
finally {
    if ((Split-Path -Leaf $malformed) -match '^horde-cli-name-[0-9a-f]{32}$') { Remove-Item -LiteralPath $malformed -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $malformed)) "the malformed-name folder was removed"

# A STAND-IN ROOT with two extra commands, so forwarding and failure can be tested without shipping
# test commands: the real dispatcher and registry, copied, with fixture commands beside them.
$tmp = Join-Path $env:TEMP ("horde-cli-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $tmp "cli\commands") | Out-Null
Copy-Item -LiteralPath (Join-Path $root "horde.ps1") -Destination $tmp
# horde.ps1 loads core\Platform.ps1 first, to opt out of power throttling, and it loads core\Tristate.ps1.
New-Item -ItemType Directory -Path (Join-Path $tmp "core") | Out-Null
foreach ($c in @("Platform.ps1", "Tristate.ps1")) { Copy-Item -LiteralPath (Join-Path $root ("core\" + $c)) -Destination (Join-Path $tmp "core") }
Copy-Item -LiteralPath (Join-Path $root "VERSION") -Destination $tmp
Copy-Item -Path (Join-Path $root "cli\*.ps1") -Destination (Join-Path $tmp "cli")
Copy-Item -LiteralPath (Join-Path $root "cli\commands\help.ps1") -Destination (Join-Path $tmp "cli\commands")
Copy-Item -LiteralPath (Join-Path $root "cli\commands\version.ps1") -Destination (Join-Path $tmp "cli\commands")
Copy-Item -Path (Join-Path $root "test\fixtures\cli\extra\*.ps1") -Destination (Join-Path $tmp "cli\commands")
Copy-Item -LiteralPath (Join-Path $root "test\fixtures\cli\bad\side-effect.ps1") -Destination (Join-Path $tmp "cli\commands")
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
    # An extension in capitals: Windows finds omega.PS1 as a .ps1 file, and a registry that compared
    # extensions without case would list it. It is named as a broken file instead, so that "X.PS1"
    # never silently becomes a command on one filesystem and not another.
    [System.IO.File]::WriteAllText((Join-Path $standInCommands "omega.PS1"), ([System.IO.File]::ReadAllText((Join-Path $standInCommands "zeta.ps1x")) -replace "zeta", "omega"))
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
    Check ($listedNames -notcontains "omega" -and @($listed.findings | Where-Object { $_ -clike "omega.PS1:*in lowercase*" }).Count -eq 1) "a command file whose extension is in capitals is named as broken, not listed"
    $h = Invoke-Horde -Root $tmp -Arguments @("help")
    Check ($h.code -eq 0 -and $h.out -like "*    horde echo-args*") "CONTROL: help in the stand-in root lists its commands"
    $r = Invoke-Horde -Root $tmp -Arguments @("nul")
    Check ($h.out -notlike "*    horde nul*" -and $r.code -ne 0 -and $r.err -like "*reserved device name*") "help does not list a command that dispatch cannot reach"
    $unreached = @($listedNames | Where-Object { -not ((Get-Command Find-HordeCommand -ErrorAction SilentlyContinue) -and (Find-HordeCommand -Name $_ -Dir $standInCommands).command) })
    Check ($listedNames.Count -gt 0 -and $unreached.Count -eq 0) ("dispatch finds every command that help lists" + $(if ($unreached.Count) { ": not " + ($unreached -join ", ") } else { "" }))

    foreach ($typed in @($false, $true)) {
        $how = "from a script"; if ($typed) { $how = "typed at a prompt" }
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "abc", "-Json", "-Count", "5") -AsTyped:$typed
        Check ($r.out.Trim() -eq "target=[abc] json=True count=5 verb=[]") ("a switch, a named value and a positional all reach the command, " + $how + " (got: " + $r.out.Trim() + $r.err.Trim() + ")")
        # A COLON BINDS A VALUE TO ITS PARAMETER. $args holds -Json:$false as two items - "-Json:" and
        # $false typed, "-Json" and "$false" from a script - and splatting them on turned -Json on and
        # sent the value to the first positional parameter: json=True target=[False], exit 0 (review
        # of PR #12, finding 1). Typed, the colon survives on the parameter's text and the pair is
        # rejoined. From a script the colon is gone and the value is the WORD "$false", so it is refused
        # rather than guessed at (cli\Arguments.ps1 says why).
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", '-Json:$false') -AsTyped:$typed
        if ($typed) {
            Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[] json=False count=0 verb=[]") ("a switch turned off with a colon stays off" + ", " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
        } else {
            Check ($r.code -eq 2 -and $r.out.Trim() -eq "" -and $r.err -like "*arrived as text*" -and $r.err -like "*usage: horde echo-args*") ("a colon value that arrived as text is refused, never guessed at" + ", " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
        }
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", '-Json:$true', "abc") -AsTyped:$typed
        if ($typed) {
            Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[abc] json=True count=0 verb=[]") ("a switch turned on with a colon is on, and the next word is still positional, " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
        } else {
            Check ($r.code -eq 2 -and $r.out.Trim() -eq "" -and $r.err -like "*arrived as text*") ("a colon value that arrived as text is refused, never guessed at, with a word after it" + ", " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
        }
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Count:5") -AsTyped:$typed
        Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[] json=False count=5 verb=[]") ("a value given with a colon reaches its parameter, " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Json") -AsTyped:$typed
        Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[] json=True count=0 verb=[]") ("a plain switch is still on, " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
        # CALLED FROM INSIDE A COMMAND, horde is in-process, so its $args carry PowerShell's own tags
        # whatever started the outer horde. The process command-line reader this replaced read the
        # OUTER horde's command line here: measured 2026-09-29, the inner call exited 1, "could not
        # match the command line (1 given, 2 delivered)" (second review of PR #12, finding 1).
        $r = Invoke-Horde -Root $tmp -Arguments @("nested-call", "hello") -AsTyped:$typed
        Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[] json=False count=0 verb=[]") ("horde called from inside a command binds its own colon value" + ", " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    # A $null VALUE KEEPS ITS PLACE. horde took its arguments as `$args | Select-Object -Skip 1`, and
    # a pipeline drops a $null item: in-process, `$m = $null; horde echo-args -Verb:$m target` bound
    # verb=[target] target=[] with exit 0 - the next word shifted into the parameter (third review of
    # PR #12, finding 1). Typed at a prompt, -Verb:$null x did the same.
    foreach ($code in @('$m = $null; & $horde echo-args -Verb:$m target', '$m = $null; & $horde echo-args -Verb $m target')) {
        $r = Invoke-HordeInProcess -Root $tmp -Code $code
        Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[target] json=False count=0 verb=[]") ("a null value keeps its place, and the next word is not shifted into its parameter" + ", in-process: " + $code + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", '-Verb:$null', "x") -AsTyped
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[x] json=False count=0 verb=[]") ("a null value keeps its place, and the next word is not shifted into its parameter" + ", typed at a prompt: -Verb:`$null x (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # A QUOTE DOUBLED INSIDE A QUOTED ARGUMENT, from a script. powershell.exe ends the quote at the
    # doubled quote and .NET's [Environment]::GetCommandLineArgs does not: measured 2026-09-29, the
    # line `"x"" -Json"` reached the script as two items, x" and -Json (a switch), and .NET read it as
    # one. The command-line reader compared the two and refused with exit 2, "could not match the
    # command line" (second review of PR #12, finding 2). Now what binds is what PowerShell delivered.
    # Typed at a prompt this line is PowerShell's own syntax, with nothing to compare, so it is not run.
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Count:5", 'x"" -Json')
    Check ($r.code -eq 0 -and $r.out.Trim() -eq 'target=[x"] json=True count=5 verb=[]') ("a doubled quote is split as PowerShell splits it, never refused as unmatched (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # "--" MEANS "END OF PARAMETERS" ONLY TO A PARSER THAT SEES IT. Typed, PowerShell consumes it and
    # passes what follows as plain words - measured 2026-09-29, "-- -Json" arrived as the untagged
    # word "-Json". From a script it arrives as the word "--", and "-Json" after it is still tagged as
    # a parameter: echo-args bound target=[--] json=True, exit 0. horde cannot honour it there, so it
    # refuses it rather than treat it as a value.
    # THE WORD "$false" IS REFUSED WHEREVER IT ARRIVES, not only after a switch - where the switch-word
    # refusal would say so first. After a [string] parameter from a script, and typed in quotes after
    # a colon, it is still text, and bound target=[$false] with exit 0 when these refusals were removed
    # (mutation-checked 2026-09-30).
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", '-Target:$false')
    Check ($r.code -eq 2 -and $r.err -like "*arrived as text*" -and $r.err -notlike "*is followed by the word*") ("the word `$false after a parameter that is not a switch is refused as text, from a script (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Target:'`$false'") -AsTyped
    Check ($r.code -eq 2 -and $r.err -like "*arrived as text*") ("the quoted text '`$false' joined by a colon is refused as text, typed at a prompt (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "--", "abc")
    Check ($r.code -eq 2 -and $r.out.Trim() -eq "" -and $r.err -like "*'--' is not supported*") ("a double dash from a script is refused, not bound as a value" + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "--", "-Json") -AsTyped
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[-Json] json=False count=0 verb=[]") ("typed, a double dash is PowerShell's and what follows it is a word (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # Typed, a colon value a switch cannot take is PowerShell's to refuse.
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Json:false") -AsTyped
    Check ($r.code -eq 2 -and $r.err -like "*usage: horde echo-args*") ("a colon value a switch cannot take is refused with the usage, as PowerShell refuses it, typed at a prompt (got " + $r.code + ": " + $r.out.Trim() + ")")
    # A SWITCH FOLLOWED BY A TRUTH WORD IS REFUSED. From a script "-Json:false" arrives exactly as
    # "-Json false" does - the tagged switch, then the untagged word "false" - and bound json=True
    # target=[false] with exit 0 (measured 2026-09-29, before this refusal). Nothing in $args says
    # whether the word was the switch's value or an argument, so a switch (read from the run block's
    # param AST, by exact name, prefix or alias, common switches included) followed by the word
    # true, false, $true or $false in any case exits 2 instead of guessing (see cli\Arguments.ps1).
    $switchWords = @(
        @("-Json:false"), @("-Json", "false"), @("-Json:TRUE"), @("-json", "False"),
        @("-J", "false"), @("abc", "-Json", "true"), @("-Verbose", "false"),
        @("-Json:0"), @("-Json:1"), @("-Json:no"), @("-Json:OFF"), @("-Json:Yes"), @("-Json", "on"))
    foreach ($w in $switchWords) {
        $r = Invoke-Horde -Root $tmp -Arguments (@("echo-args") + $w)
        Check ($r.code -eq 2 -and $r.out.Trim() -eq "" -and $r.err -like "*is followed by the word*omit the switch*" -and $r.err -like "*usage: horde echo-args*") ("a switch followed by a truth word from a script is refused, never bound as two arguments" + ": " + ($w -join " ") + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    # Typed, where PowerShell parsed the line, the same two items stand apart the same way, and are
    # refused the same way; a colon value typed keeps its own handling above.
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Json", "false") -AsTyped
    Check ($r.code -eq 2 -and $r.err -like "*is followed by the word*") ("a switch followed by a truth word is refused typed at a prompt too (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # 0, 1, yes, no, on and off are truth words too: from a script -Json:0, :1, :no and :off bound
    # json=True and the word as the target, exit 0 (third review of PR #12, finding 4). Typed, the
    # colon forms are PowerShell's to refuse, and the space form is refused like "false".
    foreach ($w in @("-Json:0", "-Json:no")) {
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", $w) -AsTyped
        Check ($r.code -eq 2 -and $r.out.Trim() -eq "" -and $r.err -like "*usage: horde echo-args*") ("a truth word joined to a switch by a colon is refused, typed at a prompt: " + $w + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Json", "no") -AsTyped
    Check ($r.code -eq 2 -and $r.err -like "*is followed by the word 'no'*") ("a switch followed by a truth word is refused typed at a prompt too: -Json no (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # CONTROLS. In-process (and typed unquoted), 0 after a switch arrives as a NUMBER, which only
    # PowerShell's own parsing makes, so it is a positional. From a script, a word outside the set is
    # a positional too.
    $r = Invoke-HordeInProcess -Root $tmp -Code '& $horde echo-args -Json 0'
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[0] json=True count=0 verb=[]") ("a number after a switch is a positional, in-process (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Json", "2")
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[2] json=True count=0 verb=[]") ("a word after a switch that is not a truth word is a positional, from a script: -Json 2 (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # THE WORD "$null" IS TEXT, LIKE "$false". From a script `-Verb:$null x` arrives as "-Verb", the
    # word "$null" and "x", and bound verb=[$null] target=[x], exit 0; -Json:$null bound json=True
    # target=[$null] (third review of PR #12, finding 4). Refused, as "$false" is.
    foreach ($w in @(@('-Json:$null'), @('-Verb:$null', "x"), @('-VERB:$NULL', "x"))) {
        $r = Invoke-Horde -Root $tmp -Arguments (@("echo-args") + $w)
        Check ($r.code -eq 2 -and $r.out.Trim() -eq "" -and $r.err -like "*arrived as text*" -and $r.err -like "*usage: horde echo-args*") ("the word `$null is refused as text, never bound as a value, from a script: " + ($w -join " ") + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Verb:'`$null'", "x") -AsTyped
    Check ($r.code -eq 2 -and $r.err -like "*arrived as text*") ("the quoted text '`$null' joined by a colon is refused as text, typed at a prompt (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # CONTROL: typed, -Json:$null is the value $null, which PowerShell binds as the switch off.
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", '-Json:$null', "abc") -AsTyped
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[abc] json=False count=0 verb=[]") ("typed, the value `$null joined to a switch leaves it off (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # A SWITCH FOLLOWED BY A TRUTH VALUE, not a word: typed or in-process, `-Json $false` arrives as
    # the tagged switch and a [bool], and bound json=True target=[False] with exit 0 - the switch ON,
    # when the caller almost certainly meant it off (third review of PR #12, finding 3). Refused.
    foreach ($tv in @('$false', '$true')) {
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Json", $tv) -AsTyped
        Check ($r.code -eq 2 -and $r.out.Trim() -eq "" -and $r.err -like "*is followed by the value*" -and $r.err -like "*usage: horde echo-args*") ("a switch followed by a truth value is refused, never turned on" + ": -Json " + $tv + ", typed at a prompt (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    foreach ($code in @('& $horde echo-args -Json $false', '$v = $true; & $horde echo-args abc -Json $v')) {
        $r = Invoke-HordeInProcess -Root $tmp -Code $code
        Check ($r.code -eq 2 -and $r.out.Trim() -eq "" -and $r.err -like "*is followed by the value*") ("a switch followed by a truth value is refused, never turned on" + ", in-process: " + $code + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    # CONTROL: a truth value before the switch is a positional, as the refusal says to reorder it.
    $r = Invoke-HordeInProcess -Root $tmp -Code '& $horde echo-args $false -Json'
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[False] json=True count=0 verb=[]") ("a truth value before a switch is a positional, in-process (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # A switch named by its alias is a switch: [Alias("AsJson")] on echo-args' -Json, read from the AST.
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-AsJson", "false")
    Check ($r.code -eq 2 -and $r.err -like "*is followed by the word*") ("a switch named by its alias and followed by a truth word is refused (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # CONTROLS: the refusal is about switches and truth words only.
    # -Verb is echo-args' own [string] parameter and a prefix of the common switch -Verbose. PowerShell
    # binds an exact name before any prefix, so "false" is -Verb's value, not a switch's. echo-args
    # prints verb=, so this also says WHERE the word went: printing only target, json and count, the
    # line read the same whether "false" bound to -Verb or was dropped (third review of PR #12).
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Verb", "false")
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[] json=False count=0 verb=[false]") ("a parameter's exact name decides, though it is a prefix of a switch: -Verb false binds (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    foreach ($typed in @($false, $true)) {
        $how = "from a script"; if ($typed) { $how = "typed at a prompt" }
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Json", "abc") -AsTyped:$typed
        Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[abc] json=True count=0 verb=[]") ("a genuine positional after a switch still binds, " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Target", "false")
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[false] json=False count=0 verb=[]") ("the word false after a parameter that is not a switch is its value (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "false", "-Json")
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[false] json=True count=0 verb=[]") ("the word false before a switch is a positional, as the refusal says to reorder it (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # Asking a command for help is not an error: `horde echo-args -?` exited 1 with PowerShell's
    # '"helpTarget" is null' (review of PR #12, finding 6). -?, -h and --help after a command name
    # print its usage and summary and exit 0, as they print horde's help before one.
    foreach ($typed in @($false, $true)) {
        $how = "from a script"; if ($typed) { $how = "typed at a prompt" }
        foreach ($ask in @("-?", "-h", "--help")) {
            $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", $ask) -AsTyped:$typed
            Check ($r.code -eq 0 -and $r.out -like 'usage: horde echo-args `[<target>`]*reports how its arguments were bound*' -and $r.err.Trim() -eq "") ("asking a command for help prints its usage and exits 0: " + $ask + ", " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
        }
    }
    # A HELP WORD THAT IS A PARAMETER'S VALUE IS THE VALUE. `echo-args -Target:-h`, `-Verb:--help` and
    # `-Verb -h` printed the usage and exited 0 instead of running the command with that value (third
    # review of PR #12, finding 2). After a colon, or after a parameter that takes a value, the word
    # belongs to the parameter; the registry says which parameters are switches.
    $helpValues = @(
        @(@("-Target:-h"), "target=[-h] json=False count=0 verb=[]"),
        @(@("-Verb:--help"), "target=[] json=False count=0 verb=[--help]"),
        @(@("-Verb", "-h"), "target=[] json=False count=0 verb=[-h]"),
        @(@("-Verb", "-?"), "target=[] json=False count=0 verb=[-?]"),
        @(@("-Verb", "--help"), "target=[] json=False count=0 verb=[--help]"))
    foreach ($typed in @($false, $true)) {
        $how = "from a script"; if ($typed) { $how = "typed at a prompt" }
        foreach ($hv in $helpValues) {
            $r = Invoke-Horde -Root $tmp -Arguments (@("echo-args") + $hv[0]) -AsTyped:$typed
            Check ($r.code -eq 0 -and $r.out.Trim() -eq $hv[1]) ("a help word that is a parameter's value is bound, not taken as a request for help" + ": " + ($hv[0] -join " ") + ", " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
        }
        # CONTROL: after a switch it is still a request for help.
        $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Json", "-h") -AsTyped:$typed
        Check ($r.code -eq 0 -and $r.out -like "usage: horde echo-args*") ("a help word after a switch still asks for help" + ", " + $how + " (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    }
    # By a prefix of a parameter that takes a value, as PowerShell accepts one.
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Targ", "-h")
    Check ($r.code -eq 0 -and $r.out.Trim() -eq "target=[-h] json=False count=0 verb=[]") ("a help word after a prefix of a parameter that takes a value is bound to it (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # Typed, a colon joins the word to the switch, so it is the switch's value - which PowerShell then
    # refuses, exit 2 - and not a request for help.
    $r = Invoke-Horde -Root $tmp -Arguments @("echo-args", "-Json:-h") -AsTyped
    Check ($r.code -eq 2 -and $r.out.Trim() -eq "" -and $r.err -like "*usage: horde echo-args*") ("a help word joined to a switch by a colon is its value, not a request for help, typed at a prompt (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    # Typed at a prompt, "-Json:" with nothing after it is a PowerShell parse error before horde runs.
    # From a script it reaches horde as nothing at all, or swallows the next word, depending on
    # position (measured 2026-09-29) - and $args keeps no trace of it, so horde cannot refuse it.
    # The process command-line reader that once did is gone (see cli\Arguments.ps1); there is no test.
    $r = Invoke-Horde -Root $tmp -Arguments @("boom")
    Check ($r.code -eq 1 -and $r.err -like "*boom failed on purpose*") "a command that fails exits 1 and says why"
    # A binding error raised INSIDE a command's body is the command failing, not the command line being
    # wrong. Every ParameterBindingException used to mean exit 2 and the usage (review of PR #12,
    # finding 5).
    # horde exits 0, 1 or 2 and nothing else. `exit` inside a run block used to end horde itself:
    # `exit 7` made horde exit 7, and a bare `exit` made it exit 0 (review of PR #12, finding 6).
    foreach ($f in @("exit-seven", "exit-bare")) {
        $r = Invoke-Horde -Root $tmp -Arguments @($f)
        Check ($r.code -eq 1 -and $r.out -like ($f + " started*") -and $r.err -like ("horde " + $f + ": *exit*")) ("a command that calls exit makes horde exit 1 and says so" + ": " + $f + " (got " + $r.code + ": " + $r.err.Trim() + ")")
    }
    # `break` and `continue` in a body travel up the call stack to the nearest loop. With none in the
    # runner, a body's `cmd /c exit 3; break` skipped horde's completion and $LASTEXITCODE checks and
    # horde exited 0 (second review of PR #12, finding 3). A label that matches no loop escapes any
    # loop, the runner's included: measured 2026-09-29, it ended horde itself with exit 0.
    foreach ($typed in @($false, $true)) {
        $how = "from a script"; if ($typed) { $how = "typed at a prompt" }
        # Each is told apart by its message, so that the runner's loop (break, continue) and horde's
        # finally block (the unmatched label) are each held by a test: without the loop, a plain break
        # would reach the finally block too and still exit 1.
        foreach ($f in @("break", "continue", "label")) {
            $said = "horde flow: the command did not return*break or continue*"
            if ($f -eq "label") { $said = "horde flow: *break or continue, and no loop took it*" }
            $r = Invoke-Horde -Root $tmp -Arguments @("flow", $f) -AsTyped:$typed
            Check ($r.code -eq 1 -and $r.out.Trim() -eq "flow started" -and $r.err -like $said) ("a command that leaves its body with break or continue makes horde exit 1" + ": " + $f + ", " + $how + " (got " + $r.code + ": " + $r.out.Trim() + " / " + $r.err.Trim() + ")")
        }
    }
    $r = Invoke-Horde -Root $tmp -Arguments @("flow", "return")
    Check ($r.code -eq 0 -and $r.out -like "flow started*flow returned*") ("CONTROL: the same command, returning, exits 0 (got " + $r.code + ": " + $r.err.Trim() + ")")
    # A command body runs in a scope below horde's and the runner's, so it could read and change their
    # variables: a body that set $state.completed = $true and then called `exit 0` made horde exit 0
    # (second review of PR #12, finding 5). They are private now; the body sees none of them.
    foreach ($typed in @($false, $true)) {
        $how = "from a script"; if ($typed) { $how = "typed at a prompt" }
        $r = Invoke-Horde -Root $tmp -Arguments @("peek") -AsTyped:$typed
        Check ($r.out.Trim() -eq "seen=[]") ("a command body cannot see horde's own variables" + ", " + $how + " (got " + $r.out.Trim() + ")")
        Check ($r.code -eq 1 -and $r.err -like "horde peek: the command did not return*") ("and cannot fake having returned" + ", " + $how + " (got " + $r.code + ": " + $r.err.Trim() + ")")
    }
    # A SUSTAINED COMMAND RUNS OPTED OUT OF POWER THROTTLING; ANY OTHER NEVER LOADS THE TYPE (core/Platform.ps1).
    $r = Invoke-Horde -Root $tmp -Arguments @("busy")
    Check ($r.code -eq 0 -and $r.out -match 'THROTTLE known 1/0') ("a command declared sustained runs opted out of power throttling (got " + $r.code + ": " + $r.out.Trim() + $r.err.Trim() + ")")
    Check ($r.out -match 'LEAKED no') ("and the dispatcher's opt-out leaks no core function into its run block (review of PR #79, point 5; got " + $r.out.Trim() + ")")
    Check ($r.out -match 'valid=True' -and $r.out -match 'BOGUS-SPACE refused=True') ("so core loaded by the command itself works as written: answers validate, a bogus process space is refused (got " + $r.out.Trim() + ")")
    $r = Invoke-Horde -Root $tmp -Arguments @("quick")
    Check ($r.code -eq 0 -and $r.out -match 'TYPE none') ("a command not declared sustained never loads the throttling type, so it pays nothing for it (got " + $r.out.Trim() + $r.err.Trim() + ")")
    # HELP DESCRIBES THE COMMANDS AS THEY ARE, NOT AS THEY WERE (YedPool/wezfleet 80aa026: a help text
    # that described the old kill and the old tell). The summary is read here from the file's text,
    # not through the registry, then changed on disk; help must follow the file.
    $echoFile = Join-Path $standInCommands "echo-args.ps1"
    $oldSummary = [regex]::Match((Get-Content -LiteralPath $echoFile -Raw), 'summary\s*=\s*"([^"]+)"').Groups[1].Value
    $h = Invoke-Horde -Root $tmp -Arguments @("help")
    Check ($oldSummary -ne "" -and $h.out -like ("*" + $oldSummary + "*")) "CONTROL: help shows the summary the file declares"
    $newSummary = "a summary changed on disk after the first help - " + [guid]::NewGuid().ToString("N")
    Set-Content -LiteralPath $echoFile -Value ((Get-Content -LiteralPath $echoFile -Raw).Replace($oldSummary, $newSummary)) -NoNewline
    $h = Invoke-Horde -Root $tmp -Arguments @("help")
    Check ($h.out -like ("*" + $newSummary + "*") -and $h.out -notlike ("*" + $oldSummary + "*")) "help shows a command's summary as its file says it now, not as it was"
    Set-Content -LiteralPath $echoFile -Value ((Get-Content -LiteralPath $echoFile -Raw).Replace($newSummary, $oldSummary)) -NoNewline

    # A program a command runs and leaves failed: horde used to exit 0 (review of PR #12, finding 6).
    $r = Invoke-Horde -Root $tmp -Arguments @("native-fail")
    Check ($r.code -eq 1 -and $r.out -like "native-fail started*" -and $r.err -like "horde native-fail: *exit code 3*") ("a program a command leaves failed makes horde exit 1 and say so (got " + $r.code + ": " + $r.err.Trim() + ")")
    # And one it handles is not a failure: version, in a folder whose .git points nowhere, runs git,
    # sees it fail, and says the commit is unknown. git exits 128 there without searching the parent
    # folders (measured).
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Set-Content -LiteralPath (Join-Path $tmp ".git") -Value "gitdir: does-not-exist"
        $r = Invoke-Horde -Root $tmp -Arguments @("version")
        Check ($r.code -eq 0 -and $r.out -like "*commit unknown*") ("a program failure the command handles is not a failure: version with a broken .git (got " + $r.code + ": " + $r.out.Trim() + ")")
        Remove-Item -LiteralPath (Join-Path $tmp ".git") -Force
    } else {
        Write-Host "  [SKIP] git is not on PATH, so a handled program failure cannot be tested here" -ForegroundColor Yellow
    }
    $r = Invoke-Horde -Root $tmp -Arguments @("inner-bind")
    Check ($r.code -eq 1 -and $r.err -like "horde inner-bind: *NoSuchParameterForHordeTests*" -and $r.err -notlike "*usage:*") ("a binding error inside a command's body exits 1 without the usage" + " (got " + $r.code + ": " + $r.err.Trim() + ")")
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    $r = Invoke-Horde -Root $tmp -Arguments @("side-effect")
    Check ($r.code -eq 1 -and $r.err.StartsWith("horde side-effect: ") -and $r.err -like "*top-level statements*") ("a broken command file is reported under its command's name and exits 1 (got " + $r.code + ": " + $r.err.Trim() + ")")
    Check (-not (Test-Path -LiteralPath $marker)) "and none of the broken file ran"
}
finally {
    # nul.ps1 first, through the same \?\ path that made it: an ordinary path names the device.
    if ([System.IO.File]::Exists($nulPath)) { [System.IO.File]::Delete($nulPath) }
    if ((Split-Path -Leaf $tmp) -match '^horde-cli-test-[0-9a-f]{32}$') { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Check (-not (Test-Path -LiteralPath $tmp)) "the stand-in root was removed"

Complete-HordeSuite -Success "every command is declared once, and every argument reaches it"
