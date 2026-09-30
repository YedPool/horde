@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite.ps1"
    Mutations = @( @{ Name = "breaks-the-file"; Find = 'function Get-Two { return 2 }'; Replace = 'function Get-Two { return 2 ' } )
}
