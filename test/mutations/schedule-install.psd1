# Mutations of Invoke-HordeMetricsSchedule in core/MetricsCollect.ps1.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\schedule-install.psd1
@{
    Target = "core\MetricsCollect.ps1"
    Suite  = "test\test-metrics-schedule.ps1"
    Mutations = @(
        @{ Name = "installed-with-metrics-off"
           Find = 'if ($gate.state -ne "known" -or $gate.value.level -cne "usage") { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "install-not-checked"
           Find = 'if ($st.state -ne "known" -or -not $st.value.marked) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "name-rule-skipped"
           Find = '    Assert-HordeJobName -Name $TaskName -Folder $Folder'
           Replace = '' }
    )
}
