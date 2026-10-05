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
        # The serve loop's recovery paths (review of PR #81, F1): a fault while answering, a result the
        # writer refuses, and a listener that keeps failing.
        @{ Name = "answer-fault-kills-node"
           Find = '$why = "$($_.Exception.Message)"'
           Replace = 'throw' }
        @{ Name = "refused-result-not-replaced"
           Find = 'if (-not $bytes.ok -and "$($Frame.kind)" -ceq "res") {'
           Replace = 'if ($false) {' }
        @{ Name = "relisten-limit-ignored"
           Find = 'if ($inARow -gt $RelistenLimit) {'
           Replace = 'if ($false) {' }
        @{ Name = "relisten-skipped"
           Find = 'Start-Sleep -Milliseconds 1000'
           Replace = 'Start-Sleep -Milliseconds 1000; $relistens++; continue' }
        @{ Name = "relisten-no-backoff"
           Find = 'Start-Sleep -Milliseconds 1000'
           Replace = '' }
        @{ Name = "fast-accept-failure-taken-as-timeout"
           Find = 'if ($took -ge ($AcceptTimeoutMs / 2)) { $inARow = 0; continue }'
           Replace = '$inARow = 0; continue' }
        @{ Name = "refused-peer-treated-as-broken-listener"
           Find = 'if ($null -ne $acc.PSObject.Properties["refused"] -and $acc.refused -eq $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "refusal-not-logged"
           Find = '[void]$refusals.Add($why)'
           Replace = '' }
        @{ Name = "refusal-list-uncapped"
           Find = 'if ($refusals.Count -gt $script:HordeNodeRefusalsKept) { $refusals.RemoveAt(0) }'
           Replace = '' }
        @{ Name = "refusal-does-not-reset-the-run"
           Find = '$inARow = 0  # reset by a refusal'
           Replace = '' }
        @{ Name = "refusals-logged-one-by-one"
           Find = 'if ($refusedCount -le $script:HordeNodeRefusalsLogged) {'
           Replace = 'if ($true) {' }
        @{ Name = "control-characters-logged"
           Find = 'return ($Text -replace ''[\x00-\x1F\x7F]'', ''?'')'
           Replace = 'return $Text' }
    )
}
