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
           Find = ' passes its check again; " + $d.why + ".") -Who "the warchief" }'
           Replace = ' passes its check again; " + $d.why + ".") -Who "the warchief" | ForEach-Object { $_.ok = $true; $_ } }' }
        # Each is told "back" only if it was told "down".
        @{ Name = "warchief-told-back-though-never-told-down"
           Find = '$w = $(if ($s.alerted) { Send-HordeRelayWatchWord'
           Replace = '$w = $(if ($true) { Send-HordeRelayWatchWord' }
        @{ Name = "founder-told-back-though-never-told-down"
           Find = 'if ($s.notified) { [void]$lines.Add('
           Replace = 'if ($true) { [void]$lines.Add(' }
        # A founder told "down" whose warchief never took it is still owed "back": no blip reset.
        @{ Name = "founder-told-down-forgotten-as-a-blip"
           Find = 'if (-not $s.alerted -and -not $s.notified) {'
           Replace = 'if (-not $s.alerted) {' }
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
