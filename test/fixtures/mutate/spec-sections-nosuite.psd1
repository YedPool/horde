# A section map on a suite that declares no sections: nothing it names can exist.
@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite.ps1"
    Mutations = @(
        @{ Name = "mapped-nowhere"; Find = 'return 2'; Replace = 'return 3'; Sections = @("two") }
    )
}
