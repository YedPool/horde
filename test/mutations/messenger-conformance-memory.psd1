# Mutations of the memory messenger, against the conformance suite (review of #102, finding 1: a
# conformance mutation spec for each messenger, as the transports have one). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\messenger-conformance-memory.psd1
@{
    Target = "messengers\memory\Messenger.ps1"
    Suite  = "test\test-messenger-conformance.ps1"
    Mutations = @(
        @{ Name = "repost-overwrites-record"
           Find = 'if (-not $script:HordeMemoryMessengerStore.ContainsKey($id)) {'
           Replace = 'if ($true) {' }
        @{ Name = "body-not-kept"
           Find = '$script:HordeMemoryMessengerStore[$id] = @{ message = $Message;'
           Replace = '$script:HordeMemoryMessengerStore[$id] = @{ message = [pscustomobject]@{ messageId = $Message.messageId; body = "" };' }
    )
}
