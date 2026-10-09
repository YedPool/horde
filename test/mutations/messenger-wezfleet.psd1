# Mutations of the wezfleet messenger (remote plan R21, slice 3b; review of #106). Run:
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
        @{ Name = "reparse-point-followed"
           Find = 'if (($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "reparse-point-above-unseen"
           Find = '$d = $d.Parent'
           Replace = '$d = $null' }
        @{ Name = "markers-unchecked"
           Find = 'if (-not (Test-Path -LiteralPath (Join-Path $dir $marker) -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "mail-commands-marker-dropped"
           Find = '"lib\MailPost.ps1", '
           Replace = '' }
        @{ Name = "timeout-floor-dropped"
           Find = 'if ($TimeoutSeconds -lt 1) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "bad-to-started"
           Find = 'if ($to -cnotmatch $script:HordeWezfleetMessengerSessionPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "bad-label-started"
           Find = 'if ($label -ne "" -and $label -cnotmatch $script:HordeWezfleetMessengerLabelPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "nameless-sender-started"
           Find = 'if (-not $sidOk -and $label -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "non-uuid-sender-passed"
           Find = 'if ($sidOk) { $argv += @("-FromSessionId", $fromSid) }'
           Replace = '$argv += @("-FromSessionId", $fromSid)' }
        @{ Name = "body-on-command-line"
           Find = '"-MessageFile", $file)'
           Replace = '"-MessageFile", $file, "-Body", [string]$Message.body)' }
        @{ Name = "message-file-kept"
           Find = 'if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }'
           Replace = '' }
        @{ Name = "body-outside-horde-folder"
           Find = '$file = Join-Path (Get-HordeWezfleetMessengerOutgoing) ('
           Replace = '$file = Join-Path ([System.IO.Path]::GetTempPath()) (' }
        @{ Name = "folder-acl-not-set"
           Find = '[System.IO.Directory]::SetAccessControl($dir, $sec)'
           Replace = '' }
        @{ Name = "folder-acl-inherits"
           Find = '$sec.SetAccessRuleProtection($true, $false)'
           Replace = '$sec.SetAccessRuleProtection($false, $true)' }
        @{ Name = "sweep-removes-nothing"
           Find = 'foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Force)) { Remove-Item -LiteralPath $f.FullName -Force; $n++ }'
           Replace = '' }
        @{ Name = "empty-label-sent"
           Find = 'if ($label -ne "") { $argv += @("-FromLabel", $label) }'
           Replace = '$argv += @("-FromLabel", "")' }
        @{ Name = "body-written-ascii"
           Find = '(New-Object System.Text.UTF8Encoding($false))'
           Replace = '[System.Text.Encoding]::ASCII' }
        @{ Name = "many-lines-read"
           Find = 'if ($lines.Count -ne 1) {'
           Replace = 'if ($lines.Count -eq 0) {' }
        # A parameter the host rejects prints nothing on stdout: the host's words on stderr are the only
        # account of it (wezfleet main 68ff08e, measured 2026-10-06).
        @{ Name = "stderr-words-dropped"
           Find = '("$($Run.stdout)" + "`n" + "$($Run.stderr)")'
           Replace = '("$($Run.stdout)")' }
        @{ Name = "non-json-read"
           Find = 'if ($null -eq $j -or $j -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-field-unchecked"
           Find = 'foreach ($k in $need) { if ($names -cnotcontains $k) {'
           Replace = 'foreach ($k in $need) { if ($false) {' }
        @{ Name = "extra-field-unchecked"
           Find = 'foreach ($k in $names) { if ($may -cnotcontains $k) {'
           Replace = 'foreach ($k in $names) { if ($false) {' }
        @{ Name = "detail-not-read"
           Find = '$may = @($need) + @("detail")'
           Replace = '$may = @($need)' }
        @{ Name = "woken-type-unchecked"
           Find = 'if ($Command -ceq "post" -and $j.woken -isnot [bool]) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-type-unchecked"
           Find = 'if ($j.$k -isnot [string]) {'
           Replace = 'if ($false) {' }
        @{ Name = "foreign-id-read"
           Find = 'if ($j.id -cne $asked) {'
           Replace = 'if ($false) {' }
        # Without its own branch, the fleet's documented exit 1 reads as "not an exit code of the fleet".
        @{ Name = "fleet-failure-read-as-foreign-exit"
           Find = 'if ([int]$Run.exit -eq 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "exit-outside-table-read"
           Find = 'if (-not $byExit.ContainsKey([int]$Run.exit)) {'
           Replace = 'if ($false) {' }
        @{ Name = "stage-exit-unpaired"
           Find = 'if (@($byExit[[int]$Run.exit]) -cnotcontains $j.stage) {'
           Replace = 'if ($false) {' }
        @{ Name = "exit-4-unread"
           Find = '; 4 = @("refused", "queued") }'
           Replace = ' }' }
        @{ Name = "exit-4-queued-unread"
           Find = '4 = @("refused", "queued")'
           Replace = '4 = @("refused")' }
        # The shape wezfleet main (its pull request 70) gives exit 4 with nothing written.
        @{ Name = "exit-4-refused-unread"
           Find = '4 = @("refused", "queued")'
           Replace = '4 = @("queued")' }
        # A shape no wezfleet shipped: exit 4 with the stage absent (the first revision of #65's review).
        @{ Name = "exit-4-absent-read"
           Find = '4 = @("refused", "queued")'
           Replace = '4 = @("absent", "refused", "queued")' }
        # wezfleet main's closed list has invalid-utf8: a code may hold digits.
        @{ Name = "code-digits-read-as-prose"
           Find = '$script:HordeWezfleetMessengerCodePattern = ''\A[a-z][a-z0-9]*(-[a-z0-9]+)*\z'''
           Replace = '$script:HordeWezfleetMessengerCodePattern = ''\A[a-z]+(-[a-z]+)*\z''' }
        # A sentence where the code is: a wezfleet from before the reason codes, never read as a stage.
        @{ Name = "prose-reason-read"
           Find = 'if ($j.reason -cne "" -and $j.reason -cnotmatch $script:HordeWezfleetMessengerCodePattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "exit-4-not-held"
           Find = 'if ([int]$Run.exit -eq 4) { $stage = "held";'
           Replace = 'if ([int]$Run.exit -eq 4) { $stage = $stage;' }
        @{ Name = "post-target-unchecked"
           Find = 'if ($j.to -cne $To) {'
           Replace = 'if ($false) {' }
        @{ Name = "moved-repost-refused"
           Find = 'if ($code -cne "already-posted" -or'
           Replace = 'if ($true -or' }
        @{ Name = "moved-repost-any-text"
           Find = ' -or $j.to -cnotmatch $script:HordeWezfleetMessengerSessionPattern) {'
           Replace = ') {' }
        @{ Name = "follow-unsaid"
           Find = '$where = "followed to " + $j.to'
           Replace = '$where = ""' }
        @{ Name = "status-target-unchecked"
           Find = 'if ($j.to -cnotmatch $script:HordeWezfleetMessengerSessionPattern) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "status-target-unsaid"
           Find = '$where = "at " + $j.to'
           Replace = '$where = ""' }
        @{ Name = "detail-uncut"
           Find = '$detail = ConvertTo-HordeWezfleetMessengerLine $dp.Value -Max $script:HordeWezfleetMessengerDetailChars'
           Replace = '$detail = [string]$dp.Value' }
        @{ Name = "detail-uncapped"
           Find = '-Max $script:HordeWezfleetMessengerDetailChars'
           Replace = '-Max 100000' }
        @{ Name = "detail-not-text-kept"
           Find = 'if ($null -ne $dp -and $dp.Value -is [string]) {'
           Replace = 'if ($null -ne $dp) {' }
        @{ Name = "detail-dropped"
           Find = 'if ($detail -ne "") { $reason = $(if ($reason -ne "") { $reason + ": " + $detail } else { $detail }) }'
           Replace = '' }
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
           Find = 'if ($code -eq "" -and $j.stage -ceq "unconfirmed") {'
           Replace = 'if ($false) {' }
        @{ Name = "refused-reasonless"
           Find = 'if ($code -eq "" -and $j.stage -ceq "refused") {'
           Replace = 'if ($false) {' }
        @{ Name = "hung-child-not-killed"
           Find = 'try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }'
           Replace = '' }
        # Review of #106, F6: the output is taken as complete once the command has exited.
        @{ Name = "exited-command-output-awaited"
           Find = 'elseif (((Get-Date) - $exitedAt).TotalMilliseconds -ge $script:HordeWezfleetMessengerDrainMs) { $drained = $true; break }'
           Replace = 'elseif ($false) { }' }
        @{ Name = "output-cap-dropped"
           Find = 'if ($got.Length -gt $script:HordeWezfleetMessengerMaxBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "spaced-argument-unquoted"
           Find = 'if ($a -ne "" -and $a -notmatch ''[\s"]'') { [void]$parts.Add($a); continue }'
           Replace = '[void]$parts.Add($a); continue' }
    )
}
