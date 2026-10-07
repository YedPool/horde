# Every way a section map can be wrong before anything runs: a name the suite does not declare, an
# empty map, and a map on a suite that declares no sections.
@{
    Target = "test\fixtures\mutate\target-sections.ps1"
    Suite  = "test\fixtures\mutate\suite-sections.ps1"
    Mutations = @(
        @{ Name = "misspelt"; Find = 'return 2'; Replace = 'return 5'; Sections = @("tow") }
        @{ Name = "empty-map"; Find = 'return 3'; Replace = 'return 6'; Sections = @() }
        @{ Name = "good"; Find = 'return 4'; Replace = 'return 7'; Sections = @("four") }
    )
}
