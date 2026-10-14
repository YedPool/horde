# Mutations of the cards channel (channels/cards/Channel.ps1): one card per lane and one for the Thrall,
# sent whole, only the latest kept. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-cards.psd1
# test\test-relay-channel-cards.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\cards\Channel.ps1"
    Suite  = "test\test-relay-channel-cards.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "old-snapshots-pile-up-in-the-phones-mailbox"
           Find = '-KeepFrom ([long]$p.seq)'
           Replace = '-KeepFrom 0' }
        @{ Name = "the-same-snapshot-is-sent-again"
           Find = 'if ($sentAs -ceq $mine.sent) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-secret-in-a-status-line-is-sent"
           Find = 'if ((Find-HordeSecretKind -Text $Text) -cne "") { [void]$Refused.Add($Field); return $script:HordeCardsChannelSecretWords }'
           Replace = '' }
        @{ Name = "a-lane-with-no-status-file-gets-no-card"
           Find = '        $c = New-HordeCardsChannelLaneCard -Folder $f'
           Replace = '        if (-not [System.IO.File]::Exists((Join-Path $f "status.txt"))) { continue }; $c = New-HordeCardsChannelLaneCard -Folder $f' }
        @{ Name = "an-unreadable-status-file-is-read-anyway"
           Find = 'if ($info.Length -gt $script:HordeCardsChannelStatusBytes) { $out.form = "unreadable"'
           Replace = 'if ($false) { $out.form = "unreadable"' }
        @{ Name = "another-form-is-called-standard"
           Find = '$out.form = $(if ($standard) { "standard" } else { "other" })'
           Replace = '$out.form = "standard"' }
        @{ Name = "another-form-names-no-orc"
           Find = '$m = [regex]::Match("$v", ''\(Orc ([A-Z][A-Z0-9]{0,3})\)'')'
           Replace = '$m = [regex]::Match("", ''x'')' }
        @{ Name = "handed-does-not-move-a-task"
           Find = '"handed" { if ($e.to -cne "") { $t.lane = $e.to }; $t.state = "opened" }'
           Replace = '"handed" { $t.state = "opened" }' }
        @{ Name = "ledger-read-in-file-order"
           Find = 'foreach ($e in @($events | Sort-Object -Property at, i)) {'
           Replace = 'foreach ($e in @($events)) {' }
        @{ Name = "done-this-week-counts-every-week"
           Find = '-and $t.doneAt -ge $since) { $c.doneWeek++ }'
           Replace = ') { $c.doneWeek++ }' }
        @{ Name = "dropped-counts-as-open"
           Find = '$script:HordeCardsChannelClosed = @("done", "verified", "dropped", "superseded")'
           Replace = '$script:HordeCardsChannelClosed = @("done", "verified")' }
        @{ Name = "a-closed-run-is-counted"
           Find = 'if ($null -ne $closed -and "$($closed.Value)" -cne "") { continue }'
           Replace = '' }
        @{ Name = "a-quiet-session-is-counted"
           Find = 'if (-not $info.Exists -or $info.LastWriteTimeUtc -lt $recent) { continue }'
           Replace = 'if (-not $info.Exists) { continue }' }
        @{ Name = "waiting-on-the-founder-not-seen"
           Find = "elseif (`$c.waitingOn -imatch 'founder' -and"
           Replace = "elseif (`$c.waitingOn -imatch 'nobody-at-all' -and" }
        @{ Name = "blocked-words-keep-their-yes"
           Find = "`$card.blockedText = [regex]::Replace("
           Replace = "`$card.blockedText = `$b; `$null = [regex]::Replace(" }
        @{ Name = "the-map-is-not-sent"
           Find = '$areasText = ConvertTo-HordeCardsChannelValueText @($areas.areas)'
           Replace = '$areasText = "[]"' }
        @{ Name = "no-lanes-folder-sends-an-empty-snapshot"
           Find = 'if (-not [System.IO.Directory]::Exists($paths.lanes)) { return (& $once "lanes"'
           Replace = 'if ($false) { return (& $once "lanes"' }
        @{ Name = "a-relative-default-is-not-under-the-home"
           Find = '[System.IO.Path]::Combine($HordeHome, "progress", $Leaf)'
           Replace = '[System.IO.Path]::Combine("progress", $Leaf)' }
    )
}
