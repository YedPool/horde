# Mutations of `horde relay pair` (cli/RelayPair.ps1). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-pair-cli.psd1
# Each breaks one promise of the command - the machine never shows its own fingerprint, three tries
# and reject reject the device, only sealed responses come from the relay, a paste for another offer
# cannot end the pairing, a flood is given up, the mailbox is acked, the picture is opened and deleted -
# and test\test-relay-pair-cli.ps1 must fail for every one. Every find string occurs once in the target.
# NOT HERE: the offer's expiry check at the top of the wait (without it the wait never ends, which is a
# timeout and not a failed check; Open and Complete refuse an expired offer by themselves, and the
# suite's expiring offer is held to the reason), and -Label's check before the offer (without it the
# label is refused by Complete only once a phone answers, after the offer's 600 s).
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
           Find = '$rv = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $Device.id -Reason "the number typed at the machine did not match the phone''s fingerprint three times" -Now (& $Clock)'
           Replace = '$rv = [pscustomobject]@{ state = "known"; reason = "" }' }
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
        @{ Name = "old-pictures-not-swept"
           Find = '    Remove-HordeRelayPairPictures -Dir $PictureDir'
           Replace = '    $null = $PictureDir' }
        @{ Name = "young-pictures-swept"
           Find = '[System.IO.File]::GetLastWriteTimeUtc($f) -lt $limit'
           Replace = '[System.IO.File]::GetLastWriteTimeUtc($f) -lt [datetime]::UtcNow' }
        @{ Name = "other-files-swept"
           Find = 'if ([System.IO.Path]::GetFileName($f) -cnotmatch ''\Ahorde-pair-[0-9a-f]{32}\.png\z'') { continue }'
           Replace = '$null = $f' }
        @{ Name = "revoke-failure-on-reject-unchecked"
           Find = '$rv = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $Device.id -Reason "rejected at the machine during horde relay pair" -Now (& $Clock)'
           Replace = '$null = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $Device.id -Reason "rejected at the machine during horde relay pair" -Now (& $Clock); $rv = [pscustomobject]@{ state = "known"; reason = "" }' }
        @{ Name = "revoke-failure-on-three-wrong-unchecked"
           Find = '$rv = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $Device.id -Reason "the number typed at the machine did not match the phone''s fingerprint three times" -Now (& $Clock)'
           Replace = '$null = Revoke-HordeRelayTrust -HordeHome $HordeHome -Subject "device" -Id $Device.id -Reason "x" -Now (& $Clock); $rv = [pscustomobject]@{ state = "known"; reason = "" }' }
        @{ Name = "fast-failing-relay-not-paced"
           Find = '$retryAt = (ConvertTo-HordeRelayRecordMs -Time (& $Clock)) + (Get-HordeRelayPairRetryMs -Failures $failures -Answer $w)'
           Replace = '$retryAt = 0' }
        # --- the wait while the relay refuses (the founder's first live use, 2026-10-11)
        @{ Name = "retry-not-backed-off"
           Find = '[double]$script:HordeRelayPairRetryFirstMs * $Failures)'
           Replace = '[double]$script:HordeRelayPairRetryFirstMs)' }
        @{ Name = "retry-not-capped"
           Find = '$script:HordeRelayPairRetryMostMs = 15000'
           Replace = '$script:HordeRelayPairRetryMostMs = 150000' }
        @{ Name = "retry-after-ignored"
           Find = 'if ($null -ne $p -and [long]$p.Value -gt $ms) { $ms = [long]$p.Value }'
           Replace = '$null = $p' }
        @{ Name = "retry-after-shortens-the-wait"
           Find = 'if ($null -ne $p -and [long]$p.Value -gt $ms) { $ms = [long]$p.Value }'
           Replace = 'if ($null -ne $p) { $ms = [long]$p.Value }' }
        @{ Name = "backoff-not-reset-by-a-watch-that-works"
           Find = '                    $failures = 0'
           Replace = '' }
        @{ Name = "refusal-said-in-the-relay-words"
           Find = 'if ($null -ne $p -and $script:HordeRelayPairRefusedStatuses -contains $p.Value) {'
           Replace = 'if ($false) {' }
        @{ Name = "failure-said-on-every-try"
           Find = 'if ($words -cne $lastDown) { $null = & $Say $words }'
           Replace = '$null = & $Say $words' }
        @{ Name = "interrupted-offer-not-voided"
           Find = 'if (-not $ended) { $null = Close-HordeRelayPairingOffer -HordeHome $HordeHome -Offer $offer.offer }'
           Replace = '$null = $ended' }
        @{ Name = "trust-list-shows-fingerprint"
           Find = '"''  key " + $d.keyId'
           Replace = '"''  key " + $d.keyId + "  fingerprint " + $d.fingerprint' }
        @{ Name = "machine-label-not-passed"
           Find = '$c = Complete-HordeRelayPairing -HordeHome $HordeHome -Response $response -Label $Label -Now $Now'
           Replace = '$c = Complete-HordeRelayPairing -HordeHome $HordeHome -Response $response -Now $Now' }
        @{ Name = "offer-names-no-machine"
           Find = '-Now (& $Clock) -Label (ConvertTo-HordeDeviceName -Text "$env:COMPUTERNAME")'
           Replace = '-Now (& $Clock)' }
        # --- the offer's life and its countdown (issue #283): each boundary from both sides, the default
        @{ Name = "ttl-30-refused"
           Find = 'if ($TtlSeconds -lt $l.minTtlSeconds -or'
           Replace = 'if ($TtlSeconds -le $l.minTtlSeconds -or' }
        @{ Name = "ttl-29-taken"
           Find = 'if ($TtlSeconds -lt $l.minTtlSeconds -or'
           Replace = 'if ($TtlSeconds -lt ($l.minTtlSeconds - 1) -or' }
        @{ Name = "ttl-900-refused"
           Find = '$TtlSeconds -gt $l.maxTtlSeconds) {'
           Replace = '$TtlSeconds -ge $l.maxTtlSeconds) {' }
        @{ Name = "ttl-901-taken"
           Find = '$TtlSeconds -gt $l.maxTtlSeconds) {'
           Replace = '$TtlSeconds -gt ($l.maxTtlSeconds + 1)) {' }
        @{ Name = "ttl-not-checked-by-the-command"
           Find = '    if ($ttlWhy -cne "") { $done.reason = $ttlWhy; return $done }'
           Replace = '' }
        @{ Name = "ttl-default-five-minutes"
           Find = '$script:HordeRelayPairDefaultTtlSeconds = 600'
           Replace = '$script:HordeRelayPairDefaultTtlSeconds = 300' }
        @{ Name = "offer-line-without-its-length"
           Find = ' + " (" + (Format-HordeRelayPairSpan -Ms ([long]$TtlSeconds * 1000)) + ").")'
           Replace = ' + ".")' }
        @{ Name = "countdown-never-said"
           Find = 'if ($mark -ge 0 -and $step -lt $mark -and $leftMs -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "countdown-said-every-look"
           Find = 'if ($mark -ge 0 -and $step -lt $mark -and $leftMs -gt 0) {'
           Replace = 'if ($mark -ge 0 -and $leftMs -gt 0) {' }
        @{ Name = "countdown-said-at-expiry"
           Find = 'if ($mark -ge 0 -and $step -lt $mark -and $leftMs -gt 0) {'
           Replace = 'if ($mark -ge 0 -and $step -lt $mark) {' }
        @{ Name = "countdown-in-minutes-to-the-end"
           Find = 'if ($LeftMs -gt 60000) {'
           Replace = 'if ($LeftMs -gt 0) {' }
        @{ Name = "countdown-late-while-the-relay-waits"
           Find = '[System.Math]::Min([System.Math]::Min([double]($retryAt - $nowMs), [double]$script:HordeRelayPairWatchMs)'
           Replace = '[System.Math]::Min([System.Math]::Min([double]($retryAt - $nowMs), [double]$script:HordeRelayPairRetryMostMs)' }
    )
}
