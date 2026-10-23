# Mutations of core/IdleState.ps1, the one answer to "idle or night?". Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\idle-state.psd1
@{
    Target = "core\IdleState.ps1"
    Suite  = "test\test-idle.ps1"
    Mutations = @(
        @{ Name = "night-start-hour-excluded"
           Find = 'return ($Hour -ge $Start -or $Hour -lt $End)'
           Replace = 'return ($Hour -gt $Start -or $Hour -lt $End)' }
        @{ Name = "night-end-hour-included"
           Find = 'return ($Hour -ge $Start -or $Hour -lt $End)'
           Replace = 'return ($Hour -ge $Start -or $Hour -le $End)' }
        @{ Name = "night-no-wrap"
           Find = 'return ($Hour -ge $Start -or $Hour -lt $End)'
           Replace = 'return ($Hour -ge $Start -and $Hour -lt $End)' }
        @{ Name = "equal-start-end-is-all-night"
           Find = 'if ($Start -eq $End) { return $false }'
           Replace = 'if ($Start -eq $End) { return $true }' }
        @{ Name = "idle-threshold-exclusive"
           Find = 'elseif ($known -and $secs -ge $Config.idleSeconds) { $why = "idle" }'
           Replace = 'elseif ($known -and $secs -gt $Config.idleSeconds) { $why = "idle" }' }
        @{ Name = "unknown-counts-as-idle"
           Find = '$why = "unknown"'
           Replace = '$why = "idle"' }
        @{ Name = "night-needs-the-reader"
           Find = '    if ($night) { $why = "night" }'
           Replace = '    if ($night -and $known) { $why = "night" }' }
        @{ Name = "reader-failure-not-caught"
           Find = 'try { $r = & $Reader } catch {'
           Replace = 'try { $r = & $Reader } catch { throw; ' }
        @{ Name = "session-zero-read-as-known"
           Find = 'if (!ProcessIdToSessionId((uint)System.Diagnostics.Process.GetCurrentProcess().Id, out session) || session == 0) return -2;'
           Replace = 'ProcessIdToSessionId((uint)System.Diagnostics.Process.GetCurrentProcess().Id, out session);' 
           Expect = "survives"
           Reason = "the suite runs in an interactive session, where session 0 is never the case; a real S4U run is the only place it shows, and that is not a thing a fixture can make" }
        @{ Name = "settings-refusal-falls-back"
           Find = 'if ($s.state -ceq "refused") { return [pscustomobject]@{ ok = $false;'
           Replace = 'if ($false) { return [pscustomobject]@{ ok = $false;' }
    )
}