$HordeCommand = @{
    name    = "exit-bare"
    group   = "about"
    usage   = "exit-bare"
    summary = "calls `exit` instead of returning or throwing"
    run     = {
        [CmdletBinding()] param()
        Write-Output "exit-bare started"
        exit
    }
}
