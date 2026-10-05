# Mutations of core/AgentLaunch.ps1 (remote R9 and engines E9, the act path's A1; issue #67). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\agent-launch.psd1
# test\test-agent-launch.ps1 must fail for every one.
@{
    Target = "core\AgentLaunch.ps1"
    Suite  = "test\test-agent-launch.ps1"
    Mutations = @(
        @{ Name = "preconditions-claimed-not-verified"
           Find = '$verified = @(& $a.preconditions $need | ForEach-Object { "" + $_ } | Where-Object { $need -ccontains $_ })'
           Replace = '$verified = $need' }
        @{ Name = "precondition-matched-without-case"
           Find = 'Where-Object { $need -ccontains $_ })'
           Replace = 'Where-Object { $need -contains $_ })' }
        @{ Name = "name-without-capability"
           Find = 'elseif (-not (Test-HordeAgentCapability -Descriptor $d -Name "session.remoteName")) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "name-not-capped"
           Find = 'if ($name.Length -gt $Max) {'
           Replace = 'if ($false) {' }
        @{ Name = "name-keeps-control-characters"
           Find = '[regex]::Replace("" + $Title, ''[^\x21-\x7E]+'', " ")'
           Replace = '[regex]::Replace("" + $Title, '' +'', " ")' }
        @{ Name = "label-unchecked"
           Find = 'if ($Label -isnot [string] -or $Label -cnotmatch $script:HordeLabelPattern) {'
           Replace = 'if ($Label -isnot [string]) {' }
        @{ Name = "session-id-unchecked"
           Find = 'if ($SessionId -cnotmatch $pattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "adapter-refusal-ignored"
           Find = 'if ($null -eq $argv -or $argv.state -ne "known") {'
           Replace = 'if ($null -eq $argv) {' }
        @{ Name = "program-path-allowed"
           Find = 'if ($Program -cnotmatch ''\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z'') {'
           Replace = 'if ($false) {' }
    )
}
