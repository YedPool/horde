# A mutant its section passes and whose whole rerun exits 3: the rerun is not a pass, so it broke.
@{
    Target = "test\fixtures\mutate\target-sections.ps1"
    Suite  = "test\fixtures\mutate\suite-sections-exit3.ps1"
    Mutations = @(
        @{ Name = "rerun-exits-3"; Find = 'return 4'; Replace = 'return 7'; Sections = @("two") }
    )
}
