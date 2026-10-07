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
        # --- the title a window can have
        @{ Name = "titles-compared-without-case"
           Find = 'if ($tabs -le 1) { if ($Title -ceq $want) { return $true }; continue }'
           Replace = 'if ($tabs -le 1) { if ($Title -eq $want) { return $true }; continue }' }
        @{ Name = "a-bare-title-fits-a-window-of-several-tabs"
           Find = 'if ($tabs -le 1) { if ($Title -ceq $want) { return $true }; continue }'
           Replace = 'if ($Title -ceq $want) { return $true }; if ($tabs -le 1) { continue }' }
        @{ Name = "any-tab-count-fits"
           Find = 'for ($i = 1; $i -le $tabs; $i++) { if ($Title -ceq ("[" + $i + "/" + $tabs + "] " + $want)) { return $true } }'
           Replace = 'for ($i = 1; $i -le 9; $i++) { for ($n = 1; $n -le 9; $n++) { if ($Title -ceq ("[" + $i + "/" + $n + "] " + $want)) { return $true } } }' }
        @{ Name = "a-pane-that-is-not-active-titles-the-window"
           Find = 'foreach ($row in @($Rows | Where-Object { $_.active })) {'
           Replace = 'foreach ($row in @($Rows)) {' }
        @{ Name = "zoomed-not-in-the-title"
           Find = 'if ($row.zoomed) { $want = "[Z] " + $want }'
           Replace = '' }
        # --- the decision
        @{ Name = "a-pane-that-is-gone-still-has-a-window"
           Find = 'if ($mine.Count -eq 0) { return (New-HordeUnknown -Reason ("the terminal lists no pane "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the terminal lists no pane "' }
        @{ Name = "a-pane-listed-twice-has-a-window"
           Find = 'if ($mine.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-first-of-two-windows-is-chosen"
           Find = 'if ($matched.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-window-that-fits-two-ids-is-chosen"
           Find = 'if ($others.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-only-window-on-screen-is-chosen-among-several-ids"
           Find = 'if ($windowIds.Count -eq 1 -and $titles.Count -eq 1) {'
           Replace = 'if ($titles.Count -eq 1) {' }
        @{ Name = "the-second-reading-of-the-windows-ignored"
           Find = 'foreach ($n in (@($Native) + @($NativeAfter))) {'
           Replace = 'foreach ($n in @($Native)) {' }
        @{ Name = "no-window-on-screen-not-said"
           Find = 'if ($titles.Count -eq 0) { return (New-HordeUnknown -Reason "the terminal''s process has no terminal window on screen, so there is none to stand beside") }'
           Replace = '' }
        # --- from the record to the terminal
        @{ Name = "any-text-is-a-pane"
           Find = 'if ($Pane -cnotmatch ''\A[0-9]{1,9}\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "a-record-chooses-the-socket-folder"
           Find = 'if ($Instance -cnotmatch $script:HordeWeztermSocketLeaf) {'
           Replace = 'if ($Instance -eq "") {' }
        @{ Name = "a-terminal-that-is-not-running-is-asked"
           Find = 'if ($target.state -cne "known") { return (New-HordeUnknown -Reason ("the session''s terminal is not running: " + $target.reason)) }'
           Replace = 'if ($target.state -cne "known") { $target = New-HordeKnown -Value ([pscustomobject]@{ socket = (Join-Path $SockDir $Instance); guiPid = 4242; guiStart = "133000000000000000" }) }' }
        @{ Name = "a-failed-listing-is-read-anyway"
           Find = 'if ($call.code -ne 0) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the terminal did not list its panes (exit "' }
        @{ Name = "a-title-out-of-step-is-not-read-again"
           Find = 'for ($try = 1; $try -le [Math]::Max($Attempts, 1); $try++) {'
           Replace = 'for ($try = 1; $try -le 1; $try++) {' }
        @{ Name = "every-unknown-is-read-again"
           Find = 'if ($last.state -ceq "known" -or $last.reason -notlike "none of the terminal''s*") { return $last }'
           Replace = 'if ($last.state -ceq "known") { return $last }' }
        @{ Name = "the-windows-are-read-once"
           Find = 'if ($null -ne $Windows) { $after = @(& $Windows ([long]$target.value.guiPid)) }'
           Replace = 'if ($null -ne $Windows) { $after = @() }' }
    )
}
