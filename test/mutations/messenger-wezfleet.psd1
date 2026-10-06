# Mutations of the wezfleet messenger (remote plan R21, slice 3b). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\messenger-wezfleet.psd1
# Each loosens one rule of messengers/wezfleet/Messenger.ps1, and its own suite must fail for every one.
# Every find string occurs exactly once, on one line.
@{
    Target = "messengers\wezfleet\Messenger.ps1"
    Suite  = "messengers\wezfleet\test\test-wezfleet-messenger.ps1"
    Mutations = @(
        @{ Name = "unset-root-used"
           Find = 'if ("$dir" -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "relative-root-used"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($dir) -or $dir -notmatch ''\A[A-Za-z]:\\'' -or @($dir -split ''[\\/]'') -contains "..") {'
           Replace = 'if ($false) {' }
        @{ Name = "climbing-root-used"
           Find = ' -or @($dir -split ''[\\/]'') -contains "..") {'
           Replace = ') {' }
        @{ Name = "timeout-floor-dropped"
           Find = 'if ($TimeoutSeconds -lt 1) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "body-on-command-line"
           Find = '"-MessageFile", $file)'
           Replace = '"-MessageFile", $file, "-Body", [string]$Message.body)' }
        @{ Name = "message-file-kept"
           Find = 'if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }'
           Replace = '' }
        @{ Name = "empty-label-sent"
           Find = 'if ($null -ne $fl -and "$($fl.Value)" -ne "") { $argv += @("-FromLabel", [string]$fl.Value) }'
           Replace = '$argv += @("-FromLabel", "")' }
        # Written in a single-byte code page, a non-ASCII letter in the body is lost. (UTF-16 is not a
        # mutant here: it carries a BOM, and wezfleet's reader detects it and decodes the body intact -
        # measured, msg-b3-mut 2026-10-06.)
        @{ Name = "body-written-ascii"
           Find = '(New-Object System.Text.UTF8Encoding($false))'
           Replace = '[System.Text.Encoding]::ASCII' }
        @{ Name = "many-lines-read"
           Find = 'if ($lines.Count -ne 1) {'
           Replace = 'if ($lines.Count -eq 0) {' }
        @{ Name = "non-json-read"
           Find = 'if ($null -eq $j -or $j -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-field-unchecked"
           Find = 'foreach ($k in $need) { if ($names -cnotcontains $k) {'
           Replace = 'foreach ($k in $need) { if ($false) {' }
        @{ Name = "extra-field-unchecked"
           Find = 'foreach ($k in $names) { if ($need -cnotcontains $k) {'
           Replace = 'foreach ($k in $names) { if ($false) {' }
        @{ Name = "woken-type-unchecked"
           Find = 'if ($Command -ceq "post" -and $j.woken -isnot [bool]) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-type-unchecked"
           Find = 'if ($j.$k -isnot [string]) {'
           Replace = 'if ($false) {' }
        @{ Name = "foreign-id-read"
           Find = 'if ($j.id -cne $asked) {'
           Replace = 'if ($false) {' }
        @{ Name = "exit-outside-table-read"
           Find = 'if (-not $byExit.ContainsKey([int]$Run.exit)) {'
           Replace = 'if ($false) {' }
        @{ Name = "stage-exit-unpaired"
           Find = 'if (@($byExit[[int]$Run.exit]) -cnotcontains $j.stage) {'
           Replace = 'if ($false) {' }
        @{ Name = "queued-misread"
           Find = '"queued" = "accepted";'
           Replace = '"queued" = "handed-over";' }
        @{ Name = "taken-misread"
           Find = '"taken" = "seen";'
           Replace = '"taken" = "handed-over";' }
        @{ Name = "unconfirmed-misread"
           Find = '"unconfirmed" = "expired";'
           Replace = '"unconfirmed" = "held";' }
        @{ Name = "refused-misread"
           Find = '"refused" = "held" }'
           Replace = '"refused" = "expired" }' }
        @{ Name = "unconfirmed-reasonless"
           Find = 'if ($reason -eq "" -and $j.stage -ceq "unconfirmed") {'
           Replace = 'if ($false) {' }
        @{ Name = "refused-reasonless"
           Find = 'if ($reason -eq "" -and $j.stage -ceq "refused") {'
           Replace = 'if ($false) {' }
        @{ Name = "hung-child-not-killed"
           Find = 'try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }'
           Replace = '' }
        @{ Name = "output-cap-dropped"
           Find = 'if ($got.Length -gt $script:HordeWezfleetMessengerMaxBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "spaced-argument-unquoted"
           Find = 'if ($a -ne "" -and $a -notmatch ''[\s"]'') { [void]$parts.Add($a); continue }'
           Replace = '[void]$parts.Add($a); continue' }
    )
}
