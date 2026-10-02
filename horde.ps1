# horde - the one entry point. Every command is a file under cli\commands; this file only finds
# the one asked for and runs it. It names no command, so it never needs editing to add one.
#
# NO PARAM BLOCK, AND THAT IS LOAD-BEARING. Arguments are forwarded to the command from $args.
# Measured 2026-09-29 on PowerShell 5.1: an array taken from $args keeps "-Json" as a switch when
# splatted on, but a param with ValueFromRemainingArguments, or any hand-built array, turns it into
# the literal string "-Json" bound to the first positional parameter - silently. test\test-cli.ps1
# fails if this file grows a param block. A value joined to its parameter with a colon (-Json:$false)
# arrives in $args as two items; cli\Arguments.ps1 rejoins them when PowerShell kept the colon.
# When -File mode dropped it, and the value could only have been meant for the switch, it refuses
# rather than guess: the text $true, $false or $null anywhere, and a switch followed by true,
# false, 0, 1, yes, no, on or off, or by a real true/false value. cli\Arguments.ps1 lists the shapes
# that remain undetectable.
#
# EXIT CODES ARE 0, 1 OR 2, AND NOTHING ELSE, so a caller can act on them:
#   0  the command ran and returned, or help was asked for: `horde`, `horde --help`, or -?, -h or
#      --help anywhere after a command name, which prints that command's usage
#   1  the command failed: it threw, its file is broken, it called `exit` - with any code, 0
#      included, because a command reports failure by throwing and success by returning, and an
#      `exit` skips horde's own reporting - or it left its body with `break` or `continue` outside a
#      loop of its own, which skips it the same way, or it returned with $LASTEXITCODE not 0, meaning the
#      last program it ran failed and it did not say it had handled that. A command that handles a
#      program's failure itself sets $global:LASTEXITCODE = 0 (see cli\commands\version.ps1).
#   2  the command line was wrong: an unknown command, or arguments the command does not accept
#
# TWO LIMITS ON THAT PROMISE, both measured 2026-09-29 on PowerShell 5.1:
# - A command that calls [Environment]::Exit(n) ends the whole process at once, and horde exits n:
#   `[Environment]::Exit(5)` in a body gave exit 5. Nothing in a script can prevent or observe it;
#   a command must return or throw, and review is what holds it to that.
# - Run as `powershell -Command "& horde.ps1 ..."`, the process exits with 0 or 1 - whether the
#   last statement succeeded - not with horde's code: an unknown command gave 1, not 2. A -Command
#   caller that wants 0, 1 or 2 appends `; exit $LASTEXITCODE`, which gave 2. `powershell -File`
#   passes horde's code through as it is.

$ErrorActionPreference = "Stop"
# OUT OF POWER THROTTLING FIRST (core/Platform.ps1). A busy background process on Windows slows about
# 3 s in, measured 2026-10-02: an empty call 23 us to 165 us. horde status and metrics collect run that
# long. Off Windows this does nothing. It costs one type compile, about 0.2 s, measured the same day.
. (Join-Path $PSScriptRoot "core\Platform.ps1")
$null = Set-HordeThrottlingOptOut
. (Join-Path $PSScriptRoot "cli\Commands.ps1")
. (Join-Path $PSScriptRoot "cli\Arguments.ps1")

# HORDE'S OWN VARIABLES ARE PRIVATE. A command body runs in a scope below this script's, and saw
# every variable here: a body that set $state.completed = $true and called `exit 0` made horde exit 0
# (second review of PR #12, finding 5). $private: hides them from the body's ordinary lookups - and from
# the Where-Object blocks below, which is why none of those names one. It does not hide them from a
# body that asks for this scope by number (Get-Variable -Scope 2), measured 2026-09-29: this keeps a
# body from colliding with horde by accident, and is not a wall against one that means to.
$private:name = ""
if ($args.Count -gt 0) { $name = "$($args[0])" }
# AN INDEX SLICE, NOT `$args | Select-Object -Skip 1`. A pipeline drops a $null item: in-process,
# `$m = $null; horde echo-args -Verb:$m target` bound verb=[target] target=[], exit 0 - the next word
# became the value (third review of PR #12, finding 1). A slice keeps the $null in its place, and
# keeps each item's parameter tag (measured 2026-09-30, cli\Arguments.ps1 says which copies lose it).
$private:rest = @()
if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }

if ($name -eq "" -or $name -eq "--help" -or $name -eq "-h" -or $name -eq "-?") { $name = "help" }

$private:lookup = Find-HordeCommand -Name $name
if (-not $lookup.command) {
    # A file of that name that is broken is not an unknown command: the command line was right and
    # the installation is wrong, so it is exit 1, under the command's own name.
    if (@($lookup.findings).Count -gt 0) {
        [Console]::Error.WriteLine("horde " + $name + ": its command file is broken: " + ($lookup.findings -join "; "))
        exit 1
    }
    [Console]::Error.WriteLine("horde: unknown command '" + $name + "'")
    Format-HordeHelp | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 2
}

# -?, -h or --help after a command name asks for that command's help, as they ask for horde's before
# one. Left to PowerShell, -? failed with '"helpTarget" is null' and exit 1, -h was an unknown
# parameter, and typed --help became the value of the first positional parameter (review of PR #12).
# Not when it is a parameter's value: -Verb -h runs the command with -Verb "-h" (cli\Arguments.ps1).
if (Test-HordeHelpRequest -Items $rest -Parameters $lookup.command.parameters) {
    Write-Output ("usage: horde " + $lookup.command.usage)
    Write-Output ("    " + $lookup.command.summary)
    exit 0
}

$private:bound = Resolve-HordeArguments -Items $rest -Parameters $lookup.command.parameters
if ($bound.problem) {
    [Console]::Error.WriteLine("horde " + $name + ": " + $bound.problem)
    [Console]::Error.WriteLine("usage: horde " + $lookup.command.usage)
    exit 2
}
$private:named = $bound.named
$private:positional = $bound.positional
$private:runner = Join-Path $PSScriptRoot "cli\Runner.ps1"

$private:state = @{ completed = $false }
# Whether control came back to this script by any ordinary route: the runner returned, or a catch
# block took an exception. A labelled `break` or `continue` whose label matches no loop is neither -
# it is not an exception a catch can take, and it passes the runner's loop - and measured 2026-09-29
# it ended horde with exit 0. Only the finally block below sees it go by.
$private:settled = $false
try {
    # Loading is inside the handled path, so a file that fails to load is reported under the
    # command's name with exit 1, never as a bare PowerShell error (review of PR #12, finding 10).
    $private:command = Import-HordeCommand -Path $lookup.command.path
    $global:LASTEXITCODE = 0
    & $runner -Run $command.run -Named $named -Positional $positional -State $state
    $settled = $true
}
catch [System.Management.Automation.ParameterBindingException] {
    $settled = $true
    # Only the run block's own binding is a command-line error; cli\Runner.ps1 says how that is told.
    $private:isOwn = $null -ne $_.Exception.CommandInvocation -and "$($_.Exception.CommandInvocation.ScriptName)" -ieq $runner
    [Console]::Error.WriteLine("horde " + $name + ": " + $_.Exception.Message)
    if (-not $isOwn) { exit 1 }
    [Console]::Error.WriteLine("usage: horde " + $lookup.command.usage)
    exit 2
}
catch {
    $settled = $true
    [Console]::Error.WriteLine("horde " + $name + ": " + $_.Exception.Message)
    exit 1
}
finally {
    if (-not $settled) {
        [Console]::Error.WriteLine("horde " + $name + ": the command left its body with break or continue, and no loop took it; a command returns, or throws to fail")
        exit 1
    }
}
if (-not $state.completed) {
    [Console]::Error.WriteLine("horde " + $name + ": the command did not return - it called exit, or used break or continue outside a loop (last exit code " + $LASTEXITCODE + "); a command returns, or throws to fail")
    exit 1
}
# A program the command ran and left failed. Only the LAST program's code survives in $LASTEXITCODE,
# so this catches a command that ends on an unchecked failure, not one that ignored a failure earlier
# and ran something that succeeded after it; checking each program remains the command's job.
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("horde " + $name + ": a program it ran failed with exit code " + $LASTEXITCODE + ", and the command did not handle it")
    exit 1
}
exit 0
