# Mutations of channels/Port.ps1's part in the unlocked session. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-sessions-port.psd1
# Each switches off one thing the port does for sessions - record a batch's vouches first, hold an
# envelope whose new vouch was not recorded, restart the idle clock - and test\test-relay-sessions.ps1
# must fail for every one. Every find string occurs once in the target.
@{
    Target = "channels\Port.ps1"
    Suite  = "test\test-relay-sessions.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "vouches-not-recorded-first"
           Find = 'if ($s.alg -cne "session" -or $null -eq $s.vouch) { continue }'
           Replace = 'continue' }
        @{ Name = "unrecorded-vouch-taken"
           Find = 'if ($p.envelope.sig.alg -ceq "session" -and $null -ne $gate.verified -and $null -ne $gate.verified.PSObject.Properties["newVouch"] -and $gate.verified.newVouch) {'
           Replace = 'if ($false) {' }
        @{ Name = "idle-clock-never-restarted"
           Find = '$why = Register-HordeRelaySessionSeen -HordeHome $Context.hordeHome -VouchId $p.envelope.sig.vouchId -NowMs $nowMs'
           Replace = '$why = ""' }
    )
}
