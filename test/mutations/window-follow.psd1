# Mutations of platform/windows/WindowFollow.ps1, the Windows follower of core/WindowFollowPort.ps1.
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\window-follow.psd1
# test\test-window-follow.ps1 must fail for each: it follows a real window of another process with a real
# window of its own, so this spec holds the native half too. Where a companion stands is the port's,
# and so are its mutants (test\mutations\window-follow-port.psd1).
#
# NOT MUTATED, each for its reason:
#   - the lines that undo a follow when Windows will not report the other window's moves: nothing here
#     can make it refuse. The rule that answer feeds is mutated (no-reports-of-moves-is-following).
#   - the scale read from the other window: the suite would catch it only on a screen that is not at
#     the ordinary scale.
#   - which of the other process's reports are counted: the other program has one window and no caret.
#   - a second start ending the first while it still follows.
#   - a stop that does not tell Windows to stop reporting: nothing a caller can see tells it apart (the
#     follow is forgotten, so a late report places nothing, and the next start stops the reports
#     before it asks for its own). Run once, 2026-10-07, it survived, and is left out for that reason.
#
# FAIL FAST: a mutant is caught at its first failed check, and this suite waits up to twenty seconds for
# each thing a broken follower never does.
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
           Find = 'SetWindowLongPtr(new IntPtr(companion), -8, new IntPtr(targetWindow));     // GWLP_HWNDPARENT: the other window owns ours'
           Replace = '' }
        @{ Name = "that-the-owner-was-set-is-assumed"
           Find = 'if (GetWindow(new IntPtr(companion), 4) != new IntPtr(targetWindow)) { return new int[] { 1, error }; }'
           Replace = '' }
        @{ Name = "an-owner-that-was-not-set-is-following"
           Find = 'if ($Code -eq 1) { return [pscustomobject]@{ state = "failed";'
           Replace = 'if ($Code -eq 1) { return [pscustomobject]@{ state = "following";' }
        @{ Name = "no-reports-of-moves-is-following"
           Find = 'if ($Code -eq 2) { return [pscustomobject]@{ state = "failed";'
           Replace = 'if ($Code -eq 2) { return [pscustomobject]@{ state = "following";' }
        @{ Name = "an-answer-nobody-knows-is-following"
           Find = 'return [pscustomobject]@{ state = "failed"; reason = ("the native half answered "'
           Replace = 'return [pscustomobject]@{ state = "following"; reason = ("the native half answered "' }
        @{ Name = "a-start-that-failed-is-kept-as-a-follow"
           Find = 'if ($started.state -cne "following") { return (New-HordeWindowFollowRecord -State "failed" -Reason $started.reason) }'
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