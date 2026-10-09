# Mutations of platform/windows/Scale.ps1, the one owner of "this process draws at the screen's real scale".
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\windows-scale.psd1
# Each breaks the call, the read, or a rule that turns Windows' answer into ours;
# test\test-windows-scale.ps1 must fail for every one.
#
# NOT MUTATED, because nothing on this machine can reach them: the two catch lines of the native half
# (a Windows without the entry point, a system without user32). The rules their answers feed are
# mutated below (no-such-call-*, cannot-be-asked-*).
@{
    Target = "platform\windows\Scale.ps1"
    Suite  = "test\test-windows-scale.ps1"
    Mutations = @(
        @{ Name = "asks-for-the-first-per-monitor"
           Find = 'if (SetProcessDpiAwarenessContext(new IntPtr(-4))) { return new int[] { 1, 0 }; }'
           Replace = 'if (SetProcessDpiAwarenessContext(new IntPtr(-3))) { return new int[] { 1, 0 }; }' }
        @{ Name = "asks-for-system-awareness"
           Find = 'if (SetProcessDpiAwarenessContext(new IntPtr(-4))) { return new int[] { 1, 0 }; }'
           Replace = 'if (SetProcessDpiAwarenessContext(new IntPtr(-2))) { return new int[] { 1, 0 }; }' }
        @{ Name = "taken-told-as-refused"
           Find = 'if (SetProcessDpiAwarenessContext(new IntPtr(-4))) { return new int[] { 1, 0 }; }'
           Replace = 'if (SetProcessDpiAwarenessContext(new IntPtr(-4))) { return new int[] { 0, 0 }; }' }
        @{ Name = "refusal-error-not-read"
           Find = 'return new int[] { 0, Marshal.GetLastWin32Error() };'
           Replace = 'return new int[] { 0, 0 };' }
        @{ Name = "last-error-not-kept"
           Find = '[DllImport("user32.dll", SetLastError = true)] static extern bool SetProcessDpiAwarenessContext(IntPtr value);'
           Replace = '[DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);' }
        @{ Name = "read-names-the-next-context"
           Find = 'if (AreDpiAwarenessContextsEqual(context, new IntPtr(-i))) { return i; }'
           Replace = 'if (AreDpiAwarenessContextsEqual(context, new IntPtr(-i))) { return i + 1; }' }
        @{ Name = "read-stops-before-the-second-version"
           Find = 'for (int i = 1; i <= 5; i++)'
           Replace = 'for (int i = 1; i <= 3; i++)' }
        @{ Name = "refused-told-as-applied"
           Find = 'if ($Taken -eq 1) { return'
           Replace = 'if ($Taken -eq 0) { return' }
        @{ Name = "no-such-call-not-told-apart"
           Find = 'if ($Taken -eq -1) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "already-is-another-error"
           Find = 'if ($ErrorCode -eq 5) { return'
           Replace = 'if ($ErrorCode -eq 87) { return' }
        @{ Name = "every-refusal-is-already"
           Find = 'if ($ErrorCode -eq 5) { return'
           Replace = 'if ($true) { return' }
        @{ Name = "refusal-reason-loses-its-number"
           Find = 'reason = ("Windows refused it, error " + $ErrorCode)'
           Replace = 'reason = "Windows refused it"' }
        @{ Name = "a-state-left-off-the-list"
           Find = 'return @("applied", "already", "unavailable")'
           Replace = 'return @("applied", "already")' }
        @{ Name = "two-names-swapped"
           Find = '1 = "unaware"; 2 = "system";'
           Replace = '1 = "system"; 2 = "unaware";' }
        @{ Name = "first-per-monitor-not-real-scale"
           Find = 'if ($Code -eq 3 -or $Code -eq 4) { $real = "yes" }'
           Replace = 'if ($Code -eq 4) { $real = "yes" }' }
        @{ Name = "second-per-monitor-not-real-scale"
           Find = 'if ($Code -eq 3 -or $Code -eq 4) { $real = "yes" }'
           Replace = 'if ($Code -eq 3) { $real = "yes" }' }
        @{ Name = "every-awareness-real-scale"
           Find = 'if ($Code -eq 3 -or $Code -eq 4) { $real = "yes" }'
           Replace = 'if ($true) { $real = "yes" }' }
        @{ Name = "unknown-number-not-refused"
           Find = 'if (-not $names.ContainsKey($Code)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "cannot-be-asked-not-told-apart"
           Find = 'if ($Code -eq -1) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "compiled-when-loaded"
           Find = 'function Enable-HordeWindowsRealScale {'
           Replace = 'Initialize-HordeWindowsScaleType; function Enable-HordeWindowsRealScale {' }
        @{ Name = "compile-errors-reach-the-caller"
           Find = 'Add-Type -TypeDefinition (Get-HordeWindowsScaleSource) -ErrorAction Stop'
           Replace = 'Add-Type -TypeDefinition (Get-HordeWindowsScaleSource)' }
        @{ Name = "read-not-asked"
           Find = 'return (ConvertTo-HordeWindowsScaleAwareness -Code ([HordeWindowsScaleV1]::Read()))'
           Replace = 'return (ConvertTo-HordeWindowsScaleAwareness -Code 4)' }
        @{ Name = "read-failure-thrown"
           Find = '} catch { return [pscustomobject]@{ awareness = "unknown"; realScale = "unknown"; reason = ("the awareness could not be read: " + $_.Exception.Message) } }'
           Replace = '} catch { throw }' }
        @{ Name = "read-failure-loses-its-cause"
           Find = 'reason = ("the awareness could not be read: " + $_.Exception.Message) } }'
           Replace = 'reason = "the awareness could not be read: " } }' }
        @{ Name = "call-not-made"
           Find = '$asked = [HordeWindowsScaleV1]::Apply()'
           Replace = '$asked = @(1, 0)' }
        @{ Name = "call-failure-thrown"
           Find = '} catch { $did = [pscustomobject]@{ state = "unavailable"; reason = ("the call could not be made: " + $_.Exception.Message) } }'
           Replace = '} catch { throw }' }
        @{ Name = "call-failure-loses-its-cause"
           Find = 'reason = ("the call could not be made: " + $_.Exception.Message) } }'
           Replace = 'reason = "the call could not be made: " } }' }
        @{ Name = "answer-says-applied-whatever-happened"
           Find = 'return [pscustomobject]@{ state = $did.state; awareness = $now.awareness; realScale = $now.realScale; reason = $did.reason }'
           Replace = 'return [pscustomobject]@{ state = "applied"; awareness = $now.awareness; realScale = $now.realScale; reason = $did.reason }' }
        @{ Name = "answer-says-aware-without-reading"
           Find = 'return [pscustomobject]@{ state = $did.state; awareness = $now.awareness; realScale = $now.realScale; reason = $did.reason }'
           Replace = 'return [pscustomobject]@{ state = $did.state; awareness = "per-monitor-v2"; realScale = "yes"; reason = $did.reason }' }
        @{ Name = "answer-loses-its-reason"
           Find = 'return [pscustomobject]@{ state = $did.state; awareness = $now.awareness; realScale = $now.realScale; reason = $did.reason }'
           Replace = 'return [pscustomobject]@{ state = $did.state; awareness = $now.awareness; realScale = $now.realScale; reason = "" }' }
    )
}
