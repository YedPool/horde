@{
    Target = "test\fixtures\mutate\target.ps1"
    Suite  = "test\fixtures\mutate\suite-hangs.ps1"
    Mutations = @( @{ Name = "no-op"; Find = 'return 2'; Replace = 'return 2 ' } )
}
