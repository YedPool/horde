# Mutations of relay/Envelope.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-envelope.psd1
# Each switches off one rule an envelope is opened by - one spelling, version 1, the caps, the trusted
# sender and its proof, the recipient's own key, the journal's verdict - and test\test-relay-envelope.ps1
# must fail for every one. Every find string occurs once in the target.
@{
    Target = "relay\Envelope.ps1"
    Suite  = "test\test-relay-envelope.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "canonical-form-not-required"
           Find = 'if ($canonical -cne $Text) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-version-read"
           Find = 'if ($e.header.v -ne 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-cap-off"
           Find = 'if ($Text.Length -gt $limits.textChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "non-ascii-parsed"
           Find = 'if ($Text -cnotmatch ''\A[\x20-\x7E]*\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "schema-findings-ignored"
           Find = 'if ($findings.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "seq-not-a-whole-number-read"
           Find = 'if (-not (Test-HordeRelayInteger -Value $h.seq)) {'
           Replace = 'if ($false) {' }
        @{ Name = "integer-range-unchecked"
           Find = 'return [bool]($Value -ge 0 -and $Value -le (Get-HordeRelayEnvelopeLimits).maxInteger)'
           Replace = 'return $true' }
        @{ Name = "recipient-named-twice-read"
           Find = 'if (@($to | Sort-Object -Unique).Count -ne $to.Count) {'
           Replace = 'if ($false) {' }
        @{ Name = "recipients-in-any-order"
           Find = 'if ($recs[$i].kid -cne $to[$i]) {'
           Replace = 'if ($false) {' }
        @{ Name = "es256-members-not-checked"
           Find = 'if (($sNames -join ",") -cne "alg,value") {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-sender-trusted"
           Find = 'if (-not $Senders.ContainsKey($h.from)) {'
           Replace = 'if ($false) {' }
        @{ Name = "sender-table-key-id-not-checked"
           Find = 'if ($sender.keyId -cne $h.from) {'
           Replace = 'if ($false) {' }
        @{ Name = "passkey-sender-takes-es256"
           Find = 'if ($sender.proof -cne "es256") {'
           Replace = 'if ($false) {' }
        @{ Name = "machine-sender-takes-passkey"
           Find = 'if ($sender.proof -cne "webauthn") {'
           Replace = 'if ($false) {' }
        @{ Name = "es256-not-verified"
           Find = 'if (-not (Test-HordeRelayEs256Signature -Public $sender.public -Bytes $signed -Signature $env.sig.value)) {'
           Replace = 'if ($false) {' }
        @{ Name = "passkey-challenge-not-this-envelope"
           Find = '-Challenge (Get-HordeRelaySha256 -Bytes $signed)'
           Replace = '-Challenge (Get-HordeRelaySha256 -Bytes $env.sig.clientDataJson)' }
        @{ Name = "replay-state-ignored"
           Find = 'if ($null -eq $state -or $state.Value -cne "known") {'
           Replace = 'if ($null -eq $state) {' }
        @{ Name = "replay-verdict-for-any-envelope"
           Find = 'if ($null -eq $vKey -or "" + $vKey.Value -cne $rk) {'
           Replace = 'if ($false) {' }
        @{ Name = "replay-seen-accepted"
           Find = 'if ($null -eq $vFresh -or $vFresh.Value -ne $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "recipient-key-not-matched-to-kid"
           Find = 'if ((Get-HordeRelayKeyId -Public (ConvertTo-HordeRelayP256Public -Key $key)) -cne $mine.kid) {'
           Replace = 'if ($false) {' }
        @{ Name = "body-cap-off-at-sender"
           Find = 'if ($Body.Length -gt $limits.bodyBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "nonce-reused"
           Find = 'nonce = (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelayRandomBytes -Count 12))'
           Replace = 'nonce = ("0" * 24)' }
        @{ Name = "aad-domain-changed"
           Find = '"aad") { return "horde-relay/envelope/v1 aad`n" }'
           Replace = '"aad") { return "horde-relay/envelope/v2 aad`n" }' }
        @{ Name = "signed-domain-changed"
           Find = '"signed") { return "horde-relay/envelope/v1 signed`n" }'
           Replace = '"signed") { return "horde-relay/envelope/v1 signed " }' }
        @{ Name = "header-left-out-of-the-sender-aad"
           Find = '$aad = Get-HordeRelayAsciiBytes -Text ((Get-HordeRelayEnvelopeDomain -Part "aad") + $headerText)'
           Replace = '$aad = Get-HordeRelayAsciiBytes -Text (Get-HordeRelayEnvelopeDomain -Part "aad")' }
    )
}
