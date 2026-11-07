# Mutations of the relay port's answer to "which files on this machine hold relays' secrets"
# (relays/Port.ps1, the section of that name, 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-port-secret-files.psd1
# Each loosens one thing the port checks or does when it asks the relays, and test\test-relay-port.ps1
# must fail for every one. Every find string occurs exactly once. The port's other rules are
# test\mutations\relay-port.psd1's and relay-port-trim.psd1's.
@{
    Target = "relays\Port.ps1"
    Suite  = "test\test-relay-port.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- a network or device path is a file like any other (round 2 of the review of PR 238, 2026-10-14) ---
        @{ Name = "a-network-or-device-path-cannot-tell-again"
           Find = 'try { $whole = [System.IO.Path]::GetFullPath($path.value) } catch { $whole = "" }'
           Replace = 'if ($path.value -cmatch ''\A[\\/]{2}'') { return (New-HordeUnknown -Reason ($at + " by a network or device path")) }; try { $whole = [System.IO.Path]::GetFullPath($path.value) } catch { $whole = "" }' }
        @{ Name = "relay-that-cannot-tell-left-out"
           Find = 'if ($a.state -cne "known") { [void]$cannot.Add($n); [void]$why.Add($a.reason); continue }'
           Replace = 'if ($a.state -cne "known") { continue }' }
        @{ Name = "unknown-does-not-say-which-relays"
           Find = '$u | Add-Member -NotePropertyName relays -NotePropertyValue @($cannot.ToArray())'
           Replace = '$u | Add-Member -NotePropertyName relays -NotePropertyValue @()' }
        @{ Name = "relays-own-reason-dropped"
           Find = '"'' cannot tell which files hold its secrets: " + $a.reason))'
           Replace = '"'' cannot tell which files hold its secrets"))' }
        @{ Name = "block-that-throws-is-thrown-on"
           Find = 'catch { return (New-HordeUnknown -Reason ("relay ''" + $name + "'' failed to say which files hold its secrets") -ErrorRecord $_) }'
           Replace = 'catch { throw }' }
        @{ Name = "something-that-is-no-answer-believed"
           Find = 'if (-not (Test-HordeAnswer $a)) { return (New-HordeUnknown -Reason ("relay ''" + $name + "'' answered which files hold its secrets with'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("relay ''" + $name + "'' answered which files hold its secrets with' }
        @{ Name = "absent-read-as-cannot-tell"
           Find = 'if ("absent" -ceq $a.state) { return (New-HordeKnown -Value @($out.ToArray())) }'
           Replace = '' }
        @{ Name = "relay-with-no-block-asked"
           Find = 'if ($null -eq $r.secretFiles) { continue }'
           Replace = '' }
        @{ Name = "block-not-kept-at-registration"
           Find = 'putKeeping = $PutKeeping; secretFiles = $SecretFiles'
           Replace = 'putKeeping = $PutKeeping; secretFiles = $null' }
        @{ Name = "home-not-handed-to-the-relay"
           Find = 'try { $a = & $Relay.secretFiles $HordeHome }'
           Replace = 'try { $a = & $Relay.secretFiles "" }' }
        @{ Name = "relative-home-asked-about"
           Find = 'if ($HordeHome -ne "" -and -not (Test-HordeRelayAbsolutePath $HordeHome)) {'
           Replace = 'if ($false) {' }
        @{ Name = "relative-path-believed"
           Find = 'if (-not $path.has -or -not (Test-HordeRelayAbsolutePath $path.value)) {'
           Replace = 'if (-not $path.has) {' }
        @{ Name = "path-on-a-drive-but-not-from-its-root"
           Find = 'return [bool]($Path -cmatch ''\A(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/])'') }'
           Replace = 'return [bool]($Path -cmatch ''\A(?:[A-Za-z]:|[\\/]{2}[^\\/])'') }' }
        @{ Name = "path-not-made-whole"
           Find = 'try { $whole = [System.IO.Path]::GetFullPath($path.value) } catch { $whole = "" }'
           Replace = '$whole = $path.value' }
        @{ Name = "description-unchecked"
           Find = 'if (-not $what.has -or $what.value -isnot [string] -or $what.value -cnotmatch $script:HordeRelaySecretWhatPattern) {'
           Replace = 'if (-not $what.has) {' }
        @{ Name = "description-of-any-length"
           Find = '$script:HordeRelaySecretWhatPattern = ''\A[\x20-\x7E]{1,80}\z'''
           Replace = '$script:HordeRelaySecretWhatPattern = ''\A[\x20-\x7E]{1,8000}\z''' }
        @{ Name = "description-of-many-lines"
           Find = '{1,80}\z'''
           Replace = '{1,80}''' }
        @{ Name = "file-does-not-say-whose"
           Find = '[void]$out.Add([pscustomobject]@{ relay = $name; path = $whole; what = [string]$what.value })'
           Replace = '[void]$out.Add([pscustomobject]@{ relay = ""; path = $whole; what = [string]$what.value })' }
        @{ Name = "a-character-no-path-may-hold-passes"
           Find = 'if ($Path -cmatch ''["<>|\x00-\x1F]'') { return $false }'
           Replace = ''
           Expect = "survives"
           Reason = "Equivalent in the shell this tool runs suites in: under 5.1 IsPathRooted throws on these characters, so the next line still answers no. Under pwsh 7 it does not throw, and the suite is red with this line removed (measured 2026-11-06)." }
    )
}
