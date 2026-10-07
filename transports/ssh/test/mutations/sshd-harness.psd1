# Mutations of the throwaway sshd's teardown (transports/ssh/test/Sshd.ps1, remote plan R16). Run, from a
# PowerShell-launched session on the machine with OpenSSH Server installed:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\sshd-harness.psd1
# transports\ssh\test\test-sshd-local.ps1 must fail for each: a harness that leaves a process behind is
# the leak the suite's teardown lines exist to catch. No mutant here leaves sshd itself out of the job:
# that one would leak a live sshd past the run, where a job close could not end it. Exit 3 (no live sshd here) is not a pass.
@{
    Target = "transports\ssh\test\Sshd.ps1"
    Suite  = "transports\ssh\test\test-sshd-local.ps1"
    Mutations = @(
        @{ Name = "job-not-ended"
           Find = '$null = [HordeTestJob]::Terminate($Sshd.job)'
           Replace = '' }
        @{ Name = "watchdog-left-out-of-the-job"
           Find = '[HordeTestJob]::Assign($job, $w.Handle)'
           Replace = '' }
    )
}
