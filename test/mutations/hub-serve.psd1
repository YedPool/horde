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
           Find = 'else { $refusal = (@(Test-HordeHelloBinding -Frame $f -BoundDeviceId "$($Entry.deviceId)") -join "; ") }'
           Replace = 'else { $refusal = "" }' }
        # The binding rule is remote/LinkBinding.ps1's, mutated by test\mutations\link-binding.psd1; here,
        # that the hub calls it for the device the link is bound to and not for the one the hello names.
        @{ Name = "hello-bound-to-its-own-claim"
           Find = '(@(Test-HordeHelloBinding -Frame $f -BoundDeviceId "$($Entry.deviceId)") -join "; ")'
           Replace = '(@(Test-HordeHelloBinding -Frame $f -BoundDeviceId "$($f.hello.id)") -join "; ")' }
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
           Find = 'if ($old.state -ceq "unknown") { $note = "; the old mirror was started afresh: " + $old.reason + "; " +'
           Replace = 'if ($old.state -ceq "unknown") { $note = "" +' }
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
           Find = 'if ($n.heard.state -cne "known") { [void]$lines.Add($n.heard.reason + $how); continue }'
           Replace = 'if ($n.heard.state -cne "known") { [void]$lines.Add($who + ": not heard" + $how); continue }' }
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
        @{ Name = "unreadable-mirror-overwritten-unkept"
           Find = '+ "; " + (Move-HordeHubMirrorAside -Path $mirrorPath) }'
           Replace = '}' }
        @{ Name = "missing-mirror-unsaid"
           Find = 'else { $note = "; no mirror file was there; started afresh" }'
           Replace = '' }
        @{ Name = "no-run-lock"
           Find = '$lock = Enter-HordeHubLock -Path (Get-HordeHubLockPath -Root $Root)'
           Replace = '$lock = New-Object System.IO.MemoryStream' }
        @{ Name = "any-lock-failure-read-as-busy"
           Find = 'if ($inner -is [System.IO.IOException] -and $inner.HResult -eq $script:HordeHubSharingViolation) { throw ("another horde hub serve is running'
           Replace = 'if ($true) { throw ("another horde hub serve is running' }
        @{ Name = "run-lock-kept-after-return"
           Find = '    } finally { $lock.Dispose() }'
           Replace = '    } finally { }' }
        @{ Name = "node-bound-ignored"
           Find = '$bound = New-HordeHubBound -BudgetMs $BudgetMs'
           Replace = '$bound = New-HordeHubBound -BudgetMs 0' }
        @{ Name = "held-mirror-moved-aside"
           Find = 'if ($old.state -ceq "unknown" -and $null -ne $old.PSObject.Properties["held"] -and $old.held -eq $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "held-mirror-not-told-apart"
           Find = '$u | Add-Member -NotePropertyName held -NotePropertyValue $isHeld'
           Replace = '$u | Add-Member -NotePropertyName held -NotePropertyValue $false' }
        # --- re-review of PR #88: held means a sharing or lock violation; the reviewer's three survivors ---
        @{ Name = "denied-read-as-held"
           Find = '$isHeld = ($inner -is [System.IO.IOException] -and ($inner.HResult -eq $script:HordeHubSharingViolation -or $inner.HResult -eq $script:HordeHubLockViolation))'
           Replace = '$isHeld = ($inner -is [System.UnauthorizedAccessException] -or $inner -is [System.IO.IOException])' }
        @{ Name = "refused-mirror-unsaid"
           Find = 'if ($old.state -ceq "unknown" -and $null -ne $old.PSObject.Properties["refused"] -and $old.refused -eq $true) {'
           Replace = 'if ($false) {' }
        @{ Name = "refusal-cause-dropped"
           Find = '$u | Add-Member -NotePropertyName cause -NotePropertyValue $inner.Message'
           Replace = '$u | Add-Member -NotePropertyName cause -NotePropertyValue "it could not be opened"' }
        @{ Name = "lock-shared-readwrite"
           Find = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None) }'
           Replace = '[System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::ReadWrite) }' }
        @{ Name = "open-not-bounded"
           Find = '-TimeoutMs ([Math]::Max(1, (Get-HordeHubWaitMs -Bound $bound -TimeoutMs ([Math]::Min($TimeoutMs, 15000)))))'
           Replace = '-TimeoutMs ([Math]::Min($TimeoutMs, 15000))' }
        @{ Name = "aside-failure-throws"
           Find = 'catch { return ("it could not be kept aside, and is overwritten: " + $_.Exception.Message) }'
           Replace = 'catch { throw }' }
        @{ Name = "bound-without-slack"
           Find = '[datetime]::UtcNow -ge $Bound.deadline.AddMilliseconds(-$script:HordeHubBoundSlackMs)'
           Replace = '[datetime]::UtcNow -ge $Bound.deadline' }
        @{ Name = "aside-copies-uncapped"
           Find = '$old = @($copies | Select-Object -Skip $script:HordeHubAsideKept)'
           Replace = '$old = @()' }
        # Verbs version 2, sessions.list's membershipComplete (ledger core-projection L-101, review of PR #243).
        @{ Name = "hub-offers-only-verbs-version-1"
           Find = '$script:HordeHubVerbsVersions = @(1, 2)'
           Replace = '$script:HordeHubVerbsVersions = @(1)' }
        @{ Name = "hub-hears-membership-on-a-version-1-link"
           Find = 'if ($verbs -lt 2 -and $null -ne $res.list.PSObject.Properties["membershipComplete"]) {'
           Replace = 'if ($false) {' }
    )
}
