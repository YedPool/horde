$HordeCommand = @{
    name      = "busy"
    group     = "about"
    usage     = "busy"
    summary   = "declares itself sustained; reports whether the dispatcher leaked core functions into it, then loads core itself and uses it"
    sustained = $true
    run       = {
        [CmdletBinding()] param()
        # Nothing of core may be visible before the command loads it: the dispatcher's opt-out runs in
        # a scope of its own (review of PR #79, point 5).
        Write-Output ("LEAKED " + $(if (Get-Command -Name New-HordePlatform -ErrorAction SilentlyContinue) { "yes" } else { "no" }))
        # Loaded here, as metrics loads what it uses, so $script: state lives where the functions run.
        $root = Get-HordeRoot
        foreach ($f in @("Tristate", "Platform")) { . (Join-Path $root ("core\" + $f + ".ps1")) }
        $s = Get-HordeThrottlingState
        Write-Output ("THROTTLE " + $s.state + " " + $s.value.controlMask + "/" + $s.value.stateMask + " valid=" + (Test-HordeAnswer $s))
        $refused = $false
        try { $null = New-HordePlatform -Name "x" -ProcessSpace "BOGUS space!" -ProcessTable { } } catch { $refused = $true }
        Write-Output ("BOGUS-SPACE refused=" + $refused)
    }
}
