# Mutations of the node's dialling loop (cli/NodeServe.ps1, Invoke-HordeNodeDial; remote plan R17c).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\node-dial.psd1
# test\test-hub-dial.ps1 must fail for each.
@{
    Target = "cli\NodeServe.ps1"
    Suite  = "test\test-hub-dial.ps1"
    Mutations = @(
        @{ Name = "dialled-link-unserved"
           Find = '$ended = Invoke-HordeNodeLink -Link $open.value -Manifest $Manifest -Namespace $Namespace -GetView $GetView -Contract $contract -JournalRoot $JournalRoot -Act $Act -Messaging $Messaging -ReadOnly:$ReadOnly -IdleTimeoutMs $IdleTimeoutMs'
           Replace = 'Close-HordeLink -Link $open.value; $ended = "closed by the protocol"' }
        @{ Name = "backoff-flat"
           Find = '$wait = [int][Math]::Min($BackoffMaxMs, 1000 * [Math]::Pow(2, [Math]::Min(16, $streak - 1)))'
           Replace = '$wait = 1000' }
        @{ Name = "backoff-unbounded"
           Find = '$wait = [int][Math]::Min($BackoffMaxMs, 1000 * [Math]::Pow(2, [Math]::Min(16, $streak - 1)))'
           Replace = '$wait = [int](1000 * [Math]::Pow(2, [Math]::Min(16, $streak - 1)))' }
        @{ Name = "no-wait-between-dials"
           Find = '        Start-Sleep -Milliseconds $wait'
           Replace = '' }
    )
}
