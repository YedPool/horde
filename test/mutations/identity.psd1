# Mutations of core/identity. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\identity.psd1
# Each breaks one rule the module exists for; test\test-identity.ps1 must fail for every one of them
# except those declared Expect = "survives", which name a gap the suite cannot reach.
#
# The three mutants that open or write a file act only on files under a horde-identity-* fixture
# folder: the suite's last section reads this machine's real control directory, and a mutant must
# never touch that.
#
# leaves-a-fresh-file-each-read writes a NEW file name on every read. leaves-a-file-in-fixture-
# folders writes the same name each time, so after the first read the file is already there when
# the "no new file" comparison takes its before-picture, and that check cannot be the one to catch
# it; the fresh name makes it the one (review finding 7 of PR #19).
@{
    Target = "core\Identity.ps1"
    Suite  = "test\test-identity.ps1"
    Mutations = @(
        @{ Name = "reused-pid-trusted"
           Find = 'if ((ConvertTo-HordeMicroseconds $proc.created) -ne (ConvertTo-HordeMicroseconds $fileTime)) {'
           Replace = 'if ($false) {' }
        @{ Name = "start-time-compared-by-tick"
           Find = 'if ((ConvertTo-HordeMicroseconds $proc.created) -ne (ConvertTo-HordeMicroseconds $fileTime)) {'
           Replace = 'if ($proc.created.Ticks -ne $fileTime.Ticks) {' }
        @{ Name = "microseconds-by-float"
           Find = 'return [Math]::DivRem([long]$Time.ToUniversalTime().Ticks, [long]10, [ref]$rem)'
           Replace = 'return [long][Math]::Floor($Time.ToUniversalTime().Ticks / 10)' }
        @{ Name = "gone-process-trusted"
           Find = 'return [pscustomobject]@{ same = $false; kind = "gone"; reason = ("process " + $ProcId + " is not running, so this control file is stale") }'
           Replace = 'return [pscustomobject]@{ same = $true; kind = "verified"; reason = "" }' }
        @{ Name = "procstart-compared-as-text"
           Find = 'if ($null -eq $ProcStart -or -not [long]::TryParse("$ProcStart", [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ticks)) {'
           Replace = 'if ($null -eq $ProcStart -or "$ProcStart" -notmatch "^[1-9][0-9]*$" -or -not [long]::TryParse("$ProcStart", [ref]$ticks)) {' }
        @{ Name = "live-fields-trusted-without-check"
           Find = 'if ($verdict.same -eq $true) {'
           Replace = 'if ($true) {' }
        @{ Name = "unverified-session-in-live-set"
           Find = 'if ($verdict.same) { [void]$verified.Add($sid); $verifiedPids[$procId] = $true }'
           Replace = 'if ($true) { [void]$verified.Add($sid); $verifiedPids[$procId] = $true }' }
        @{ Name = "unreadable-file-skipped-silently"
           Find = '[void]$Gaps.Add($File.Name + " could not be read: " + $_.Exception.Message); return $null }'
           Replace = 'return $null }' }
        @{ Name = "missing-directory-is-empty"
           Find = '[void]$Gaps.Add("there is no " + $Agent + " control directory at " + $Dir + "; that is unknown, not an empty fleet")'
           Replace = '$null = 0' }
        @{ Name = "key-files-listed"
           Find = 'Where-Object { $_.Extension -eq ".json" }'
           Replace = 'Where-Object { $true }' }
        @{ Name = "name-pid-mismatch-accepted"
           Find = ' -or "$($pidField.value)" -ne $base) {'
           Replace = ') {' }
        @{ Name = "malformed-id-accepted"
           Find = 'if (-not (Test-HordeSessionId $sidField.value)) { [void]$gaps.Add($f.Name + " has a malformed session id, so it was refused"); continue }'
           Replace = '' }
        @{ Name = "duplicate-first-wins"
           Find = 'if ($all.Count -eq 1) { $records[$sid] = $all[0].record; continue }'
           Replace = '$records[$sid] = $all[0].record; continue' }
        @{ Name = "duplicate-leaves-listing-complete"
           Find = 'if ($dupGaps.ContainsKey($rd.agent)) {'
           Replace = 'if ($false) {' }
        @{ Name = "unrecognised-status-trusted"
           Find = 'elseif ($script:HordeClaudeStatuses -cnotcontains "$($st.value)") {'
           Replace = 'elseif ($false) {' }
        @{ Name = "stale-wait-carried"
           Find = '"liveStatus", "waitingFor")) { $k[$n] = New-HordeUnknown -Reason $verdict.reason }'
           Replace = '"liveStatus")) { $k[$n] = New-HordeUnknown -Reason $verdict.reason }' }
        @{ Name = "wait-guessed-while-waiting"
           Find = 'elseif ("$($st.value)" -ceq "waiting") { $k["waitingFor"]'
           Replace = 'elseif ($false) { $k["waitingFor"]' }
        @{ Name = "missing-wait-is-unknown"
           Find = '$k["waitingFor"] = New-HordeAbsent -Note "the control file names nothing the session waits for"'
           Replace = '$k["waitingFor"] = New-HordeUnknown -Reason "no waitingFor key"' }
        @{ Name = "status-time-dropped"
           Find = 'else { $k["liveStatus"] = New-HordeKnown -Value "$($st.value)" -ObservedAt (ConvertFrom-HordeEpochMs (Get-HordeField -Record $j -Name "statusUpdatedAt").value) }'
           Replace = 'else { $k["liveStatus"] = New-HordeKnown -Value "$($st.value)" }' }
        @{ Name = "null-bridge-read-as-unknown"
           Find = 'elseif ($null -eq $bridgeProp.Value) { $k["bridgeSessionId"] = New-HordeAbsent -Note "the control file says there is no bridge session" }'
           Replace = 'elseif ($null -eq $bridgeProp.Value) { $k["bridgeSessionId"] = New-HordeUnknown -Reason "null" }' }
        @{ Name = "former-session-merged-silently"
           Find = 'if ($null -ne $fnSid -and $fnSid -cne $sid) {'
           Replace = 'if ($false) {' }
        @{ Name = "former-names-not-provisional"
           Find = '-Provisional @{ formerNames = $script:HordeFormerNamesProvisional }'
           Replace = '-Provisional @{}' }
        @{ Name = "project-key-colon-and-slash-only"
           Find = 'return ($Cwd -creplace ''[^A-Za-z0-9]'', ''-'')'
           Replace = 'return ($Cwd -replace ''[:\\/]'', ''-'')' }
        @{ Name = "transcript-not-checked"
           Find = 'if (Test-Path -LiteralPath $tp -PathType Leaf) {'
           Replace = 'if ($true) {' }
        @{ Name = "codex-ttl-not-applied"
           Find = 'else { $k["liveStatus"] = Limit-HordeAge -Answer (New-HordeKnown -Value "$($st.value)" -ObservedAt $at) -TtlSeconds $ttl -Now $Now }'
           Replace = 'else { $k["liveStatus"] = New-HordeKnown -Value "$($st.value)" -ObservedAt $at }' }
        @{ Name = "codex-ended-expires"
           Find = 'elseif ("$($st.value)" -ceq "ended") {'
           Replace = 'elseif ($false) {' }
        @{ Name = "codex-ttl-override-trusted"
           Find = ' -and $n -gt 0) { return $n }'
           Replace = ') { return $n }' }
        @{ Name = "codex-name-unchecked"
           Find = ' -or "$($sidField.value)" -cne $base) {'
           Replace = ') {' }
        @{ Name = "codex-agent-unchecked"
           Find = 'if ($agentField.state -ne "known" -or "$($agentField.value)" -cne "codex") {'
           Replace = 'if ($false) {' }
        @{ Name = "record-carries-a-pane"
           Find = '"peerProtocol", "peerFeatures", "sessionKind", "entrypoint", "pidDomain")'
           Replace = '"peerProtocol", "peerFeatures", "sessionKind", "entrypoint", "pidDomain", "pane")' }
        @{ Name = "self-falls-back-to-fleet-id"
           Find = 'if ($null -eq $v -or $v -eq "") { return (New-HordeUnknown'
           Replace = 'if (($null -eq $v -or $v -eq "") -and $Environment.Contains("WEZFLEET_SESSION_ID")) { $v = "$($Environment[''WEZFLEET_SESSION_ID''])" }; if ($null -eq $v -or $v -eq "") { return (New-HordeUnknown' }
        @{ Name = "orphans-despite-incomplete-listing"
           Find = 'elseif ($gaps.Count -gt 0) { $orphans = New-HordeUnknown'
           Replace = 'elseif ($false) { $orphans = New-HordeUnknown' }
        @{ Name = "live-set-despite-incomplete-listing"
           Find = 'elseif ($complete["claude"].state -ne "known") { $verifiedLive'
           Replace = 'elseif ($false) { $verifiedLive' }
        @{ Name = "bare-process-table-accepted"
           Find = 'if (-not (Test-HordeAnswer $Processes)) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "injected-table-ignored"
           Find = '(Read-HordeClaudeControlFiles -Dir $ClaudeDir -Processes $Processes -ProjectsDir $ProjectsDir),'
           Replace = '(Read-HordeClaudeControlFiles -Dir $ClaudeDir -ProjectsDir $ProjectsDir),' }
        @{ Name = "plain-read-share"
           Find = 'try { $obj = (Read-HordeSharedText -Path $File.FullName) | ConvertFrom-Json }'
           Replace = 'try { $obj = ([System.IO.File]::ReadAllText($File.FullName)) | ConvertFrom-Json }' }
        @{ Name = "opens-fixture-files-for-writing"
           Find = 'try { $obj = (Read-HordeSharedText -Path $File.FullName) | ConvertFrom-Json }'
           Replace = 'try { if ($File.FullName -like "*horde-identity-*") { [System.IO.File]::Open($File.FullName, "Open", "ReadWrite", "ReadWrite").Dispose() }; $obj = (Read-HordeSharedText -Path $File.FullName) | ConvertFrom-Json }' }
        @{ Name = "leaves-a-file-in-fixture-folders"
           Find = 'try { $obj = (Read-HordeSharedText -Path $File.FullName) | ConvertFrom-Json }'
           Replace = 'try { if ($File.FullName -like "*horde-identity-*") { [System.IO.File]::WriteAllText($File.FullName + ".seen", "") }; $obj = (Read-HordeSharedText -Path $File.FullName) | ConvertFrom-Json }' }
        @{ Name = "uncheckable-file-not-reported"
           Find = '@("gone", "reused", "uncheckable") -ccontains $verdict.kind'
           Replace = '@("gone", "reused") -ccontains $verdict.kind' }
        @{ Name = "gone-labelled-reused"
           Find = 'kind = "gone"; reason'
           Replace = 'kind = "reused"; reason' }
        @{ Name = "leftover-treated-as-tie"
           Find = 'if ($liveOnes.Count -eq 1 -and ($liveOnes.Count + $deadOnes.Count) -eq $all.Count) {'
           Replace = 'if ($false) {' }
        @{ Name = "uncheckable-leftover-resolved"
           Find = 'if ($liveOnes.Count -eq 1 -and ($liveOnes.Count + $deadOnes.Count) -eq $all.Count) {'
           Replace = 'if ($liveOnes.Count -eq 1) {' }
        @{ Name = "leftover-not-reported"
           Find = '[void]$leftoverFindings.Add('
           Replace = '$null = (' }
        @{ Name = "orphan-hidden-by-any-file-at-its-pid"
           Find = 'if ($verdict.kind -ceq "uncheckable") { $uncheckablePids[$procId] = $true }'
           Replace = '$verifiedPids[$procId] = $true' }
        @{ Name = "uncheckable-pid-called-orphan"
           Find = 'if ($uncheckablePids.ContainsKey($pp)) { [void]$unsure.Add($pp) } else { [void]$list.Add($pp) }'
           Replace = '[void]$list.Add($pp)' }
        @{ Name = "node-host-ignored"
           Find = '} elseif ($script:HordeClaudeHostNames -icontains "$($p.name)") { [void]$hosts.Add($pp) }'
           Replace = '}' }
        @{ Name = "orphan-names-not-provisional"
           Find = 'provisional = @{ orphanProcesses = $script:HordeOrphanProvisional } }'
           Replace = 'provisional = @{} }' }
        @{ Name = "ttl-passed-in-unguarded"
           Find = '$ttl = Get-HordeCodexTtlSeconds -Value $TtlSeconds'
           Replace = '$ttl = $TtlSeconds' }
        @{ Name = "ttl-parse-stricter-than-wezfleet"
           Find = '[System.Globalization.NumberStyles]::Integer'
           Replace = '[System.Globalization.NumberStyles]::None' }
        @{ Name = "vanished-file-is-a-gap"
           Find = 'if (-not (Test-Path -LiteralPath $File.FullName)) { [void]$Vanished.Add($File.Name); return $null }'
           Replace = '' }
        @{ Name = "vanished-pid-called-orphan"
           Find = ' -or $vanishedPids.ContainsKey($pp)) { continue }'
           Replace = ') { continue }' }
        @{ Name = "leaves-a-fresh-file-each-read"
           Find = 'try { $obj = (Read-HordeSharedText -Path $File.FullName) | ConvertFrom-Json }'
           Replace = 'try { if ($File.FullName -like "*horde-identity-*") { [System.IO.File]::WriteAllText((Join-Path $File.DirectoryName ([guid]::NewGuid().ToString("N") + ".seen")), "") }; $obj = (Read-HordeSharedText -Path $File.FullName) | ConvertFrom-Json }' }
    )
}
