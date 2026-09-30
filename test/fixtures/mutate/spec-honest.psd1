@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite.ps1"
    Mutations = @(
        @{ Name = "tested-rule"; Find = 'return 2'; Replace = 'return 3' }
        @{ Name = "known-gap"; Find = 'return "two"'; Replace = 'return "three"'; Expect = "survives"
           Reason = "The fixture suite deliberately never checks the label." }
    )
}
