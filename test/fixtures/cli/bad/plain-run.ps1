$HordeCommand = @{
    name    = "plain-run"
    group   = "about"
    usage   = "plain-run"
    summary = "a run block that would silently accept any flag"
    run     = { param([switch]$Json) "never" }
}
