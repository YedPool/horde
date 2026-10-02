@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite-partial.ps1"
    Environment = @{ HORDE_MUTATE_FIXTURE_ENV = "set" }
    Mutations = @(
        @{ Name = "tested-rule"; Find = 'return 2'; Replace = 'return 3' }
    )
}
