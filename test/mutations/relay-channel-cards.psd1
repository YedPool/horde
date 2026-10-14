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
           Find = 'if ((Find-HordeSecretKind -Text $whole) -cne "") { [void]$Refused.Add($Field); return $script:HordeCardsChannelSecretWords }'
           Replace = '' }
        @{ Name = "a-lane-with-no-status-file-gets-no-card"
           Find = '        $c = New-HordeCardsChannelLaneCard -Folder $f'
           Replace = '        if (-not [System.IO.File]::Exists((Join-Path $f "status.txt"))) { continue }; $c = New-HordeCardsChannelLaneCard -Folder $f' }
        @{ Name = "an-unreadable-status-file-is-read-anyway"
           Find = 'if ($info.Length -gt $script:HordeCardsChannelStatusBytes) { $out.form = "unreadable"'
           Replace = 'if ($false) { $out.form = "unreadable"' }
        @{ Name = "another-form-is-called-standard"
           Find = 'if (@($judged.problems).Count -eq 0) {'
           Replace = 'if ($true) {' }
        @{ Name = "the-broken-rules-not-sent"
           Find = '; $card.problems = $s.reason }'
           Replace = ' }' }
        @{ Name = "a-standard-record-read-loosely"
           Find = 'foreach ($k in @($judged.fields.Keys)) { $keys[$k] = $judged.fields[$k] }'
           Replace = 'foreach ($k in @()) { }' }
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
           Find = '(@($areaTexts | Select-Object -First $AreasKept) -join ",")'
           Replace = '""' }
        @{ Name = "the-map-does-not-fill-the-room-left"
           Find = 'while ($areasKept -lt $areaTexts.Count) {'
           Replace = 'while ($false) {' }
        @{ Name = "the-map-fills-past-the-budget"
           Find = 'if ($more.body.Length -gt $Budget) { break }'
           Replace = '' }
        @{ Name = "no-lanes-folder-sends-an-empty-snapshot"
           Find = 'if (-not [System.IO.Directory]::Exists($paths.lanes)) { return (& $once "lanes"'
           Replace = 'if ($false) { return (& $once "lanes"' }
        @{ Name = "a-relative-default-is-not-under-the-home"
           Find = '[System.IO.Path]::Combine($HordeHome, "progress", $Leaf)'
           Replace = '[System.IO.Path]::Combine("progress", $Leaf)' }
        @{ Name = "the-refusal-looks-at-the-cut-text"
           Find = '$whole = Get-HordeCardsChannelClean $Text'
           Replace = '$whole = Get-HordeCardsChannelPlain $Text' }
        @{ Name = "a-lane-field-is-cut-before-the-refusal"
           Find = '$get = { param($name) if ($k.ContainsKey($name)) { return (Get-HordeCardsChannelClean $k[$name]) }; return "" }'
           Replace = '$get = { param($name) if ($k.ContainsKey($name)) { return (Get-HordeCardsChannelPlain $k[$name]) }; return "" }' }
        @{ Name = "the-thrall-now-is-cut-before-the-refusal"
           Find = '$now = $(if ($s.keys.ContainsKey("doing")) { $s.keys["doing"] }'
           Replace = '$now = $(if ($s.keys.ContainsKey("doing")) { Get-HordeCardsChannelPlain $s.keys["doing"] }' }
        # Which folder is retired is fleet/StatusPanel.ps1's rule (Test-HordeFleetStatusRetired); its
        # both-files and neither-file mutants are in test\mutations\fleet-status.psd1.
        @{ Name = "a-retired-lane-gets-a-card"
           Find = '$folders = @($folders | Where-Object { -not (Test-HordeFleetStatusRetired -Path $_) })'
           Replace = '' }
        @{ Name = "why-a-card-has-its-own-id-not-sent"
           Find = '$c.idNote = Protect-HordeCardsChannelField'
           Replace = '$c.note = Protect-HordeCardsChannelField' }
        @{ Name = "two-cards-share-one-id"
           Find = 'if ($taken.ContainsKey($c.lane)) {'
           Replace = 'if ($false) {' }
        @{ Name = "every-unnamed-lane-is-lane"
           Find = '$fallback = "lane-" + $Place'
           Replace = '$fallback = "lane"' }
        @{ Name = "the-map-is-never-capped"
           Find = '-le [long]($Budget / 4)) {'
           Replace = '-le [long]::MaxValue) {' }
        @{ Name = "with-no-card-left-the-map-is-not-cut"
           Find = 'elseif ($areasKept -gt 0) { $areasKept-- }'
           Replace = 'elseif ($false) { }' }
        @{ Name = "cards-left-out-not-counted"
           Find = '$left = $cardTexts.Count - $cardsKept'
           Replace = '$left = 0' }
        @{ Name = "one-bad-run-wipes-the-census"
           Find = '} catch { $answer.skipped++ }'
           Replace = '} catch { throw }' }
        @{ Name = "a-run-json-list-is-read-as-a-run"
           Find = 'if ($m -isnot [System.Management.Automation.PSCustomObject]) { $answer.skipped++; continue }'
           Replace = '' }
        @{ Name = "the-whole-events-file-is-read"
           Find = '$from = [long][System.Math]::Max(0, $stream.Length - $script:HordeCardsChannelTailBytes)'
           Replace = '$from = [long]0' }
        @{ Name = "the-tail-of-a-line-is-read-as-a-line"
           Find = '$start = $(if ($from -gt 0) { 1 } else { 0 })'
           Replace = '$start = 0' }
        @{ Name = "a-ledger-object-is-read-as-text"
           Find = 'if ($null -ne $field[$name] -and $field[$name] -isnot [string]) { $typed = $false }'
           Replace = '' }
        @{ Name = "a-one-item-list-is-unrolled-to-text"
           Find = '$field[$name] = $null; if ($null -ne $pp) { $field[$name] = $pp.Value }'
           Replace = '$field[$name] = $(if ($null -ne $pp) { $pp.Value } else { $null })' }
    )
}
