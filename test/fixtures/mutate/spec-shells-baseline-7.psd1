@{
    Target = "test\fixtures\mutate\target-shells.ps1"
    Suite  = "test\fixtures\mutate\suite-fails-under-7.ps1"
    Shells = @("powershell", "pwsh")
    Mutations = @(
        @{ Name = "both-see"; Find = 'function Get-Two { return 2 }'; Replace = 'function Get-Two { return 3 }' }
    )
}
