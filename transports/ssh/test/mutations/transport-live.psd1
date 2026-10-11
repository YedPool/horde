# Mutations of the ssh transport's adapter that only a live sshd can show (the first live mesh link,
# 2026-10-11). Run, from a PowerShell-launched session on the machine with OpenSSH Server installed:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\transport-live.psd1
# transports\ssh\test\test-sshd-local.ps1 must fail for each: its node inside an ssh session must stall.
# It exits 3 when this machine cannot run its sshd, and this spec accepts only 0: a run where the live
# cases were skipped is "not run", never a survivor.
@{
    Target = "transports\ssh\Transport.ps1"
    Suite  = "transports\ssh\test\test-sshd-local.ps1"
    Mutations = @(
        @{ Name = "fd-state-passed-on-live"
           Find = 'if ("$name" -match $script:HordeSshInheritedFdState) {'
           Replace = 'if ($false) {' }
    )
}
