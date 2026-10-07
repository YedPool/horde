# Mutations of the one builder of a device's forced command (transports/ssh/Attach.ps1, remote plan
# R17b). Run: powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\attach.psd1
# transports\ssh\test\test-enroll.ps1 must fail for each.
@{
    Target = "transports\ssh\Attach.ps1"
    Suite  = "transports\ssh\test\test-enroll.ps1"
    Mutations = @(
        # R17a: horde.ps1 attach hangs at exit while stdin is an open pipe; the shim is cli\attach.ps1.
        @{ Name = "attach-via-horde-ps1"
           Find = '[System.IO.Path]::Combine($HordeRoot, "cli", "attach.ps1")'
           Replace = '[System.IO.Path]::Combine($HordeRoot, "horde.ps1")' }
        @{ Name = "powershell-by-path-lookup"
           Find = '$script:HordeSshAttachPowerShell = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")'
           Replace = '$script:HordeSshAttachPowerShell = "powershell.exe"' }
        @{ Name = "root-with-space-accepted"
           Find = 'if ($exe -match ''[\s"]'' -or $script -match ''[\s"]'') {'
           Replace = 'if ($false) {' }
        @{ Name = "relative-root-accepted"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($HordeRoot)) {'
           Replace = 'if ($false) {' }
        @{ Name = "device-unchecked"
           Find = 'if ($DeviceId -cnotmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'') {'
           Replace = 'if ($false) {' }
    )
}
