# Mutations of the machine's adapter for the hosted relay, where it carries a sender's trim
# (relays/cloudflare/Relay.ps1, A SENDER TRIMS ITS OWN STREAM; 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec relays\cloudflare\test\mutations\cloudflare-relay-trim.psd1
# relays\cloudflare\test\test-cloudflare-worker.ps1 must fail for every one (it drives the adapter
# against a local dev of the Worker). Every find string occurs once. The adapter's other promises are
# cloudflare-relay.psd1's.
@{
    Target = "relays\cloudflare\Relay.ps1"
    Suite  = "relays\cloudflare\test\test-cloudflare-worker.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "keep-from-never-leaves-the-machine"
           Find = 'if ($KeepFrom -gt 0) { $path = $path + "?keepFrom=" + $KeepFrom }'
           Replace = '' }
        @{ Name = "relays-count-not-read-back"
           Find = 'if ($KeepFrom -gt 0 -and $null -ne $trimmed) { $out | Add-Member -NotePropertyName trimmed -NotePropertyValue $trimmed.Value }'
           Replace = '' }
        @{ Name = "relay-registered-with-no-trimming-put"
           Find = 'return (Send-HordeCloudflareRelayPut -State $State -Mailbox $Mailbox -Key $Key -Text $Text -KeepFrom $KeepFrom)'
           Replace = 'return (Send-HordeCloudflareRelayPut -State $State -Mailbox $Mailbox -Key $Key -Text $Text)' }
    )
}
