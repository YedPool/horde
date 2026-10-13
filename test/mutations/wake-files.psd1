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
           Find = 'foreach ($leaf in @("journal.1.jsonl", "journal.jsonl")) {'
           Replace = 'foreach ($leaf in @("journal.jsonl")) {' }
        @{ Name = "tick-not-written-in-the-heartbeat"
           Find = 'shadow = [bool]$Shadow; tickSeconds = $TickSeconds }'
           Replace = 'shadow = [bool]$Shadow; tickSeconds = 0 }' }
        @{ Name = "shadow-state-file-is-the-live-one"
           Find = 'if ($Shadow) { $leaf = $Name + "-shadow.json" }'
           Replace = '' }
    )
}
