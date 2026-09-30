$HordeCommand = @{
    name    = "native-fail"
    group   = "about"
    usage   = "native-fail"
    summary = "runs a program that fails, and does not check it"
    run     = {
        [CmdletBinding()] param()
        Write-Output "native-fail started"
        & cmd.exe /c exit 3
    }
}
