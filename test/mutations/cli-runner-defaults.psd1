# Mutations of the runner's one rule about a session's parameter defaults. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\cli-runner-defaults.psd1
# The rule is in cli\Runner.ps1: a command is bound with what was typed and never with the calling
# session's $PSDefaultParameterValues. It is seen only where a real command is started from inside such
# a session, which test\e2e\e2e-wake.ps1 does; test\test-cli.ps1, the runner's own suite, starts no
# session with defaults set.
@{
    Target = "cli\Runner.ps1"
    Suite  = "test\e2e\e2e-wake.ps1"
    Mutations = @(
        @{ Name = "a-sessions-parameter-defaults-reach-the-command"
           Find = '$PSDefaultParameterValues = @{}'
           Replace = '' }
    )
}
