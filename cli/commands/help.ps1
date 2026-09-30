$HordeCommand = @{
    name    = "help"
    group   = "about"
    usage   = "help"
    summary = "every command, generated from the command files themselves"
    run     = {
        [CmdletBinding()] param()
        Format-HordeHelp | ForEach-Object { Write-Output $_ }
    }
}
