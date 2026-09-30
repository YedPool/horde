$HordeCommand = @{
    name    = "echo-args"
    group   = "about"
    usage   = "echo-args [<target>] [-Json] [-Count <n>] [-Verb <word>]"
    summary = "reports how its arguments were bound"
    run     = {
        [CmdletBinding()] param([Parameter(Position = 0)][string]$Target = "", [Alias("AsJson")][switch]$Json, [int]$Count = 0, [string]$Verb = "")
        Write-Output ("target=[" + $Target + "] json=" + $Json + " count=" + $Count)
    }
}
