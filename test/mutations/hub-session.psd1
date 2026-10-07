# Mutations of cli/commands/session.ps1 (the act path's A4, review of #126). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-session.psd1
# test\test-hub-act.ps1 must fail for every one.
@{
    Target = "cli\commands\session.ps1"
    Suite  = "test\test-hub-act.ps1"
    Mutations = @(
        @{ Name = "spawn-node-defaulted"
           Find = '                    if ($Node -eq "") { throw "session spawn needs -Node: the node is always named, never defaulted to the hub''s own machine" }'
           Replace = '' }
    )
}
