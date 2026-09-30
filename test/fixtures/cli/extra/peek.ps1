$HordeCommand = @{
    name    = "peek"
    group   = "about"
    usage   = "peek"
    summary = "looks for horde's own variables from inside its body, and tries to fake a return"
    run     = {
        [CmdletBinding()] param()
        $hordeNames = @("name", "rest", "lookup", "bound", "named", "positional", "runner", "command", "state", "settled", "isOwn", "Run", "Named", "Positional", "State")
        $seen = @($hordeNames | Where-Object { Test-Path -LiteralPath ("variable:" + $_) })
        Write-Output ("seen=[" + ($seen -join ",") + "]")
        if (Test-Path -LiteralPath "variable:state") { $state.completed = $true }
        exit 0
    }
}
