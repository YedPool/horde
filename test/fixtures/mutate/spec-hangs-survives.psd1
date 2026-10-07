# A mutant declared to survive that hangs the suite: a timeout is never a survival.
@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite-hangs-when-mutated.ps1"
    Mutations = @(
        @{ Name = "hangs"; Find = 'return 2'; Replace = 'return 3'; Expect = "survives"
           Reason = "Declared to survive, so that only the timeout rule can make it bad." }
    )
}
