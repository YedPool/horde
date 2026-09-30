# Mutations of the runner. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\cli-runner.psd1
# Each breaks one rule cli\Runner.ps1 enforces; test\test-cli.ps1 must fail for every one of them.
@{
    Target = "cli\Runner.ps1"
    Suite  = "test\test-cli.ps1"
    Mutations = @(
        @{ Name = "no-loop-for-break"
           Find = 'do { & $Run @Named @Positional; $State.completed = $true } while ($false)'
           Replace = '& $Run @Named @Positional; $State.completed = $true' }
        @{ Name = "completion-never-recorded"
           Find = '; $State.completed = $true }'
           Replace = ' }' }
        @{ Name = "runner-variables-visible-to-body"
           Find = '(Get-Variable -Name $hordeParam -Scope Local).Options = "Private"'
           Replace = '$null = $hordeParam' }
    )
}
