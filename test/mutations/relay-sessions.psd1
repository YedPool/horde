# Mutations of relay/Session.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-sessions.psd1
# Each switches off one rule a session-signed envelope is taken by - the vouch's passkey assertion, its
# sender, the session signature, the binding, the phone key, the seq, end-all, the window, the cap, the
# idle limit - and test\test-relay-sessions.ps1 must fail for every one. Every find string occurs once
# in the target.
@{
    Target = "relay\Session.ps1"
    Suite  = "test\test-relay-sessions.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "vouch-assertion-not-checked"
           Find = 'if (-not $wa.ok) { $fail.reason = ("session-refused: the vouch''s passkey assertion is refused: "'
           Replace = 'if ($false) { $fail.reason = ("session-refused: the vouch''s passkey assertion is refused: "' }
        @{ Name = "another-senders-vouch"
           Find = 'if ($vouch.deviceKeyId -cne $h.from) {'
           Replace = 'if ($false) {' }
        @{ Name = "session-signature-not-checked"
           Find = 'if (-not (Test-HordeRelayEs256Signature -Public $vouch.sessionPublic -Bytes $toVerify -Signature $sig.value -AllowHighS)) {'
           Replace = 'if ($false) {' }
        @{ Name = "another-mailbox"
           Find = 'if ($vouch.horde -cne $p.horde -or $vouch.machine -cne $p.machine -or $vouch.mailbox -cne $p.mailbox) {'
           Replace = 'if ($false) {' }
        @{ Name = "stale-seq-taken"
           Find = 'if ($isNew -and [long]$vouch.seq -le [long]$p.highestSeq) {'
           Replace = 'if ($false) {' }
        @{ Name = "end-all-ignored"
           Find = 'if ([long]$p.endedAt -gt 0 -and'
           Replace = 'if ($false -and' }
        @{ Name = "end-all-trusts-a-fast-phone-clock"
           Find = '(([long]$vouch.notBefore - [long]$p.skewMs) -le [long]$p.endedAt'
           Replace = '([long]$vouch.notBefore -le [long]$p.endedAt' }
        @{ Name = "new-vouch-never-idle"
           Find = 'if ($isNew -and [long]$p.nowMs - [long]$vouch.notBefore -gt [long]$p.idleMs + [long]$p.skewMs) {'
           Replace = 'if ($false) {' }
        @{ Name = "envelope-time-outside-window"
           Find = 'if ($ts -lt [long]$vouch.notBefore -or $ts -gt [long]$vouch.notAfter) {'
           Replace = 'if ($false) {' }
        @{ Name = "pc-clock-past-cap"
           Find = 'if ([long]$p.nowMs -gt [long]$vouch.notAfter -or'
           Replace = 'if ($false -and' }
        @{ Name = "idle-ignored"
           Find = 'if ([long]$p.nowMs - $last -gt [long]$p.idleMs) {'
           Replace = 'if ($false) {' }
        @{ Name = "broken-records-trusted"
           Find = 'if ("" + $p.broken -cne "") {'
           Replace = 'if ($false) {' }
    )
}
