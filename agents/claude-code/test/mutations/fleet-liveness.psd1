# Mutations of agents/claude-code/Fleet.ps1, hibernation's port of the restore guard. Run:
#   powershell -File tools\Mutate.ps1 -Spec agents\claude-code\test\mutations\fleet-liveness.psd1
# Each breaks one rule of the guard; agents\claude-code\test\test-fleet-liveness.ps1 must fail a check for every one.
@{
    Target = "agents\claude-code\Fleet.ps1"
    Suite  = "agents\claude-code\test\test-fleet-liveness.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "no-start-tolerance"
           Find = 'if ([Math]::Abs($expected - $actual) -le $script:ClaudeCodeFleetStartTolerance) { return "live" }'
           Replace = 'if ($expected -eq $actual) { return "live" }' }
        @{ Name = "unconfirmed-is-stopped"
           Find = 'return [pscustomobject]@{ state = "unknown"; kind = "unconfirmed";'
           Replace = 'return [pscustomobject]@{ state = "stopped"; kind = "unconfirmed";' }
        @{ Name = "empty-folder-trusted"
           Find = '$err = "no control files were found, so what is running cannot be established"'
           Replace = '$err = ""' }
        @{ Name = "unparseable-running-ignored"
           Find = 'if ($state -cne "dead" -and $err -eq "") { $err = "the control file of running process "'
           Replace = 'if ($false) { $err = "the control file of running process "' }
        @{ Name = "reading-error-ignored"
           Find = 'if ("" + $Snapshot.error -ne "") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "rotation-ignored"
           Find = 'if ($wanted -eq "" -or (ConvertTo-ClaudeCodeFleetCwd -Cwd $r.cwd) -ceq $wanted) {'
           Replace = 'if ($false) {' }
        @{ Name = "folder-case-matters"
           Find = 'return $n.TrimEnd("/").ToLowerInvariant()'
           Replace = 'return $n.TrimEnd("/")' }
        @{ Name = "since-ignored"
           Find = '$began -le $sinceTicks) { continue }'
           Replace = '$false) { continue }' }
        @{ Name = "unreadable-start-excluded"
           Find = '-and [long]::TryParse("" + $r.startTime, [ref]$began) -and $began -le $sinceTicks) { continue }'
           Replace = '-or $began -le $sinceTicks) { continue }' }
        @{ Name = "ignore-ignored"
           Find = 'if ($r.state -ceq "dead" -or @($Ignore) -ccontains $r.sessionId) { continue }'
           Replace = 'if ($r.state -ceq "dead") { continue }' }
        @{ Name = "first-folder-optional"
           Find = 'if ($i -eq 0) { return [pscustomobject]@{ records = @(); error = ("control directory not found: "'
           Replace = 'if ($false) { return [pscustomobject]@{ records = @(); error = ("control directory not found: "' }
        @{ Name = "scrub-too-narrow"
           Find = 'if ("" + $n -imatch ''\ACLAUDE'' -and'
           Replace = 'if ("" + $n -imatch ''\ACLAUDE_CODE_'' -and' }
        @{ Name = "resume-id-unchecked"
           Find = 'if ($SessionId -cnotmatch $script:ClaudeCodeFleetIdPattern) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "home-not-profile"
           Find = 'param([string]$ProfileDir = $env:USERPROFILE)'
           Replace = 'param([string]$ProfileDir = $env:HOME)' }
        @{ Name = "unreadable-file-has-no-pid"
           Find = 'if ($procId -cnotmatch ''\A[0-9]{1,10}\z'') { $procId = [System.IO.Path]::GetFileNameWithoutExtension("" + $f) }'
           Replace = 'if ($false) { }' }
        @{ Name = "own-process-not-matched"
           Find = '        if ($procPid -ne "") {'
           Replace = '        if ($false) {' }
        @{ Name = "since-without-process"
           Find = 'if ($procPid -ne "" -and $Since -is [datetime])'
           Replace = 'if ($Since -is [datetime])' }
        @{ Name = "folderless-passed-over"
           Find = 'if ((ConvertTo-ClaudeCodeFleetCwd -Cwd $r.cwd) -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "running-without-start"
           Find = 'cwd = $_.cwd; start = $_.startTime }'
           Replace = 'cwd = $_.cwd }' }
    )
}
