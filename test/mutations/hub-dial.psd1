# Mutations of the hub's dialled links (cli/HubServe.ps1; remote plan R17c). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-dial.psd1
# test\test-hub-dial.ps1 must fail for each. The preamble checks are this file's stand-in for R17a's
# Read-HordeAttachPreamble; the cases keep holding when the stand-in becomes a call to it.
@{
    Target = "cli\HubServe.ps1"
    Suite  = "test\test-hub-dial.ps1"
    Mutations = @(
        @{ Name = "preamble-not-required"
           Find = 'if ($dev.state -cne "known") { return ("a dialled link was refused: " + $dev.reason) }'
           Replace = 'if ($dev.state -cne "known") { $dev = New-HordeKnown -Value "0f8fad5b-d9cb-469f-a165-70867728950e" }' }
        @{ Name = "preamble-read-from-a-later-line"
           Find = '$dev = Read-HordeAttachPreamble -Line "$($first.value)"'
           Replace = '$dev = Read-HordeAttachPreamble -Line ("horde-attach 1 " + "$($first.value)".Split(" ")[-1])' }
        @{ Name = "dialled-link-left-open"
           Find = '    } finally { Close-HordeLink -Link $Link }'
           Replace = '    } finally { }' }
        @{ Name = "listener-window-skipped"
           Find = 'if ($null -ne $Listener) {'
           Replace = 'if ($false) {' }
    )
}
