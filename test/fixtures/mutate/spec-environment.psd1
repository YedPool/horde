@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite-env.ps1"
    # Set for this spec's runs only, and cleared afterwards.
    Environment = @{ HORDE_MUTATE_FIXTURE_ENV = "set" }
    Mutations = @(
        @{ Name = "tested-rule"; Find = 'return 2'; Replace = 'return 3' }
    )
}
