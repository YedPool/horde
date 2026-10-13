# Mutations of the local relay's trim of a sender's stream (relays/local/Relay.ps1, A SENDER TRIMS ITS OWN
# STREAM, 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\local\test\mutations\relay-local-trim.psd1
# Each breaks one rule of it, and test\test-relay-conformance.ps1 must fail for every one. Every find
# string occurs exactly once. The relay's other promises are test\mutations\relay-local.psd1's; this
# spec lives in the relay's own folder, where naming its functions needs no entry in its allowlist.
#
# NOT HERE, and why: the trim's place AFTER the item is written, and the top marker's place BEFORE the
# deletes (only a kill between two steps shows either, and no suite here can place one there - as
# relay-local.psd1 says of the floor before an ack's deletes).
@{
    Target = "relays\local\Relay.ps1"
    Suite  = "test\test-relay-conformance.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "trim-takes-every-stream"
           Find = 'if ($m.Success -and $m.Groups[1].Value -ceq $stream -and [long]$m.Groups[2].Value -lt $KeepFrom) { [void]$older.Add($e) }'
           Replace = 'if ($m.Success -and [long]$m.Groups[2].Value -lt $KeepFrom) { [void]$older.Add($e) }' }
        @{ Name = "trim-takes-the-seq-it-was-told-to-keep-from"
           Find = '-ceq $stream -and [long]$m.Groups[2].Value -lt $KeepFrom)'
           Replace = '-ceq $stream -and [long]$m.Groups[2].Value -le $KeepFrom)' }
        @{ Name = "trim-keeps-everything"
           Find = 'if ($KeepFrom -gt 0) { $trimmed = Remove-HordeLocalRelayOlder -Dir $dir -Key $Key -KeepFrom $KeepFrom }'
           Replace = '' }
        @{ Name = "trim-of-the-newest-item-reuses-its-number"
           Find = 'if (@($older | Where-Object { $_.seq -eq $now.head }).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "top-marker-not-read"
           Find = '$head = [Math]::Max($floor, $top)'
           Replace = '$head = $floor' }
        @{ Name = "relay-takes-a-trim-from-past-its-own-seq"
           Find = 'if (-not $named.Success -or $KeepFrom -gt [long]$named.Groups[2].Value) { return'
           Replace = 'if (-not $named.Success) { return' }
        @{ Name = "relay-takes-a-trim-with-a-key-that-names-no-stream"
           Find = 'if (-not $named.Success -or $KeepFrom -gt [long]$named.Groups[2].Value) {'
           Replace = 'if ($named.Success -and $KeepFrom -gt [long]$named.Groups[2].Value) {' }
        @{ Name = "duplicate-put-does-not-say-it-is-one"
           Find = 'duplicate = ($held.Count -gt 0); trimmed = [long]$trimmed'
           Replace = 'duplicate = $false; trimmed = [long]$trimmed' }
    )
}
