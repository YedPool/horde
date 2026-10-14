# Mutations of cli/RelayPublish.ps1, the pass's step that keeps the hosted phone page current. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-publish.psd1
# Each breaks one guard of the rule; test\test-relay-publish.ps1 must fail for every one.
@{
    Target = "cli\RelayPublish.ps1"
    Suite  = "test\test-relay-publish.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "worker-folder-not-the-worker"
           Find = 'foreach ($w in @($Shipped.workerPrefixes)) { if ($p.StartsWith($w, [System.StringComparison]::Ordinal)) { $inFolder = $true } }'
           Replace = '' }
        @{ Name = "worker-tests-are-the-worker"
           Find = 'foreach ($x in @($Shipped.workerExcept)) { if ($p.StartsWith($x, [System.StringComparison]::Ordinal)) { $inFolder = $false } }'
           Replace = '' }
        @{ Name = "imported-file-not-the-worker"
           Find = 'if ($inFolder -or @($Shipped.workerFiles) -ccontains $p) {'
           Replace = 'if ($inFolder) {' }
        @{ Name = "page-before-worker"
           Find = 'if ($inFolder -or @($Shipped.workerFiles) -ccontains $p) { [void]$worker.Add($p) }'
           Replace = 'if (@($Shipped.pageFiles) -ccontains $p) { [void]$page.Add($p) } elseif ($inFolder -or @($Shipped.workerFiles) -ccontains $p) { [void]$worker.Add($p) }' }
        @{ Name = "ignored-is-the-page"
           Find = '        elseif (@($Shipped.pageFiles) -ccontains $p) { [void]$page.Add($p) }'
           Replace = '        elseif ($true) { [void]$page.Add($p) }' }
        @{ Name = "imports-not-followed"
           Find = '                if ($seen.Add($t)) { $todo.Enqueue($t) }'
           Replace = '                if ($seen.Add($t) -and $false) { $todo.Enqueue($t) }' }
        @{ Name = "relay-tests-shipped"
           Find = '-and -not $rel.StartsWith($prefix + "test/", [System.StringComparison]::Ordinal)'
           Replace = '' }
        @{ Name = "worker-change-deployed"
           Find = '    if (@($Classes.worker).Count -gt 0) {'
           Replace = '    if ($false) {' }
        @{ Name = "ignored-only-deployed"
           Find = 'if (@($Classes.page).Count -eq 0) { return (& $say "ignore"'
           Replace = 'if ($false) { return (& $say "ignore"' }
        @{ Name = "checked-range-read-again"
           Find = 'if ($s.checked.through -ceq $h.commit) { & $say ("current - nothing the deploy ships changed since "'
           Replace = 'if ($false) { & $say ("current - nothing the deploy ships changed since "' }
        @{ Name = "checked-range-not-continued"
           Find = '            $from = $s.checked.through'
           Replace = '' }
        @{ Name = "checked-range-kept-after-deploy"
           Find = '$s.checked = $null; $origin = "" + $r.value.origin'
           Replace = '$origin = "" + $r.value.origin' }
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
           Find = 'if ($Before -ne "" -and $Built -cne $Before -and $now -ceq $Before) {'
           Replace = 'if ($false) {' }
        @{ Name = "version-change-always-required"
           Find = 'if ($Before -ne "" -and $Built -cne $Before -and $now -ceq $Before) {'
           Replace = 'if ($Before -ne "" -and $now -ceq $Before) {' }
        @{ Name = "stale-version-accepted"
           Find = 'if ($now -cne $Built) {'
           Replace = 'if ($false) {' }
        @{ Name = "hosted-bytes-not-compared"
           Find = 'if (("" + $f.expected) -eq "" -or ("" + $a.value.sha256) -cne ("" + $f.expected)) {'
           Replace = 'if ($false) {' }
        @{ Name = "changed-files-not-checked"
           Find = '    foreach ($f in @($Files)) {'
           Replace = '    foreach ($f in @()) {' }
        @{ Name = "served-file-missed"
           Find = 'if (@($Changed) -ccontains ("" + $SiteMap[$site])'
           Replace = 'if ($false' }
        @{ Name = "sw-not-compared"
           Find = '    [void]$out.Add("app/sw.js")'
           Replace = '' }
        @{ Name = "builder-change-compares-little"
           Find = 'if (@($Changed | Where-Object { @($BuildFiles) -ccontains $_ }).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "dirty-checkout-deployed"
           Find = 'if ($h.clean -ne $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-diff-not-told"
           Find = '        if (-not (Test-HordeAnswer $diff) -or $diff.state -cne "known") {'
           Replace = '        if ($false) {' }
        @{ Name = "unreadable-shipped-not-told"
           Find = '        if (-not (Test-HordeAnswer $shipped) -or $shipped.state -cne "known") {'
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
        @{ Name = "shared-only-not-measured"
           Find = 'if (Test-HordeRelayPublishSharedOnly -Classes $classes -Shipped $shipped.value) {'
           Replace = 'if ($false) {' }
        @{ Name = "worker-only-measured"
           Find = 'return [bool](@($Classes.worker | Where-Object { @($Shipped.sharedFiles) -cnotcontains $_ }).Count -eq 0)'
           Replace = 'return $true' }
        @{ Name = "differing-bundles-alike"
           Find = 'if ($Base.value.sha256 -cne $Head.value.sha256) {'
           Replace = 'if ($false) {' }
        @{ Name = "unmade-bundle-alike"
           Find = 'if (-not (& $known $Base) -or -not (& $known $Head)) {'
           Replace = 'if ($false) {' }
        @{ Name = "bundle-not-kept"
           Find = '$had = @(@($s.bundles) | Where-Object { $_.commit -ceq $Commit }) | Select-Object -First 1'
           Replace = '$had = $null' }
        @{ Name = "shared-includes-worker-only-imports"
           Find = 'sharedFiles = [string[]]@($outside | Where-Object { $page -ccontains $_ })'
           Replace = 'sharedFiles = [string[]]$outside' }
        @{ Name = "unmeasured-told-as-changed"
           Find = 'if ("" + $Classes.measured -ceq "unknown") { return (& $say "warn" "worker-unmeasured"'
           Replace = 'if ($false) { return (& $say "warn" "worker-unmeasured"' }
    )
}
