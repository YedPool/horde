# Mutations of channels/Port.ps1, the one path in and out for every relay channel (relay PR 6). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channels-port.psd1
# Each breaks one step of the path; test\test-relay-channels.ps1 must fail for every one.
@{
    Target = "channels\Port.ps1"
    Suite  = "test\test-relay-channels.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- step 2: the batch in the senders' own order ---
        @{ Name = "batch-left-in-the-relays-order"
           Find = '$ordered = @($parsed | Sort-Object @{ Expression = { $_.envelope.header.from } }, @{ Expression = { [long]$_.envelope.header.seq } })'
           Replace = '$ordered = @($parsed)' }
        # --- step 3: what the journal never sees ---
        @{ Name = "founder-channel-takes-machines"
           Find = '    if ($Channel.senders -ceq "horde") { return $built }'
           Replace = '    return $built' }
        @{ Name = "address-left-to-the-journal"
           Find = '    if ($forMe.Count -eq 0) { return [pscustomobject]@{ why = "it is not addressed to any agreement key of this machine";'
           Replace = '    if ($false) { return [pscustomobject]@{ why = "it is not addressed to any agreement key of this machine";' }
        @{ Name = "kind-not-asked"
           Find = '    if (@($ch.kinds) -cnotcontains $h.kind) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "unknown-trust-store-refuses-for-good"
           Find = 'return [pscustomobject]@{ why = ("the trust store cannot be read: " + $senders.reason); transient = $true;'
           Replace = 'return [pscustomobject]@{ why = ("the trust store cannot be read: " + $senders.reason); transient = $false;' }
        # --- step 5: the ack stops before what is held ---
        @{ Name = "ack-past-a-held-item"
           Find = '        if ($settled.ContainsKey([long]$it.seq)) { $through = [long]$it.seq } else { $stop = $true }'
           Replace = '        $through = [long]$it.seq' }
        # --- step 6: a retry stays unfinished ---
        @{ Name = "retry-marked-done"
           Find = '            if ($outcome.outcome -ceq "retry") { [void]$retry.Add($line); continue }'
           Replace = '' }
        # --- the path out: recorded before it is put ---
        @{ Name = "sent-without-the-journal"
           Find = '        $rec = Register-HordeRelayJournalSent -Text $text -HordeHome $Context.hordeHome -Now $Now'
           Replace = '        $rec = New-HordeKnown -Value ([pscustomobject]@{ fresh = $true; key = (Get-HordeRelayReplayKey -Header (Read-HordeRelayEnvelope -Text $text).value.header) })' }
        # --- review of 48bc492 ---
        @{ Name = "senders-read-for-every-item"
           Find = '    if ($null -ne $Cache -and $Cache.ContainsKey("all")) { $all = $Cache["all"] }'
           Replace = '    if ($false) { }' }
        @{ Name = "reopen-forgets-the-cursor"
           Find = '    if ($made.value.mailbox -ceq $Context.mailbox) { $made.value.cursor = $Context.cursor; $made.value.acked = $Context.acked }'
           Replace = '' }
        @{ Name = "reopen-forgets-the-channels"
           Find = '    $made.value.state = $Context.state'
           Replace = '' }
        @{ Name = "oversized-envelope-journaled"
           Find = '        if ($text.Length -gt $most) {'
           Replace = '        if ($false) {' }
        @{ Name = "failed-tick-not-reported"
           Find = '                if ($null -ne $got[0].PSObject.Properties["failed"] -and $got[0].failed -eq $true) { $failed = $true }'
           Replace = '' }
        @{ Name = "tick-asks-for-a-turn-and-is-not-heard"
           Find = 'if ($null -ne $ask -and $ask.Value -is [int] -and $ask.Value -gt 0 -and ($again -eq 0 -or $ask.Value -lt $again)) { $again = [int]$ask.Value }'
           Replace = 'if ($false) { $again = [int]$ask.Value }' }
        # --- T-0467: a channel that fails on a record is counted, and refused for good at the cap ---
        @{ Name = "failure-cap-never-reached"
           Find = '                if ($times -lt $script:HordeRelayChannelFailureCap) {'
           Replace = '                if ($true) {' }
        @{ Name = "failure-cap-one-too-many"
           Find = '                if ($times -lt $script:HordeRelayChannelFailureCap) {'
           Replace = '                if ($times -le $script:HordeRelayChannelFailureCap) {' }
        @{ Name = "failure-count-always-one"
           Find = '                $times = [int]$counted.value.failures'
           Replace = '                $times = 1' }
        @{ Name = "throw-is-not-the-channels-fault"
           Find = 'reason = ("the channel " + $Channel.name + " failed: " + $_.Exception.Message); channelFault = $true;'
           Replace = 'reason = ("the channel " + $Channel.name + " failed: " + $_.Exception.Message); channelFault = $false;' }
        @{ Name = "bad-answer-is-not-the-channels-fault"
           Find = 'refused or retry"); channelFault = $true;'
           Replace = 'refused or retry"); channelFault = $false;' }
        @{ Name = "asked-retry-counted"
           Find = 'reason = $why; channelFault = $false;'
           Replace = 'reason = $why; channelFault = $true;' }
        @{ Name = "trust-store-retry-counted"
           Find = 'if (-not $o.ok) { return [pscustomobject]@{ outcome = $o.outcome; reason = $o.reason; channelFault = $false;'
           Replace = 'if (-not $o.ok) { return [pscustomobject]@{ outcome = $o.outcome; reason = $o.reason; channelFault = $true;' }
        @{ Name = "capped-record-left-a-retry"
           Find = '$outcome = [pscustomobject]@{ outcome = "refused"; reason = ("the channel " + $name + " failed on this record "'
           Replace = '$outcome = [pscustomobject]@{ outcome = "retry"; reason = ("the channel " + $name + " failed on this record "' }
        @{ Name = "capped-refusal-forgets-the-last-error"
           Find = ' times and is not asked again; the last: " + $outcome.detail)'
           Replace = ' times and is not asked again; the last: ")' }
        @{ Name = "notice-carries-the-message"
           Find = '" + $u.key + ". Last error type: " + $err)'
           Replace = '" + $u.key + ". Last error type: " + $err + " " + $capped.detail)' }
        @{ Name = "capped-refusal-tells-nobody"
           Find = '                $told = Submit-HordeSystemNotice -HordeHome $Context.hordeHome -Now $Now -Text ("A record of the relay'
           Replace = '                $told = [pscustomobject]@{ outcome = "sent"; reason = "" }; $null = ("A record of the relay' }
        @{ Name = "capped-refusal-forgets-the-channel"
           Find = '                $outcome = [pscustomobject]@{ outcome = "refused"; reason = ("the channel " + $name + " failed'
           Replace = '                $outcome = [pscustomobject]@{ outcome = "refused"; reason = ("the channel " + "x" + " failed' }
    )
}
