# Mutations of the supervisor's state file (core/AnalystSession.ps1), T-0391 slice 7: the key generations that give a later event a new
# notice id are written, read back, and an older file without them is still read.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-tell-taken-session.psd1
@{
    Target = "core\AnalystSession.ps1"
    Suite  = "test\test-analyst-tell-taken.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "analyst-state-generations-not-written"
           Find = 'tellGen = @($State.tellGen)'
           Replace = 'tellGenLost = @()' }
        @{ Name = "analyst-state-generations-not-read"
           Find = 'if ($null -ne $doc.PSObject.Properties["tellGen"])'
           Replace = 'if ($false)' }
        @{ Name = "analyst-state-without-generations-refused"
           Find = '} else { [string[]]@() })'
           Replace = '} else { throw "no generations" })' }
    )
}
