# Mutations of horde node serve -Dial's hand-over (cli/commands/node.ps1; remote plan R17c). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\node-dial-cli.psd1
# test\test-hub-dial.ps1 must fail for each: the dial loop gets the node's acts, messaging and -ReadOnly.
@{
    Target = "cli\commands\node.ps1"
    Suite  = "test\test-hub-dial.ps1"
    Mutations = @(
        @{ Name = "cli-dial-drops-readonly"
           Find = '-Act $act -Messaging $messaging -ReadOnly:$ReadOnly -MaxDials $MaxLinks'
           Replace = '-Act $act -Messaging $messaging -MaxDials $MaxLinks' }
        @{ Name = "cli-dial-drops-messaging"
           Find = '-Act $act -Messaging $messaging -ReadOnly:$ReadOnly -MaxDials $MaxLinks'
           Replace = '-Act $act -ReadOnly:$ReadOnly -MaxDials $MaxLinks' }
    )
}
