# Mutations of the tmux isolation harness that only a real server can catch. Run:
#   powershell -File tools\Mutate.ps1 -Spec hosts\tmux\test\mutations\isolation-e2e.psd1
# The suite is the e2e, so each mutant runs against real isolated servers in WSL. A mutant that breaks
# containment lets the e2e's markless children escape; they sleep for a few minutes at most and the
# e2e's own cleanup kills them by their unique command line, so a mutant run leaves nothing behind.
@{
    Target = "hosts\tmux\test\Isolation.ps1"
    Suite  = "hosts\tmux\test\e2e\e2e-isolation.ps1"
    Mutations = @(
        @{ Name = "owner-without-pid-namespace"
           Find = '@("unshare", "--pid", "--fork", "--kill-child", "--mount-proc",'
           Replace = '@("unshare", "--fork", "--kill-child", "--mount-proc",' }
        @{ Name = "no-crash-exit"
           Find = '{ cat >/dev/null; kill -TERM "$srv" 2>/dev/null; } <&3 &'
           Replace = ':' }
        @{ Name = "crash-exit-leaves-the-directory"
           Find = 'rmdir -- "$sub" "$dir" 2>/dev/null'
           Replace = ':' }
    )
}
