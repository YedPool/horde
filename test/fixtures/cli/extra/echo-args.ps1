$HordeCommand = @{
    name    = "echo-args"
    group   = "about"
    usage   = "echo-args [<target>] [-Json] [-Count <n>]"
    summary = "reports how its arguments were bound"
    run     = {
        [CmdletBinding()] param([Parameter(Position = 0)][string]$Target = "", [switch]$Json, [int]$Count = 0)
        Write-Output ("target=[" + $Target + "] json=" + $Json + " count=" + $Count)
    }
}
