# Mutations of decisions/Console.ps1, the command line's side of the decisions list. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-console.psd1
# test\test-decisions-cli.ps1 must fail for each. That suite starts powershell.exe for every command
# it runs (measured 2026-10-06 on a throttled machine: 81 s a run), so this spec is kept to the
# promises only the command line makes.
@{
    Target = "decisions\Console.ps1"
    Suite  = "test\test-decisions-cli.ps1"
    Mutations = @(
        @{ Name = "piped-output-left-in-the-console-code-page"
           Find = '[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)'
           Replace = '' }
        # No mutant for the byte-order mark: with UTF8Encoding($true) in that line Windows PowerShell 5.1
        # still wrote none to a pipe (measured 2026-10-06, the mutant survived), so the suite's check
        # that none opens the output guards against a host that would, and cannot be made to fail here.
        @{ Name = "console-encoding-not-put-back"
           Find = '} finally { [Console]::OutputEncoding = $was }'
           Replace = '} finally { }' }
        @{ Name = "stray-files-not-shown"
           Find = 'if ($loose.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "parser-message-repeated"
           Find = 'is not JSON. Nothing of it is quoted here, because it may hold what must not be printed; ConvertFrom-Json on the file says where it stops being JSON")'
           Replace = 'is not JSON: " + $_.Exception.Message)' }
        @{ Name = "json-not-ascii"
           Find = 'return [regex]::Replace($json, ''[^\x20-\x7E]'', {'
           Replace = 'return [regex]::Replace($json, ''(?!)'', {' }
        @{ Name = "refusal-exits-zero"
           Find = 'elseif ($answer.value.outcome -ceq "refused") { $failure = "$($answer.value.reason)" }'
           Replace = '' }
        @{ Name = "missing-question-exits-zero"
           Find = 'if ($answer.state -cne "known") { $failure = "$($answer.reason)" }'
           Replace = 'if ($false) { $failure = "$($answer.reason)" }' }
        @{ Name = "flag-of-another-verb-ignored"
           Find = 'if ($spec.flags -notcontains $flag) {'
           Replace = 'if ($false) {' }
        @{ Name = "file-read-in-any-encoding"
           Find = 'return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)'
           Replace = 'return [System.Text.Encoding]::Default.GetString($bytes)' }
        @{ Name = "key-given-twice-allowed"
           Find = 'if ($twice.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "outcome-given-twice-allowed"
           Find = 'if ($have.ContainsKey("Outcome") -eq $have.ContainsKey("OutcomeFile")) {'
           Replace = 'if ($false) {' }
        @{ Name = "number-not-required"
           Find = 'if ($numberText -cnotmatch ''\A[1-9][0-9]{0,8}\z'') {'
           Replace = 'if ($false) {' }
        @{ Name = "unreadable-records-not-printed"
           Find = 'foreach ($l in @(Format-HordeDecisionProblems -Value $value)) { [void]$lines.Add($l) }'
           Replace = '' }
        @{ Name = "new-id-for-every-send"
           Find = '            $id = "$($have[''Id''])"'
           Replace = '            $id = [guid]::NewGuid().ToString("N")' }
    )
}
