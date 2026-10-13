# Mutations of core/WakeFiles.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-files.psd1
# Each breaks one rule of the wake folder's files; test\test-wake.ps1 must fail for every one.
@{
    Target = "core\WakeFiles.ps1"
    Suite  = "test\test-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "unknown-journaled-every-pass"
           Find = '-and "$($Unknown["$($e.id)"])" -ceq "$($e.reason)") { continue }'
           Replace = '-and $false) { continue }' }
        @{ Name = "elapsed-time-not-journaled"
           Find = 'if ($null -ne $e.PSObject.Properties["elapsedMs"]) { $row["elapsedMs"] = [long]$e.elapsedMs }'
           Replace = '' }
        @{ Name = "stale-fixed-whatever-the-tick"
           Find = 'return [int][System.Math]::Max($script:HordeWakeStaleSeconds, 3 * $TickSeconds)'
           Replace = 'return [int]$script:HordeWakeStaleSeconds' }
        @{ Name = "stale-below-the-floor"
           Find = 'return [int][System.Math]::Max($script:HordeWakeStaleSeconds, 3 * $TickSeconds)'
           Replace = 'return [int](3 * $TickSeconds)' }
        @{ Name = "journal-never-set-aside"
           Find = '(New-Object System.IO.FileInfo($path)).Length -ge $MaxBytes) {'
           Replace = '$false) {' }
        @{ Name = "tail-forgets-the-journal-set-aside"
           Find = 'foreach ($ext in @(".1.jsonl", ".jsonl")) {'
           Replace = 'foreach ($ext in @(".jsonl")) {' }
        @{ Name = "live-reads-the-unsuffixed-files-of-earlier-builds"
           Find = '$leaf = $Stem + "-live" + $Extension'
           Replace = '$leaf = $Stem + $Extension' }
        @{ Name = "state-file-is-the-unsuffixed-one-of-earlier-builds"
           Find = '$leaf = $Name + "-" + (Get-HordeWakeModeWord -Mode $Mode -Shadow:$Shadow) + ".json"'
           Replace = '$leaf = $Name + ".json"' }
        @{ Name = "shadow-journal-and-heartbeat-are-the-live-ones"
           Find = 'if ($Shadow) { $leaf = $Stem + "-shadow" + $Extension }'
           Replace = '' }
        @{ Name = "journal-written-to-the-live-file-whatever-the-mode"
           Find = '$path = Get-HordeWakeModeFile -Stem "journal" -Extension ".jsonl" -Shadow:$Shadow -HordeHome $HordeHome'
           Replace = '$path = Get-HordeWakeModeFile -Stem "journal" -Extension ".jsonl" -HordeHome $HordeHome' }
        @{ Name = "tick-not-written-in-the-heartbeat"
           Find = 'shadow = [bool]$Shadow; tickSeconds = $TickSeconds }'
           Replace = 'shadow = [bool]$Shadow; tickSeconds = 0 }' }
        @{ Name = "shadow-state-file-is-the-live-one"
           Find = 'if ($Mode -ceq "") { if ($Shadow) { return "shadow" }; return "live" }'
           Replace = 'if ($Mode -ceq "") { return "live" }' }
    )
}
