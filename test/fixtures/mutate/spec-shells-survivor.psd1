@{
    Target = "test\fixtures\mutate\target-shells.ps1"
    Suite  = "test\fixtures\mutate\suite-shells.ps1"
    Shells = @("powershell", "pwsh")
    Mutations = @(
        @{ Name = "only-7-sees"; Find = '-ceq "Core") { return 2 }'; Replace = '-ceq "Core") { return 7 }'; Expect = "survives"
           Reason = "Wrongly declared: 5.1 cannot see it, but 7 can." }
    )
}
