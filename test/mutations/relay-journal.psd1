# Mutations of relay/Journal.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-journal.psd1
# Each switches off one rule an envelope is judged fresh by - verified first, the sequence only up, the
# nonce, the window, the clock, a marker that must be there and be this version's, damage refused
# rather than read past, one writer, the write-once record, the sweep that never takes a held file, the
# verdict's own shape - and test\test-relay-journal.ps1 must fail for every one. Every find string occurs
# once in the target. Each replacement keeps the code running, so a mutant is caught by a check that
# fails, never by a crash (tools\Mutate.ps1 counts [FAIL] only).
@{
    Target = "relay\Journal.ps1"
    Suite  = "test\test-relay-journal.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "unverified-envelope-judged"
           Find = '$verified = Test-HordeRelayEnvelope -Envelope $Envelope -Senders $Senders'
           Replace = '$verified = [pscustomobject]@{ ok = $true; reason = ""; value = [pscustomobject]@{ envelope = $Envelope; header = $Envelope.header } }' }
        @{ Name = "seq-at-or-below-last-taken"
           Find = 'if ($last -ge 0 -and $seq -le $last) {'
           Replace = 'if ($false) {' }
        @{ Name = "nonce-not-compared"
           Find = 'if ($same.meta.nonce -ceq $Header.nonce) {'
           Replace = 'if ($true) {' }
        @{ Name = "damaged-same-seq-read-as-replay"
           Find = 'if (-not $same.ok) {'
           Replace = 'if (-not $same.ok) { return (New-HordeRelayJournalVerdict -Key $key -Fresh $false -Why "a replay" -GapBefore 0 -Direction $Direction) }; if ($false) {' }
        @{ Name = "seq-window-off"
           Find = 'if (($seq - $base) -gt [long]$ctx.settings.seqWindow) {'
           Replace = 'if ($false) {' }
        @{ Name = "new-stream-exempt-from-window"
           Find = '$base = $(if ($last -ge 0) { $last } else { [long]0 })'
           Replace = '$base = $(if ($last -ge 0) { $last } else { $seq })' }
        @{ Name = "future-ts-taken"
           Find = 'if ($ts -gt ($nowMs + $skewMs)) {'
           Replace = 'if ($false) {' }
        @{ Name = "ts-before-journal-taken"
           Find = 'if ($ts -lt ($ctx.createdAt - $skewMs)) {'
           Replace = 'if ($false) {' }
        @{ Name = "clock-not-checked-on-receive"
           Find = '-CheckClock $true)'
           Replace = '-CheckClock $false)' }
        @{ Name = "no-marker-read-as-empty"
           Find = 'if (-not $m.ok) { $fail.reason = $m.reason; return $fail }'
           Replace = '' }
        @{ Name = "marker-of-any-version"
           Find = 'if ($m.text -cnotmatch $script:HordeRelayJournalMarkerPattern) {'
           Replace = 'if ($m.text -cnotmatch ''\A\{.*"createdAt":([0-9]+)\}\z'') {' }
        @{ Name = "lost-marker-made-again"
           Find = 'if ($present -ccontains "in" -or $present -ccontains "out") {'
           Replace = 'if ($false) {' }
        @{ Name = "damaged-last-record-read-past"
           Find = 'if (-not $top.ok) {'
           Replace = 'if ($false) {' }
        @{ Name = "stray-file-ignored"
           Find = 'if ($nm -cnotmatch $script:HordeRelayJournalRecordPattern) { return'
           Replace = 'if ($nm -cnotmatch $script:HordeRelayJournalRecordPattern) { continue; return' }
        @{ Name = "link-in-stream-read-as-a-folder"
           Find = 'if (($e.attrs -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "folder-in-stream-ignored"
           Find = 'if (($e.attrs -band [System.IO.FileAttributes]::Directory) -ne 0) { return'
           Replace = 'if (($e.attrs -band [System.IO.FileAttributes]::Directory) -ne 0) { continue; return' }
        @{ Name = "seq-past-2-53-taken"
           Find = 'if ($s -gt $limit) {'
           Replace = 'if ($false) {' }
        @{ Name = "record-length-unchecked"
           Find = 'if (($r.text.Length - $cut - 1) -ne [long]$g[10]) {'
           Replace = 'if ($false) {' }
        @{ Name = "record-place-unchecked"
           Find = 'if ($g[1] -cne $Direction -or $g[3] -cne $From -or $g[4] -cne $Channel -or $mSeq -ne $Seq) {'
           Replace = 'if ($false) {' }
        @{ Name = "stream-lock-not-taken"
           Find = '$lock = Enter-HordeRelayJournalLock -Dir $dir -WaitMs $ctx.settings.lockWaitMs'
           Replace = '$lock = [pscustomobject]@{ ok = $true; held = (New-Object System.IO.MemoryStream); reason = "" }' }
        @{ Name = "leftovers-not-swept"
           Find = 'Remove-HordeRelayJournalLeftovers -Temps $st.temps'
           Replace = '$null = $st.temps' }
        @{ Name = "leftover-deleted-by-name"
           Find = '$claim = New-Object System.IO.FileStream -ArgumentList $t, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::None), 1, ([System.IO.FileOptions]::DeleteOnClose)'
           Replace = '[System.IO.File]::Delete($t); $claim = New-Object System.IO.MemoryStream' }
        @{ Name = "temporary-file-kept-on-failure"
           Find = 'if ($moved -cne "moved" -and $moved -cne "unconfirmed") { try { [System.IO.File]::Delete($tmp) } catch { } }'
           Replace = '' }
        @{ Name = "unconfirmed-called-fresh"
           Find = 'if ($moved -ceq "moved") {'
           Replace = 'if ($moved -ceq "moved" -or $moved -ceq "unconfirmed") {' }
        @{ Name = "fresh-not-a-boolean"
           Find = 'fresh = $Fresh; why'
           Replace = 'fresh = [int]$Fresh; why' }
        @{ Name = "verdict-about-another-key"
           Find = '$key = Get-HordeRelayReplayKey -Header $Header'
           Replace = '$key = (Get-HordeRelayReplayKey -Header $Header) + "x"' }
        @{ Name = "gap-not-reported"
           Find = '$gap = [long][System.Math]::Max([long]0, $seq - $base - 1)'
           Replace = '$gap = [long]0' }
        @{ Name = "next-seq-reuses-the-last"
           Find = 'return (New-HordeKnown -Value ([long]($st.last + 1))'
           Replace = 'return (New-HordeKnown -Value ([long]($st.last))' }
    )
}
