# Mutations of core/projection's serving rule for a node: Remove-HordeEndedSessions and the guards of
# Test-HordeSessionProvenEnded (ledger core-projection L-100). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\projection-ended.psd1
# test\test-projection.ps1 must fail for each. Only the two sections that kill them run: ended, and scope,
# which holds the live-handle case beside signal 5. The reality check is skipped, as in projection.psd1,
# so a passing run exits 3.
@{
    Target = "core\Projection.ps1"
    Suite  = "test\test-projection.ps1"
    Environment = @{ HORDE_SKIP_REALITY = "1"; HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "scope,ended" }
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "unknown-liveness-taken-as-ended"
           Find = 'if (@("gone", "reused") -cnotcontains "$($C.identity.records[$id].processCheck)") { return $false }'
           Replace = 'if (@("gone", "reused", "uncheckable", "no-table") -cnotcontains "$($C.identity.records[$id].processCheck)") { return $false }' }
        @{ Name = "reused-pid-not-proof"
           Find = 'if (@("gone", "reused") -cnotcontains "$($C.identity.records[$id].processCheck)") { return $false }'
           Replace = 'if (@("gone") -cnotcontains "$($C.identity.records[$id].processCheck)") { return $false }' }
        @{ Name = "unread-command-line-ignored"
           Find = 'if (@($C.procIndex.unreadPids).Count -gt 0) { return $false }'
           Replace = 'if ($false) { return $false }' }
        @{ Name = "live-handle-ignored"
           Find = 'if ($Session.fields["pane"].answer.state -eq "known") { return $false }'
           Replace = 'if ($false) { return $false }' }
        @{ Name = "other-live-signals-ignored"
           Find = 'return ((Get-HordeLiveSignal -C $C -Id $id -NotItsControlFile) -eq "")'
           Replace = 'return $true' }
        @{ Name = "stale-control-file-counted-as-a-signal"
           Find = 'if (-not $NotItsControlFile -and $C.identity.records.ContainsKey($Id)) { return "a control file names it" }'
           Replace = 'if ($C.identity.records.ContainsKey($Id)) { return "a control file names it" }' }
        @{ Name = "nothing-left-out"
           Find = '$kept = @($Projection.sessions | Where-Object { -not (Test-HordeSessionProvenEnded -C $C -Session $_) })'
           Replace = '$kept = @($Projection.sessions)' }
    )
}
