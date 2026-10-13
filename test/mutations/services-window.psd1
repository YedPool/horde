# Mutations of the window close in platform/windows/Services.ps1. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\services-window.psd1
# Each lets a close be sent where it must not, or says one was sent that was not;
# test\test-services-window.ps1 must fail for every one. That suite needs a desktop, and passes with
# exit 3 where there is none, having checked only what needs no window.
@{
    Target = "platform\windows\Services.ps1"
    Suite  = "test\test-services-window.ps1"
    Mutations = @(
        @{ Name = "close-sent-to-another-process"
           Find = '        if (owner != processId) { return 2; }'
           Replace = '' }
        @{ Name = "non-window-reported-asked"
           Find = '        if (!IsWindow(window)) { return 1; }'
           Replace = '        if (!IsWindow(window)) { return 0; }' }
        @{ Name = "nothing-posted"
           Find = 'if (!PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero)) {'
           Replace = 'if (false) {' }
        @{ Name = "wrong-message"
           Find = 'if (!PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero)) {'
           Replace = 'if (!PostMessage(window, 0x0000, IntPtr.Zero, IntPtr.Zero)) {' }
        @{ Name = "foreign-window-is-unknown"
           Find = 'if ($result -eq 2) { return (New-HordeAbsent -Note ("window " + $Handle + " is not a window of process "'
           Replace = 'if ($result -eq 2) { return (New-HordeUnknown -Reason ("window " + $Handle + " is not a window of process "' }
        @{ Name = "close-not-registered"
           Find = '        CloseWindow = { param($ProcessId, $Handle) Close-HordeWindowsServiceWindow -ProcessId $ProcessId -Handle $Handle }'
           Replace = '' }
    )
}
