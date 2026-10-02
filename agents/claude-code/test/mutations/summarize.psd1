# Mutations of core/MetricsReport.ps1, caught end to end through the real horde command.
# Run: powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\summarize.psd1
# The suite lives here because its fixtures are this harness's transcripts (CONTRIBUTING 14).
@{
    Target = "core\MetricsReport.ps1"
    Suite  = "agents\claude-code\test\test-transcript.ps1"
    Mutations = @(
        @{ Name = "window-ignored"
           Find = 'if ($windowed) { $records = Select-HordeRecordsInWindow -Records $records -From $From -To $To }'
           Replace = '' }
        @{ Name = "written-whatever-the-gate-says"
           Find = '        if ($decision.write) {'
           Replace = '        if ($true) {' }
        @{ Name = "window-recorded"
           Find = '-StoreRoots $roots -Windowed:$windowed'
           Replace = '-StoreRoots $roots -Windowed:$false' }
        @{ Name = "store-roots-not-collected"
           Find = 'foreach ($a in (Get-HordeTranscriptAdapters)) { $roots += @(& $a.storeRoots) }'
           Replace = '' }
    )
}
