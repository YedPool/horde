# Mutations of core/ServicesFiles.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\services-files.psd1
# Each breaks one promise of the supervisor's files; test\test-services.ps1 must fail for every one.
@{
    Target = "core\ServicesFiles.ps1"
    Suite  = "test\test-services.ps1"
    Mutations = @(
        @{ Name = "secrets-kept"
           Find = '    $line = (Protect-HordeSecretText -Text $line).text'
           Replace = '' }
        @{ Name = "reason-keeps-line-breaks"
           Find = '$line = (($Text -replace ''[\r\n\t]+'', '' '') -replace ''\p{Cc}'', '''').Trim()'
           Replace = '$line = $Text.Trim()' }
        @{ Name = "unreadable-state-is-new"
           Find = '    } catch { return (New-HordeUnknown -Reason ("its state file " + $path + " could not be read") -ErrorRecord $_) }'
           Replace = '    } catch { return (New-HordeAbsent -Note "new") }' }
        @{ Name = "malformed-state-is-new"
           Find = 'if ($null -eq $made.state) { return (New-HordeUnknown -Reason ("its state file " + $path + " is not a state the supervisor wrote: "'
           Replace = 'if ($null -eq $made.state) { return (New-HordeAbsent -Note ("its state file " + $path + " is not a state the supervisor wrote: "' }
        @{ Name = "unknown-phase-accepted"
           Find = 'if ($script:HordeServicePhases -cnotcontains $s.phase) { return (& $bad "its phase is not one the supervisor knows") }'
           Replace = '' }
        @{ Name = "other-services-state-accepted"
           Find = 'if (-not $have.ContainsKey("name") -or "" + $have["name"] -cne $Name) {'
           Replace = 'if ($false) {' }
        @{ Name = "schema-version-unchecked"
           Find = 'if (-not $have.ContainsKey("schemaVersion") -or $have["schemaVersion"] -ne 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "revision-unchecked"
           Find = 'if ($v -ne "" -and $v -cnotmatch $script:HordeServiceRevisionPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "phase-without-intent-accepted"
           Find = 'if (@("update", "rollback", "withdraw", "heal") -cnotcontains $s.intent) {'
           Replace = 'if ($false) {' }
        @{ Name = "phase-without-time-accepted"
           Find = 'if ($s.phaseSince -isnot [datetime]) { return (& $bad "it is part way through something and does not say since when") }'
           Replace = '' }
        @{ Name = "update-without-revisions-accepted"
           Find = 'if ($s.intent -cne "heal" -and ($s.target -eq "" -or $s.from -eq "")) {'
           Replace = 'if ($false) {' }
        @{ Name = "half-a-process-accepted"
           Find = '-or $null -eq $pStart -or $null -eq $pAt) { return (& $bad "the process it names is not whole'
           Replace = ') { return (& $bad "the process it names is not whole' }
        @{ Name = "bad-time-accepted"
           Find = '            if ($null -eq $t) { return (& $bad ("its " + $k + " is not a time")) }'
           Replace = '            if ($null -eq $t) { continue }' }
        @{ Name = "pin-not-written"
           Find = 'pinnedRevision = "" + $State.pinnedRevision;'
           Replace = 'pinnedRevision = "";' }
        @{ Name = "told-not-written"
           Find = 'told = @($State.told | ForEach-Object { "" + $_ });'
           Replace = 'told = @();' }
        @{ Name = "state-path-from-any-name"
           Find = 'if ($Name -cnotmatch $script:HordeServiceNamePattern) { throw ("not a service name: ''" + $Name + "''") }'
           Replace = '' }
        @{ Name = "wait-journaled-every-pass"
           Find = '    return ((Get-HordeServiceSaidKey -Decision $Decision) -cne $LastSaid)'
           Replace = '    return $true' }
        @{ Name = "step-journaled-once"
           Find = '    if ($Decision.step -ne "") { return $true }'
           Replace = '' }
        @{ Name = "journal-unbounded"
           Find = 'if ([System.IO.File]::Exists($path) -and (New-Object System.IO.FileInfo($path)).Length -ge $MaxBytes) { Move-HordeFileAtomic -From $path -To ([System.IO.Path]::ChangeExtension($path, ".1.jsonl")) }'
           Replace = '' }
        @{ Name = "tail-forgets-the-set-aside"
           Find = 'foreach ($p in @([System.IO.Path]::ChangeExtension($path, ".1.jsonl"), $path)) {'
           Replace = 'foreach ($p in @($path)) {' }
        @{ Name = "lock-shared"
           Find = '([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::None)) }'
           Replace = '([System.IO.FileAccess]::ReadWrite), ([System.IO.FileShare]::ReadWrite)) }' }
        @{ Name = "lock-wait-ignored"
           Find = '    $tries = 1 + [int]([System.Math]::Max(0, $WaitSeconds) * 2)'
           Replace = '    $tries = 1' }
        @{ Name = "log-never-set-aside"
           Find = 'if ([System.IO.File]::Exists($path) -and (New-Object System.IO.FileInfo($path)).Length -ge $MaxBytes) { Move-HordeFileAtomic -From $path -To ([System.IO.Path]::ChangeExtension($path, ".1.log")) }'
           Replace = '' }
        # --- safety review of the first build ---
        @{ Name = "held-not-written"
           Find = 'held = [bool]($State.held -eq $true); heldWhy'
           Replace = 'held = $false; heldWhy' }
        @{ Name = "move-mark-not-written"
           Find = 'if ($null -ne $State.moving) { $r["moving"] ='
           Replace = 'if ($false) { $r["moving"] =' }
        @{ Name = "half-a-move-mark-accepted"
           Find = ' -or ("" + $m["target"]) -cnotmatch $script:HordeServiceRevisionPattern -or $null -eq $mAt) {'
           Replace = ') {' }
        @{ Name = "held-as-a-word-accepted"
           Find = 'if ($have["held"] -isnot [bool]) { return (& $bad "its held mark is not true or false") }; '
           Replace = '' }
        @{ Name = "refusal-count-not-written"
           Find = 'at = (& $time $State.refused.at); count = (Get-HordeServiceRefusedCount -Refused $State.refused) } }'
           Replace = 'at = (& $time $State.refused.at); count = 1 } }' }
        @{ Name = "notice-kind-not-written"
           Find = 'at = (& $time $_.at); what = (Get-HordeServiceNoticeWhat -Notice $_) } })'
           Replace = 'at = (& $time $_.at); what = "" } })' }
        @{ Name = "exit-record-of-another-start-taken"
           Find = ' -or -not (Test-HordeHeartbeatSameStart -One $started -Other $Process.startedAt)) { return (New-HordeUnknown -Reason "its exit record is about another process") }'
           Replace = ') { return (New-HordeUnknown -Reason "its exit record is about another process") }' }
        @{ Name = "exit-record-of-another-pid-taken"
           Find = ' -or [long]$have["pid"] -ne [long]$Process.pid'
           Replace = '' }
        @{ Name = "exit-record-without-a-code-taken"
           Find = 'if ($have["code"] -isnot [int] -and $have["code"] -isnot [long]) { return (New-HordeUnknown -Reason "its exit record holds no code") }'
           Replace = 'if ($have["code"] -isnot [int] -and $have["code"] -isnot [long]) { return (New-HordeKnown -Value 0) }' }
            # --- review of PR 249, round 2 ---
        @{ Name = "withdraw-not-a-state"
           Find = 'if (@("update", "rollback", "withdraw", "heal") -cnotcontains $s.intent)'
           Replace = 'if (@("update", "rollback", "heal") -cnotcontains $s.intent)' }
    )
}
