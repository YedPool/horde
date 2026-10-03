# Mutations of core/MetricsReport.ps1, caught end to end through the real horde command.
# Run: powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\summarize.psd1
# The suite lives here because its fixtures are this harness's transcripts (CONTRIBUTING 14).
@{
    Target = "core\MetricsReport.ps1"
    Suite  = "agents\claude-code\test\test-transcript.ps1"
    Mutations = @(
        @{ Name = "window-ignored"
           Find = '$acc = New-HordeMetricsAccumulator -PriceTable $PriceTable -From $From -To $To'
           Replace = '$acc = New-HordeMetricsAccumulator -PriceTable $PriceTable' }
        @{ Name = "written-whatever-the-gate-says"
           Find = '        if ($decision.write) {'
           Replace = '        if ($true) {' }
        @{ Name = "window-recorded"
           Find = '-FirstEventAt $mv.worker.firstEventAt -Windowed:$windowed'
           Replace = '-FirstEventAt $mv.worker.firstEventAt -Windowed:$false' }
    )
}
