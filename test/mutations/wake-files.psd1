# Mutations of core/WakeFiles.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-files.psd1
# Each breaks one rule of the wake folder's files; test\test-wake.ps1 must fail for every one.
@{
    Target = "core\WakeFiles.ps1"
    Suite  = "test\test-wake.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-heartbeat-drops-the-watchers-own-session"
           Find = 'if ($PSBoundParameters.ContainsKey("Self")) { $beat["self"] = "$Self" }'
           Replace = '' }
        @{ Name = "a-heartbeat-that-does-not-say-reads-as-none"
           Find = 'tickSeconds = 0; self = $null; counts = $null }'
           Replace = 'tickSeconds = 0; self = ""; counts = $null }' }
        @{ Name = "a-proof-run-has-a-lock-and-a-ledger-of-its-own"
           Find = 'if ((Get-HordeWakeModeWord -Mode $Mode) -ceq "shadow") { return "shadow" }'
           Replace = 'if ((Get-HordeWakeModeWord -Mode $Mode) -cne "live") { return (Get-HordeWakeModeWord -Mode $Mode) }' }
        @{ Name = "no-mode-named-is-the-sending-runs-files"
           Find = 'if ($Mode -ceq "") { return "shadow" }'
           Replace = 'if ($Mode -ceq "") { return "live" }' }
        @{ Name = "a-word-that-is-no-mode-names-a-file"
           Find = 'if (@("shadow", "proof", "live") -cnotcontains $Mode) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "proof-files-are-the-live-ones"
           Find = 'if ($Mode -ceq "") { return "shadow" }'
           Replace = 'if ($Mode -ceq "") { return "shadow" }; if ($Mode -ceq "proof") { return "live" }' }
        @{ Name = "heartbeat-does-not-say-its-mode"
           Find = 'shadow = ($word -ceq "shadow"); mode = $word;'
           Replace = 'shadow = ($word -ceq "shadow"); mode = "";' }
        @{ Name = "proof-heartbeat-says-shadow"
           Find = 'shadow = ($word -ceq "shadow"); mode = $word;'
           Replace = 'shadow = ($word -cne "live"); mode = $word;' }
        @{ Name = "heartbeat-read-from-the-live-file-whatever-the-mode"
           Find = '$path = Get-HordeWakeModeFile -Stem "heartbeat" -Extension ".json" -Shadow:$Shadow -Mode $Mode -HordeHome $HordeHome'
           Replace = '$path = Get-HordeWakeModeFile -Stem "heartbeat" -Extension ".json" -HordeHome $HordeHome' }
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
           Find = '$leaf = $Stem + "-" + (Get-HordeWakeModeWord -Mode $Mode -Shadow:$Shadow) + $Extension'
           Replace = '$leaf = $Stem + $Extension' }
        @{ Name = "state-file-is-the-unsuffixed-one-of-earlier-builds"
           Find = '$leaf = $Name + "-" + (Get-HordeWakeModeWord -Mode $Mode -Shadow:$Shadow) + ".json"'
           Replace = '$leaf = $Name + ".json"' }
        @{ Name = "shadow-journal-and-heartbeat-are-the-live-ones"
           Find = '$leaf = $Stem + "-" + (Get-HordeWakeModeWord -Mode $Mode -Shadow:$Shadow) + $Extension'
           Replace = '$leaf = $Stem + "-" + (Get-HordeWakeModeWord -Mode $Mode) + $Extension' }
        @{ Name = "journal-written-to-the-live-file-whatever-the-mode"
           Find = '$path = Get-HordeWakeModeFile -Stem "journal" -Extension ".jsonl" -Shadow:$Shadow -Mode $Mode -HordeHome $HordeHome'
           Replace = '$path = Get-HordeWakeModeFile -Stem "journal" -Extension ".jsonl" -HordeHome $HordeHome' }
        @{ Name = "tick-not-written-in-the-heartbeat"
           Find = 'mode = $word; tickSeconds = $TickSeconds }'
           Replace = 'mode = $word; tickSeconds = 0 }' }
    )
}
