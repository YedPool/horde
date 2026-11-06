# Mutations of cli/RelayPublish.ps1, the pass's step that keeps the hosted phone page current. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-publish.psd1
# Each breaks one guard of the rule; test\test-relay-publish.ps1 must fail for every one.
@{
    Target = "cli\RelayPublish.ps1"
    Suite  = "test\test-relay-publish.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "newer-record-diffed"
           Find = '        if ($rel.value -ceq "newer") {'
           Replace = '        if ($false) {' }
        @{ Name = "newer-record-told"
           Find = '        if ($rel.value -ceq "newer") {'
           Replace = '        if ($rel.value -ceq "newer") { & $queue "unreadable" "x" $h.commit' }
        @{ Name = "absent-commit-is-failure"
           Find = 'if ($has.code -eq 1) { return (New-HordeKnown -Value "absent") }'
           Replace = '' }
        @{ Name = "cat-file-failure-is-absent"
           Find = 'if ($has.code -eq 1) { return (New-HordeKnown -Value "absent") }'
           Replace = 'if ($true) { return (New-HordeKnown -Value "absent") }' }
        @{ Name = "presence-asked-of-the-wrong-commit"
           Find = '"cat-file", "-e", $Base'
           Replace = '"cat-file", "-e", $Head' }
        @{ Name = "ancestry-failure-is-not-unknown"
           Find = 'if ($r.code -ne 1) {'
           Replace = 'if ($true) {' }
        @{ Name = "newer-is-diverged"
           Find = 'if ($back.ok) { return (New-HordeKnown -Value "newer") }'
           Replace = '' }
        @{ Name = "head-ancestor-asked-backwards"
           Find = '"merge-base", "--is-ancestor", $Head, $Base)'
           Replace = '"merge-base", "--is-ancestor", $Base, $Head)' }
        @{ Name = "diverged-not-told"
           Find = '& $queue "diverged" ("diverged:" + $b.base + ":" + $h.commit) $h.commit'
           Replace = '' }
        @{ Name = "absent-told-at-once"
           Find = 'if ($s.absent -ge $script:HordeRelayPublishAbsentPasses) {'
           Replace = 'if ($s.absent -ge 1) {' }
        @{ Name = "absent-told-too-late"
           Find = 'if ($s.absent -ge $script:HordeRelayPublishAbsentPasses) {'
           Replace = 'if ($s.absent -ge 6) {' }
        @{ Name = "absent-count-not-incremented"
           Find = '$s.absent = [int]$s.absent + 1'
           Replace = '$s.absent = [int]$s.absent + 0' }
        @{ Name = "absent-count-never-reset"
           Find = 'if ($rel.value -cne "absent") { $s.absent = 0 }'
           Replace = '' }
        @{ Name = "ancestry-unknown-is-newer"
           Find = '        if (-not (Test-HordeAnswer $rel) -or $rel.state -cne "known") {'
           Replace = '        if ($false) {' }
        @{ Name = "head-in-record-failure-is-diverged"
           Find = 'if ($back.code -eq 1) { return (New-HordeKnown -Value "diverged") }'
           Replace = 'return (New-HordeKnown -Value "diverged")' }
        @{ Name = "slow-ancestry-told-at-once"
           Find = '            if (& $quietSlow $rel "asking whether the checkout holds the deployed commit") { return }'
           Replace = '' }
        @{ Name = "slow-git-told-at-once"
           Find = '        if ($slowBefore -ge 1) { return $false }'
           Replace = '        return $false' }
        @{ Name = "slow-count-never-reset"
           Find = '$s.slow = 0'
           Replace = '' }
        @{ Name = "slow-count-not-incremented"
           Find = '$s.slow = $slowBefore + 1'
           Replace = '$s.slow = $slowBefore + 0' }
        @{ Name = "slow-match-never-matches"
           Find = "-cnotmatch 'did not finish within [0-9]+ s and was ended'"
           Replace = "-cnotmatch 'zzz'" }
        @{ Name = "slow-match-always-matches"
           Find = " -or `"`" + `$Answer.reason -cnotmatch 'did not finish within [0-9]+ s and was ended'"
           Replace = '' }
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
        @{ Name = "retry-within-the-hour"
           Find = '$Now -lt $State.failure.at.AddSeconds($script:HordeRelayPublishRetrySeconds)'
           Replace = '$false' }
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
        @{ Name = "differing-bundles-alike"
           Find = 'if ($Base.value.sha256 -cne $Head.value.sha256) {'
           Replace = 'if ($false) {' }
        @{ Name = "unmade-bundle-alike"
           Find = 'if (-not (& $known $Base) -or -not (& $known $Head)) {'
           Replace = 'if ($false) {' }
        @{ Name = "shared-includes-worker-only-imports"
           Find = 'sharedFiles = [string[]]@($outside | Where-Object { $page -ccontains $_ })'
           Replace = 'sharedFiles = [string[]]$outside' }
        @{ Name = "worker-own-file-deployed"
           Find = 'if ($own.Count -gt 0) { return (& $say "warn" "worker-changed"'
           Replace = 'if ($false) { return (& $say "warn" "worker-changed"' }
        @{ Name = "ignored-only-deployed"
           Find = 'if (@($Classes.page).Count -eq 0 -and @($Classes.worker).Count -eq 0) { return (& $say "ignore"'
           Replace = 'if ($false) { return (& $say "ignore"' }
        @{ Name = "settled-by-time-must-1"
           Find = 'if (("" + $f.recordId) -ceq ("" + $r.id)) {'
           Replace = 'if (-not ($r.at -gt $f.at)) {' }
        @{ Name = "other-record-ignored-must-2"
           Find = '        else { $settles = $true }'
           Replace = '        else { if ($f.base -cmatch $script:HordeRelayPublishCommitPattern) { $base = $f.base } }' }
        @{ Name = "settled-failure-kept"
           Find = 'if ($b.settles) { $s.failure = $null;'
           Replace = 'if ($b.settles) {' }
        @{ Name = "failure-keeps-no-record-id"
           Find = '            $s.failure = [pscustomobject]@{ head = $h.commit; base = $b.base; at = $relayPublishLogAt; what = $What; recordId = (& $recordId) }'
           Replace = '            $s.failure = [pscustomobject]@{ head = $h.commit; base = $b.base; at = $relayPublishLogAt; what = $What; recordId = "" }' }
        @{ Name = "told-every-pass"
           Find = '    if (@($State.told) -ccontains $k) { return $State }'
           Replace = '' }
        @{ Name = "episode-never-ends"
           Find = '    if ($State.troubled -eq $true) { $State.episode = [int]$State.episode + 1; $State.troubled = $false }'
           Replace = '' }
        @{ Name = "pending-uncapped"
           Find = ' | Select-Object -Last $script:HordeRelayPublishPendingMost)'
           Replace = ')' }
        @{ Name = "off-main-deployed"
           Find = 'if ($on.value -ne $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "main-unknown-deployed"
           Find = 'if (-not (Test-HordeAnswer $on) -or $on.state -cne "known") {'
           Replace = 'if ($false) {' }
        @{ Name = "page-only-not-bundled"
           Find = '$classes = Get-HordeRelayPublishMeasured -Classes $classes -Base (& $bundleOf $b.base) -Head $headBundle'
           Replace = '$classes = [pscustomobject]@{ worker = @(); page = @(@($classes.page) + @($classes.worker)); ignored = $classes.ignored; measured = "same" }' }
        @{ Name = "bundle-not-kept"
           Find = '$had = @(@($s.bundles) | Where-Object { $_.commit -ceq $Commit -and ("" + $_.sha256) -cmatch'
           Replace = '$had = @(@() | Where-Object { $_.commit -ceq $Commit -and ("" + $_.sha256) -cmatch' }
        @{ Name = "failed-bundle-kept"
           Find = '            if ((Test-HordeAnswer $a) -and $a.state -ceq "known" -and ("" + $a.value.sha256) -cmatch'
           Replace = '            if ($true -or ("" + $a.value.sha256) -cmatch' }
        @{ Name = "unmeasured-not-a-failure"
           Find = 'if ($classes.measured -ceq "unknown") { & $failed "worker-unmeasured"'
           Replace = 'if ($classes.measured -ceq "unknown") { & $warn "worker-unmeasured" "unmeasured"' }
        @{ Name = "different-bundle-deployed"
           Find = 'if ($classes.measured -cne "same") {'
           Replace = 'if ($false) {' }
        @{ Name = "moved-is-a-failure"
           Find = 'if ((Test-HordeAnswer $r) -and $r.state -ceq "unknown" -and $r.reason -ceq $script:HordeRelayPublishMovedReason) {'
           Replace = 'if ($false) {' }
        @{ Name = "deploy-not-handed-the-commit"
           Find = '-Name "Deploy" -With @($HordeHome, $log, $Checkout, $h.commit)'
           Replace = '-Name "Deploy" -With @($HordeHome, $log, $Checkout, ("f" * 40))' }
        @{ Name = "check-not-waited-for"
           Find = 'if ($check.ok -or (Invoke-HordeRelayPublishTool -Tools $Tools -Name "Now") -ge $until) { break }'
           Replace = 'break' }
        @{ Name = "check-waits-for-ever"
           Find = 'if ($check.ok -or (Invoke-HordeRelayPublishTool -Tools $Tools -Name "Now") -ge $until) { break }'
           Replace = 'if ($check.ok -or $W.sleeps -gt 40) { break }' }
        @{ Name = "machinery-not-the-worker"
           Find = ' + @(Get-HordeRelayDeployMachineryFiles) | Sort-Object -Unique)'
           Replace = ' | Sort-Object -Unique)' }
        @{ Name = "tend-test-home-looked-at"
           Find = 'if (Test-HordeServiceHomeIsATests -HordeHome $HordeHome -TempRoot $TempRoot) { return @("phone page: this Horde home is under the temp folder'
           Replace = 'if ($false) { return @("phone page: this Horde home is under the temp folder' }
        @{ Name = "tend-home-not-pointed"
           Find = '    Write-HordeRelayTendHomePointer -Path $PointerPath -HordeHome $HordeHome'
           Replace = '' }
        @{ Name = "http-allowed"
           Find = 'if ($Url -cnotmatch ''\Ahttps://[a-z0-9.-]+(:[0-9]{1,5})?/'') {'
           Replace = 'if ($Url -cnotmatch ''\Ahttps?://'') {' }
        @{ Name = "renames-folded"
           Find = '@("diff", "--name-only", "--no-renames", $Base, $Head)'
           Replace = '@("diff", "--name-only", "-M", $Base, $Head)' }
        @{ Name = "dirty-read-as-clean"
           Find = 'clean = [bool]($st.out -eq "")'
           Replace = 'clean = $true' }
        @{ Name = "worker-notice-keyed-by-commit"
           Find = '("held:" + $b.base + ":bundle:" + $headBundle.value.sha256)'
           Replace = '("held:" + $b.base + ":bundle:" + $h.commit)' }
        @{ Name = "worker-notice-keyed-by-base-alone"
           Find = '("held:" + $b.base + ":bundle:" + $headBundle.value.sha256)'
           Replace = '("held:" + $b.base + ":bundle")' }
        @{ Name = "pointer-any-path-accepted"
           Find = 'if ($t -cnotmatch ''\A[A-Za-z]:\\[^\\/:*?"<>|]'' -or $t -match'
           Replace = 'if ($false -and $t -match' }
        @{ Name = "pointer-dot-parts-accepted"
           Find = ' -or $t -match ''(\A|\\)\.{1,2}(\\|\z)'' -or'
           Replace = ' -or' }
        @{ Name = "pointer-temp-accepted"
           Find = 'if (Test-HordeServiceHomeIsATests -HordeHome $full -TempRoot $TempRoot) {'
           Replace = 'if ($false) {' }
        @{ Name = "pointer-bare-folder-accepted"
           Find = 'if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($full, "settings", "service-definitions.json"))) {'
           Replace = 'if ($false) {' }
        @{ Name = "also-from-a-test-home"
           Find = 'if (Test-HordeServiceHomeIsATests -HordeHome $mineFull -TempRoot $TempRoot) {'
           Replace = 'if ($false) {' }
        @{ Name = "refused-pointer-silent"
           Find = 'note = ("note: this deploy is recorded only in " + $mineFull + ": " + $p.reason) }'
           Replace = 'note = "" }' }
        @{ Name = "also-own-home"
           Find = 'if ($p.value.Equals($mineFull, [System.StringComparison]::OrdinalIgnoreCase)) {'
           Replace = 'if ($false) {' }
        # T-0391 slice 6: the teller's own lines are the pass's lines.
        @{ Name = "teller-lines-dropped"
           Find = 'foreach ($tl in @($answer.lines)) { [void]$lines.Add("" + $tl) }'
           Replace = '$null = 0' }
    )
}
