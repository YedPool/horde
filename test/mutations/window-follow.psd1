# Mutations of platform/windows/WindowFollow.ps1, the Windows follower of core/WindowFollowPort.ps1.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\window-follow.psd1
# test\test-window-follow.ps1 must fail for each. Where a companion stands is the port's, and so are
# its mutants (test\mutations\window-follow-port.psd1).
@{
    Target = "platform\windows\WindowFollow.ps1"
    Suite  = "test\test-window-follow.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "not-registered-by-being-loaded"
           Find = 'Register-HordeWindowFollower @blocks'
           Replace = '' }
        @{ Name = "registered-for-no-system"
           Find = 'Applies   = { Test-HordeIsWindows }'
           Replace = 'Applies   = { $false }' }
        @{ Name = "compiled-when-loaded"
           Find = 'function Initialize-HordeWindowsFollowType {'
           Replace = 'Add-Type -TypeDefinition (Get-HordeWindowsFollowSource); function Initialize-HordeWindowsFollowType {' }
        @{ Name = "a-window-that-is-not-there-is-followed"
           Find = 'if (-not [HordeWindowsFollowV1]::Exists($Target)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "the-other-window-is-not-made-the-owner"
           Find = 'SetWindowLongPtr(new IntPtr(companion), -8, target);     // GWLP_HWNDPARENT: the other window owns ours'
           Replace = '' }
        @{ Name = "left-under-the-other-window"
           Find = 'if (above != new IntPtr(companion)) { SetWindowPos(new IntPtr(companion), above, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); }'
           Replace = '' }
        @{ Name = "standing-above-takes-the-keyboard"
           Find = 'if (above != new IntPtr(companion)) { SetWindowPos(new IntPtr(companion), above, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010); }'
           Replace = 'if (above != new IntPtr(companion)) { SetWindowPos(new IntPtr(companion), above, 0, 0, 0, 0, 0x0001 | 0x0002); }' }
        @{ Name = "placing-takes-the-keyboard"
           Find = 'return SetWindowPos(new IntPtr(h), IntPtr.Zero, x, y, cx, cy, 0x0004 | 0x0010); }'
           Replace = 'return SetWindowPos(new IntPtr(h), IntPtr.Zero, x, y, cx, cy, 0x0004); }' }
        @{ Name = "another-report-is-listened-for"
           Find = 'hook = SetWinEventHook(0x800B, 0x800B, IntPtr.Zero,'
           Replace = 'hook = SetWinEventHook(0x8005, 0x8005, IntPtr.Zero,' }
        @{ Name = "a-report-of-a-move-places-nothing"
           Find = 'if (moved != null) { moved(); }'
           Replace = '' }
        @{ Name = "placed-from-a-minimised-windows-rectangle"
           Find = 'if ($Place -and -not [HordeWindowsFollowV1]::Minimised($s.target)) {'
           Replace = 'if ($Place) {' }
        @{ Name = "asking-places"
           Find = 'if ($Place -and -not [HordeWindowsFollowV1]::Minimised($s.target)) {'
           Replace = 'if (-not [HordeWindowsFollowV1]::Minimised($s.target)) {' }
        @{ Name = "a-window-that-is-gone-is-still-followed"
           Find = 'if (-not [HordeWindowsFollowV1]::Exists($s.target)) {'
           Replace = 'if ($false) {' }
        @{ Name = "another-programs-window-is-placed"
           Find = 'if ([HordeWindowsFollowV1]::ProcessOf($Companion) -ne [uint32]$PID) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-companion-that-is-no-window-is-looked-up"
           Find = 'if (-not [HordeWindowsFollowV1]::Exists($Companion)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "the-place-is-not-recorded"
           Find = '                $s.placed = $at.value'
           Replace = '' }
        @{ Name = "stopping-leaves-it-owned"
           Find = 'if ($s.state -ceq "following") { [HordeWindowsFollowV1]::Unhook(); [HordeWindowsFollowV1]::Disown($s.companion) }'
           Replace = 'if ($s.state -ceq "following") { [HordeWindowsFollowV1]::Unhook() }' }
        @{ Name = "letting-go-changes-nothing"
           Find = 'if ($null -ne $s -and $s.state -ceq "following") { Set-HordeWindowsFollowFree -State "free"'
           Replace = 'if ($false) { Set-HordeWindowsFollowFree -State "free"' }
        @{ Name = "a-lost-window-is-called-free"
           Find = 'Set-HordeWindowsFollowFree -State "lost" -Reason'
           Replace = 'Set-HordeWindowsFollowFree -State "free" -Reason' }
    )
}