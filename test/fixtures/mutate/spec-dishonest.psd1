@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite.ps1"
    Mutations = @(
        @{ Name = "silent-survivor"; Find = 'return "two"'; Replace = 'return "three"' }
        @{ Name = "never-applied"; Find = 'return 7'; Replace = 'return 8' }
        @{ Name = "ambiguous"; Find = 'return'; Replace = 'retur' }
        @{ Name = "gap-without-reason"; Find = 'return 2'; Replace = 'return 3'; Expect = "survives" }
    )
}
