# Mutations of `horde relay pair` (cli/RelayPair.ps1). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-pair-cli.psd1
# Each breaks one promise of the command - the machine never shows its own fingerprint, three tries
# and reject reject the device, only sealed responses come from the relay, a paste for another offer
# cannot end the pairing, a flood is given up, the mailbox is acked, the picture is opened and deleted -
# and test\test-relay-pair-cli.ps1 must fail for every one. Every find string occurs once in the target.
# NOT HERE: the offer's expiry check at the top of the wait (without it the wait never ends, which is a
# timeout and not a failed check; Open and Complete refuse an expired offer by themselves, and the
# suite's expiring offer is held to the reason), and -Label's check before the offer (without it the
# label is refused by Complete only once a phone answers, after the offer's 300 s).
@{
    Target = "cli\RelayPair.ps1"
    Suite  = "test\test-relay-pair-cli.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "machine-prints-its-fingerprint"
           Find = '$null = & $Say "Look at your PHONE: it shows a 12-digit number. Type that number here (or type reject):"'
           Replace = '$null = & $Say ("Type that number here: " + $Device.fingerprint)' }
        @{ Name = "tries-unlimited"
           Find = 'if ($tries -ge $script:HordeRelayPairTries) {'
           Replace = 'if ($false) {' }
        @{ Name = "three-wrong-not-rejected"
           Find = '$null = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $Device.id -Reason "the number typed at the machine did not match the phone''s fingerprint three times" -Now (& $Clock)'
           Replace = '$null = 0' }
        @{ Name = "reject-word-ignored"
           Find = 'if ($line.Trim() -ieq "reject") {'
           Replace = 'if ($false) {' }
        @{ Name = "relay-items-not-only-sealed"
           Find = '-Label $Label -Now (& $Clock) -Sealed'
           Replace = '-Label $Label -Now (& $Clock)' }
        @{ Name = "paste-for-another-offer-taken"
           Find = 'if (-not $m.Success -or $m.Groups[1].Value -cne $Offer.offer) {'
           Replace = 'if ($false) {' }
        @{ Name = "flood-not-capped"
           Find = 'if ($refused -ge $script:HordeRelayPairMaxRefused) {'
           Replace = 'if ($false) {' }
        @{ Name = "mailbox-not-acked"
           Find = 'if ($null -ne $Connection -and $cursor -gt 0) { $null = Confirm-HordeRelayItems'
           Replace = 'if ($false) { $null = Confirm-HordeRelayItems' }
        @{ Name = "picture-not-opened"
           Find = 'if ($null -ne $OpenPicture) { $null = & $OpenPicture $png }'
           Replace = '$null = $OpenPicture' }
        @{ Name = "picture-left-on-interruption"
           Find = 'try { if ([System.IO.File]::Exists($png)) { [System.IO.File]::Delete($png) } } catch { }'
           Replace = '$null = $png' }
        @{ Name = "machine-label-not-passed"
           Find = '$c = Complete-HordeRelayPairing -HordeHome $HordeHome -Response $response -Label $Label -Now $Now'
           Replace = '$c = Complete-HordeRelayPairing -HordeHome $HordeHome -Response $response -Now $Now' }
    )
}
