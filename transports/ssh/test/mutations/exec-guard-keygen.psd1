# Mutations of the exec guard's second sanctioned start (transports/ssh/test/ExecGuard.ps1, remote plan
# R17b). Run: powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\exec-guard-keygen.psd1
# transports\ssh\test\test-enroll.ps1 must fail for each: a guard that admits a second start anywhere,
# a second ssh-keygen start, or an argv with a caller's flag has lost the coordinator's limits.
@{
    Target = "transports\ssh\test\ExecGuard.ps1"
    Suite  = "transports\ssh\test\test-enroll.ps1"
    Mutations = @(
        @{ Name = "keygen-start-anywhere"
           Find = 'elseif ($isProc -and $fn.Name -ceq $script:HordeSshGuardKeygenFunction -and $p.name -ceq $script:HordeSshGuardKeygenFile) {'
           Replace = 'elseif ($isProc) {' }
        @{ Name = "keygen-started-twice"
           Find = 'if ($keygenStarts.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "keygen-argv-unpinned"
           Find = 'elseif ($keygenArgvs[0].Extent.Text -cne $script:HordeSshGuardKeygenArgv) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "keygen-argv-reassignable"
           Find = 'if ($keygenArgvs.Count -ne 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "keygen-setup-any-program"
           Find = 'elseif ($isPsi -and $m.Extent.Text -ceq $script:HordeSshGuardKeygenSetup -and'
           Replace = 'elseif ($isPsi -and' }
    )
}
