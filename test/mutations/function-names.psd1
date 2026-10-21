# Mutations of tools/FunctionNames.ps1, the guard against a function name defined twice. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\function-names.psd1
# Each breaks one rule of the parse; test\test-function-names.ps1 must fail for every one of them.
@{
    Target = "tools\FunctionNames.ps1"
    Suite  = "test\test-function-names.ps1"
    Mutations = @(
        @{ Name = "names-compared-by-case"
           Find = '-replace ''^(global|script|local|private):'', '''').ToLowerInvariant()'
           Replace = '-replace ''^(global|script|local|private):'', '''')' }
        @{ Name = "class-methods-counted"
           Find = '            if ($d.Parent -is [System.Management.Automation.Language.FunctionMemberAst]) { continue }'
           Replace = '' }
        @{ Name = "nested-functions-counted"
           Find = 'if ($nested -and $d.Name -notmatch ''^(global|script):'') { continue }'
           Replace = '' }
        @{ Name = "parse-error-skipped"
           Find = 'if (@($errors).Count -gt 0) { [void]$out.Add([pscustomobject]@{ name = "<parse error>"; file = $rel; line = $errors[0].Extent.StartLineNumber }); continue }'
           Replace = 'if (@($errors).Count -gt 0) { continue }' }
        @{ Name = "test-folders-scanned"
           Find = 'if (@($rel -split ''/'') -contains "test") { continue }'
           Replace = '' }
        @{ Name = "a-folder-left-out"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "fleet-metrics-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks")' }
        @{ Name = "messengers-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "decisions-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "platform-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "surfaces-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "fleet-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "relay-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relays", "conversations", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "relays-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "conversations", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "conversations-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "wakers-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "files-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "orcs-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "fleet-db", "hooks", "fleet-metrics")' }
        @{ Name = "fleet-db-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-metrics")' }
        @{ Name = "channels-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "notices", "orcs", "fleet-metrics")' }
        @{ Name = "notices-not-shipped"
           Find = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "notices", "orcs", "fleet-db", "hooks", "fleet-metrics")'
           Replace = '$script:HordeShippedCodeFolders = @("core", "remote", "transports", "messengers", "decisions", "fleet", "platform", "surfaces", "tools", "cli", "hosts", "agents", "relay", "relays", "conversations", "wakers", "files", "channels", "orcs", "fleet-metrics")' }
        @{ Name = "unlisted-folder-not-reported"
           Find = '        if ($found) { [void]$out.Add($top.Name) }'
           Replace = '' }
        @{ Name = "unlisted-folder-subfolders-not-walked"
           Find = '                $stack.Push($d.FullName)'
           Replace = '' }
        @{ Name = "unlisted-folder-test-walked"
           Find = '                if ($d.Name -ieq "test" -or $d.Name -ieq "node_modules") { continue }'
           Replace = '                if ($d.Name -ieq "node_modules") { continue }' }
        @{ Name = "unlisted-folder-node-modules-walked"
           Find = '                if ($d.Name -ieq "test" -or $d.Name -ieq "node_modules") { continue }'
           Replace = '                if ($d.Name -ieq "test") { continue }' }
        @{ Name = "unlisted-folder-js-not-code"
           Find = '$script:HordeCodeExtensions = @(".ps1", ".psm1", ".js", ".mjs")'
           Replace = '$script:HordeCodeExtensions = @(".ps1", ".psm1", ".mjs")' }
        @{ Name = "duplicates-not-reported"
           Find = 'if ($byName[$k].Count -gt 1) {'
           Replace = 'if ($byName[$k].Count -gt 2) {' }
        @{ Name = "subfolders-not-scanned"
           Find = 'Get-ChildItem -LiteralPath $dir -Recurse -File -Filter "*.ps1"'
           Replace = 'Get-ChildItem -LiteralPath $dir -File -Filter "*.ps1"' }
        @{ Name = "horde-ps1-not-scanned"
           Find = '$script:HordeShippedCodeFiles = @("horde.ps1")'
           Replace = '$script:HordeShippedCodeFiles = @()' }
        @{ Name = "scope-prefix-kept"
           Find = '$k = ("$($d.name)" -replace ''^(global|script|local|private):'', '''').ToLowerInvariant()'
           Replace = '$k = "$($d.name)".ToLowerInvariant()' }
        @{ Name = "nested-global-ignored"
           Find = 'if ($nested -and $d.Name -notmatch ''^(global|script):'') { continue }'
           Replace = 'if ($nested) { continue }' }
        @{ Name = "item-definitions-ignored"
           Find = 'if (@("Set-Item", "New-Item", "si", "ni") -contains $nm) { $kind = "item" }'
           Replace = 'if ($false) { $kind = "item" }' }
        @{ Name = "alias-definitions-ignored"
           Find = 'elseif (@("Set-Alias", "New-Alias", "sal", "nal") -contains $nm) { $kind = "alias" }'
           Replace = 'elseif ($false) { $kind = "alias" }' }
    )
}
