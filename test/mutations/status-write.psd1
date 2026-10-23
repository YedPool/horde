# Mutations of fleet/StatusWrite.ps1, the one writer of an Orc's status card. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\status-write.psd1
# Each breaks one rule of what is written or when; test\test-status-set.ps1 must fail a check for every one.
@{
    Target = "fleet\StatusWrite.ps1"
    Suite  = "test\test-status-set.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "reader-verdict-ignored"
           Find = '$problems += @($verdict.problems)'
           Replace = '$problems += @()' }
        @{ Name = "dry-run-writes"
           Find = 'if ($DryRun) {'
           Replace = 'if ($false) {' }
        @{ Name = "last-good-not-kept"
           Find = 'Write-HordeStatusFileAtomic -Path (Join-Path $Folder $script:HordeStatusLastGoodFile) -Bytes $bytes'
           Replace = '$null = $bytes' }
        @{ Name = "waiting-on-line-always"
           Find = 'if ($null -ne $WaitingOn) { $lines +='
           Replace = 'if ($true) { $lines +=' }
        @{ Name = "orc-not-inherited"
           Find = 'if ($current.written) { $Orc = $current.orc }'
           Replace = 'if ($current.written) { $Orc = "Z" }' }
        @{ Name = "lane-not-inherited"
           Find = 'if ($current.written) { $Lane = $current.lane }'
           Replace = 'if ($current.written) { $Lane = "zz" }' }
        @{ Name = "missing-orc-lane-not-refused"
           Find = 'if ($missing.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "line-break-in-value-allowed"
           Find = '-match "[\r\n]"'
           Replace = '-match "QQQ"' }
        @{ Name = "missing-folder-not-refused"
           Find = 'if (-not [System.IO.Directory]::Exists($Folder)) {'
           Replace = 'if ($false) {' }
        @{ Name = "non-ascii-transliterated"
           Find = 'return (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)'
           Replace = 'return [System.Text.Encoding]::ASCII.GetBytes($text)' }
        @{ Name = "undo-stamps-now"
           Find = ' -Mtime $previousTime; $undone'
           Replace = '; $undone' }
        @{ Name = "size-cap-ignored"
           Find = 'if ($bytes.Length -gt $script:HordeFleetStatusMostBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "sibling-letter-ignored"
           Find = 'if ($rivals.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "failed-readback-not-undone"
           Find = 'if ($null -ne $previous) { Write-HordeStatusFileAtomic -Path $target -Bytes $previous -Mtime'
           Replace = 'if ($false) { Write-HordeStatusFileAtomic -Path $target -Bytes $previous -Mtime' }
        @{ Name = "readback-skipped-last-good-from-bad"
           Find = 'Write-HordeStatusFileAtomic -Path $target -Bytes $bytes'
           Replace = 'Write-HordeStatusFileAtomic -Path $target -Bytes ([System.Text.Encoding]::ASCII.GetBytes("junk"))' }
        @{ Name = "row-no-home-goes-on"
           Find = 'if ($resolved.source -eq "default") {'
           Replace = 'if ($false) {' }
        @{ Name = "row-thrall-folder-not-detected"
           Find = 'if ($leaf -ceq "thrall") {'
           Replace = 'if ($false) {' }
        @{ Name = "row-made-for-wrong-orc"
           Find = 'orc = $back.orc; lane = $back.lane }'
           Replace = 'orc = "Z"; lane = $back.lane }' }
    )
}
