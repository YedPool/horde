# Mutations of test/lib/Browser.ps1's PROFILE PATH rule (THE PROFILE'S PATH IS KEPT SHORT). Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\test-browser-profile.psd1
# test\test-browser-cleanup.ps1 must fail for each.
@{
    Target = "test\lib\Browser.ps1"
    Suite  = "test\test-browser-cleanup.ps1"
    Mutations = @(
        @{ Name = "a-too-deep-profile-is-started"
           Find = '    if ($profileDir.Length -gt $room) { throw'
           Replace = '    if ($false) { throw' }
        @{ Name = "the-long-leaf-is-back"
           Find = '[guid]::NewGuid().ToString("N").Substring(0, 8))'
           Replace = '[guid]::NewGuid().ToString("N"))' }
    )
}
