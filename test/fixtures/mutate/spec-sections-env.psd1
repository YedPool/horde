# The spec's own Environment already narrows the suite to two and three; a mutant mapped outside that
# would run a section the spec's whole run never does.
@{
    Target = "test\fixtures\mutate\target-sections.ps1"
    Suite  = "test\fixtures\mutate\suite-sections.ps1"
    Environment = @{ HORDE_SECTIONS = "two,three" }
    PassCodes = @(3)
    Mutations = @(
        @{ Name = "inside"; Find = 'return 2'; Replace = 'return 5'; Sections = @("two") }
        @{ Name = "outside"; Find = 'return 4'; Replace = 'return 7'; Sections = @("four") }
    )
}
