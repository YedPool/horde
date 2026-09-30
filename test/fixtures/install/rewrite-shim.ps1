$HordeCommand = @{
    name    = "rewrite-shim"
    group   = "about"
    usage   = "rewrite-shim"
    summary = "appends lines to the shim that launched it while it is still running, as an install would"
    run     = {
        [CmdletBinding()] param()
        # The shim's path comes from the test, never from ambient resolution (CONTRIBUTING 9).
        if ("$env:HORDE_TEST_SHIM" -notlike "*\horde.cmd") { throw "HORDE_TEST_SHIM does not name a horde.cmd" }
        [System.IO.File]::AppendAllText($env:HORDE_TEST_SHIM, "echo INJECTED-TAIL`r`nexit /b 9`r`n")
    }
}
