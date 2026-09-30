@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite-helper.ps1"
    Mutations = @( @{ Name = "throws-under-the-helper"; Find = 'function Get-Two { return 2 }'; Replace = 'function Get-Two { throw "broken on purpose" }' } )
}
