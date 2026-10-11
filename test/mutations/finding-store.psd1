# Mutations of core/FindingStore.ps1, the local writer of findings. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\finding-store.psd1
# Each breaks one thing the writer promises - only what reads is written, never over another file,
# nothing left behind, the home it was given - and test\test-finding.ps1 must fail a check for every one.
#
# NOT HERE: that the bytes reach the disk before the name does. That is core/FileAtomic.ps1's durable
# move, held by test\mutations\file-move-new.psd1; no test here can cut the power.
@{
    Target = "core\FindingStore.ps1"
    Suite  = "test\test-finding.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "refused-is-written"
           Find = '    if ($read.state -cne "read") { return'
           Replace = '    if ($false) { return' }
        @{ Name = "folder-made-before-reading"
           Find = '    $read = Read-HordeFindingText -Text $Text'
           Replace = '    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::Combine($HordeHome, "findings")); $read = Read-HordeFindingText -Text $Text' }
        @{ Name = "relative-home-used"
           Find = '    elseif (-not [System.IO.Path]::IsPathRooted($base)) { throw'
           Replace = '    elseif ($false) { throw' }
        @{ Name = "environment-home-ignored"
           Find = '    if ($base -eq "") { $base = Get-HordeHome }'
           Replace = '    if ($base -eq "") { $base = $env:HORDE_HOME + "-other" }' }
        @{ Name = "name-not-from-content"
           Find = '    $target = [System.IO.Path]::Combine($folder, (Get-HordeFindingFileName -Text $Text))'
           Replace = '    $target = [System.IO.Path]::Combine($folder, ("finding-" + [guid]::NewGuid().ToString("N") + ".json"))' }
        @{ Name = "overwrites"
           Find = '        $moved = Move-HordeFileNewDurable -From $tmpPath -To $target -Open $fs'
           Replace = '        $fs.Dispose(); [System.IO.File]::Copy($tmpPath, $target, $true); [System.IO.File]::Delete($tmpPath); $moved = "moved"' }
        @{ Name = "temp-left-behind"
           Find = '        if ($moved -cne "moved" -and $moved -cne "unconfirmed") { try { [System.IO.File]::Delete($tmpPath) } catch { } }'
           Replace = '' }
        @{ Name = "text-not-kept-exactly"
           Find = '    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)'
           Replace = '    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text.Trim())' }
        @{ Name = "exists-reads-as-written"
           Find = '    if ($moved -ceq "moved") { return'
           Replace = '    if ($moved -ceq "moved" -or $moved -ceq "exists") { return' }
        @{ Name = "folder-in-the-way-reads-as-exists"
           Find = 'if ($moved -ceq "exists" -and [System.IO.File]::Exists($target)) {'
           Replace = 'if ($moved -ceq "exists") {' }
        @{ Name = "name-from-part-of-the-text"
           Find = '[System.Text.Encoding]::ASCII.GetBytes($Text)) } finally'
           Replace = '[System.Text.Encoding]::ASCII.GetBytes($Text.Substring(0, 20))) } finally' }
    )
}
