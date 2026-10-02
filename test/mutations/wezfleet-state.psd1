# Mutations of core/WezfleetState.ps1, the reader of wezfleet's stores. Run one spec at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\wezfleet-state.psd1
# The spec sets HORDE_SKIP_REALITY=1 for its own runs (see test\mutations\hostport.psd1).
@{
    Target = "core\WezfleetState.ps1"
    Suite  = "test\test-projection.ps1"
    # Fixtures only, and stop at the first failed check: a caught mutant needs nothing more.
    # Only the sections that kill these mutants (test	est-projection.ps1 SECTIONS): the stored fields, runs and reports, the registry checks, and the shared-reader scan.
    # Every mutant is still run; the whole list must come out as expected (PR #31, 2026-10-01).
    Environment = @{ HORDE_SKIP_REALITY = "1"; HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "precedence,runs,cardinality,writes" }
    # With the reality check skipped the suite passes with exit 3 (test\test-projection.ps1).
    PassCodes = @(3)
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
