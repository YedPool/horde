$HordeCommand = @{
    name    = "ungrouped"
    group   = "no-such-group"
    usage   = "ungrouped"
    summary = "names a group help does not list"
    run     = { [CmdletBinding()] param() "never" }
}
