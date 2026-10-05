# Mutations of cli/HubServe.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-serve.psd1
# Each breaks one rule of how the hub pulls its nodes and keeps their mirror files (remote plan R13a);
# test\test-hub-serve.ps1 must fail for every one of them. HORDE_FAIL_FAST stops a mutant's run at its
# first failed check: the suite runs a node in a second runspace several times, and a caught mutant
# need not wait for the rest.
@{
    Target = "cli\HubServe.ps1"
    Suite  = "test\test-hub-serve.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "node-of-another-device-accepted"
           Find = 'elseif ("$($f.hello.id)" -cne "$($Entry.deviceId)") {'
           Replace = 'elseif ($false) {' }
        @{ Name = "refusal-without-bye"
           Find = '$null = Send-HordeHubFrame -Link $link -Frame (New-HordeLinkBye -Code "refused" -Reason $refusal -Seq $seq -Contract $Contract) -Contract $Contract'
           Replace = '' }
        @{ Name = "round-ends-without-bye"
           Find = '$null = Send-HordeHubFrame -Link $link -Frame (New-HordeLinkBye -Code "shutdown" -Reason "the hub''s round is done" -Seq $seq -Contract $Contract) -Contract $Contract'
           Replace = '' }
        @{ Name = "error-answer-not-read-as-error"
           Find = 'if ($null -ne (Get-HordeLinkProp $r "error")) {'
           Replace = 'if ($false) {' }
        @{ Name = "clock-not-sampled"
           Find = '$res.clock = Get-HordeClockSample'
           Replace = '$null = Get-HordeClockSample' }
        @{ Name = "failed-pull-not-recorded"
           Find = '$m = Set-HordeNodeMirrorLost -Mirror $m -At $began -Reason "$($p.reason)"'
           Replace = '$m = $m' }
        @{ Name = "throw-while-pulling-not-caught"
           Find = 'catch { $p = [pscustomobject]@{ ok = $false; reason = ("the hub failed while pulling: " + $_.Exception.Message) } }'
           Replace = 'catch { throw }' }
        @{ Name = "unreadable-mirror-not-said"
           Find = 'if ($old.state -ceq "unknown") { $note = "; the old mirror was started afresh: " + $old.reason }'
           Replace = '' }
        @{ Name = "mirror-file-trusted-unchecked"
           Find = 'if ($found.Count -gt 0) { return (New-HordeUnknown -Reason ("the mirror file " + $Path + " could not be read as a mirror: "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the mirror file " + $Path + " could not be read as a mirror: "' }
        @{ Name = "mirror-schema-skipped"
           Find = 'if ($found.Count -gt 0) { return @($found | ForEach-Object { "node-mirror.v1: " + $_ }) }'
           Replace = '' }
        @{ Name = "inventory-not-checked-by-the-contract"
           Find = 'if (-not $b.ok) { [void]$out.Add("the inventory is not a sessions.list the link contract accepts: " + $b.reason) }'
           Replace = '' }
        @{ Name = "carried-not-checked-by-the-contract"
           Find = 'if (-not $b.ok) { [void]$out.Add("the carried sessions are not sessions the link contract accepts: " + $b.reason) }'
           Replace = '' }
        @{ Name = "unchecked-mirror-written"
           Find = 'if ($found.Count -gt 0) { throw ("this mirror is not one to write: "'
           Replace = 'if ($false) { throw ("this mirror is not one to write: "' }
        @{ Name = "missing-file-unknown-not-absent"
           Find = 'return (New-HordeAbsent -Note ("no mirror file at " + $Path))'
           Replace = 'return (New-HordeUnknown -Reason ("no mirror file at " + $Path))' }
        @{ Name = "registry-dials-the-name-not-the-id"
           Find = 'endpoint = "$($Node.deviceId)"'
           Replace = 'endpoint = "$($Node.deviceName)"' }
        @{ Name = "registry-on-another-transport"
           Find = '$script:HordeHubOwnTransport = "local"'
           Replace = '$script:HordeHubOwnTransport = "other"' }
        @{ Name = "report-answer-without-state"
           Find = 'return (ConvertTo-HordeAnswerRecord $Answer)'
           Replace = 'return $Answer.value' }
        @{ Name = "text-hides-why-unheard"
           Find = 'if ($n.heard.state -cne "known") { [void]$lines.Add($n.heard.reason); continue }'
           Replace = 'if ($n.heard.state -cne "known") { [void]$lines.Add($who + ": not heard"); continue }' }
        @{ Name = "mirror-of-another-device-read"
           Find = 'if ("$($m.deviceId)" -cne $DeviceId) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "reader-without-shared-access"
           Find = 'try { $m = Read-HordeSharedText -Path $Path | ConvertFrom-Json }'
           Replace = 'try { $m = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json }' }
        @{ Name = "write-not-a-rename"
           Find = 'try { Move-HordeFileAtomic -From $tmp -To $path }'
           Replace = 'try { [System.IO.File]::Copy($tmp, $path, $true) }' }
        @{ Name = "failed-write-leaves-its-temporary-file"
           Find = 'catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw }'
           Replace = 'catch { throw }' }
        @{ Name = "whole-temporary-mirror-not-recovered"
           Find = 'Move-HordeFileAtomic -From $t.FullName -To $path'
           Replace = 'Remove-Item -LiteralPath $t.FullName -Force' }
        @{ Name = "temporary-files-never-cleared"
           Find = '        Remove-Item -LiteralPath $t.FullName -Force'
           Replace = '' }
        @{ Name = "hub-start-does-not-sweep"
           Find = 'foreach ($l in @(Clear-HordeHubMirrorTemps -Root $Root -DeviceId "$($e.deviceId)" -Contract $Contract))'
           Replace = 'foreach ($l in @())' }
        @{ Name = "mirror-path-not-anchored"
           Find = '-cnotmatch ''\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z'') { throw'
           Replace = '-cnotmatch ''[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'') { throw' }
    )
}
