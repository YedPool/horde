# Mutations of the hub listener's live half (transports/ssh/Listen.ps1, remote plan R17a): what only a
# running sshd shows. Run locally, one at a time, through the local gate (the suite is machine-bound):
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\listen-live.psd1
# transports\ssh\test\test-listen-local.ps1 must fail for each. Every process a mutant leaves behind is
# in the suite's own kill-on-close job, so nothing outlives the run.
@{
    Target = "transports\ssh\Listen.ps1"
    Suite  = "transports\ssh\test\test-listen-local.ps1"
    PassCodes = @(0)
    Mutations = @(
        @{ Name = "sshd-outside-the-job"
           Find = 'try { [HordeSshNative]::Assign($Job, $started.Handle) }'
           Replace = 'try { $null = $Job }' }
        @{ Name = "listener-not-stopped"
           Find = 'try { $Listener.job.Dispose() } catch { }'
           Replace = '' }
        @{ Name = "session-without-home"
           Find = '(''SetEnv "HORDE_HOME='' + $HordeHome.Replace(''\'', ''/'') + ''"''),'
           Replace = '' }
    )
}
