# The review of #115 (round 2): a mutant on the path a section takes only when run alone. Its section
# catches it; the whole suite, where the cache is warm, does not - it is a survivor.
@{
    Target = "test\fixtures\mutate\target-cache.ps1"
    Suite  = "test\fixtures\mutate\suite-sections-cache.ps1"
    Mutations = @(
        @{ Name = "cold-path"; Find = 'return (2 + 3)'; Replace = 'return (2 + 4)'; Sections = @("use") }
    )
}
