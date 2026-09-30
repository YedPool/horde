# Mutations of core/WezfleetState.ps1, the reader of wezfleet's stores. Run one spec at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\wezfleet-state.psd1
# The spec sets HORDE_SKIP_REALITY=1 for its own runs (see test\mutations\hostport.psd1).
@{
    Target = "core\WezfleetState.ps1"
    Suite  = "test\test-projection.ps1"
    Environment = @{ HORDE_SKIP_REALITY = "1" }
    Mutations = @(
        @{ Name = "corrupt-record-forgets-its-session"
           Find = 'if ($null -eq $j) { [void]$unreadable.Add($id); continue }'
           Replace = 'if ($null -eq $j) { continue }' }
        @{ Name = "misnamed-record-accepted"
           Find = 'if ($storedId -ne $id) {'
           Replace = 'if ($false) {' }
        @{ Name = "misnamed-only-copy-not-a-gap"
           Find = 'if ($m.storedId -eq "" -or -not $records.ContainsKey($m.storedId)) {'
           Replace = 'if ($false) {' }
        @{ Name = "torn-event-line-skipped"
           Find = 'if ($null -eq $e -or $e -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($null -eq $e) { continue }; if ($false) {' }
        @{ Name = "closed-runs-read-as-open"
           Find = '$closed = New-HordeKnown -Value ($null -ne $ca -and $null -ne $ca.Value -and "$($ca.Value)" -ne "")'
           Replace = '$closed = New-HordeKnown -Value $false' }
        @{ Name = "command-log-time-not-read"
           Find = 'cmdlogAt = (Get-HordeWriteTime -Path (Join-Path $sf.FullName "cmdlog.txt"))'
           Replace = 'cmdlogAt = (Get-HordeWriteTime -Path (Join-Path $sf.FullName "cmdlog.missing"))' }
        @{ Name = "fleet-index-empty"
           Find = 'if (-not $byFleetId[$e.id].Contains($run)) { [void]$byFleetId[$e.id].Add($run) }'
           Replace = '' }
        @{ Name = "plain-read-share"
           Find = '$j = (Read-HordeSharedText -Path $Path) | ConvertFrom-Json'
           Replace = '$j = ([System.IO.File]::ReadAllText($Path)) | ConvertFrom-Json' }
    )
}
