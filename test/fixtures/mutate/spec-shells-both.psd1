@{
    Target = "test\fixtures\mutate\target-shells.ps1"
    Suite  = "test\fixtures\mutate\suite-shells.ps1"
    Shells = @("powershell", "pwsh")
    Mutations = @(
        @{ Name = "only-7-sees"; Find = '-ceq "Core") { return 2 }'; Replace = '-ceq "Core") { return 7 }' }
        @{ Name = "both-see"; Find = 'function Get-Two { return 2 }'; Replace = 'function Get-Two { return 3 }' }
    )
}
