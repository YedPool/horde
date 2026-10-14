# Mutations of what core/projection tells a node's sessions.list about its store folders, for
# membershipComplete (ledger core-projection L-101, review of PR #243). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\projection-membership.psd1
# test\test-projection.ps1 must fail for each. Only the membership section runs; the reality check is
# skipped, as in projection-ended.psd1, so a passing run exits 3.
@{
    Target = "core\Projection.ps1"
    Suite  = "test\test-projection.ps1"
    Environment = @{ HORDE_SKIP_REALITY = "1"; HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "membership" }
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "store-folders-not-served"
           Find = '$doc["storeFolders"] = $sf'
           Replace = '$doc["storeFolders"] = $null' }
        @{ Name = "pane-folder-not-seen"
           Find = 'X1 = (Test-Path -LiteralPath $PaneSessionsDir -PathType Container)'
           Replace = 'X1 = $false' }
        @{ Name = "other-agent-folder-not-seen"
           Find = 'W8 = (Test-Path -LiteralPath $agentDirs.W8 -PathType Container)'
           Replace = 'W8 = $false' }
    )
}
