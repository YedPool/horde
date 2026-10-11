# Mutations of core/FileAtomic.ps1's durable move to a free name (Move-HordeFileNewDurable). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\file-move-new.psd1
# Each breaks one thing its caller is told; test\test-file-move-new.ps1 must fail for every one.
#
# THE WRITE-THROUGH FLAG IS CAUGHT BY READING IT, NOT BY ITS EFFECT. A move without it behaves the same
# in every way a test can see; only a power cut tells them apart. The suite reads the flags the
# function hands over and finds them in the call, which is what "the flag is passed" can mean here.
@{
    Target = "core\FileAtomic.ps1"
    Suite  = "test\test-file-move-new.ps1"
    Mutations = @(
        @{ Name = "move-replaces"
           Find = '    return 0x8'
           Replace = '    return 0x9' }
        @{ Name = "move-not-written-through"
           Find = '    return 0x8'
           Replace = '    return 0x0' }
        @{ Name = "flags-written-at-the-call"
           Find = '[HordeNative.FileMove]::MoveFileEx($From, $To, (Get-HordeFileMoveNewFlags))'
           Replace = '[HordeNative.FileMove]::MoveFileEx($From, $To, 0x0)' }
        @{ Name = "taken-name-is-an-error"
           Find = 'if ($moveError -eq 80 -or $moveError -eq 183) { return "exists" }'
           Replace = '' }
        @{ Name = "any-failure-reads-as-taken"
           Find = 'if ($moveError -eq 80 -or $moveError -eq 183) { return "exists" }'
           Replace = 'return "exists"' }
        @{ Name = "any-failure-reads-as-moved"
           Find = 'throw (New-Object System.ComponentModel.Win32Exception($moveError))'
           Replace = 'return "moved"' }
        @{ Name = "no-flush-after-the-move"
           Find = 'if ($null -ne $Open -and (Confirm-HordeFileFlushed -Open $Open) -cne "confirmed") { return "unconfirmed" }'
           Replace = '' }
        @{ Name = "failed-flush-reads-as-moved"
           Find = 'if ($null -ne $Open -and (Confirm-HordeFileFlushed -Open $Open) -cne "confirmed") { return "unconfirmed" }'
           Replace = 'if ($null -ne $Open) { $null = Confirm-HordeFileFlushed -Open $Open }' }
        # --- the one flush path, and the confirming of a file that already exists ---
        @{ Name = "flush-of-the-buffer-only"
           Find = '    try { $Open.Flush($true) } catch { return "unconfirmed" }'
           Replace = '    try { $Open.Flush($false) } catch { return "unconfirmed" }' }
        @{ Name = "failed-flush-reads-as-confirmed"
           Find = '    try { $Open.Flush($true) } catch { return "unconfirmed" }'
           Replace = '    try { $Open.Flush($true) } catch { }' }
        @{ Name = "failed-flush-throws"
           Find = '    try { $Open.Flush($true) } catch { return "unconfirmed" }'
           Replace = '    $Open.Flush($true)' }
        @{ Name = "confirming-flushes-nothing"
           Find = '    try { return (Confirm-HordeFileFlushed -Open $held) } finally { $held.Dispose() }'
           Replace = '    try { return "confirmed" } finally { $held.Dispose() }' }
        @{ Name = "confirming-a-file-that-is-not-there-creates-it"
           Find = '    if (-not [System.IO.File]::Exists($Path)) { return "missing" }'
           Replace = '    if (-not [System.IO.File]::Exists($Path)) { [System.IO.File]::WriteAllBytes($Path, [byte[]]@()) }' }
        @{ Name = "confirming-truncates-the-file"
           Find = '$held = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write,'
           Replace = '$held = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write,' }
        @{ Name = "file-that-cannot-be-opened-reads-as-confirmed"
           Find = '    catch { return "unconfirmed" }'
           Replace = '    catch { return "confirmed" }' }
        @{ Name = "confirming-stands-in-a-readers-way"
           Find = '([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)) }'
           Replace = '[System.IO.FileShare]::None) }' }
        @{ Name = "another-system-moved-anyway"
           Find = 'if ("" + $OsPlatform -cne "Win32NT") { throw ('
           Replace = 'if ($false) { throw (' }
    )
}
