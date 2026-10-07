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
           Find = 'if ($null -ne $Open) { try { $Open.Flush($true) } catch { return "unconfirmed" } }'
           Replace = '' }
        @{ Name = "flush-of-the-buffer-only"
           Find = 'if ($null -ne $Open) { try { $Open.Flush($true) } catch { return "unconfirmed" } }'
           Replace = 'if ($null -ne $Open) { try { $Open.Flush($false) } catch { return "unconfirmed" } }' }
        @{ Name = "failed-flush-reads-as-moved"
           Find = 'if ($null -ne $Open) { try { $Open.Flush($true) } catch { return "unconfirmed" } }'
           Replace = 'if ($null -ne $Open) { try { $Open.Flush($true) } catch { } }' }
        @{ Name = "failed-flush-throws"
           Find = 'if ($null -ne $Open) { try { $Open.Flush($true) } catch { return "unconfirmed" } }'
           Replace = 'if ($null -ne $Open) { $Open.Flush($true) }' }
        @{ Name = "another-system-moved-anyway"
           Find = 'if ("" + $OsPlatform -cne "Win32NT") { throw ('
           Replace = 'if ($false) { throw (' }
    )
}
