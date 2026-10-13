# Mutations of channels/progress/Channel.ps1, the progress channel. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-progress.psd1
# Each lets a line that does not hold together reach the phone, an entry reach it twice or out of the
# order it was written, a half-written line be read, a replaced file be sent again or started over, a
# revoked key be sent to, or something come in on a channel that only sends;
# test\test-relay-channel-progress.ps1 must fail for every one. Every find string occurs once.
#
# NOT HERE, and why: the reading of a ts that PowerShell 7 hands over already parsed as a date (the
# suites of the changed files run under Windows PowerShell 5.1, where it is always text); the turn that
# skips opening a file whose length and time have not changed (it only saves a read: with it gone the
# same nothing is sent); and the cap on an envelope's recipients, which the chat channel's twin line
# also leaves to relay/Envelope.ps1's own refusal.
@{
    Target = "channels\progress\Channel.ps1"
    Suite  = "test\test-relay-channel-progress.ps1"
    Mutations = @(
        # --- which file ---
        @{ Name = "default-file-not-under-the-home"
           Find = 'return [System.IO.Path]::Combine($HordeHome, "progress", "changelog.jsonl")'
           Replace = 'return [System.IO.Path]::Combine($HordeHome, "changelog.jsonl")' }
        @{ Name = "progress-file-setting-ignored"
           Find = 'if ($Setting -cne "") { return $Setting }'
           Replace = '' }
        # --- one line, read strictly ---
        @{ Name = "bytes-not-utf8-taken"
           Find = '$strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true'
           Replace = '$strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $false' }
        @{ Name = "blank-line-named-as-bad"
           Find = 'if ($text.Trim() -eq "") { $fail.blank = $true; return $fail }'
           Replace = '' }
        @{ Name = "repeated-member-taken"
           Find = 'if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { $fail.reason = "it has a member more than once"; return $fail }'
           Replace = '' }
        @{ Name = "member-names-compared-loosely"
           Find = '-ArgumentList ([System.StringComparer]::Ordinal)'
           Replace = '-ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)' }
        @{ Name = "missing-member-not-named"
           Find = 'if (-not $has.ContainsKey($need)) { $fail.reason = ("it has no " + $need); return $fail }'
           Replace = '' }
        @{ Name = "version-not-checked"
           Find = '-or $has["v"] -ne 1) { $fail.reason = "it is not version 1"; return $fail }'
           Replace = '-or $false) { $fail.reason = "it is not version 1"; return $fail }' }
        @{ Name = "id-shape-not-checked"
           Find = 'if ($has["id"] -isnot [string] -or $has["id"] -cnotmatch $script:HordeProgressChannelIdPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "time-in-any-spelling-taken"
           Find = 'elseif ($has["ts"] -is [string] -and $has["ts"] -cmatch $script:HordeProgressChannelTimePattern) {'
           Replace = 'elseif ($has["ts"] -is [string]) {' }
        @{ Name = "time-sent-as-it-was-written"
           Find = 'ts = $when.ToString("yyyy-MM-ddTHH:mm:ss.fffZ", [System.Globalization.CultureInfo]::InvariantCulture)'
           Replace = 'ts = [string]$has["ts"]' }
        @{ Name = "blank-title-taken"
           Find = 'if ($has["title"] -isnot [string] -or $has["title"].Trim() -eq "") {'
           Replace = 'if ($has["title"] -isnot [string]) {' }
        @{ Name = "long-title-taken"
           Find = 'if ($has["title"].Length -gt $script:HordeProgressChannelTitleChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "title-with-a-line-break-taken"
           Find = 'if ($has["title"] -cmatch ''\p{Cc}'') {'
           Replace = 'if ($false) {' }
        @{ Name = "long-text-taken"
           Find = 'if ($words.Length -gt $script:HordeProgressChannelTextChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-with-a-control-character-taken"
           Find = 'if ($words -cmatch ''[^\P{Cc}\n\t]'') {'
           Replace = 'if ($false) {' }
        @{ Name = "crlf-in-a-text-refused"
           Find = '$words = $has["text"].Replace("`r`n", "`n")'
           Replace = '$words = $has["text"]' }
        @{ Name = "label-of-any-shape-taken"
           Find = 'if ($has[$name] -isnot [string] -or $has[$name].Length -gt'
           Replace = 'if ($false -or $has[$name].Length -gt' }
        @{ Name = "corrects-of-any-shape-taken"
           Find = 'if ($has["corrects"] -isnot [string] -or $has["corrects"] -cnotmatch $script:HordeProgressChannelIdPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "unknown-kind-sent-as-written"
           Find = '$script:HordeProgressChannelKinds -ccontains $has["kind"]) { $kind = $has["kind"] }'
           Replace = '$true) { $kind = $has["kind"] }' }
        @{ Name = "every-kind-a-note"
           Find = '$script:HordeProgressChannelKinds -ccontains $has["kind"]) { $kind = $has["kind"] }'
           Replace = '$false) { $kind = $has["kind"] }' }
        @{ Name = "secret-sent-to-the-phone"
           Find = 'if ($secret -cne "") {'
           Replace = 'if ($false) {' }
        # --- the file, read ---
        @{ Name = "file-not-shared-with-its-writer"
           Find = '$share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete'
           Replace = '$share = [System.IO.FileShare]::Read' }
        @{ Name = "unfinished-line-read"
           Find = 'if ($end -lt 0) { break }'
           Replace = 'if ($end -lt 0) { $end = $n }' }
        @{ Name = "long-line-read-as-an-entry"
           Find = 'if ($len -gt $script:HordeProgressChannelLineBytes) { [void]$bad.Add("line " + $Line + " " + $tooLong) }'
           Replace = 'if ($false) { }' }
        @{ Name = "line-longer-than-a-look-never-passed"
           Find = 'if (-not $Skip -and ($n - $pos) -gt $script:HordeProgressChannelLineBytes) { $Skip = $true; $pos = $n }'
           Replace = '' }
        @{ Name = "passed-over-line-not-named"
           Find = 'else { $Line++; [void]$bad.Add("line " + $Line + " " + $tooLong); $pos = $end + 1; $Skip = $false }'
           Replace = 'else { $Line++; $pos = $end + 1; $Skip = $false }' }
        @{ Name = "bad-line-not-reported"
           Find = 'elseif (-not $e.blank) { [void]$bad.Add("line " + $Line + ": " + $e.reason) }'
           Replace = '' }
        @{ Name = "backfill-reads-past-what-was-read"
           Find = 'if ($Upto -gt 0) { $count = [long][System.Math]::Min([double]$MaxBytes, [double]($Upto - $Offset)) }'
           Replace = '' }
        @{ Name = "first-look-sends-the-whole-file"
           Find = 'if ($queue.Count -gt $Keep) { [void]$queue.Dequeue() }'
           Replace = '' }
        @{ Name = "repeat-in-the-first-look-sent"
           Find = 'if ($seen.ContainsKey($e.entry.id)) { [void]$bad.Add("line " + $e.line + " repeats the id of line " + $seen[$e.entry.id] + "; the first stands"); continue }'
           Replace = '' }
        @{ Name = "first-look-ids-forgotten"
           Find = '[void]$marks.Add((Get-HordeProgressChannelIdMark -Id $e.entry.id) + ":" + $e.line)'
           Replace = '' }
        @{ Name = "id-mark-of-one-digit"
           Find = '.Substring(0, 16)'
           Replace = '.Substring(0, 1).PadRight(16, "0")' }
        # --- what the phone gets ---
        @{ Name = "quote-not-escaped"
           Find = '[regex]::Replace($Text, ''[^\x20\x21\x23-\x5B\x5D-\x7E]'''
           Replace = '[regex]::Replace($Text, ''[^\x20-\x5B\x5D-\x7E]''' }
        @{ Name = "line-number-not-sent"
           Find = ''',"n":'' + $Line + '',"ts":"'''
           Replace = ''',"n":1,"ts":"''' }
        @{ Name = "missing-label-sent-as-empty"
           Find = 'if ($Entry.$name -cne "") { $t +='
           Replace = 'if ($true) { $t +=' }
        @{ Name = "entries-not-paged"
           Find = 'if ($current.Count -gt 0 -and $used + $add -gt $room) {'
           Replace = 'if ($false) {' }
        @{ Name = "entry-too-large-sent-anyway"
           Find = 'if ($text.Length -gt $room) { [void]$bad.Add('
           Replace = 'if ($false) { [void]$bad.Add(' }
        @{ Name = "backfill-not-marked"
           Find = '$(if ($Backfill) { "true" } else { "false" })'
           Replace = '"false"' }
        @{ Name = "sent-on-another-channel"
           Find = '-Channel "progress" -Kind $Kind -Body'
           Replace = '-Channel "chat" -Kind $Kind -Body' }
        # --- the state, read back strictly ---
        @{ Name = "state-members-not-checked"
           Find = 'if (($names -join ",") -cne "head,line,offset,path,pending,phones,rewind,sent,skip,started,stopped,tail,v") {'
           Replace = 'if ($false) {' }
        @{ Name = "state-repeated-member-taken"
           Find = 'if (@(Find-HordeJsonDuplicateKey -Text $text).Count -gt 0) { return (New-HordeUnknown -Reason ($why + ": a member is repeated")) }'
           Replace = '' }
        @{ Name = "state-version-not-checked"
           Find = 'if (-not ($s.v -is [int] -or $s.v -is [long]) -or $s.v -ne 1) { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "state-flags-not-checked"
           Find = 'if ($s.started -isnot [bool] -or $s.skip -isnot [bool]) {'
           Replace = 'if ($false) {' }
        @{ Name = "state-path-not-checked"
           Find = 'if ($s.path -isnot [string] -or $s.path.Length -gt 1024) {'
           Replace = 'if ($false) {' }
        @{ Name = "state-offset-not-checked"
           Find = 'if (-not (& $whole $s.offset) -or -not (& $whole $s.line)) {'
           Replace = 'if ($false) {' }
        @{ Name = "state-marks-not-checked"
           Find = 'if (-not (& $hash $s.head) -or -not (& $hash $s.tail)) {'
           Replace = 'if ($false) {' }
        @{ Name = "state-phones-not-checked"
           Find = 'if (-not (& $keyIds $s.phones)) {'
           Replace = 'if ($false) {' }
        @{ Name = "state-pending-not-checked"
           Find = 'if ($k -isnot [string] -or $k.Length -gt 160) {'
           Replace = 'if ($false) {' }
        @{ Name = "state-sent-not-checked"
           Find = 'if ($m -isnot [string] -or $m -cnotmatch ''\A[0-9a-f]{16}:[1-9][0-9]{0,15}\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "state-stop-not-checked"
           Find = 'if ($s.stopped -isnot [string] -or @("", "file-replaced") -cnotcontains $s.stopped) {'
           Replace = 'if ($false) {' }
        @{ Name = "state-rewind-not-checked"
           Find = 'if ($rwNames -cne "head,line,offset,phones,skip,started,tail" -or $rw.started -isnot [bool]'
           Replace = 'if ($rwNames -cne "head,line,offset,phones,skip,started,tail" -and $false -or $rw.started -isnot [bool]' }
        @{ Name = "state-bytes-not-checked"
           Find = 'Assert-HordeAsciiBytes -Bytes $bytes -What ("the progress state " + $path);'
           Replace = '' }
        @{ Name = "state-not-written"
           Find = 'try { if ((ConvertTo-HordeProgressChannelStateText -State $d) -cne $was) { Write-HordeProgressChannelState -HordeHome $homeDir -State $d } }'
           Replace = 'try { }' }
        # --- recorded, then put; never to a revoked key ---
        @{ Name = "pending-not-kept"
           Find = '$State.pending = @(@($State.pending) + @($Keys))'
           Replace = '$null = $Keys' }
        @{ Name = "rewind-not-marked"
           Find = 'if (@($State.pending).Count -eq 0) { $State.rewind = $Before }'
           Replace = '' }
        @{ Name = "pending-put-from-elsewhere"
           Find = 'if ($rec.value.sent) {'
           Replace = 'if ($false) {' }
        @{ Name = "pending-put-to-a-revoked-key"
           Find = 'if (@($to | Where-Object { $trusted -cnotcontains $_ }).Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "revoked-lines-not-read-again"
           Find = '$d.started = $d.rewind.started; $d.offset = $d.rewind.offset; $d.line = $d.rewind.line; $d.skip = $d.rewind.skip'
           Replace = '$d.started = $d.rewind.started' }
        # --- the file that is not the one that was followed ---
        @{ Name = "another-file-by-the-setting-followed"
           Find = 'if ($State.path -cne "" -and $State.path -cne $Path) {'
           Replace = 'if ($false) {' }
        @{ Name = "gone-file-is-nothing-yet"
           Find = 'if ($State.offset -gt 0) { $answer.broken = "is gone, after "'
           Replace = 'if ($false) { $answer.broken = "is gone, after "' }
        @{ Name = "cut-file-not-noticed"
           Find = 'if ($marks.length -lt $State.offset) { $answer.broken = "was cut short: "'
           Replace = 'if ($false) { $answer.broken = "was cut short: "' }
        @{ Name = "replaced-file-not-noticed-by-its-start"
           Find = 'if ($marks.head -cne $State.head) {'
           Replace = 'if ($false) {' }
        @{ Name = "rewritten-file-not-noticed"
           Find = 'if ($marks.tail -cne $State.tail) {'
           Replace = 'if ($false) {' }
        @{ Name = "marks-not-kept"
           Find = '$d.head = $marksNow.head; $d.tail = $marksNow.tail; $d.path = $path'
           Replace = '$d.path = $path' }
        @{ Name = "stopped-channel-reads-on"
           Find = 'if ($file.broken -cne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "stop-said-every-turn"
           Find = 'if ($mine.said.ContainsKey("stopped")) { return [pscustomobject]@{ lines = @(); failed = $false } }'
           Replace = '' }
        @{ Name = "stop-kept-in-the-runs-memory-only"
           Find = '$d.stopped = "file-replaced"'
           Replace = '$null = "file-replaced"' }
        @{ Name = "phone-not-told-of-the-stop"
           Find = '-Bodies @((New-HordeProgressChannelNotice -Context $Context -Code "file-replaced")) -Phones $all'
           Replace = '-Bodies @() -Phones $all' }
        @{ Name = "phone-not-told-it-goes-on"
           Find = '[void]$notices.Add((New-HordeProgressChannelNotice -Context $Context -Code "following"))'
           Replace = '' }
        # --- the turn ---
        @{ Name = "rate-ignored"
           Find = 'if ([long]$set.sendIntervalMs -gt 0 -and'
           Replace = 'if ($false -and' }
        @{ Name = "new-key-gets-no-backfill"
           Find = 'if ($fresh.Count -gt 0 -and $d.offset -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "new-keys-backfill-sent-to-every-key"
           Find = '[void]$batches.Add([pscustomobject]@{ phones = $fresh; backfill = $true; entries = @($tail.entries) })'
           Replace = '[void]$batches.Add([pscustomobject]@{ phones = $all; backfill = $true; entries = @($tail.entries) })' }
        @{ Name = "repeated-id-sent"
           Find = 'if ($sentMarks.ContainsKey($mark) -and $sentMarks[$mark] -ne $e.line) {'
           Replace = 'if ($false) {' }
        @{ Name = "line-read-again-taken-for-a-repeat"
           Find = 'if ($sentMarks.ContainsKey($mark) -and $sentMarks[$mark] -ne $e.line) {'
           Replace = 'if ($sentMarks.ContainsKey($mark)) {' }
        @{ Name = "sent-ids-not-remembered"
           Find = 'if (-not $sentMarks.ContainsKey($mark)) { $sentMarks[$mark] = $e.line; [void]$marks.Add($mark + ":" + $e.line) }'
           Replace = '' }
        @{ Name = "left-out-lines-not-said"
           Find = 'if ($n -le $script:HordeProgressChannelSaidLines) { [void]$lines.Add("left out of the progress sent: " + $b) }'
           Replace = '' }
        @{ Name = "phone-not-told-how-many-were-left-out"
           Find = '-Code "lines-skipped" -Count $bad.Count))'
           Replace = '-Code "lines-skipped"))' }
        @{ Name = "phone-not-told-any-were-left-out"
           Find = 'if ($fail -ceq "" -and $bad.Count -gt 0) {'
           Replace = 'if ($false) {' }
        # --- machine to phone only ---
        @{ Name = "channel-takes-entries-in"
           Find = '-Name "progress" -Kinds @() -Senders "founder"'
           Replace = '-Name "progress" -Kinds @("entries") -Senders "founder"' }
        @{ Name = "accept-takes-what-it-is-handed"
           Find = 'outcome = "refused"; reason = "the progress channel takes nothing in'
           Replace = 'outcome = "done"; reason = "the progress channel takes nothing in' }
        # --- the phone's mailbox holds the last keepEnvelopes (2026-10-13)
        @{ Name = "progress-envelopes-pile-up-in-the-phones-mailbox"
           Find = '-Mailbox $mailbox -KeepFrom (Get-HordeRelayChannelKeepFrom -Key $key -Keep $keep)'
           Replace = '-Mailbox $mailbox' }
        @{ Name = "keep-envelopes-setting-not-read"
           Find = '$mine["keepEnvelopes"] = [long]$set.keepEnvelopes'
           Replace = '' }
        @{ Name = "keep-envelopes-setting-not-used"
           Find = 'if ($Mine.ContainsKey("keepEnvelopes")) { $keep = [long]$Mine["keepEnvelopes"] }'
           Replace = '' }
    )
}
