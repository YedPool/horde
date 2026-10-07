# A map to a section that fails when run without the one before it: every mutant would read as caught.
@{
    Target = "test\fixtures\mutate\target-sections.ps1"
    Suite  = "test\fixtures\mutate\suite-sections-dependent.ps1"
    Mutations = @(
        @{ Name = "mapped-to-a-dependent-section"; Find = 'return 4'; Replace = 'return 7'; Sections = @("use") }
    )
}
