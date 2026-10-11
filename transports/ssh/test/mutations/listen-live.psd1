# Mutations of the hub listener's live half (transports/ssh/Listen.ps1, remote plan R17a): what only a
# running sshd shows. Run locally, one at a time, through the local gate (the suite is machine-bound):
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\listen-live.psd1
# transports\ssh\test\test-listen-local.ps1 must fail for each, except the one declared to survive.
# A process a mutant leaves behind is NOT reliably in the suite's own job: under sshd-outside-the-job an
# sshd escaped it, held the suite's stdout and hung Mutate for 900 s (2026-10-07, round 2). So the
# suite's teardown stops every process carrying its marker, by pid and creation time, and fails.
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
           Replace = ''
           Expect = "survives"
           Reason = "measured 2026-10-07: a session of this non-SYSTEM sshd inherits horde listen's environment, HORDE_HOME included, so attach finds the home without SetEnv; SetEnv is kept so that does not rest on the inheritance (Listen.ps1 header), and test-listen.ps1 holds the line in the configuration (home-not-passed)" }
        @{ Name = "revoked-keys-written-plainly"
           Find = 'if (-not (Test-Path -LiteralPath $files.revoked -PathType Leaf)) { Write-HordeSshLines -Path $files.revoked -Lines @() }'
           Replace = 'if (-not (Test-Path -LiteralPath $files.revoked -PathType Leaf)) { [System.IO.File]::WriteAllText($files.revoked, "") }' }
        @{ Name = "no-memory-cap"
           Find = '[HordeSshNative]::LimitProcessMemory($job, [long]$script:HordeSshListenProcessBytes)'
           Replace = '' }
    )
}
