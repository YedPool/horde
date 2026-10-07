# Mutations of hosts/wezterm/Window.ps1, which says which native window shows a pane. Run:
#   powershell -File tools\Mutate.ps1 -Spec hosts\wezterm\test\mutations\window.psd1
# hosts\wezterm\test\test-window.ps1 must fail for every one. Each breaks one rule that keeps the finder
# from guessing a window.
@{
    Target = "hosts\wezterm\Window.ps1"
    Suite  = "hosts\wezterm\test\test-window.ps1"
    Mutations = @(
        # --- the listing is UTF-8, and is mended in this file (the host's call is not this file's to change)
        @{ Name = "the-listing-is-compared-as-it-was-read"
           Find = '$listing = $mended.value'
           Replace = '' }
        @{ Name = "an-answer-read-as-utf8-is-mended-again"
           Find = 'if ($ReadAs.CodePage -eq 65001 -or '
           Replace = 'if (' }
        @{ Name = "a-lost-byte-is-not-noticed"
           Find = 'if ($ReadAs.GetString($bytes) -cne $Text) { $bytes = $null }'
           Replace = '' }
        @{ Name = "bytes-that-are-not-utf8-are-accepted"
           Find = 'UTF8Encoding($false, $true)'
           Replace = 'UTF8Encoding($false, $false)' }
        # --- the listing
        @{ Name = "a-pane-with-no-is-active-accepted"
           Find = 'foreach ($need in @("pane_id", "window_id", "tab_id", "title", "is_active")) {'
           Replace = 'foreach ($need in @("pane_id", "window_id", "tab_id", "title")) {' }
        @{ Name = "empty-output-is-no-panes"
           Find = 'if ($joined -eq "") { return (New-HordeUnknown -Reason "the terminal''s pane list was empty output, which is unknown, not none") }'
           Replace = 'if ($joined -eq "") { return (New-HordeKnown -Value @()) }' }
        @{ Name = "an-id-of-any-kind-is-read"
           Find = 'if (($number -isnot [int] -and $number -isnot [long]) -or $number -lt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-id-below-zero-is-read"
           Find = 'if (($number -isnot [int] -and $number -isnot [long]) -or $number -lt 0) {'
           Replace = 'if ($number -isnot [int] -and $number -isnot [long]) {' }
        @{ Name = "a-title-that-is-not-text-is-converted"
           Find = 'if ($p.title -isnot [string]) {'
           Replace = 'if ($false) {' }
        @{ Name = "is-active-of-any-kind-is-converted"
           Find = 'if ($p.is_active -isnot [bool]) {'
           Replace = 'if ($false) {' }
        @{ Name = "is-zoomed-of-any-kind-is-converted"
           Find = 'if ($p.is_zoomed -isnot [bool]) {'
           Replace = 'if ($false) {' }
        # --- the size of a pane, a tab and a window, as the listing gives them
        @{ Name = "a-width-that-is-not-whole-cells-is-a-size"
           Find = 'if (($n["pixel_width"] % $n["cols"]) -ne 0 -or ($n["pixel_height"] % $n["rows"]) -ne 0) { return $null }'
           Replace = 'if (($n["pixel_height"] % $n["rows"]) -ne 0) { return $null }' }
        @{ Name = "a-height-that-is-not-whole-cells-is-a-size"
           Find = 'if (($n["pixel_width"] % $n["cols"]) -ne 0 -or ($n["pixel_height"] % $n["rows"]) -ne 0) { return $null }'
           Replace = 'if (($n["pixel_width"] % $n["cols"]) -ne 0) { return $null }' }
        @{ Name = "a-pane-need-not-say-where-it-starts"
           Find = 'foreach ($f in @("left_col", "top_row")) {'
           Replace = 'foreach ($f in @("top_row")) {' }
        @{ Name = "a-split-tab-is-as-wide-as-one-pane"
           Find = '$row.shape.left + $row.shape.cols'
           Replace = '$row.shape.cols' }
        @{ Name = "a-split-tab-is-as-tall-as-one-pane"
           Find = '$row.shape.top + $row.shape.rows'
           Replace = '$row.shape.rows' }
        @{ Name = "tabs-of-two-sizes-are-one-window-size"
           Find = 'Sort-Object -Unique).Count -ne 1) { return [pscustomobject]@{ shapes = $null; why = ("the tabs of window "'
           Replace = 'Sort-Object -Unique).Count -lt 1) { return [pscustomobject]@{ shapes = $null; why = ("the tabs of window "' }
        @{ Name = "cells-of-two-sizes-are-one-window-size"
           Find = 'if ($row.shape.cellWidth -ne $cell.cellWidth -or $row.shape.cellHeight -ne $cell.cellHeight) {'
           Replace = 'if ($false) {' }
        # --- the padding: worked out from the windows, never below zero, never a whole cell left over
        @{ Name = "a-padding-below-zero-is-tried"
           Find = 'if ($padding -lt 0 -or $tried.ContainsKey($padding)) { continue }'
           Replace = 'if ($tried.ContainsKey($padding)) { continue }' }
        @{ Name = "a-whole-cell-left-over-fits"
           Find = '($left -ge 0 -and $left -lt [long]($_ -split "\|")[1])'
           Replace = '($left -ge 0 -and $left -le [long]($_ -split "\|")[1])' }
        @{ Name = "a-span-wider-than-the-window-fits"
           Find = '($left -ge 0 -and $left -lt [long]($_ -split "\|")[1])'
           Replace = '($left -lt [long]($_ -split "\|")[1])' }
        @{ Name = "two-windows-share-one-listed-window"
           Find = 'if ($groups[$group] -gt $ids.Count) { $whole = $false; break }'
           Replace = '' }
        # --- the title a window can carry
        @{ Name = "titles-compared-without-case"
           Find = '[System.StringComparison]::Ordinal) -ge 0) { return $true }'
           Replace = '[System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }' }
        @{ Name = "a-pane-with-no-title-is-carried-by-every-window"
           Find = 'if ($row.title -cne "" -and $Title.IndexOf('
           Replace = 'if ($Title.IndexOf(' }
        @{ Name = "a-pane-that-is-not-active-titles-the-window"
           Find = 'foreach ($row in @($Rows | Where-Object { $_.active })) {'
           Replace = 'foreach ($row in @($Rows)) {' }
        # --- the decision
        @{ Name = "a-pane-that-is-gone-still-has-a-window"
           Find = 'if ($mine.Count -eq 0) { return (New-HordeUnknown -Reason ("the terminal lists no pane "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the terminal lists no pane "' }
        @{ Name = "a-pane-listed-twice-has-a-window"
           Find = 'if ($mine.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "sizes-are-not-used"
           Find = '$could = Get-HordeWeztermSizeCandidates -Shapes $listed.shapes -Sized $sized; if'
           Replace = '$could = $null; if' }
        @{ Name = "a-size-that-changed-while-read-is-kept"
           Find = 'if ([long]$n.width -ne $seen[$key].width -or [long]$n.height -ne $seen[$key].height) { $seen[$key].width = [long]0; $seen[$key].height = [long]0 }'
           Replace = '' }
        @{ Name = "the-one-window-of-its-size-is-not-taken"
           Find = 'if ($pool.Count -eq 1) { return (New-HordeKnown -Value ([pscustomobject]@{ handle = $pool[0].handle; window = $windowId; detail = ("the one of the terminal''s " + $all.Count + " windows with the size'
           Replace = 'if ($false) { return (New-HordeKnown -Value ([pscustomobject]@{ handle = $pool[0].handle; window = $windowId; detail = ("the one of the terminal''s " + $all.Count + " windows with the size' }
        @{ Name = "size-proves-with-fewer-windows-than-they-could-be"
           Find = 'if ($bySize.Count -gt 0 -and $theirs.Count -le $bySize.Count) {'
           Replace = 'if ($bySize.Count -gt 0) {' }
        @{ Name = "the-one-left-over-needs-no-count"
           Find = ' -and $all.Count -eq $windowIds.Count) { return'
           Replace = ') { return' }
        @{ Name = "no-window-of-the-size-is-not-said"
           Find = 'if ($pool.Count -eq 0) { return (New-HordeWeztermUnsettled'
           Replace = 'if ($false) { return (New-HordeWeztermUnsettled' }
        @{ Name = "the-title-is-asked-of-windows-of-every-size"
           Find = '$matched = @($pool | Where-Object { & $fits $_ $windowId })'
           Replace = '$matched = @($all | Where-Object { & $fits $_ $windowId })' }
        @{ Name = "the-first-of-two-windows-is-chosen"
           Find = 'if ($matched.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-window-that-fits-two-ids-is-chosen"
           Find = 'if ($others.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-only-window-on-screen-is-chosen-among-several-ids"
           Find = 'if ($windowIds.Count -eq 1 -and $all.Count -eq 1) {'
           Replace = 'if ($all.Count -eq 1) {' }
        @{ Name = "the-second-reading-of-the-windows-ignored"
           Find = 'foreach ($n in (@($Native) + @($NativeAfter))) {'
           Replace = 'foreach ($n in @($Native)) {' }
        @{ Name = "no-window-on-screen-not-said"
           Find = 'if ($all.Count -eq 0) { return (New-HordeUnknown -Reason "the terminal''s process has no terminal window on screen, so there is none to stand beside") }'
           Replace = '' }
        # --- a window is believed only when a second whole reading names it again (review finding C2)
        @{ Name = "a-window-found-once-is-believed"
           Find = '$last = Compare-HordeWeztermWindowReadings -First $last -Second $again -ApartMs $Values.confirmWaitMs'
           Replace = '' }
        @{ Name = "the-second-reading-is-the-first-again"
           Find = '$again = Read-HordeWeztermWindowReading -Target $target.value -Pane $Pane -Runner $Runner -Windows $Windows -ReadAs $ReadAs'
           Replace = '$again = $last' }
        @{ Name = "the-second-reading-is-not-waited-for"
           Find = 'Wait-HordeWeztermWindowMoment -Milliseconds $Values.confirmWaitMs -Wait $Wait'
           Replace = '' }
        @{ Name = "a-second-reading-that-found-nothing-is-ignored"
           Find = 'if ($Second.state -cne "known") { return (New-HordeWeztermUnsettled'
           Replace = 'if ($false) { return (New-HordeWeztermUnsettled' }
        @{ Name = "two-different-windows-are-believed"
           Find = 'if ([long]$First.value.handle -ne [long]$Second.value.handle) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-pane-in-another-window-id-is-believed"
           Find = 'if ("" + $First.value.window -cne "" + $Second.value.window) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-disagreement-is-never-read-again"
           Find = 'return (New-HordeWeztermUnsettled -Reason ("two readings " + $ApartMs + " ms apart named different windows'
           Replace = 'return (New-HordeUnknown -Reason ("two readings " + $ApartMs + " ms apart named different windows' }
        @{ Name = "an-unsettled-answer-carries-no-mark"
           Find = 'Add-Member -InputObject $unsettled -NotePropertyName readAgain -NotePropertyValue $true'
           Replace = '' }
        # --- the settings (core/ModuleSettings.ps1): one table, one file, and a finding is never silent
        @{ Name = "the-persons-file-is-not-read"
           Find = 'if ($null -eq $Settings) { $Settings = Get-HordeWeztermWindowSettings }'
           Replace = 'if ($null -eq $Settings) { $Settings = Read-HordeModuleSettingsText -Declaration $script:HordeWeztermWindowSettings -Text $null }' }
        @{ Name = "the-socket-folder-setting-ignored"
           Find = 'if ($Configured -ne "") { return $Configured }'
           Replace = '' }
        @{ Name = "the-retry-wait-is-not-waited"
           Find = 'if ($try -gt 1) { Wait-HordeWeztermWindowMoment -Milliseconds $Values.retryWaitMs -Wait $Wait }'
           Replace = '' }
        @{ Name = "a-settings-finding-is-silent"
           Find = 'if (@($Findings).Count -eq 0) { return $Answer }'
           Replace = 'return $Answer' }
        @{ Name = "a-found-window-hides-the-finding"
           Find = 'if ($Answer.state -ceq "known") { $Answer.value.detail = ("" + $Answer.value.detail) + $note; return $Answer }'
           Replace = 'if ($Answer.state -ceq "known") { return $Answer }' }
        # --- from the record to the terminal
        @{ Name = "any-text-is-a-pane"
           Find = 'if ($Pane -cnotmatch ''\A[0-9]{1,9}\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "a-record-chooses-the-socket-folder"
           Find = 'if ($Instance -cnotmatch $script:HordeWeztermSocketLeaf) {'
           Replace = 'if ($Instance -eq "") {' }
        @{ Name = "a-terminal-that-is-not-running-is-asked"
           Find = 'if ($target.state -cne "known") { return (New-HordeUnknown -Reason ("the session''s terminal is not running: " + $target.reason)) }'
           Replace = 'if ($target.state -cne "known") { $target = New-HordeKnown -Value ([pscustomobject]@{ socket = (Join-Path (Get-HordeWeztermWindowSockDir -Configured $Values.socketFolder) $Instance); guiPid = 4242; guiStart = "133000000000000000" }) }' }
        @{ Name = "a-failed-listing-is-read-anyway"
           Find = 'if ($call.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit "' }
        @{ Name = "a-title-out-of-step-is-not-read-again"
           Find = 'for ($try = 1; $try -le $Values.attempts; $try++) {'
           Replace = 'for ($try = 1; $try -le 1; $try++) {' }
        @{ Name = "every-unknown-is-read-again"
           Find = 'if ($null -eq $last.PSObject.Properties["readAgain"]) { return $last }'
           Replace = '' }
        @{ Name = "the-windows-are-read-once"
           Find = 'if ($null -ne $Windows) { $after = @(& $Windows ([long]$Target.guiPid)) }'
           Replace = 'if ($null -ne $Windows) { $after = @() }' }
    )
}
