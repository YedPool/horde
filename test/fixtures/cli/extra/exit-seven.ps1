$HordeCommand = @{
    name    = "exit-seven"
    group   = "about"
    usage   = "exit-seven"
    summary = "calls `exit 7` instead of returning or throwing"
    run     = {
        [CmdletBinding()] param()
        Write-Output "exit-seven started"
        exit 7
    }
}
