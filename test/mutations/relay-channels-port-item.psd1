# Mutations of channels/Port.ps1: what an Accept is handed of the envelope's own header (the time its
# sender signed, which the chat channel hands back to the phone as when the founder sent a line). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channels-port-item.psd1
# A spec of its own because the suite that reads the item is the chat channel's, not the port's
# (test\test-relay-channels.ps1 has no channel that looks at it). The find string occurs once.
@{
    Target = "channels\Port.ps1"
    Suite  = "test\test-relay-channel-chat.ps1"
    Mutations = @(
        @{ Name = "item-without-the-signed-time"
           Find = 'evidence = $Record.evidence; ts = [long]$r.value.header.ts; body'
           Replace = 'evidence = $Record.evidence; body' }
        @{ Name = "item-time-is-the-machines-clock"
           Find = 'ts = [long]$r.value.header.ts; body'
           Replace = 'ts = [long]([datetime]::UtcNow - (New-Object datetime -ArgumentList 1970, 1, 1, 0, 0, 0, ([System.DateTimeKind]::Utc))).TotalMilliseconds; body' }
    )
}
