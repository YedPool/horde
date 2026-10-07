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
        # --- review of PR #103, H3 to H6 ---
        @{ Name = "no-forcecommand"
           Find = '("ForceCommand " + $ForceCommand)'
           Replace = '("# ForceCommand " + $ForceCommand)' }
        @{ Name = "watchdog-by-path-lookup"
           Find = '$wsi = New-Object System.Diagnostics.ProcessStartInfo($script:HordeSshdPowerShellExe, '
           Replace = '$wsi = New-Object System.Diagnostics.ProcessStartInfo("powershell.exe", ' }
        @{ Name = "folder-print-blind"
           Find = '$lines = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable unread | Sort-Object FullName | ForEach-Object { $_.FullName + " " + $_.Length + " " + $_.LastWriteTimeUtc.Ticks })'
           Replace = '$lines = @()' }
        @{ Name = "key-print-without-hash"
           Find = '$_.FullName + " " + $_.Length + " " + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash'
           Replace = '$_.FullName + " " + $_.Length' }
        @{ Name = "stale-age-ignored"
           Find = 'if ($d.CreationTimeUtc -ge $cut) { continue }'
           Replace = '' }
        @{ Name = "stale-name-unchecked"
           Find = 'if ($d.Name -cnotmatch $script:HordeSshdRootPattern) { continue }'
           Replace = 'if ($d.Name -cnotlike "horde-sshd-*") { continue }' }
        @{ Name = "stale-never-swept"
           Find = 'Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue'
           Replace = '' }
    )
}
