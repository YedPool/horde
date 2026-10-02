@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite-partial.ps1"
    Environment = @{ HORDE_MUTATE_FIXTURE_ENV = "set" }
    # The suite passes with 3 when it skips part of itself; only this spec says 3 is a pass.
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "tested-rule"; Find = 'return 2'; Replace = 'return 3' }
    )
}
