$HordeCommand = @{
    name    = "flow"
    group   = "about"
    usage   = "flow <how>"
    summary = "leaves its body with break, continue or a labelled break, instead of returning"
    run     = {
        [CmdletBinding()] param([Parameter(Position = 0, Mandatory = $true)][string]$How)
        Write-Output "flow started"
        if ($How -eq "break") { & cmd.exe /c exit 3; break }
        if ($How -eq "continue") { continue }
        if ($How -eq "label") { break nowhere }
        Write-Output "flow returned"
    }
}
