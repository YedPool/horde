@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite.ps1"
    Mutations = @( @{ Name = "throws-at-run-time"; Find = 'function Get-Two { return 2 }'; Replace = 'function Get-Two { throw "broken on purpose" }' } )
}
