# Mutations of the counts file and the heartbeat's counts in core/WakeFiles.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-blind-files.psd1
# test\test-wake-blind.ps1 must fail for every one.
@{
    Target = "core\WakeFiles.ps1"
    Suite  = "test\test-wake-blind.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-counts-file-is-not-the-one-the-run-reads"
           Find = '-Stem "counts" -Extension ".json"'
           Replace = '-Stem "counts" -Extension ".txt"' }
        @{ Name = "the-heartbeat-carries-no-counts"
           Find = '$beat["counts"] = $row'
           Replace = '' }
        @{ Name = "the-heartbeat-reader-drops-the-counts"
           Find = '"tickSeconds", "self", "counts")) {'
           Replace = '"tickSeconds", "self")) {' }
        @{ Name = "a-counts-write-failure-kills-the-heartbeat"
           Find = 'catch { $countsError = '
           Replace = 'catch { throw $_; $countsError = ' }
        @{ Name = "a-counts-write-failure-is-not-returned"
           Find = 'if ($null -ne $countsError) { return $countsError }'
           Replace = '' }
    )
}
