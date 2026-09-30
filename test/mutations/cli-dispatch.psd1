# Mutations of the dispatcher. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\cli-dispatch.psd1
# Each breaks one rule horde.ps1 enforces; test\test-cli.ps1 must fail for every one of them.
@{
    Target = "horde.ps1"
    Suite  = "test\test-cli.ps1"
    Mutations = @(
        @{ Name = "forwards-through-remaining-arguments"
           Find = '$ErrorActionPreference = "Stop"'
           Replace = "param([Parameter(Position = 0)]`$Command, [Parameter(ValueFromRemainingArguments = `$true)]`$Rest)`n`$ErrorActionPreference = `"Stop`"" }
        # -?, -h and --help.
        # The command's items, taken with every $null in its place.
        @{ Name = "rest-drops-null"
           Find = 'if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }'
           Replace = '$rest = @($args | Select-Object -Skip 1)' }
        @{ Name = "no-default-to-help"
           Find = 'if ($name -eq "" -or $name -eq "--help" -or $name -eq "-h" -or $name -eq "-?") { $name = "help" }'
           Replace = 'if ($name -eq "") { $name = "help" }' }
        @{ Name = "command-help-not-asked-for"
           Find = 'if (Test-HordeHelpRequest -Items $rest -Parameters $lookup.command.parameters) {'
           Replace = 'if ($false) {' }
        @{ Name = "command-help-without-parameters"
           Find = 'Test-HordeHelpRequest -Items $rest -Parameters $lookup.command.parameters'
           Replace = 'Test-HordeHelpRequest -Items $rest' }
        @{ Name = "command-help-exits-one"
           Find = 'Write-Output ("    " + $lookup.command.summary)'
           Replace = 'Write-Output ("    " + $lookup.command.summary); exit 1' }
        # Exit codes: 2 for a wrong command line, 1 for a failed command, 0 only for a returned one.
        @{ Name = "broken-file-is-unknown-command"
           Find = 'if (@($lookup.findings).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-command-exits-zero"
           Find = 'Format-HordeHelp | ForEach-Object { [Console]::Error.WriteLine($_) }'
           Replace = 'Format-HordeHelp | ForEach-Object { [Console]::Error.WriteLine($_) }; exit 0' }
        @{ Name = "argument-problem-exits-one"
           Find = '[Console]::Error.WriteLine("horde " + $name + ": " + $bound.problem)'
           Replace = '[Console]::Error.WriteLine("horde " + $name + ": " + $bound.problem); exit 1' }
        @{ Name = "switch-words-not-checked"
           Find = 'Resolve-HordeArguments -Items $rest -Parameters $lookup.command.parameters'
           Replace = 'Resolve-HordeArguments -Items $rest' }
        @{ Name = "binding-error-is-a-plain-failure"
           Find = 'catch [System.Management.Automation.ParameterBindingException] {'
           Replace = 'catch [System.ArgumentNullException] {' }
        @{ Name = "body-binding-error-is-command-line"
           Find = 'if (-not $isOwn) { exit 1 }'
           Replace = '' }
        @{ Name = "exit-in-body-accepted"
           Find = 'if (-not $state.completed) {'
           Replace = 'if ($false) {' }
        @{ Name = "unmatched-label-accepted"
           Find = 'if (-not $settled) {'
           Replace = 'if ($false) {' }
        @{ Name = "failed-program-accepted"
           Find = 'if ($LASTEXITCODE -ne 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "stale-exit-code-not-cleared"
           Find = '    $global:LASTEXITCODE = 0'
           Replace = '    $null = 0' }
        # Horde's variables are private.
        @{ Name = "state-visible-to-body"
           Find = '$private:state = @{ completed = $false }'
           Replace = '$state = @{ completed = $false }' }
    )
}
