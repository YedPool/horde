# Mutations that take a load away from a core file. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\core-load.psd1
# test\test-core-load.ps1 must fail for every one: each makes a core file call a function it no longer
# loads, the class of #109's bug.
@{
    Target = "core\NodeEngineLayers.ps1"
    Suite  = "test\test-core-load.ps1"
    Mutations = @(
        @{ Name = "policy-file-not-loaded"
           Find = '. (Join-Path $PSScriptRoot "NodePolicy.ps1")'
           Replace = '' }
    )
}
