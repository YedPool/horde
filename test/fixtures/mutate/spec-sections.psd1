# A spec that maps mutants to the suite's sections: one the map kills, one the map misses and the
# whole suite catches, one that survives everything, and one with no map. The map is used only under
# -Fast; a plain run gives every one of them the whole suite.
@{
    Target = "test\fixtures\mutate\target-sections.ps1"
    Suite  = "test\fixtures\mutate\suite-sections.ps1"
    Mutations = @(
        @{ Name = "mapped"; Find = 'return 2'; Replace = 'return 5'; Sections = @("two") }
        @{ Name = "map-miss"; Find = 'return 3'; Replace = 'return 6'; Sections = @("two") }
        @{ Name = "survivor"; Find = 'return "two"'; Replace = 'return "three"'; Sections = @("four"); Expect = "survives"
           Reason = "The fixture suite deliberately never checks the label." }
        @{ Name = "unmapped"; Find = 'return 4'; Replace = 'return 7' }
    )
}
