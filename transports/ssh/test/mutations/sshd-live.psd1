# Mutations of the live sshd suite's own fixtures (transports/ssh/test/test-sshd-local.ps1, remote plan
# R16; review of PR #103, H1 and H2). Run, from a PowerShell-launched session on the machine with
# OpenSSH Server installed:
#   powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\sshd-live.psd1
# The suite must fail for each. Exit 3 (no live sshd here) is not a pass.
@{
    Target = "transports\ssh\test\test-sshd-local.ps1"
    Suite  = "transports\ssh\test\test-sshd-local.ps1"
    Mutations = @(
        # H2, issue #100: under Windows sshd a forced command reading stdin through a .NET Console stream
        # never gets the session's data; only $input does. The frame round trip must fail without it.
        @{ Name = "echo-reads-console-stdin"
           Find = 'foreach (`$l in `$input) { [Console]::Out.Write(`$l + [char]10); [Console]::Out.Flush() }'
           Replace = '`$r = New-Object System.IO.StreamReader([Console]::OpenStandardInput()); while (`$null -ne (`$l = `$r.ReadLine())) { [Console]::Out.Write(`$l + [char]10); [Console]::Out.Flush() }' }
        # H1: an unquoted expiry-time is malformed, and sshd refuses the key as it refuses an expired one.
        # Only the date-to-come control can tell the two apart.
        @{ Name = "expiry-option-malformed"
           Find = 'return (''expiry-time="'' + $Day + ''" '')'
           Replace = 'return (''expiry-time='' + $Day + '' '')' }
    )
}
