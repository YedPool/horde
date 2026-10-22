# Mutations of core/AnalystSession.ps1 (T-0341: a start that brings no session is failed and retried, bounded).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\analyst-session.psd1
# test\test-analyst-tend.ps1 must fail for every one.
@{
    Target = "core\AnalystSession.ps1"
    Suite  = "test\test-analyst-tend.ps1"
    Mutations = @(
        @{ Name = "bound-ignored"
           Find = 'elseif ($utcNow -ge $since.AddMinutes([int]$Policy.startBoundMinutes))'
           Replace = 'elseif ($false)' }
        @{ Name = "attempts-unbounded"
           Find = '-lt [long]$Policy.startMaxAttempts)'
           Replace = '-lt [long]100000)' }
        @{ Name = "older-state-not-counted-as-a-start"
           Find = '[Math]::Max([long]1, [long]$State.startAttempts) -lt'
           Replace = '[long]$State.startAttempts -lt' }
        @{ Name = "unasked-spawn-log-is-a-failure"
           Find = 'if ($SpawnLogged -eq $false -and'
           Replace = 'if ($SpawnLogged -ne $true -and' }
        @{ Name = "spawn-log-grace-removed"
           Find = '$since.AddSeconds($script:HordeAnalystSpawnLogGraceSeconds)'
           Replace = '$since.AddSeconds(0)' }
        @{ Name = "attempts-not-written"
           Find = 'startReason = "" + $State.startReason; startAttempts = [long]$State.startAttempts'
           Replace = 'startReason = "" + $State.startReason' }
    )
}
