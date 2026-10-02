# Mutations of core/Device.ps1. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\device.psd1
# Each breaks one rule the device id exists for; test\test-device.ps1 must fail for every one of
# them. The rules that matter most downstream: one id per home however many first calls race, an id
# never derived from the machine, and a file Horde cannot read refused rather than replaced - a new
# id over it would make the hub see a new device.
#
# The suite's racers run whatever copy of core/Device.ps1 they are given, and only ever on a home the
# suite made under %TEMP%; a mutant cannot reach the real home.
@{
    Target = "core\Device.ps1"
    Suite  = "test\test-device.ps1"
    Mutations = @(
        @{ Name = "create-overwrites"
           Find = '[System.IO.File]::Move($tmp, $file)'
           Replace = '[System.IO.File]::Copy($tmp, $file, $true)' }
        @{ Name = "loser-keeps-its-own-id"
           Find = '    $w = Read-HordeNodeFile -Path $file'
           Replace = '    $w = [pscustomobject]@{ deviceId = $id; deviceName = $name }' }
        @{ Name = "loser-says-it-created"
           Find = 'path = $file; created = $false; raced = $true }'
           Replace = 'path = $file; created = $true; raced = $true }' }
        @{ Name = "winner-says-it-did-not-create"
           Find = 'return [pscustomobject]@{ deviceId = $id; deviceName = $name; path = $file; created = $true; raced = $false }'
           Replace = 'return [pscustomobject]@{ deviceId = $id; deviceName = $name; path = $file; created = $false; raced = $false }' }
        @{ Name = "reader-says-it-created"
           Find = 'return [pscustomobject]@{ deviceId = $r.deviceId; deviceName = $r.deviceName; path = $file; created = $false; raced = $false }'
           Replace = 'return [pscustomobject]@{ deviceId = $r.deviceId; deviceName = $r.deviceName; path = $file; created = $true; raced = $false }' }
        @{ Name = "id-from-the-machine"
           Find = '$id = [guid]::NewGuid().ToString("D").ToLowerInvariant()'
           Replace = '$id = ("00000000-0000-4000-8000-" + ("{0:x12}" -f ([long]("$env:COMPUTERNAME".Length))))' }
        @{ Name = "id-upper-case"
           Find = '$id = [guid]::NewGuid().ToString("D").ToLowerInvariant()'
           Replace = '$id = [guid]::NewGuid().ToString("D").ToUpperInvariant()' }
        @{ Name = "unreadable-file-replaced"
           Find = '    if (-not $m.Success) { throw'
           Replace = '    if (-not $m.Success) { Remove-Item -LiteralPath $Path -Force; return (Get-HordeNode -HomeRoot (Split-Path -Parent (Split-Path -Parent $Path))) ; throw' }
        @{ Name = "line-not-anchored"
           Find = '$script:HordeNodeLinePattern = ''^\{"schemaVersion":1,'
           Replace = '$script:HordeNodeLinePattern = ''\{"schemaVersion":1,' }
        @{ Name = "id-pattern-ignores-case"
           Find = '$m = [regex]::Match($text, $script:HordeNodeLinePattern)'
           Replace = '$m = [regex]::Match($text, $script:HordeNodeLinePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)' }
        @{ Name = "non-ascii-bytes-decoded"
           Find = 'foreach ($b in $bytes) { if ($b -gt 0x7F) {'
           Replace = 'foreach ($b in $bytes) { if ($false) {' }
        @{ Name = "bytes-decoded-as-utf8"
           Find = '    foreach ($b in $bytes) { if ($b -gt 0x7F) {'
           Replace = '    $bytes = [System.Text.Encoding]::ASCII.GetBytes([System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)); foreach ($b in $bytes) { if ($b -gt 0x7F) {' }
        @{ Name = "folder-worked-around"
           Find = 'if (Test-Path -LiteralPath $Path -PathType Container) { throw'
           Replace = 'if (Test-Path -LiteralPath $Path -PathType Container) { Remove-Item -LiteralPath $Path -Recurse -Force; return (Get-HordeNode -HomeRoot (Split-Path -Parent (Split-Path -Parent $Path))); throw' }
        @{ Name = "home-ignored"
           Find = 'if ($HomeRoot -eq "") { $HomeRoot = Get-HordeHome }'
           Replace = 'if ($HomeRoot -eq "") { $HomeRoot = Join-Path $env:TEMP "horde-device-mutant-home" }' }
        @{ Name = "name-not-sanitised"
           Find = '$s = ($Text -replace ''[^A-Za-z0-9._-]'', ''-'') -replace ''^[^A-Za-z0-9]+'', '''''
           Replace = '$s = $Text' }
        @{ Name = "name-front-not-trimmed"
           Find = ' -replace ''^[^A-Za-z0-9]+'', '''''
           Replace = '' }
        @{ Name = "name-not-cut"
           Find = 'if ($s.Length -gt 64) { $s = $s.Substring(0, 64) }'
           Replace = '' }
        @{ Name = "empty-name-kept"
           Find = 'if ($s -eq "") { return "node" }'
           Replace = '' }
        @{ Name = "any-io-error-read-as-lost-race"
           Find = 'if ([System.IO.File]::Exists($file)) { break }'
           Replace = 'break'
           Expect = "survives"
           Reason = "a rename that fails for a reason other than a lost race then reads the missing node.json, which throws too; only the message differs, and no test can make the rename fail that way without racing the filesystem" }
        @{ Name = "rename-not-retried"
           Find = '$script:HordeNodeMoveTries = 5'
           Replace = '$script:HordeNodeMoveTries = 1'
           Expect = "survives"
           Reason = "the retry is for a scanner briefly holding the candidate open; a test cannot hold a candidate whose name is a fresh GUID chosen inside the call, so the count is carried as a comment" }
        @{ Name = "candidate-not-flushed-to-disk"
           Find = '$fs.Flush($true)'
           Replace = '$fs.Flush()'
           Expect = "survives"
           Reason = "what WriteThrough and Flush(true) prevent is an empty node.json after a power cut, which no test can cause" }
        @{ Name = "existing-file-not-read-first"
           Find = '    if (Test-Path -LiteralPath $file) {'
           Replace = '    if ($false) {' }
        @{ Name = "loser-leaves-its-candidate"
           Find = 'if (-not $won -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }'
           Replace = '' }
        @{ Name = "line-end-not-absolute"
           Find = ')"\}(\r?\n)?\z'''
           Replace = ')"\}(\r?\n)?$''' }
        @{ Name = "name-not-from-the-computer"
           Find = '$name = ConvertTo-HordeDeviceName -Text "$env:COMPUTERNAME"'
           Replace = '$name = "node"' }
    )
}
