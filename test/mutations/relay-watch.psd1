# Mutations of core/RelayWatch.ps1 (the hosted relay watch, PR 307).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-watch.psd1
# Each breaks one rule the review of PR 307 asked for; test\test-relay-watch.ps1 must fail for every one.
@{
    Target = "core\RelayWatch.ps1"
    Suite  = "test\test-relay-watch.ps1"
    Mutations = @(
        # Told only when taken: a failed tell leaves the outage untold.
        @{ Name = "alerted-before-the-tell-is-taken"
           Find = 'if ($w.ok) { $s.alerted = $true }'
           Replace = '$s.alerted = $true' }
        # Two healthy checks in a row before it is called back.
        @{ Name = "recovered-after-one-healthy-check"
           Find = 'if ($s.healthy -lt 2) { return'
           Replace = 'if ($s.healthy -lt 1) { return' }
        @{ Name = "healthy-run-not-reset-by-a-failure"
           Find = '    $s.healthy = 0'
           Replace = '' }
        # A recovery the warchief did not take stays owed.
        @{ Name = "recovery-cleared-though-not-taken"
           Find = ' passes its check again; " + $d.why + ".") -Who "the warchief"'
           Replace = ' passes its check again; " + $d.why + ".") -Who "the warchief"; $w = [pscustomobject]@{ ok = $true; line = $w.line }' }
        # One blip tells nobody.
        @{ Name = "down-on-first-failure"
           Find = '$s.failures -ge [int]$Policy.relayFailuresBeforeAlert) {'
           Replace = '$s.failures -ge 1) {' }
        # An unreadable state file is told, not a silent stop.
        @{ Name = "unreadable-state-silent"
           Find = 'if ($utcNow -ge $last.AddHours(24)) {'
           Replace = 'if ($false) {' }
        # PR 275's client-id rule: a byte order mark in the client id is a fault.
        @{ Name = "client-id-bom-accepted"
           Find = 'if ($Value.Contains([string][char]0xFEFF)) { return "the client_id carries a byte order mark (U+FEFF)" }'
           Replace = '' }
    )
}
