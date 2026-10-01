# Mutations of core/PaneSessions.ps1, the pane-sessions reader. Run one spec at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pane-sessions.psd1
# The spec sets HORDE_SKIP_REALITY=1 for its own runs (see test\mutations\hostport.psd1).
@{
    Target = "core\PaneSessions.ps1"
    Suite  = "test\test-projection.ps1"
    # Fixtures only, and stop at the first failed check: a caught mutant needs nothing more.
    # Only the sections that kill these mutants (test	est-projection.ps1 SECTIONS): the pane and its pane-sessions guard and judge, and the shared-reader scan.
    # Every mutant is still run; the whole list must come out as expected (PR #31, 2026-10-01).
    Environment = @{ HORDE_SKIP_REALITY = "1"; HORDE_FAIL_FAST = "1"; HORDE_SECTIONS = "pane,judge,pane-guard,holes,writes" }
    # With the reality check skipped the suite passes with exit 3 (test\test-projection.ps1).
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "schema-breaking-file-accepted"
           Find = 'if ($problems.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "missing-directory-is-empty"
           Find = '[void]$gaps.Add("there is no pane-sessions directory at " + $Dir)'
           Replace = '$null = 0' }
        @{ Name = "write-time-not-the-files"
           Find = '$written = [System.IO.File]::GetLastWriteTimeUtc($f.FullName)'
           Replace = '$written = [datetime]::UtcNow' }
        @{ Name = "plain-read-share"
           Find = '$j = (Read-HordeSharedText -Path $f.FullName) | ConvertFrom-Json'
           Replace = '$j = ([System.IO.File]::ReadAllText($f.FullName)) | ConvertFrom-Json' }
    )
}
