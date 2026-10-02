# Mutations of cli/NodeServe.ps1, the serve loop. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\node-serve-loop.psd1
# Each breaks one rule of the loop (remote plan R12a); test\test-node-serve.ps1, whose last section runs
# the loop over the memory transport, must fail for every one.
@{
    Target = "cli\NodeServe.ps1"
    Suite  = "test\test-node-serve.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "view-reused-across-requests"
           Find = 'try { $data.view = & $GetView } catch {'
           Replace = 'if ($null -eq $script:cachedView) { $script:cachedView = & $GetView }; try { $data.view = $script:cachedView } catch {' }
        @{ Name = "view-failure-not-caught"
           Find = 'try { $data.view = & $GetView } catch { $data.viewError = "$($_.Exception.Message)" }'
           Replace = '$data.view = & $GetView' }
        @{ Name = "idle-limit-ignored"
           Find = '$line = Receive-HordeLinkFrame -Link $link -TimeoutMs $IdleTimeoutMs'
           Replace = '$line = Receive-HordeLinkFrame -Link $link -TimeoutMs 600000' }
        @{ Name = "protocol-close-ignored"
           Find = 'if ($r.close) { $ended = "closed by the protocol"; break }'
           Replace = '' }
        @{ Name = "manifest-names-another-device"
           Find = '        deviceId = "$($Node.deviceId)"'
           Replace = '        deviceId = "7c9e6679-7425-40de-944b-e07fc1f90ae7"' }
    )
}
