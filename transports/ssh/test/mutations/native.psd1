# Mutations of the ssh transport's native job object. Run: powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\native.psd1
# Each changes the C# in transports\ssh\Native.ps1; transports\ssh\test\test-ssh.ps1 must fail for every one,
# by its pinned SHA-256 (ExecGuard) and, for the flag, by a killed driver's ssh.exe surviving.
@{
    Target = "transports\ssh\Native.ps1"
    Suite  = "transports\ssh\test\test-ssh.ps1"
    Mutations = @(
        @{ Name = "kill-on-close-not-set"
           Find = 'info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;'
           Replace = 'info.BasicLimitInformation.LimitFlags = 0;' }
        @{ Name = "source-changed-unpinned"
           Find = '// Put a running process into the job. Throws if Windows refuses.'
           Replace = '// Put a running process into the job.' }
    )
}
