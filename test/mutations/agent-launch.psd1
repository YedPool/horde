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
        # Survives by design: Get-HordePermissionArgs compares each name exactly as well, so this filter
        # is the second of two lines; the test that Folder-OK is not folder-ok holds through the first.
        @{ Name = "precondition-matched-without-case"
           Find = 'Where-Object { $need -ccontains $_ })'
           Replace = 'Where-Object { $need -contains $_ })'
           Expect = "survives"
           Reason = "Get-HordePermissionArgs compares each precondition name exactly, so this filter is the second of two lines; the test that Folder-OK is not folder-ok holds through the first." }
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
        @{ Name = "no-close-text-accepted"
           Find = 'if (@($CloseText | Where-Object { "" + $_ -ne "" }).Count -eq 0) {'
           Replace = 'if ($false) {' }
    )
}
