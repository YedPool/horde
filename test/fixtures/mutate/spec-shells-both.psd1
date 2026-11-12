@{
    Target = "test\fixtures\mutate\target-shells.ps1"
    Suite  = "test\fixtures\mutate\suite-shells.ps1"
    Shells = @("powershell", "pwsh")
    Mutations = @(
        @{ Name = "only-7-sees"; Find = '-ceq "Core") { return 2 }'; Replace = '-ceq "Core") { return 7 }' }
        @{ Name = "broken-under-5-1-caught-under-7"; Find = '-ceq "Core") { return 3 } return 3 }'; Replace = '-ceq "Core") { return 4 } throw "broken under 5.1" }' }
        @{ Name = "both-see"; Find = 'function Get-Two { return 2 }'; Replace = 'function Get-Two { return 3 }' }
    )
}
