@{
    Target = "test\fixtures\mutate\target-shells.ps1"
    Suite  = "test\fixtures\mutate\suite-shells.ps1"
    Mutations = @(
        @{ Name = "only-7-sees"; Find = '-ceq "Core") { return 2 }'; Replace = '-ceq "Core") { return 7 }'; Expect = "survives"
           Reason = "With no Shells the suite runs under 5.1 alone, which never takes the Core branch." }
    )
}
