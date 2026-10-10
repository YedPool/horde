# Mutations of relay/Journal.ps1's done marks, resumption and evidence (relay PR 6). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-journal-resume.psd1
# Each breaks one promise the channels rely on; test\test-relay-channels.ps1 must fail for every one.
@{
    Target = "relay\Journal.ps1"
    Suite  = "test\test-relay-channels.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "done-mark-ignored"
           Find = '            if ($st.dones.ContainsKey($seqText)) { continue }'
           Replace = '' }
        @{ Name = "done-mark-beside-nothing-believed"
           Find = '        if (-not $seqs.ContainsKey($d)) { return [pscustomobject]@{ ok = $false; reason = ("the stream " + $where + " holds a done mark for seq "'
           Replace = '        if ($false) { return [pscustomobject]@{ ok = $false; reason = ("the stream " + $where + " holds a done mark for seq "' }
        @{ Name = "resumed-verdict-not-fresh"
           Find = '[pscustomobject]@{ key = $r.meta.key; fresh = $true; why = ""; gapBefore = [long]0; direction = "in"; resumed = $true }'
           Replace = '[pscustomobject]@{ key = $r.meta.key; fresh = $false; why = ""; gapBefore = [long]0; direction = "in"; resumed = $true }' }
        @{ Name = "evidence-of-the-envelope-alone"
           Find = 'return (New-HordeKnown -Value (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $r.whole))) -ObservedAt'
           Replace = 'return (New-HordeKnown -Value (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $r.envelope))) -ObservedAt' }
        @{ Name = "unfinished-evidence-of-the-envelope-alone"
           Find = 'evidence = (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $r.whole))); verdict = $verdict'
           Replace = 'evidence = (ConvertTo-HordeRelayHex -Bytes (Get-HordeRelaySha256 -Bytes (Get-HordeRelayAsciiBytes -Text $r.envelope))); verdict = $verdict' }
        @{ Name = "done-mark-without-its-record"
           Find = '    if (-not $r.ok) { return (New-HordeUnknown -Reason ($r.reason + "; a done mark is only ever written beside its record")) }'
           Replace = '' }
        @{ Name = "second-done-mark-not-already"
           Find = 'already = ($moved -ceq "exists") }) -ObservedAt'
           Replace = 'already = $false }) -ObservedAt' }
        @{ Name = "stray-sender-folder-skipped"
           Find = 'if (($e.attrs -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or ($e.attrs -band [System.IO.FileAttributes]::Directory) -eq 0 -or $nm -cnotmatch $script:HordeRelayJournalSenderDirPattern) {'
           Replace = 'if ($nm -cnotmatch $script:HordeRelayJournalSenderDirPattern) { continue }; if ($false) {' }
        # --- review of 48bc492 ---
        @{ Name = "any-record-at-the-seq-is-the-snapshot"
           Find = '$same = ($r.meta.key -ceq $Key)'
           Replace = '$same = $true' }
    )
}
