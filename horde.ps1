# horde - the one entry point. Every command is a file under cli\commands; this file only finds
# the one asked for and runs it. It names no command, so it never needs editing to add one.
#
# NO PARAM BLOCK, AND THAT IS LOAD-BEARING. Arguments are forwarded to the command from $args.
# Measured 2026-09-29 on PowerShell 5.1: an array taken from $args keeps "-Json" as a switch when
# splatted on, but a param with ValueFromRemainingArguments, or any hand-built array, turns it into
# the literal string "-Json" bound to the first positional parameter - silently. test\test-cli.ps1
# fails if this file grows a param block. A value joined to its parameter with a colon (-Json:$false)
# arrives in $args as two items and is rejoined by cli\Arguments.ps1, which says how.
#
# Exit codes: 0 ran, 1 the command failed, 2 the command line was wrong (unknown command or
# arguments the command does not accept).

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "cli\Commands.ps1")
. (Join-Path $PSScriptRoot "cli\Arguments.ps1")

$name = ""
if ($args.Count -gt 0) { $name = "$($args[0])" }
$rest = @($args | Select-Object -Skip 1)

if ($name -eq "" -or $name -eq "--help" -or $name -eq "-h" -or $name -eq "-?") { $name = "help" }

$lookup = Find-HordeCommand -Name $name
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

$raw = Get-HordeFileModeArguments -ScriptPath $PSCommandPath
$rawRest = $null
if ($raw.found) { $rawRest = @($raw.args | Select-Object -Skip 1) }
$bound = Resolve-HordeArguments -Items $rest -Raw $rawRest
if ($bound.problem) {
    [Console]::Error.WriteLine("horde " + $name + ": " + $bound.problem)
    [Console]::Error.WriteLine("usage: horde " + $lookup.command.usage)
    exit 2
}
$named = $bound.named
$positional = $bound.positional
$runner = Join-Path $PSScriptRoot "cli\Runner.ps1"

try {
    # Loading is inside the handled path, so a file that fails to load is reported under the
    # command's name with exit 1, never as a bare PowerShell error (review of PR #12, finding 10).
    $command = Import-HordeCommand -Path $lookup.command.path
    & $runner -Run $command.run -Named $named -Positional $positional
}
catch [System.Management.Automation.ParameterBindingException] {
    # Only the run block's own binding is a command-line error; cli\Runner.ps1 says how that is told.
    $isOwn = $null -ne $_.Exception.CommandInvocation -and "$($_.Exception.CommandInvocation.ScriptName)" -ieq $runner
    [Console]::Error.WriteLine("horde " + $name + ": " + $_.Exception.Message)
    if (-not $isOwn) { exit 1 }
    [Console]::Error.WriteLine("usage: horde " + $lookup.command.usage)
    exit 2
}
catch {
    [Console]::Error.WriteLine("horde " + $name + ": " + $_.Exception.Message)
    exit 1
}
exit 0
