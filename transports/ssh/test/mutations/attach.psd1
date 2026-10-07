# Mutations of the one builder of a device's forced command (transports/ssh/Attach.ps1, remote plan
# R17b). Run: powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\attach.psd1
# transports\ssh\test\test-enroll.ps1 must fail for each.
@{
    Target = "transports\ssh\Attach.ps1"
    Suite  = "transports\ssh\test\test-enroll.ps1"
    Mutations = @(
        # R17a: horde.ps1 attach hangs at exit while stdin is an open pipe; the shim is cli\attach.ps1.
        @{ Name = "attach-via-horde-ps1"
           Find = '$HordeRoot.TrimEnd(''\'') + "\cli\attach.ps1"'
           Replace = '$HordeRoot.TrimEnd(''\'') + "\horde.ps1"' }
        @{ Name = "powershell-by-path-lookup"
           Find = '$script:HordeSshAttachPowerShell = [System.IO.Path]::Combine([System.Environment]::SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe")'
           Replace = '$script:HordeSshAttachPowerShell = "powershell.exe"' }
        # Review of PR #111, N1 and N2: cmd.exe runs the forced command, and C:h or \h is not a full path.
        @{ Name = "unsafe-root-accepted"
           Find = 'if ($HordeRoot -cnotmatch ''\A[A-Za-z]:\\[A-Za-z0-9\\._-]*\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "cmd-metacharacters-accepted"
           Find = '''\A[A-Za-z]:\\[A-Za-z0-9\\._-]*\z'') { throw ("Horde''s root'
           Replace = '''\A[A-Za-z]:\\[^\s"]*\z'') { throw ("Horde''s root' }
        @{ Name = "relative-root-accepted"
           Find = 'if ($HordeRoot -cnotmatch ''\A[A-Za-z]:\\'') {'
           Replace = 'if ($false) {' }
        @{ Name = "device-unchecked"
           Find = 'if ($DeviceId -cnotmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'') {'
           Replace = 'if ($false) {' }
    )
}
