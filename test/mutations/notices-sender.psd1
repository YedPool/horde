# Mutations of the sender proof of `horde notify` (notices/Sender.ps1): no session may send as another. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\notices-sender.psd1
# test\test-notices.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "notices\Sender.ps1"
    Suite  = "test\test-notices.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-claim-is-believed"
           Find = '    $up = Test-HordeNoticeAncestor -Table $Processes.value -Self $Self -Ancestor ([int]$pidAnswer.value)'
           Replace = '    $up = [pscustomobject]@{ ok = $true; reason = "" }' }
        @{ Name = "a-later-process-is-taken-for-a-parent"
           Find = 'if ($null -eq $parent.created -or $null -eq $child.created -or $parent.created -gt $child.created) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-process-not-verified-running-counts"
           Find = 'if (@($verified | Where-Object { "$_" -ieq $sid }).Count -eq 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-session-may-take-a-services-form"
           Find = 'if (Test-HordeNoticeServiceForm -Label $label) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-look-alike-letter-is-no-way-round"
           Find = 'if ($step -eq 1 -and [int]$c -lt 128) { [void]$sb.Append([char]::ToLowerInvariant($c)) } else { [void]$sb.Append("?") }'
           Replace = 'if ($step -eq 1 -and [int]$c -lt 128) { [void]$sb.Append([char]::ToLowerInvariant($c)) } else { [void]$sb.Append("x") }' }
        @{ Name = "marks-and-punctuation-are-kept-in-the-skeleton"
           Find = 'if ($isLetter) {'
           Replace = 'if ($true) {' }
        @{ Name = "a-word-of-another-script-is-refused"
           Find = 'return ($head -cmatch ''\A[s?][e?][r?][v?][i?][c?][e?]\z'' -and $head -cmatch ''[a-z]'')'
           Replace = 'return ($head -cmatch ''\A[s?][e?][r?][v?][i?][c?][e?]\z'')' }
        @{ Name = "an-invisible-character-is-part-of-the-label"
           Find = '$label = (Remove-HordeNoticeInvisible -Text $label).Trim()'
           Replace = '$label = $label.Trim()' }
        @{ Name = "the-registry-label-is-ignored"
           Find = 'if ($l.state -ceq "known" -and $l.value -is [string]) { $label = $l.value.Trim(); if ($label -cne "") { $labelSource = "registry" } }'
           Replace = 'if ($false) { $label = $l.value.Trim() }' }
        @{ Name = "a-session-with-no-name-sends"
           Find = 'if ($label -ceq "") { return (& $no ('
           Replace = 'if ($label -ceq "") { $label = "?" }; if ($false) { return (& $no (' }
        @{ Name = "no-parent-pid-is-the-session"
           Find = 'if ($null -eq $up -or $up.Value -isnot [int] -or $up.Value -le 0) {'
           Replace = 'if ($null -eq $up) { return [pscustomobject]@{ ok = $true; reason = "" } }; if ($up.Value -isnot [int] -or $up.Value -le 0) {' }
    )
}
