# Mutations of core/WindowFollowPort.ps1, the port through which a window is made another's companion.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\window-follow-port.psd1
# test\test-window-follow-port.ps1 must fail for each. That suite touches no window: this spec holds
# where a companion stands, what the port refuses, which follower it asks and how it answers for one
# that fails. The following itself is the Windows follower's spec, test\mutations\window-follow.psd1.
@{
    Target = "core\WindowFollowPort.ps1"
    Suite  = "test\test-window-follow-port.ps1"
    Mutations = @(
        @{ Name = "placed-at-the-left"
           Find = 'left = [int]($right - $marginRight - $width); top'
           Replace = 'left = [int]($left + $marginRight); top' }
        @{ Name = "right-margin-forgotten"
           Find = 'left = [int]($right - $marginRight - $width); top'
           Replace = 'left = [int]($right - $width); top' }
        @{ Name = "top-margin-forgotten"
           Find = 'top = [int]($top + $marginTop); width'
           Replace = 'top = [int]$top; width' }
        @{ Name = "half-the-width"
           Find = 'default = (1.0 / 3); min = 0.1;'
           Replace = 'default = (1.0 / 2); min = 0.1;' }
        @{ Name = "no-smallest-width"
           Find = '$width = [Math]::Max([int][Math]::Round($targetWidth * [double]$f.floatingWidthShare), $smallestWidth)'
           Replace = '$width = [int][Math]::Round($targetWidth * [double]$f.floatingWidthShare)' }
        @{ Name = "wider-than-the-other-window"
           Find = '$width = [Math]::Min($width, [Math]::Max($targetWidth - 2 * $marginRight, 1))'
           Replace = '' }
        @{ Name = "bottom-margin-forgotten"
           Find = '$height = [Math]::Max($targetHeight - $marginTop - $marginBottom,'
           Replace = '$height = [Math]::Max($targetHeight - $marginTop,' }
        @{ Name = "below-the-other-windows-bottom"
           Find = '[Math]::Min($smallestHeight, [Math]::Max($targetHeight - $marginTop, 1)))'
           Replace = '$smallestHeight)' }
        @{ Name = "margins-not-scaled"
           Find = '$marginBottom = [int][Math]::Round($f.floatingMarginBottomPx * $Scale)'
           Replace = '$marginBottom = [int]$f.floatingMarginBottomPx' }
        @{ Name = "smallest-width-not-scaled"
           Find = '$smallestWidth = [int][Math]::Round($f.floatingMinWidthPx * $Scale)'
           Replace = '$smallestWidth = [int]$f.floatingMinWidthPx' }
        @{ Name = "smallest-height-not-scaled"
           Find = '$smallestHeight = [int][Math]::Round($f.floatingMinHeightPx * $Scale)'
           Replace = '$smallestHeight = [int]$f.floatingMinHeightPx' }
        @{ Name = "top-margin-of-another-size"
           Find = 'default = 48;'
           Replace = 'default = 24;' }
        @{ Name = "any-mode-placed-as-floating"
           Find = 'if (@(Get-HordeWindowFollowModes) -cnotcontains $Mode) { return (New-HordeUnknown -Reason ('
           Replace = 'if ($false) { return (New-HordeUnknown -Reason (' }
        @{ Name = "mode-matched-without-case"
           Find = 'if (@(Get-HordeWindowFollowModes) -cnotcontains $Mode) { return (New-HordeUnknown -Reason ('
           Replace = 'if (@(Get-HordeWindowFollowModes) -notcontains $Mode) { return (New-HordeUnknown -Reason (' }
        @{ Name = "empty-rectangle-placed"
           Find = 'if ($right -le $left -or $bottom -le $top) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-window-with-no-height-placed"
           Find = 'if ($right -le $left -or $bottom -le $top) {'
           Replace = 'if ($right -le $left) {' }
        @{ Name = "any-scale-taken"
           Find = 'if ([double]::IsNaN($Scale) -or $Scale -lt 0.5 -or $Scale -gt 10) {'
           Replace = 'if ($Scale -lt 0) {' }
        @{ Name = "a-scale-that-is-not-a-number-taken"
           Find = 'if ([double]::IsNaN($Scale) -or $Scale -lt 0.5 -or $Scale -gt 10) {'
           Replace = 'if ($Scale -lt 0.5 -or $Scale -gt 10) {' }
        @{ Name = "a-side-that-is-text-is-read"
           Find = 'if ($value -is [int] -or $value -is [long]) { return [long]$value }'
           Replace = 'if ($null -ne $value) { return [long]$value }' }
        @{ Name = "a-table-is-not-read"
           Find = 'if ($From -is [System.Collections.IDictionary]) { if ($From.Contains($Name)) { $value = $From[$Name] } }'
           Replace = 'if ($false) { }' }
        @{ Name = "the-right-margin-is-the-top-one"
           Find = '$marginRight = [int][Math]::Round($f.floatingMarginRightPx * $Scale)'
           Replace = '$marginRight = [int][Math]::Round($f.floatingMarginTopPx * $Scale)' }
        @{ Name = "the-bottom-margin-is-the-right-one"
           Find = '$marginBottom = [int][Math]::Round($f.floatingMarginBottomPx * $Scale)'
           Replace = '$marginBottom = [int][Math]::Round($f.floatingMarginRightPx * $Scale)' }
        @{ Name = "the-smallest-height-is-the-smallest-width"
           Find = '$smallestHeight = [int][Math]::Round($f.floatingMinHeightPx * $Scale)'
           Replace = '$smallestHeight = [int][Math]::Round($f.floatingMinWidthPx * $Scale)' }
        @{ Name = "settings-handed-in-are-ignored"
           Find = '    $f = $Settings'
           Replace = '    $f = $null' }
        @{ Name = "a-setting-that-is-text-is-taken"
           Find = 'if ($null -eq $field -or ($field.Value -isnot [int] -and $field.Value -isnot [double])) {'
           Replace = 'if ($null -eq $field) {' }
        @{ Name = "a-follow-starts-with-the-defaults-whatever-the-file-says"
           Find = '        $with = $read.values'
           Replace = '        $with = (Read-HordeModuleSettingsText -Declaration (Get-HordeWindowFollowSettingsDeclaration) -Text $null).values' }
        # THE REFUSE RULE: a settings file that is refused is no follow and no place, never the defaults.
        # Not mutated: refusing on exactly the word "refused" in place of on every state that is not
        # "defaults" or "read". The module settings answer only those three, so no suite can tell the
        # two apart; the wider test is there for a state this file does not know.
        @{ Name = "a-refused-file-is-not-refused-at-the-start"
           Find = 'if ($read.state -cne "defaults" -and $read.state -cne "read") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-file-that-was-read-is-refused"
           Find = 'if ($read.state -cne "defaults" -and $read.state -cne "read") { return'
           Replace = 'if ($read.state -cne "defaults") { return' }
        @{ Name = "no-file-at-all-is-refused"
           Find = 'if ($read.state -cne "defaults" -and $read.state -cne "read") { return'
           Replace = 'if ($read.state -cne "read") { return' }
        @{ Name = "the-refusal-does-not-say-what-is-wrong"
           Find = '(@($read.findings) -join "; ")) -Findings'
           Replace = '"") -Findings' }
        @{ Name = "only-the-first-thing-wrong-is-the-reason"
           Find = '(@($read.findings) -join "; ")) -Findings'
           Replace = '@($read.findings)[0]) -Findings' }
        @{ Name = "the-refusal-carries-no-findings"
           Find = ' -Findings @($read.findings)) }'
           Replace = ') }' }
        @{ Name = "a-refusals-nothing-is-placed-by-the-defaults"
           Find = 'if ($PSBoundParameters.ContainsKey("Settings") -and $null -eq $Settings) {'
           Replace = 'if ($false) {' }
        @{ Name = "settings-left-out-give-no-place-either"
           Find = 'if ($PSBoundParameters.ContainsKey("Settings") -and $null -eq $Settings) {'
           Replace = 'if ($null -eq $Settings) {' }
        @{ Name = "settings-handed-in-are-not-checked-at-the-start"
           Find = 'if ($fault -ne "") { return (New-HordeWindowFollowRecord -State "failed" -Reason $fault) }'
           Replace = '' }
        @{ Name = "a-home-that-cannot-be-one-is-thrown"
           Find = 'try { $read = Get-HordeWindowFollowSettings } catch { return (New-HordeWindowFollowRecord -State "failed" -Reason ("the settings could not be read: " + $_.Exception.Message)) }'
           Replace = '$read = Get-HordeWindowFollowSettings' }
        @{ Name = "the-module-has-another-name"
           Find = 'New-HordeModuleSettings -Module "window-follow"'
           Replace = 'New-HordeModuleSettings -Module "follow"' }
        @{ Name = "a-share-of-the-whole-width-is-allowed"
           Find = 'min = 0.1; max = 0.9;'
           Replace = 'min = 0.1; max = 1.0;' }
        @{ Name = "a-margin-below-nothing-is-allowed"
           Find = 'min = 0;   max = 2000; what = "Floating: gap between the other'
           Replace = 'min = -9;  max = 2000; what = "Floating: gap between the other' }
        @{ Name = "a-smallest-width-of-nothing-is-allowed"
           Find = 'default = 320;       min = 100;'
           Replace = 'default = 320;       min = 1;' }
        @{ Name = "a-mode-not-built-is-started"
           Find = 'if (@(Get-HordeWindowFollowModes) -cnotcontains $Mode) { return (New-HordeWindowFollowRecord -State "failed"'
           Replace = 'if ($false) { return (New-HordeWindowFollowRecord -State "failed"' }
        @{ Name = "no-window-to-stand-beside-is-asked-for"
           Find = 'if ($Target -le 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-handle-below-zero-names-a-window"
           Find = 'if ($Target -le 0) { return'
           Replace = 'if ($Target -eq 0) { return' }
        @{ Name = "no-window-to-place-is-asked-for"
           Find = 'if ($Companion -le 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-window-beside-itself-is-asked-for"
           Find = 'if ($Target -eq $Companion) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "the-rectangle-of-no-window-is-asked-for"
           Find = 'if ($Handle -le 0) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "asking-places"
           Find = 'return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "update" -With @($false)))'
           Replace = 'return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "update" -With @($true)))' }
        @{ Name = "placing-again-only-asks"
           Find = 'return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "update" -With @($true)))'
           Replace = 'return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "update" -With @($false)))' }
        @{ Name = "letting-go-stops"
           Find = 'return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "release"))'
           Replace = 'return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "stop"))' }
        @{ Name = "stopping-lets-go"
           Find = 'return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "stop"))'
           Replace = 'return (ConvertTo-HordeWindowFollowRecord -Asked (Invoke-HordeWindowFollower -Verb "release"))' }
        @{ Name = "a-follower-for-another-system-is-asked"
           Find = 'if ($here -is [bool] -and $here) { return (New-HordeKnown -Value $follower) }'
           Replace = 'if ($true) { return (New-HordeKnown -Value $follower) }' }
        @{ Name = "applies-need-not-be-exactly-true"
           Find = 'if ($here -is [bool] -and $here) { return (New-HordeKnown -Value $follower) }'
           Replace = 'if ($here) { return (New-HordeKnown -Value $follower) }' }
        @{ Name = "a-second-registration-is-kept-beside-the-first"
           Find = 'foreach ($known in @($script:HordeWindowFollowers)) { if ($known.name -ceq $Name) { $script:HordeWindowFollowers.Remove($known) } }'
           Replace = '' }
        @{ Name = "any-name-registers"
           Find = 'if ($Name -cnotmatch ''\A[a-z][a-z0-9-]*\z'') { throw ("a platform name'
           Replace = 'if ($false) { throw ("a platform name' }
        @{ Name = "any-state-is-a-record"
           Find = 'if (@(Get-HordeWindowFollowStates) -cnotcontains $State) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "a-record-with-a-field-missing-is-taken"
           Find = 'foreach ($field in @("state", "reason", "target", "companion", "mode", "placed", "placements", "events", "findings")) {'
           Replace = 'foreach ($field in @("state")) {' }
        @{ Name = "a-state-in-another-case-is-taken"
           Find = 'if ($got.state -isnot [string] -or @(Get-HordeWindowFollowStates) -cnotcontains $got.state) { return'
           Replace = 'if ($got.state -isnot [string] -or @(Get-HordeWindowFollowStates) -notcontains $got.state) { return' }
        @{ Name = "a-real-scale-that-is-no-word-is-passed-on"
           Find = '-or $got.realScale -isnot [string] -or $words -cnotcontains $got.realScale) {'
           Replace = ') {' }
        @{ Name = "a-rectangle-that-is-no-answer-is-passed-on"
           Find = 'if (-not $asked.asked -or -not (Test-HordeAnswer $asked.value)) { return (New-HordeUnknown -Reason $asked.reason) }'
           Replace = 'if (-not $asked.asked) { return (New-HordeUnknown -Reason $asked.reason) }' }
        @{ Name = "an-absent-window-is-made-unknown"
           Find = 'if ($asked.value.state -cne "known") { return $asked.value }'
           Replace = 'if ($asked.value.state -cne "known") { return (New-HordeUnknown -Reason $asked.reason) }' }
        @{ Name = "a-rectangle-with-a-side-missing-is-passed-on"
           Find = 'foreach ($side in @("left", "top", "right", "bottom")) { if ($null -eq (Get-HordeWindowFollowWhole -From $at -Name $side)) { return (New-HordeUnknown -Reason $asked.reason) } }'
           Replace = '' }
        @{ Name = "a-rectangle-with-no-scale-is-passed-on"
           Find = 'if ($null -eq $scale -or ($scale.Value -isnot [double] -and $scale.Value -isnot [int])) { return (New-HordeUnknown -Reason $asked.reason) }'
           Replace = '' }
        @{ Name = "a-follower-that-throws-is-thrown-through"
           Find = 'catch { return [pscustomobject]@{ asked = $false; value = $null; reason = ($follower.value.name + ": its follower failed: " + $_.Exception.Message) } }'
           Replace = 'catch { throw }' }
        @{ Name = "a-follower-whose-applies-throws-ends-the-search"
           Find = 'catch { [void]$said.Add($follower.name + ": it could not say whether it is for this system: " + $_.Exception.Message); continue }'
           Replace = 'catch { return (New-HordeUnknown -Reason "the search ended") }' }
        @{ Name = "a-platform-folder-without-the-file-is-named"
           Find = 'ForEach-Object { Join-Path $_.FullName "WindowFollow.ps1" } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })'
           Replace = 'ForEach-Object { Join-Path $_.FullName "WindowFollow.ps1" })' }
        @{ Name = "a-tree-with-no-platform-folder-is-an-error"
           Find = 'if (-not (Test-Path -LiteralPath $platforms -PathType Container)) { return @() }'
           Replace = '' }
    )
}
