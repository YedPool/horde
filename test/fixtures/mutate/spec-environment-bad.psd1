@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite.ps1"
    # Only HORDE_ variables may be set by a spec: PATH or TEMP would change what every run means.
    Environment = @{ PATH = "C:\nowhere" }
    Mutations = @(
        @{ Name = "tested-rule"; Find = 'return 2'; Replace = 'return 3' }
    )
}
