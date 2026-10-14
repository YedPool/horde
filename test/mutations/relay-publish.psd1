# Mutations of cli/RelayPublish.ps1, the pass's step that keeps the hosted phone page current. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-publish.psd1
# Each breaks one guard of the rule; test\test-relay-publish.ps1 must fail for every one.
@{
    Target = "cli\RelayPublish.ps1"
    Suite  = "test\test-relay-publish.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "relay-change-not-the-relay"
           Find = '        elseif ($p.StartsWith($script:HordeRelayPublishRelayPrefix, [System.StringComparison]::Ordinal)) { [void]$relay.Add($p) }'
           Replace = '' }
        @{ Name = "relay-change-deployed"
           Find = 'if (@($Classes.relay).Count -gt 0) { return (& $say "warn" "relay-changed"'
           Replace = 'if ($false) { return (& $say "warn" "relay-changed"' }
        @{ Name = "other-change-deployed"
           Find = 'if (@($Classes.other).Count -gt 0) { return (& $say "warn" "other-changed"'
           Replace = 'if ($false) { return (& $say "warn" "other-changed"' }
        @{ Name = "page-prefix-loose"
           Find = 'foreach ($prefix in $script:HordeRelayPublishPagePrefixes) { if ($p.StartsWith($prefix, [System.StringComparison]::Ordinal)) { $isPage = $true } }'
           Replace = 'foreach ($prefix in $script:HordeRelayPublishPagePrefixes) { if ($p.StartsWith($prefix.TrimEnd("/"), [System.StringComparison]::OrdinalIgnoreCase)) { $isPage = $true } }' }
        @{ Name = "unknown-base-deployed"
           Find = '        if ($b.kind -ceq "unknown") {'
           Replace = '        if ($false) {' }
        @{ Name = "unclean-record-a-base"
           Find = 'if ($r.clean -ne $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "failed-check-base-forgotten"
           Find = '{ $base = $f.base }'
           Replace = '{ }' }
        @{ Name = "hand-deploy-does-not-settle"
           Find = '-and -not ($r.commit -ceq $Head.commit -and $r.at -gt $f.at)'
           Replace = '' }
        @{ Name = "retry-within-the-hour"
           Find = '$Now -lt $State.failure.at.AddSeconds($script:HordeRelayPublishRetrySeconds)'
           Replace = '$false' }
        @{ Name = "told-every-pass"
           Find = '    if (@($State.told) -ccontains $Key) { return $State }'
           Replace = '' }
        @{ Name = "version-unchanged-accepted"
           Find = 'if ($Before -ne "" -and $now -ceq $Before) {'
           Replace = 'if ($false) {' }
        @{ Name = "stale-version-accepted"
           Find = 'if ($now -cne $Built) {'
           Replace = 'if ($false) {' }
        @{ Name = "changed-files-not-checked"
           Find = '    foreach ($f in @($Files)) {'
           Replace = '    foreach ($f in @()) {' }
        @{ Name = "served-file-missed"
           Find = 'if (@($Changed) -ccontains ("" + $SiteMap[$site])'
           Replace = 'if ($false'  }
        @{ Name = "dirty-checkout-deployed"
           Find = 'if ($h.clean -ne $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-diff-not-told"
           Find = '        if (-not (Test-HordeAnswer $diff) -or $diff.state -cne "known") {'
           Replace = '        if ($false) {' }
        @{ Name = "busy-is-a-failure"
           Find = 'if ((Test-HordeAnswer $r) -and $r.state -ceq "unknown" -and $r.reason -ceq (Get-HordeRelayDeployBusyReason)) {'
           Replace = 'if ($false) {' }
        @{ Name = "interrupted-deploy-forgotten"
           Find = '        if ($null -ne $s.attempt) {'
           Replace = '        if ($false) {' }
        @{ Name = "unreadable-state-is-new"
           Find = 'if ($kept.state -ceq "unknown") { & $say ("LEFT ALONE - "'
           Replace = 'if ($false) { & $say ("LEFT ALONE - "' }
        @{ Name = "telling-off-ignored"
           Find = 'if ($null -ne $Policy -and $Policy.tellWarchief -ne $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "test-home-deploys"
           Find = 'if (Test-HordeServiceHomeIsATests -HordeHome $HordeHome) { return (New-HordeUnknown -Reason "this Horde home is under the temp folder, so it is a test''s: nothing is deployed") }'
           Replace = '' }
    )
}
