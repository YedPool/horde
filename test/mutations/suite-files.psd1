# Mutations of test/lib/SuiteFiles.ps1, the list of where suites live. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\suite-files.psd1
# test\test-suite.ps1 must fail for each.
@{
    Target = "test\lib\SuiteFiles.ps1"
    Suite  = "test\test-suite.ps1"
    Mutations = @(
        @{ Name = "transports-not-gated"
           Find = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test", "messengers/*/test", "surfaces/*/test", "relays/*/test")'
           Replace = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "agents/*/test", "messengers/*/test", "surfaces/*/test", "relays/*/test")' }
        @{ Name = "agents-not-gated"
           Find = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test", "messengers/*/test", "surfaces/*/test", "relays/*/test")'
           Replace = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "messengers/*/test", "surfaces/*/test", "relays/*/test")' }
        @{ Name = "messengers-not-gated"
           Find = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test", "messengers/*/test", "surfaces/*/test", "relays/*/test")'
           Replace = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test", "surfaces/*/test", "relays/*/test")' }
        @{ Name = "surfaces-not-gated"
           Find = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test", "messengers/*/test", "surfaces/*/test", "relays/*/test")'
           Replace = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test", "messengers/*/test", "relays/*/test")' }
        @{ Name = "relays-not-gated"
           Find = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test", "messengers/*/test", "surfaces/*/test", "relays/*/test")'
           Replace = '$script:HordeSuiteFolders = @("test", "hosts/*/test", "transports/*/test", "agents/*/test", "messengers/*/test", "surfaces/*/test")' }
        @{ Name = "fixtures-counted-as-stray"
           Find = 'if ($rel -like ".git/*" -or $rel -like ($script:HordeSuiteDataFolder + "/*")) { continue }'
           Replace = 'if ($rel -like ".git/*") { continue }' }
        @{ Name = "strays-never-reported"
           Find = 'if (-not $known.ContainsKey($f.FullName.ToLowerInvariant())) { [void]$stray.Add($rel) }'
           Replace = '' }
        @{ Name = "extension-not-exact"
           Find = 'foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter "test-*.ps1" -File | Where-Object { $_.Extension -ceq ".ps1" })) { [void]$out.Add($f) }'
           Replace = 'foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter "test-*" -File)) { [void]$out.Add($f) }' }
        @{ Name = "machine-bound-suite-renamed"
           Find = '"transports/local/test/test-local.ps1" = '
           Replace = '"transports/local/test/test-locals.ps1" = ' }
        # --- no test file makes a drive letter (Get-HordeDriveLetterMakers) ---
        @{ Name = "every-file-may-make-a-drive-letter"
           Find = 'if ($rel -ceq $script:HordeDriveLetterFile) { continue }'
           Replace = 'if ($true) { continue }' }
        @{ Name = "no-file-may-make-a-drive-letter"
           Find = 'if ($rel -ceq $script:HordeDriveLetterFile) { continue }'
           Replace = '' }
        @{ Name = "the-allowed-file-is-known-by-its-name-alone"
           Find = 'if ($rel -ceq $script:HordeDriveLetterFile) { continue }'
           Replace = 'if ($script.Name -ceq "test-path-text.ps1") { continue }' }
        @{ Name = "another-file-is-the-allowed-one"
           Find = '$script:HordeDriveLetterFile = "test/test-path-text.ps1"'
           Replace = '$script:HordeDriveLetterFile = "test/test-breaks.ps1"' }
        @{ Name = "makers-found-and-not-reported"
           Find = 'if ($what.Count -gt 0) { [void]$makers.Add('
           Replace = 'if ($false) { [void]$makers.Add(' }
        @{ Name = "only-the-suites-themselves-are-read"
           Find = 'Get-ChildItem -LiteralPath $folder -Filter "*.ps1" -File -Recurse -Force'
           Replace = 'Get-ChildItem -LiteralPath $folder -Filter "test-*.ps1" -File -Force' }
        @{ Name = "files-below-a-suite-folder-not-read"
           Find = 'Get-ChildItem -LiteralPath $folder -Filter "*.ps1" -File -Recurse -Force'
           Replace = 'Get-ChildItem -LiteralPath $folder -Filter "*.ps1" -File -Force' }
        @{ Name = "comments-are-read-as-code"
           Find = 'if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) { continue }'
           Replace = '' }
        @{ Name = "the-system-call-not-seen"
           Find = 'if ($token.Text.IndexOf($systemCall, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { & $say $systemCall }'
           Replace = '' }
        @{ Name = "the-scripting-object-not-seen"
           Find = 'if ($token.Text.IndexOf($scriptingCall, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { & $say $scriptingCall }'
           Replace = '' }
        @{ Name = "the-command-not-seen"
           Find = 'if ($leaf -match ''\Asubst(?:\.exe)?\z'') { & $say "subst" }'
           Replace = '' }
        @{ Name = "the-command-seen-only-without-its-extension"
           Find = 'if ($leaf -match ''\Asubst(?:\.exe)?\z'') { & $say "subst" }'
           Replace = 'if ($leaf -match ''\Asubst\z'') { & $say "subst" }' }
        @{ Name = "the-command-by-its-whole-path-not-seen"
           Find = '$leaf = ($name -split ''[\\/]'')[-1]'
           Replace = '$leaf = $name' }
        @{ Name = "a-mapped-drive-by-the-old-command-not-seen"
           Find = ').Count -gt 0) { & $say "net use" }'
           Replace = ').Count -gt 0) { }' }
        @{ Name = "the-old-command-caught-whatever-it-is-asked"
           Find = '-and @($rest | Where-Object { $_ -match ''\A["'''']?use["'''']?\z'' }).Count -gt 0) { & $say "net use" }'
           Replace = ') { & $say "net use" }' }
        @{ Name = "a-mapped-drive-by-the-newer-command-not-seen"
           Find = ') { & $say "New-SmbMapping" }'
           Replace = ') { }' }
        @{ Name = "a-lasting-powershell-drive-not-seen"
           Find = ').Count -gt 0) { & $say "New-PSDrive -Persist" }'
           Replace = ').Count -gt 0) { }' }
        @{ Name = "every-powershell-drive-caught"
           Find = '-and @($rest | Where-Object { $_ -match ''\A-Persist'' }).Count -gt 0) { & $say "New-PSDrive -Persist" }'
           Replace = ') { & $say "New-PSDrive -Persist" }' }
        @{ Name = "a-command-line-in-quotes-not-read"
           Find = 'if ($token -is [System.Management.Automation.Language.StringToken]) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-thing-found-twice-is-named-twice"
           Find = 'if ($found -cnotcontains $What) { [void]$found.Add($What) }'
           Replace = '[void]$found.Add($What)' }
    )
}
