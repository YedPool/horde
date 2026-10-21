# Mutations of `horde decisions publish` (decisions/Publish.ps1): each lets in what the verb exists to refuse,
# or refuses what it must publish. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-publish.psd1
# test\test-decisions-publish.ps1 must fail for every one. Every find string occurs once.
@{
    Target = "decisions\Publish.ps1"
    Suite  = "test\test-decisions-publish.ps1"
    Mutations = @(
        @{ Name = "file-may-name-the-orc"
           Find = 'if ($p.Name -imatch $script:HordePublishWhoNames) {'
           Replace = 'if ($false) {' }
        @{ Name = "secret-text-published"
           Find = 'if ($secrets.Count -gt 0) { return (& $no ("the file holds'
           Replace = 'if ($false) { return (& $no ("the file holds' }
        @{ Name = "misspelt-item-field-dropped"
           Find = 'if ($script:HordePublishItemFields -cnotcontains $p.Name) { return (& $no ($at'
           Replace = 'if ($false) { return (& $no ($at' }
        @{ Name = "misspelt-top-field-dropped"
           Find = 'if ($script:HordePublishTopFields -cnotcontains $p.Name) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "text-limit-gone"
           Find = 'if ($Value.Length -gt $script:HordePublishMaxText)'
           Replace = 'if ($Value.Length -gt 999999)' }
        @{ Name = "non-ascii-published"
           Find = 'if ($bad.Success) {'
           Replace = 'if ($false) {' }
        @{ Name = "line-break-in-text"
           Find = 'if ($brk.Success) {'
           Replace = 'if ($false) {' }
        @{ Name = "tab-in-text"
           Find = '$problem = $(if ($OneLine) { Get-HordeDecisionCharProblem -Text $Value -OneLine }'
           Replace = '$problem = $(if ($false) { Get-HordeDecisionCharProblem -Text $Value -OneLine }' }
        @{ Name = "any-importance-word"
           Find = 'if ($word -isnot [string] -or @($pair[1]) -cnotcontains $word) {'
           Replace = 'if ($false) {' }
        @{ Name = "number-as-text-accepted"
           Find = 'if (($number -isnot [int] -and $number -isnot [long]) -or $number -lt 1'
           Replace = 'if (($false) -or $number -lt 1' }
        @{ Name = "empty-list-refused"
           Find = 'return [pscustomobject]@{ ok = $true; reason = ""; items = @($out) }'
           Replace = 'if ($out.Count -eq 0) { return (& $no "empty") }; return [pscustomobject]@{ ok = $true; reason = ""; items = @($out) }' }
        @{ Name = "items-not-a-list-accepted"
           Find = 'if ($member.Value -isnot [System.Array]) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-may-be-missing"
           Find = 'if ($Required) { return ($Where + " is missing") }'
           Replace = '' }
        @{ Name = "unproven-session-publishes"
           Find = 'if ($null -eq $who -or -not [bool]$who.ok) { throw ("decisions publish is run by'
           Replace = 'if ($null -eq $who) { throw ("decisions publish is run by' }
        @{ Name = "node-failure-swallowed"
           Find = 'if ($r.code -ne 0) { return [pscustomobject]@{ lines = @(); failure = $(if ($r.err'
           Replace = 'if ($false) { return [pscustomobject]@{ lines = @(); failure = $(if ($r.err' }
        @{ Name = "orc-letter-unchecked"
           Find = 'if ($letter -cnotmatch ''\A[A-Z][A-Z0-9]{0,3}\z'') { throw "-Orc is'
           Replace = 'if ($false) { throw "-Orc is' }
        @{ Name = "home-defaulted"
           Find = 'if ("$env:HORDE_HOME".Trim() -eq "") { throw "horde decisions publish needs HORDE_HOME'
           Replace = 'if ($false) { throw "horde decisions publish needs HORDE_HOME' }
    )
}
