# Mutations of remote/Journal.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\journal.psd1
# Each breaks one rule the journal exists for; test\test-journal.ps1 must fail for every one of them
# except those declared Expect = "survives", which name a gap the suite cannot reach.
#
# Racing processes have their own suite and spec (journal-race.psd1). create-overwrites is in both:
# here a resend one after another catches it, there racing processes do.
#
# id-not-validated lets "..\x" name a path outside the journal. Each of the suite's journals sits in a
# folder of its own under %TEMP%, so that path lands in the suite's folder and is removed with it.
@{
    Target = "remote\Journal.ps1"
    Suite  = "test\test-journal.ps1"
    Mutations = @(
        @{ Name = "create-overwrites"
           Find = '[System.IO.FileMode]::CreateNew'
           Replace = '[System.IO.FileMode]::OpenOrCreate' }
        @{ Name = "reuse-not-checked"
           Find = 'if ($null -ne $got.entry -and $got.entry.argsHash -cne $hash) {'
           Replace = 'if ($false) {' }
        @{ Name = "half-done-acts-again"
           Find = 'return (New-HordeJournalDecision -Decision "unknown" -Reason $why -Result (New-HordeUnknown -Reason $why) -State "accepted" -Entry $e)'
           Replace = 'return (New-HordeJournalDecision -Decision "act" -Reason "" -State "accepted")' }
        @{ Name = "torn-record-acts"
           Find = 'if ($got.kind -eq "unknown") { return (New-HordeJournalDecision -Decision "unknown"'
           Replace = 'if ($got.kind -eq "unknown") { return (New-HordeJournalDecision -Decision "act"' }
        @{ Name = "busy-read-as-absent"
           Find = 'if ($script:HordeJournalBusyCodes -contains $code) { return [pscustomobject]@{ kind = "busy"'
           Replace = 'if ($script:HordeJournalBusyCodes -contains $code) { return [pscustomobject]@{ kind = "absent"' }
        @{ Name = "no-marker-is-a-journal"
           Find = 'if (-not $m.ok) { return (New-HordeJournalDecision -Decision "unknown" -Reason $m.reason -Result (New-HordeUnknown -Reason $m.reason)) }'
           Replace = 'if (-not $m.ok) { [void][System.IO.Directory]::CreateDirectory($Root); $m = [pscustomobject]@{ ok = $true; settings = [pscustomobject]@{ admitDays = 7; maxFutureMinutes = 60 } } }' }
        @{ Name = "window-too-old-not-checked"
           Find = '$tooOld = ($nowUtc - $issuedUtc) -gt (New-TimeSpan -Days $cfg.admitDays)'
           Replace = '$tooOld = $false' }
        @{ Name = "window-future-not-checked"
           Find = '$tooNew = ($issuedUtc - $nowUtc) -gt (New-TimeSpan -Minutes $cfg.maxFutureMinutes)'
           Replace = '$tooNew = $false' }
        @{ Name = "window-may-reach-retention"
           Find = 'if ((New-TimeSpan -Days $AdmitDays -Minutes $MaxFutureMinutes) -ge (New-TimeSpan -Days $RetentionDays)) {'
           Replace = 'if ($false) {' }
        @{ Name = "settings-change-accepted"
           Find = 'if ($s.kind -cne $Kind -or $s.retentionDays -ne $RetentionDays -or $s.admitDays -ne $AdmitDays -or $s.maxFutureMinutes -ne $MaxFutureMinutes) {'
           Replace = 'if ($false) {' }
        @{ Name = "hash-ignores-issue-time"
           Find = '(ConvertTo-HordeJournalCanonical -Value (ConvertTo-HordeJournalTime -Time $IssuedAt -What "the issue time")) +'
           Replace = '''"t"'' +' }
        @{ Name = "hash-ignores-verb"
           Find = ''',"verb":'' + (ConvertTo-HordeJournalCanonical -Value $Verb) + ''}'''
           Replace = ''',"verb":"v"}''' }
        @{ Name = "keys-unsorted"
           Find = '$parts = foreach ($k in $sorted) { (ConvertTo-HordeJournalCanonical -Value $k -Depth ($Depth + 1)) + ":" + (ConvertTo-HordeJournalCanonical -Value $Value[$k]'
           Replace = '$parts = foreach ($k in $keys) { (ConvertTo-HordeJournalCanonical -Value $k -Depth ($Depth + 1)) + ":" + (ConvertTo-HordeJournalCanonical -Value $Value[$k]' }
        @{ Name = "whole-double-as-exponent"
           Find = 'if ([Math]::Floor($d) -eq $d -and [Math]::Abs($d) -lt 9007199254740992) { return ([long]$d).ToString($inv) }'
           Replace = '' }
        @{ Name = "decimal-keeps-scale"
           Find = 'if ($Value -eq [decimal]::Truncate($Value)) {'
           Replace = 'if ($false) {' }
        @{ Name = "non-ascii-raw"
           Find = 'elseif ($c -lt 0x20 -or $c -gt 0x7E) {'
           Replace = 'elseif ($c -lt 0x20) {' }
        @{ Name = "date-stringified"
           Find = 'throw ("a value of type " + $Value.GetType().FullName + " cannot be hashed: only JSON data can")'
           Replace = 'return (ConvertTo-HordeJournalCanonical -Value ("" + $Value) -Depth ($Depth + 1))' }
        @{ Name = "second-outcome-accepted"
           Find = 'if ($made -eq "exists") { throw ("request "'
           Replace = 'if ($false) { throw ("request "' }
        @{ Name = "id-not-validated"
           Find = 'if ($Id -cnotmatch $script:HordeJournalIdPattern) { return (New-HordeJournalDecision -Decision "refuse"'
           Replace = 'if ($false) { return (New-HordeJournalDecision -Decision "refuse"' }
        @{ Name = "id-case-ignored"
           Find = 'if ($Id -cnotmatch $script:HordeJournalIdPattern) { return (New-HordeJournalDecision -Decision "refuse"'
           Replace = 'if ($Id -notmatch $script:HordeJournalIdPattern) { return (New-HordeJournalDecision -Decision "refuse"' }
        @{ Name = "verb-anchored-with-dollar"
           Find = '\A[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*\z'
           Replace = '^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*$' }
        @{ Name = "id-anchored-with-dollar"
           Find = '\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'
           Replace = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' }
        @{ Name = "verb-not-validated"
           Find = 'if ($Verb -cnotmatch $script:HordeJournalVerbPattern) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "prune-half-done"
           Find = 'if ($e.state -ceq "accepted") { if (($nowUtc - $e.receivedAt) -gt $retention) { [void]$kept.Add('
           Replace = 'if ($e.state -ceq "accepted") { if (($nowUtc - $e.receivedAt) -gt $retention) { [System.IO.File]::Delete((Join-Path $Root ($id + ".json"))); [void]$removed.Add($id); continue; [void]$kept.Add(' }
        @{ Name = "prune-torn"
           Find = 'if ($got.kind -eq "unknown") { [void]$kept.Add([pscustomobject]@{ id = $id; reason = ("never pruned: " + $got.reason) }); continue }'
           Replace = 'if ($got.kind -eq "unknown") { [System.IO.File]::Delete((Join-Path $Root ($id + ".json"))); [void]$removed.Add($id); continue }' }
        @{ Name = "prune-ignores-retention"
           Find = 'if (($nowUtc - $e.doneAt) -le $retention -or ($nowUtc - $e.issuedAt) -le $window) { continue }'
           Replace = 'if ($false) { continue }' }
        @{ Name = "prune-outcome-first"
           Find = 'try { [System.IO.File]::Delete((Join-Path $Root ($id + ".json"))) }'
           Replace = 'try { [System.IO.File]::Delete((Join-Path $Root ($id + ".outcome.json"))); [System.IO.File]::Delete((Join-Path $Root ($id + ".json"))) }' }
        @{ Name = "prune-without-marker"
           Find = 'if (-not $m.ok) { return (New-HordeUnknown -Reason ("nothing was pruned: " + $m.reason)) }'
           Replace = 'if (-not $m.ok) { return (New-HordeKnown -Value ([pscustomobject]@{ removed = @(); kept = @() })) }' }
        @{ Name = "not-written-through"
           Find = '$fs.Flush($true)'
           Replace = '$fs.Flush($false)'
           Expect = "survives"
           Reason = "Flush(true) is what puts the record on the disk, not only in the operating system's cache, before the caller acts; only a power cut between the two shows the difference, and no test here can cut the power. The WriteThrough file option still stands in this mutant." }
    )
}
