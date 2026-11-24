# Mutations of core/NightlyNet.ps1's run-file names (Get-HordeNightlyFileStem). Night 2026-11-23 the net FAILED
# writing a bisect .nodes file named after a whole pytest node id (281 characters of path). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-file-stem.psd1
@{
    Target = "core\NightlyNet.ps1"
    Suite  = "test\test-nightly-net.ps1"
    Mutations = @(
        @{ Name = "long-tag-never-cut"
           Find = 'if ($safe.Length -le $MaxLength) { return $safe }'
           Replace = 'if ($true) { return $safe }' }
        @{ Name = "cut-without-the-hash"
           Find = 'return ($safe.Substring(0, $MaxLength - 13) + "-" + $hex.Substring(0, 12))'
           Replace = 'return ($safe.Substring(0, $MaxLength - 13))' }
        @{ Name = "hash-of-the-cut-not-the-whole-tag"
           Find = '$hex = -join @($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Tag))'
           Replace = '$hex = -join @($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($safe.Substring(0, $MaxLength - 13)))' }
    )
}
