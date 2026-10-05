# core/FileAtomic - replace a file whole, in one step.
#
# WHY ITS OWN FILE. It was core/MetricsStore.ps1's (review of PR #70); the hub's mirror files need the same
# write (review of PR #86, F3: File.Replace failed while a reader held the mirror with ordinary read
# sharing, and Win32 ReplaceFile works in steps), so it moved here, unchanged, for both.
#
# No Set-StrictMode here: this file is dot-sourced (see core/Tristate.ps1).

function Move-HordeFileAtomic {
    # Rename -From over -To in ONE step: MoveFileEx with REPLACE_EXISTING and WRITE_THROUGH, a single
    # rename on NTFS. Review of PR #70 measured why File.Replace is not enough: Win32 ReplaceFile works in
    # steps, and one of 40 kills inside it left NO index - the new one only in its temp file. A rename is
    # all or nothing: a kill leaves the old file or the new one, never neither. A reader holding the file
    # without delete sharing makes the rename fail for a moment; it is tried again for up to 2 s.
    param([Parameter(Mandatory = $true)][string]$From, [Parameter(Mandatory = $true)][string]$To)
    if (-not ([System.Management.Automation.PSTypeName]"HordeNative.FileMove").Type) {
        Add-Type -Namespace HordeNative -Name FileMove -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);'
    }
    $err = 0
    for ($i = 0; $i -lt 20; $i++) {
        # 0x1 MOVEFILE_REPLACE_EXISTING, 0x8 MOVEFILE_WRITE_THROUGH.
        if ([HordeNative.FileMove]::MoveFileEx($From, $To, 0x9)) { return }
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Start-Sleep -Milliseconds 100
    }
    throw (New-Object System.ComponentModel.Win32Exception($err))
}
