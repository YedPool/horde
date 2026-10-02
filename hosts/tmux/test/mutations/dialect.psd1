# Mutations of the shared dialect's data. Run: powershell -File tools\Mutate.ps1 -Spec hosts\tmux\test\mutations\dialect.psd1
# Each changes the list another host scrubs; hosts\tmux\test\test-dialect.ps1 must fail for every one.
# The suite starts nothing, so no mutant here can reach a real server.
@{
    Target = "hosts\tmux\Dialect.ps1"
    Suite  = "hosts\tmux\test\test-dialect.ps1"
    Mutations = @(
        @{ Name = "pane-variable-dropped"
           Find = 'return @("TMUX", "TMUX_PANE")'
           Replace = 'return @("TMUX")' }
        @{ Name = "socket-folder-variable-added"
           Find = 'return @("TMUX", "TMUX_PANE")'
           Replace = 'return @("TMUX", "TMUX_PANE", "TMUX_TMPDIR")' }
        @{ Name = "variable-lower-cased"
           Find = 'return @("TMUX", "TMUX_PANE")'
           Replace = 'return @("TMUX", "tmux_pane")' }
        @{ Name = "variables-swapped"
           Find = 'return @("TMUX", "TMUX_PANE")'
           Replace = 'return @("TMUX_PANE", "TMUX")' }
        @{ Name = "variable-not-the-hosts"
           Find = 'return @("TMUX", "TMUX_PANE")'
           Replace = 'return @("TMUX", "PANE_ID")' }
    )
}
