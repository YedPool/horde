# Mutations of the ssh transport's adapter. Run: powershell -File tools\Mutate.ps1 -Spec transports\ssh\test\mutations\transport.psd1
# Each breaks one rule transports\ssh\Transport.ps1 holds; transports\ssh\test\test-ssh.ps1 must fail for every one.
# No mutant here can reach a real server: the suite dials only a closed loopback port and its own
# stand-in children, and a mutant that adds a program start does so behind if ($false).
@{
    Target = "transports\ssh\Transport.ps1"
    Suite  = "transports\ssh\test\test-ssh.ps1"
    Mutations = @(
        @{ Name = "exe-found-through-path"
           Find = '$p = Join-Path "$env:SystemRoot" $script:HordeSshExeRelative'
           Replace = '$p = "" + (Get-Command ssh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source' }
        @{ Name = "key-absent-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $Paths.identity -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "known-hosts-absent-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $Paths.knownHosts -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "config-absent-accepted"
           Find = 'if (-not (Test-Path -LiteralPath $Paths.config -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "config-directive-accepted"
           Find = 'if ($t -ne "" -and -not $t.StartsWith("#")) {'
           Replace = 'if ($false) {' }
        @{ Name = "exit-255-read-as-a-close"
           Find = '$st.process.ExitCode -eq $script:HordeSshExitTransportError'
           Replace = '$false' }
        @{ Name = "every-exit-a-transport-error"
           Find = '$st.process.ExitCode -eq $script:HordeSshExitTransportError'
           Replace = '$true' }
        @{ Name = "all-of-stderr-as-the-reason"
           Find = 'if ($l.Trim() -ne "") { return $l.Trim() }'
           Replace = 'if ($l.Trim() -ne "") { return ($State.errTask.Result -replace "\s+", " ") }' }
        @{ Name = "stdin-buffered"
           Find = '[System.IO.FileAccess]::Write, 1, $false)'
           Replace = '[System.IO.FileAccess]::Write, 4096, $false)' }
        @{ Name = "probe-takes-any-banner"
           Find = 'if ($line.StartsWith($pfx, [System.StringComparison]::Ordinal)) {'
           Replace = 'if ($true) {' }
        @{ Name = "probe-refused-is-unknown"
           Find = 'return (New-HordeKnown -Value $false)'
           Replace = 'return (New-HordeUnknown -Reason "refused")' }
        @{ Name = "listen-pretends"
           Find = 'return [pscustomobject]@{ ok = $false; listener = $null; reason = $script:HordeSshHubSide }'
           Replace = 'return [pscustomobject]@{ ok = $true; listener = @{}; reason = "" }' }
        @{ Name = "peer-claimed-verified"
           Find = 'verified = $false'
           Replace = 'verified = $true' }
        @{ Name = "a-second-program-start"
           Find = 'return (Test-HordeSshBanner -Endpoint $Endpoint)'
           Replace = 'if ($false) { $null = [System.Diagnostics.Process]::Start("cmd.exe") }; return (Test-HordeSshBanner -Endpoint $Endpoint)' }
        @{ Name = "a-call-with-ampersand"
           Find = 'return (Test-HordeSshBanner -Endpoint $Endpoint)'
           Replace = 'return (& Test-HordeSshBanner -Endpoint $Endpoint)' }
    )
}
