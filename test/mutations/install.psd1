# Mutations of the installer. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\install.psd1
# Each breaks one rule cli\Install.ps1 enforces; test\test-install.ps1 must fail for every one of them.
@{
    Target = "cli\Install.ps1"
    Suite  = "test\test-install.ps1"
    Mutations = @(
        # The launch line: exit codes, the file never read again, powershell by full path.
        @{ Name = "bare-exit-drops-the-code"
           Find = '%* & call exit /b %%ERRORLEVEL%%'')'
           Replace = '%* & exit /b'')' }
        @{ Name = "launch-as-plain-last-line"
           Find = '%* & call exit /b %%ERRORLEVEL%%'')'
           Replace = '%*'')' }
        @{ Name = "powershell-found-on-path"
           Find = '(''"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile'
           Replace = '(''powershell -NoProfile' }
        @{ Name = "percent-not-doubled"
           Find = '$escaped = $Target.Replace("%", "%%")'
           Replace = '$escaped = $Target' }
        @{ Name = "lf-line-endings"
           Find = 'return (($lines -join "`r`n") + "`r`n")'
           Replace = 'return (($lines -join "`n") + "`n")' }
        # Which checkout may install, and which paths a .cmd can carry.
        @{ Name = "worktree-not-refused"
           Find = 'if ($kind -eq "worktree" -and -not $AllowWorktree) {'
           Replace = 'if ($false) {' }
        @{ Name = "worktree-read-as-checkout"
           Find = 'if (Test-Path -LiteralPath $g -PathType Leaf) { return "worktree" }'
           Replace = 'if ($false) { return "worktree" }' }
        @{ Name = "bang-allowed"
           Find = 'if ($Path.Contains("!")) {'
           Replace = 'if ($false) {' }
        @{ Name = "non-ascii-allowed"
           Find = 'if ($Path -cmatch ''[^\x20-\x7E]'') {'
           Replace = 'if ($false) {' }
        # No silent overwrite.
        @{ Name = "foreign-not-named"
           Find = 'if ($now.state -eq "foreign") { $refusal ='
           Replace = 'if ($false) { $refusal =' }
        @{ Name = "hand-edit-not-detected"
           Find = 'if ((Get-HordeShimHash -Bytes $rest) -ne $m.Groups[1].Value) {'
           Replace = 'if ($false) {' }
        @{ Name = "other-checkout-replaced"
           Find = 'elseif ("$($now.target)" -ine $target) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "force-ignored"
           Find = 'if ($refusal -and -not $Force) {'
           Replace = 'if ($refusal) {' }
        @{ Name = "folder-not-seen"
           Find = 'if (Test-Path -LiteralPath $Path -PathType Container) { return [pscustomobject]@{ state = "directory"'
           Replace = 'if ($false) { return [pscustomobject]@{ state = "directory"' }
        @{ Name = "header-hash-wrong"
           Find = '$hash = Get-HordeShimHash -Bytes ([System.Text.Encoding]::ASCII.GetBytes($body))'
           Replace = '$hash = "0" * 64' }
        # Idempotence.
        @{ Name = "always-rewrites"
           Find = 'if ($now.state -eq "ours" -and [System.Linq.Enumerable]::SequenceEqual('
           Replace = 'if ($false -and [System.Linq.Enumerable]::SequenceEqual(' }
        # PATH.
        @{ Name = "path-compared-with-trailing-backslash"
           Find = '$_.Trim().TrimEnd("\") -ieq $want'
           Replace = '$_.Trim() -ieq $want' }
        # A declared gap.
        @{ Name = "write-not-read-back"
           Find = 'if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]]$back, [byte[]]$wanted)) { throw'
           Replace = 'if ($false) { throw'
           Expect = "survives"
           Reason = "Nothing a test can arrange makes WriteAllBytes and Replace succeed while leaving other bytes in the file, so the read-back cannot be made to fire; it stays because a line that says written must have checked." }
    )
}
