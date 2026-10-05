# Mutations of core/Platform.ps1's power-throttling seam.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\platform-throttling.psd1
# Each breaks the opt-out or its readback; test\test-platform-throttling.ps1 must fail for every one.
@{
    Target = "core\Platform.ps1"
    Suite  = "test\test-platform-throttling.ps1"
    Mutations = @(
        @{ Name = "opt-out-asks-for-nothing"
           Find = 'var s = new State { Version = 1, ControlMask = 1, StateMask = 0 };'
           Replace = 'var s = new State { Version = 1, ControlMask = 0, StateMask = 0 };' }
        @{ Name = "opt-out-asks-for-throttling"
           Find = 'var s = new State { Version = 1, ControlMask = 1, StateMask = 0 };'
           Replace = 'var s = new State { Version = 1, ControlMask = 1, StateMask = 1 };' }
        @{ Name = "opted-out-read-from-control-alone"
           Find = 'optedOut = [bool](($r[0] -band 1) -eq 1 -and ($r[1] -band 1) -eq 0)'
           Replace = 'optedOut = [bool](($r[0] -band 1) -eq 1)' }
        @{ Name = "every-system-taken-for-windows"
           Find = 'return [bool]("" + $OsPlatform -ceq "Win32NT")'
           Replace = 'return $true' }
        @{ Name = "child-handle-ignored"
           Find = '$err = [HordePowerThrottlingV1]::OptOut($h)'
           Replace = '$err = [HordePowerThrottlingV1]::OptOut([HordePowerThrottlingV1]::GetCurrentProcess())' }
    )
}
