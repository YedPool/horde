# Mutations of core/FleetWork.ps1, the pure reading of one fleet-work line and the fold of a record. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-work.psd1
# Each breaks one refusal or one rule of the fold; test\test-fleet-work.ps1 must fail a check for every one.
#
# NOT HERE: the patterns of the content check (credential, customer data, conversation). They are
# core/Finding.ps1's and decisions/Rules.ps1's, held by test\mutations\finding.psd1 and
# test\mutations\decisions-rules.psd1; here only their use is mutated.
@{
    Target = "core\FleetWork.ps1"
    Suite  = "test\test-fleet-work.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "size-not-checked"
           Find = 'if ($Text.Length -gt $script:HordeFleetWorkMaxLength) {'
           Replace = 'if ($false) {' }
        @{ Name = "line-break-kept"
           Find = 'if ($Text.IndexOfAny([char[]]@([char]10, [char]13)) -ge 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "non-ascii-kept"
           Find = '    if ($wide.Success) {'
           Replace = '    if ($false) {' }
        @{ Name = "non-object-read"
           Find = 'if ($null -eq $parsedValue -or $parsedValue -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($null -eq $parsedValue) {' }
        @{ Name = "content-not-checked"
           Find = '    if ($content.Count -gt 0) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "duplicate-keys-kept"
           Find = '    if ($twice.Count -gt 0) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "values-not-checked-by-kind"
           Find = '    if ($unfit.Count -eq 0) {'
           Replace = '    if ($false) {' }
        @{ Name = "schema-not-checked"
           Find = '    if ($unfit.Count -gt 0) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "rules-not-checked"
           Find = '    if ($broken.Count -gt 0) { return'
           Replace = '    if ($false) { return' }
        @{ Name = "time-not-parsed"
           Find = '    if ($null -eq $written) { [void]$out.Add('
           Replace = '    if ($false) { [void]$out.Add(' }
        @{ Name = "since-not-parsed"
           Find = '        if ($null -eq $since) { [void]$out.Add('
           Replace = '        if ($false) { [void]$out.Add(' }
        @{ Name = "since-after-time-kept"
           Find = 'elseif ($null -ne $written -and $since -gt $written) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "end-may-name-itself"
           Find = 'if ($e["kind"] -ceq "wait-end" -and ("" + $v["ends"]) -ceq ("" + $e["id"])) {'
           Replace = 'if ($false) {' }
        @{ Name = "torn-tail-not-set-apart"
           Find = '    if ($parts[$last].TrimEnd([char]13) -ne "") { $torn = $true;'
           Replace = '    if ($false) { $torn = $true;' }
        @{ Name = "torn-tail-read"
           Find = '    for ($n = 0; $n -lt $last; $n++) {'
           Replace = '    for ($n = 0; $n -le $last; $n++) {' }
        @{ Name = "carriage-return-kept"
           Find = '        $lineText = $parts[$n].TrimEnd([char]13)'
           Replace = '        $lineText = $parts[$n]' }
        @{ Name = "repeated-id-replaces"
           Find = '        if ($seen.ContainsKey($ev.id)) {'
           Replace = '        if ($false) {' }
        @{ Name = "end-from-any-lane"
           Find = '                if ($open[$target].lane -cne $ev.lane) {'
           Replace = '                if ($false) {' }
        @{ Name = "end-closes-nothing"
           Find = '                $open.Remove($target); [void]$endedIds.Add($target); $ended++'
           Replace = '                [void]$endedIds.Add($target); $ended++' }
        @{ Name = "second-end-counted"
           Find = '            elseif ($endedIds.Contains($target)) {'
           Replace = '            elseif ($false) {' }
        @{ Name = "first-status-kept"
           Find = '            $statuses[$ev.lane] = [pscustomobject]@{'
           Replace = '            if (-not $statuses.ContainsKey($ev.lane)) { $statuses[$ev.lane] = $null }; if ($null -ne $statuses[$ev.lane]) { continue }; $statuses[$ev.lane] = [pscustomobject]@{' }
    )
}
