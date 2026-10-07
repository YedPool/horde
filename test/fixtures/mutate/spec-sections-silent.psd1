# A map whose sections exit 1 unmutated, printing nothing: not a pass.
@{
    Target = "test\fixtures\mutate\target-sections.ps1"
    Suite  = "test\fixtures\mutate\suite-sections-noisy.ps1"
    Mutations = @(
        @{ Name = "mapped-to-a-silent-section"; Find = 'return 2'; Replace = 'return 5'; Sections = @("silent") }
    )
}
