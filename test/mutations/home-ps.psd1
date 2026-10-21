# Mutations of core/Home.ps1 (T-0299): the one resolution order (HORDE_HOME, then the pointer file, then the default),
# the pointer's refusals, and the atomic set / clear. test\test-home.ps1 must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\home-ps.psd1
@{
    Target = "core\Home.ps1"
    Suite  = "test\test-home.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "horde-home-ignored"
           Find = 'if ($set -ne "") {'
           Replace = 'if ($false) {' }
        @{ Name = "relative-horde-home-accepted"
           Find = 'if (-not (Test-HordeHomeRooted $set)) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "pointer-ignored"
           Find = 'if (Test-Path -LiteralPath $pointer) {'
           Replace = 'if ($false) {' }
        @{ Name = "bad-pointer-skipped"
           Find = 'if (-not $r.ok) { throw $r.message }'
           Replace = 'if (-not $r.ok) { return [pscustomobject]@{ path = (Join-Path "$env:USERPROFILE".Trim() ".horde"); source = "default" } }' }
        @{ Name = "default-folder-changed"
           Find = 'return [pscustomobject]@{ path = (Join-Path "$env:USERPROFILE".Trim() ".horde"); source = "default" }'
           Replace = 'return [pscustomobject]@{ path = (Join-Path "$env:USERPROFILE".Trim() ".horde2"); source = "default" }' }
        @{ Name = "non-ascii-accepted"
           Find = 'if ($b -gt 0x7E -or ($b -lt 0x20 -and $b -ne 0x09 -and $b -ne 0x0A -and $b -ne 0x0D))'
           Replace = 'if ($false)' }
        @{ Name = "version-unchecked"
           Find = '-or $v.Value -ne 1)'
           Replace = '-or $false)' }
        @{ Name = "missing-hordehome-accepted"
           Find = 'if ($null -eq $h -or $h.Value -isnot [string] -or $h.Value.Trim() -eq "")'
           Replace = 'if ($false)' }
        @{ Name = "relative-pointer-target-accepted"
           Find = 'if (-not (Test-HordeHomeRooted $target))'
           Replace = 'if ($false)' }
        @{ Name = "missing-folder-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $target -PathType Container))'
           Replace = 'if ($false)' }
        @{ Name = "set-accepts-relative-path"
           Find = 'if (-not (Test-HordeHomeRooted $p))'
           Replace = 'if ($false)' }
        @{ Name = "set-accepts-missing-folder"
           Find = 'if (-not (Test-Path -LiteralPath $p -PathType Container))'
           Replace = 'if ($false)' }
        @{ Name = "set-accepts-folder-without-fleet-db"
           Find = 'if (-not (Test-Path -LiteralPath (Join-Path $full "fleet.db") -PathType Leaf))'
           Replace = 'if ($false)' }
        @{ Name = "set-accepts-non-ascii-path"
           Find = 'if ($p -notmatch ''\A[\x20-\x7E]+\z'' -or $p.Contains(''"''))'
           Replace = 'if ($false)' }
        @{ Name = "set-writes-in-place"
           Find = 'Move-HordeFileAtomic -From $temp -To $file'
           Replace = '[System.IO.File]::WriteAllBytes($file, [System.Text.Encoding]::ASCII.GetBytes($json))' }
        @{ Name = "set-writes-wrong-version"
           Find = '$json = ''{"v":1,"hordeHome":"'''
           Replace = '$json = ''{"v":2,"hordeHome":"''' }
        @{ Name = "horde-home-rooted-test-too-loose"
           Find = 'if (-not (Test-HordeHomeRooted $set)) { throw' 
           Replace = 'if (-not [System.IO.Path]::IsPathRooted($set)) { throw' }
        @{ Name = "clear-leaves-the-pointer"
           Find = 'Remove-Item -LiteralPath $file -Force; $removed = $true'
           Replace = '$removed = $true' }
    )
}
