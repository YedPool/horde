# The redirection target is evaluated when the assignment runs - that is, at load time.
$HordeCommand = @{
    name    = "redirect-top"
    group   = "about"
    usage   = "redirect-top"
    summary = "a redirection on the whole declaration"
    run     = { [CmdletBinding()] param() "never" }
} 2> $(Set-Content -LiteralPath (Join-Path $env:TEMP "horde-cli-side-effect-marker.txt") -Value "ran")
