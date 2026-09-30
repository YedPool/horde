$HordeCommand = @{
    name    = "nested-call"
    group   = "about"
    usage   = "nested-call [<word>]"
    summary = "calls horde from inside its own body, with a colon value"
    run     = {
        [CmdletBinding()] param([Parameter(Position = 0)][string]$Word = "")
        & (Join-Path (Get-HordeRoot) "horde.ps1") echo-args -Json:$false
    }
}
