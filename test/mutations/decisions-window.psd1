# Mutations of decisions/Window.ps1, the composer of the decisions window. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-window.psd1
# test\test-decisions-window.ps1 must fail for each.
#
# NOT MUTATED HERE: Open-HordeDecisionWindow itself - the named mutex and event, the placement worked
# out before the window exists, the spec handed to the surface. No suite can run it without a
# window; it is held by test/e2e/e2e-decisions-window.ps1 and the terminal host's own scenario, which
# drive the real command. Nor the list request's "every state": the suite's list holds open
# questions only, and a closed one is drawn by the page under its own heading (the scenario's page
# does not have one either: said in the pull request).
@{
    Target = "decisions\Window.ps1"
    Suite  = "test\test-decisions-window.ps1"
    Mutations = @(
        # --- the settings
        @{ Name = "another-role-by-default"
           Find = '@{ name = "role"; kind = "text"; default = "warchief";'
           Replace = '@{ name = "role"; kind = "text"; default = "orc";' }
        @{ Name = "changes-gathered-for-another-time"
           Find = 'default = 400; min = 50;'
           Replace = 'default = 401; min = 50;' }
        @{ Name = "silence-of-another-length"
           Find = 'default = 30000; min = 1000; max = 3600000;'
           Replace = 'default = 30001; min = 1000; max = 3600000;' }
        @{ Name = "fleet-read-at-another-pace"
           Find = 'default = 5000; min = 1000; max = 600000;'
           Replace = 'default = 5001; min = 1000; max = 600000;' }
        @{ Name = "follow-checked-at-another-pace"
           Find = 'default = 1000; min = 100; max = 60000;'
           Replace = 'default = 1001; min = 100; max = 60000;' }
        @{ Name = "picture-after-another-quiet"
           Find = 'default = 700; min = 100; max = 10000;'
           Replace = 'default = 701; min = 100; max = 10000;' }
        @{ Name = "letters-of-another-size"
           Find = 'default = 14; min = 10; max = 32;'
           Replace = 'default = 13; min = 10; max = 32;' }
        @{ Name = "small-marks-of-another-size"
           Find = 'default = 12; min = 9; max = 28;'
           Replace = 'default = 11; min = 9; max = 28;' }
        @{ Name = "a-line-of-another-height"
           Find = 'default = 22; min = 12; max = 64;'
           Replace = 'default = 21; min = 12; max = 64;' }
        @{ Name = "the-family-is-another"
           Find = 'default = ''"Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif'';'
           Replace = 'default = ''"Segoe UI", system-ui, sans-serif'';' }
        @{ Name = "the-settings-of-another-module"
           Find = '$script:HordeDecisionWindowModule = "decisions-window"'
           Replace = '$script:HordeDecisionWindowModule = "decisions-windows"' }
        # --- the window's name and its folder
        @{ Name = "a-shorter-fingerprint"
           Find = '$script:HordeDecisionWindowNameHexChars = 16'
           Replace = '$script:HordeDecisionWindowNameHexChars = 12' }
        @{ Name = "a-home-written-in-capitals-is-another-home"
           Find = '.TrimEnd(''\'').ToLowerInvariant()))'
           Replace = '.TrimEnd(''\'')))' }
        @{ Name = "the-surface-files-somewhere-else"
           Find = 'return (Join-Path (Join-Path $HordeHome "cache") $script:HordeDecisionWindowModule)'
           Replace = 'return (Join-Path (Join-Path $HordeHome "caches") $script:HordeDecisionWindowModule)' }
        @{ Name = "the-title-counts-what-is-not-open"
           Find = '$open = @($Record.value.questions | Where-Object { "$($_.state)" -ceq "open" })'
           Replace = '$open = @($Record.value.questions | Where-Object { "$($_.state)" -cne "open" })' }
        # --- attached, or saying why not
        @{ Name = "a-hidden-window-looks-for-a-terminal"
           Find = 'if ($Hidden) { return (& $free "it was opened hidden'
           Replace = 'if ($false) { return (& $free "it was opened hidden' }
        @{ Name = "an-off-screen-window-looks-for-a-terminal"
           Find = 'if ($OffScreen) { return (& $free "it was opened where no screen is'
           Replace = 'if ($false) { return (& $free "it was opened where no screen is' }
        @{ Name = "no-holder-is-not-said"
           Find = 'if ($seat.state -ceq "absent") {'
           Replace = 'if ($false) {' }
        @{ Name = "an-unknown-seat-is-believed"
           Find = 'if ($seat.state -cne "known") { return (& $free $seat.reason) }'
           Replace = 'if ($false) { return (& $free $seat.reason) }' }
        @{ Name = "an-unproven-window-is-attached-to"
           Find = 'if ($window.state -cne "known") { return (& $free $window.reason) }'
           Replace = 'if ($false) { return (& $free $window.reason) }' }
        @{ Name = "the-callers-reading-of-who-runs-is-not-used"
           Find = 'if ($null -ne $Identity) { $seat = Get-HordeRoleSeat -Role $Role -Identity $Identity } else'
           Replace = 'if ($false) { $seat = Get-HordeRoleSeat -Role $Role -Identity $Identity } else' }
        # --- what the reader is shown first
        @{ Name = "unfold-takes-anything"
           Find = 'if ($Unfold -cnotmatch '
           Replace = 'if ($false -and $Unfold -cnotmatch ' }
        @{ Name = "an-orc-in-any-letter-case"
           Find = '$Orc -cnotmatch ''\A[A-Z]\z'') {'
           Replace = '$Orc -cnotmatch ''\A[A-Za-z]\z'') {' }
        @{ Name = "a-picked-orc-leaves-the-fleet-line-folded"
           Find = 'fleetOpen = [bool]($Orc -ne ""); pick = $Orc }'
           Replace = 'fleetOpen = $false; pick = $Orc }' }
        # --- what the page drew, held to its shape and bounds
        @{ Name = "a-report-of-any-version"
           Find = 'if ($drawn.v -isnot [int] -or $drawn.v -ne 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-report-missing-a-member"
           Find = 'if (-not (& $has $drawn $name)) { return (& $bad ("has no member " + $name)) }'
           Replace = 'if ($false) { return (& $bad ("has no member " + $name)) }' }
        @{ Name = "lines-that-are-not-a-list"
           Find = 'if ($null -ne $items -and $items -isnot [array]) {'
           Replace = 'if ($false) {' }
        @{ Name = "more-lines-than-the-bound"
           Find = 'if (@($items).Count -gt $list.most) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-line-of-any-length"
           Find = ' -or $item.t -isnot [string] -or $item.t.Length -gt $Bounds.lineChars) {'
           Replace = ' -or $item.t -isnot [string]) {' }
        @{ Name = "a-number-that-is-words"
           Find = ' -or $item.n -isnot [string] -or $item.n -cnotmatch ''\A[0-9]{1,9}(\.[0-9]{1,4})?\z'')) {'
           Replace = ' -or $item.n -isnot [string])) {' }
        @{ Name = "a-line-with-no-number"
           Find = 'if ($list.name -cne "headings" -and (-not (& $has $item "n") -or '
           Replace = 'if ($list.name -cne "headings" -and (& $has $item "n") -and (' }
        @{ Name = "unfolded-may-be-anything"
           Find = ' -or -not (& $has $line "open") -or $line.open -isnot [bool]'
           Replace = '' }
        @{ Name = "dimmed-may-be-left-out"
           Find = ' -or -not (& $has $line "dim") -or $line.dim -isnot [bool]'
           Replace = '' }
        @{ Name = "more-fleet-lines-than-the-bound"
           Find = ' -or @($drawn.fleet.rows).Count -gt $Bounds.fleetRows) {'
           Replace = ') {' }
        @{ Name = "a-fleet-line-that-is-not-text"
           Find = 'if ($row -isnot [string] -or $row.Length -gt $Bounds.lineChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-notice-of-any-length"
           Find = ' -or $drawn.notice.Length -gt $Bounds.textChars'
           Replace = '' }
        @{ Name = "a-letter-size-that-is-words"
           Find = 'if ($null -ne $number -and $number -isnot [int]'
           Replace = 'if ($false -and $number -isnot [int]' }
        @{ Name = "the-scale-may-be-left-out"
           Find = 'foreach ($name in @("fontPx", "linePx", "smallFontPx", "smallLinePx", "ratio")) {'
           Replace = 'foreach ($name in @("fontPx", "linePx", "smallFontPx", "smallLinePx")) {' }
        @{ Name = "the-report-bound-ignores-the-surface"
           Find = '$chars = [Math]::Min($chars, [int]$Bridge.limits.messageChars - $script:HordeDecisionWindowEnvelopeChars)'
           Replace = '$chars = [Math]::Max($chars, [int]$Bridge.limits.messageChars - $script:HordeDecisionWindowEnvelopeChars)' }
        @{ Name = "no-room-left-for-the-envelope"
           Find = '$script:HordeDecisionWindowEnvelopeChars = 1024'
           Replace = '$script:HordeDecisionWindowEnvelopeChars = 0' }
        @{ Name = "another-bound-on-lines"
           Find = '[pscustomobject]@{ lines = 400; subLines = 200; fleetRows = 80; lineChars = 400; textChars = 2000; chars = 60000; quietMs = 60 }'
           Replace = '[pscustomobject]@{ lines = 401; subLines = 200; fleetRows = 80; lineChars = 400; textChars = 2000; chars = 60000; quietMs = 60 }' }
        # --- the closed list
        @{ Name = "an-event-nothing-pushes"
           Find = '-Events @("list-changed", "fleet-changed", "attachment-changed", "probe", "said")'
           Replace = '-Events @("list-changed", "fleet-changed", "attachment-changed", "probe", "said", "show")' }
        @{ Name = "a-broken-report-is-kept"
           Find = 'if (-not $drawn.ok) { $State.reportsRefused = [int]$State.reportsRefused + 1; throw $drawn.reason }'
           Replace = 'if ($false) { $State.reportsRefused = [int]$State.reportsRefused + 1; throw $drawn.reason }' }
        @{ Name = "a-broken-report-is-not-counted"
           Find = 'if (-not $drawn.ok) { $State.reportsRefused = [int]$State.reportsRefused + 1; throw'
           Replace = 'if (-not $drawn.ok) { throw' }
        @{ Name = "a-report-is-not-counted"
           Find = '$State.reports = [int]$State.reports + 1'
           Replace = '$State.reports = 0' }
        @{ Name = "the-letters-are-not-the-settings"
           Find = 'textPx = [int]$v.textPx; linePx = [int]$v.linePx;'
           Replace = 'textPx = 15; linePx = [int]$v.linePx;' }
        @{ Name = "the-findings-are-not-handed-to-the-page"
           Find = 'findings = @($State.findings | ForEach-Object { "" + $_ })'
           Replace = 'findings = @()' }
        @{ Name = "the-title-does-not-follow-the-list-asked-for"
           Find = '            if ($null -ne $Window) { & $Window.setTitle $State.title }'
           Replace = '            if ($false) { & $Window.setTitle $State.title }' }
        # --- when the list is read again, and when it is pushed
        @{ Name = "what-the-page-has-is-forgotten"
           Find = '$State.listJson = ConvertTo-HordeSurfaceJson -Value $record'
           Replace = '' }
        @{ Name = "a-change-is-acted-on-late"
           Find = '($Now - $State.dirtyAt).TotalMilliseconds -ge $State.settings.changeQuietMs) {'
           Replace = '($Now - $State.dirtyAt).TotalMilliseconds -gt $State.settings.changeQuietMs) {' }
        @{ Name = "a-change-is-acted-on-at-once"
           Find = '($Now - $State.dirtyAt).TotalMilliseconds -ge $State.settings.changeQuietMs) {'
           Replace = '($Now - $State.dirtyAt).TotalMilliseconds -ge 0) {' }
        @{ Name = "the-same-list-is-pushed-again"
           Find = 'if ($Json -ceq $State.listJson) { return $false }'
           Replace = 'if ($false) { return $false }' }
        @{ Name = "silence-is-never-broken"
           Find = 'elseif ($null -eq $State.dirtyAt -and ($Now - $State.listReadAt).TotalMilliseconds -ge $State.settings.listRereadMs) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "silence-is-broken-late"
           Find = '($Now - $State.listReadAt).TotalMilliseconds -ge $State.settings.listRereadMs) {'
           Replace = '($Now - $State.listReadAt).TotalMilliseconds -gt $State.settings.listRereadMs) {' }
        @{ Name = "the-silence-is-not-the-setting"
           Find = '.TotalMilliseconds -ge $State.settings.listRereadMs) {'
           Replace = '.TotalMilliseconds -ge 30000) {' }
        @{ Name = "a-read-in-silence-is-not-counted"
           Find = '$State.rereads = [int]$State.rereads + 1'
           Replace = '' }
        @{ Name = "a-read-does-not-restart-the-silence"
           Find = '    $State.listReadAt = $Now'
           Replace = '' }
        @{ Name = "a-failed-watch-does-not-ask-for-the-list"
           Find = '$s.watchFailures = [int]$s.watchFailures + 1; $s.dirtyAt = [datetime]::UtcNow }'
           Replace = '$s.watchFailures = [int]$s.watchFailures + 1 }' }
        @{ Name = "a-failed-watch-is-not-counted"
           Find = '$s.watchFailed = $true; $s.watchFailures = [int]$s.watchFailures + 1;'
           Replace = '$s.watchFailed = $true;' }
        @{ Name = "a-failed-watch-is-left-standing"
           Find = 'if ($State.watchFailed) { Stop-HordeDecisionWindowWatch -State $State }'
           Replace = '' }
        @{ Name = "a-watch-with-no-thread-to-be-heard-on"
           Find = 'if ($null -eq $Sync) { return $false }'
           Replace = '' }
        @{ Name = "the-watch-knows-the-records-file-names"
           Find = '$watcher = New-Object System.IO.FileSystemWatcher($State.storeRoot)'
           Replace = '$watcher = New-Object System.IO.FileSystemWatcher($State.storeRoot, "*.json")' }
        # --- come forward
        @{ Name = "asked-forward-and-not-shown"
           Find = '$State.shows = [int]$State.shows + 1; $State.reportDue = $true; & $Window.show }'
           Replace = '$State.shows = [int]$State.shows + 1; $State.reportDue = $true }' }
        @{ Name = "asked-forward-and-not-counted"
           Find = '{ $State.shows = [int]$State.shows + 1; $State.reportDue = $true; & $Window.show }'
           Replace = '{ $State.reportDue = $true; & $Window.show }' }
        @{ Name = "shown-without-being-asked"
           Find = 'if ($null -ne $State.showEvent -and $State.showEvent.WaitOne(0)) {'
           Replace = 'if ($null -ne $State.showEvent) {' }
        # --- the follow
        @{ Name = "a-follow-that-failed-is-believed"
           Find = 'if ($follow.state -ceq "following") { $State.followed = $true }'
           Replace = 'if ($true) { $State.followed = $true }' }
        @{ Name = "the-follow-is-asked-on-every-tick"
           Find = '$State.followDueAt = $Now.AddMilliseconds($State.settings.followCheckMs)'
           Replace = '$State.followDueAt = $Now' }
        @{ Name = "lost-is-not-heard"
           Find = 'if ($follow.state -ceq "lost") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-free-window-goes-on-being-asked-about"
           Find = 'if ($State.followed -and $Now -ge $State.followDueAt) {'
           Replace = 'if ($Now -ge $State.followDueAt) {' }
        @{ Name = "standing-free-is-not-said-to-the-page"
           Find = 'if ($null -ne $Window) { & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "attachment-changed"'
           Replace = 'if ($false) { & $Window.post (ConvertTo-HordeSurfaceEvent -Bridge $State.bridge -Name "attachment-changed"' }
        @{ Name = "a-lost-window-is-stopped-as-well"
           Find = '            $State.lost = $true'
           Replace = '            $State.lost = $true; [void](Stop-HordeWindowFollow)' }
        @{ Name = "the-follow-outlives-the-window"
           Find = '    [void](Stop-HordeWindowFollow)'
           Replace = '' }
        # --- the fleet, the picture, the report file
        @{ Name = "the-fleet-is-read-on-every-tick"
           Find = '$State.fleetDueAt = $Now.AddMilliseconds($State.settings.fleetReadMs)'
           Replace = '$State.fleetDueAt = $Now' }
        @{ Name = "an-unchanged-fleet-is-pushed"
           Find = 'if ($fleet.signature -cne $State.fleetSignature) {'
           Replace = 'if ($true) {' }
        @{ Name = "a-picture-of-a-page-still-drawing"
           Find = '($Now - $State.lastReportAt).TotalMilliseconds -ge $State.settings.pictureSettleMs) {'
           Replace = '($Now - $State.lastReportAt).TotalMilliseconds -ge 0) {' }
        @{ Name = "a-picture-before-any-report"
           Find = '$null -ne $State.lastReportAt -and ($Now - $State.lastReportAt).TotalMilliseconds -ge $State.settings.pictureSettleMs) {'
           Replace = '$true) {' }
        @{ Name = "a-picture-on-every-tick"
           Find = 'if ($State.picturePath -ne "" -and -not $State.pictureAsked -and '
           Replace = 'if ($State.picturePath -ne "" -and ' }
        @{ Name = "more-errors-repeated"
           Find = '$script:HordeDecisionWindowReportErrors = 5'
           Replace = '$script:HordeDecisionWindowReportErrors = 6' }
        @{ Name = "the-report-file-says-another-version"
           Find = 'schemaVersion = 2; pid = $PID;'
           Replace = 'schemaVersion = 1; pid = $PID;' }
        @{ Name = "what-the-page-drew-is-not-in-the-file"
           Find = 'drawn = $State.drawn; reports = [int]$State.reports;'
           Replace = 'drawn = $null; reports = [int]$State.reports;' }
        @{ Name = "asked-forward-is-not-in-the-file"
           Find = 'askedForward = [int]$State.shows'
           Replace = 'askedForward = 0' }
        @{ Name = "the-report-file-is-written-in-place"
           Find = '$temp = $State.reportPath + "." + $PID + ".tmp"'
           Replace = '$temp = $State.reportPath + ".part"; [System.IO.File]::WriteAllText($State.reportPath + ".half", "x")' }
        # --- a refused settings file refuses the window, every finding said ---
        @{ Name = "a-refused-settings-file-opens-the-window"
           Find = 'if (@("defaults", "read") -ccontains $state) { continue }'
           Replace = 'continue' }
        @{ Name = "only-the-first-finding-is-said"
           Find = 'foreach ($f in $found) { [void]$lines.Add($f) }'
           Replace = '[void]$lines.Add($found[0])' }
    )
}
