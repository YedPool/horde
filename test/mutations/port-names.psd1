# Mutations of the port-names ratchet's second family: agents/<name>/, a harness, held to the rule
# hosts/<name>/ already was (CONTRIBUTING rule 14; engine-settings design, 2026-09-30, build step E1).
# Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\port-names.psd1
# Each breaks one way the ratchet treats a harness as a port; test\test-host-names.ps1 must fail for
# every one. The host rules themselves are mutated by test\mutations\host-names.psd1.
@{
    Target = "tools\HostNames.ps1"
    Suite  = "test\test-host-names.ps1"
    Mutations = @(
        # --- agents/ is scanned at all
        @{ Name = "agents-family-dropped"
           Find = '$script:HordePortFamilies = @("hosts", "agents", "transports", "messengers")'
           Replace = '$script:HordePortFamilies = @("hosts", "transports", "messengers")' }
        @{ Name = "messengers-family-dropped"
           Find = '$script:HordePortFamilies = @("hosts", "agents", "transports", "messengers")'
           Replace = '$script:HordePortFamilies = @("hosts", "agents", "transports")' }
        # --- a port is its family AND its name, never its name alone
        # The whole Add: since 56e99a7 (PR #57) the same own = (...) expression also builds the list of
        # declared names, so the expression alone matched twice and the mutant did not apply.
        @{ Name = "port-own-folder-assumed-hosts"
           Find = '[void]$hostDirs.Add([pscustomobject]@{ own = ($fam + "/" + $d.Name); dir = $d })'
           Replace = '[void]$hostDirs.Add([pscustomobject]@{ own = ("hosts/" + $d.Name); dir = $d })' }
        @{ Name = "same-name-folders-exempt-across-families"
           Find = '$skip = @($own)'
           Replace = '$skip = @($script:HordePortFamilies | ForEach-Object { $_ + "/" + $h.Name })' }
        @{ Name = "whole-family-exempt"
           Find = '$skip = @($own)'
           Replace = '$skip = @($own.Split("/")[0])' }
        # --- shrink-only against origin/main, for a harness too
        @{ Name = "shrink-agents-not-read-from-ref"
           Find = 'ls-tree -r --name-only $Ref -- @($script:HordePortFamilies)'
           Replace = 'ls-tree -r --name-only $Ref -- hosts' }
        @{ Name = "shrink-removed-agent-unseen"
           Find = '''^([^/]+/[^/]+)/names\.txt$'''
           Replace = '''^(hosts/[^/]+)/names\.txt$''' }
        @{ Name = "shrink-ports-keyed-by-bare-name"
           Find = '$here[$fam + "/" + $h.Name] = $h.FullName'
           Replace = '$here[$h.Name] = $h.FullName' }
        @{ Name = "shrink-new-port-reported-by-bare-name"
           Find = '[void]$out.newHosts.Add($own); continue'
           Replace = '[void]$out.newHosts.Add((Split-Path -Leaf $own)); continue' }
        # --- each port's growth is its own
        @{ Name = "growth-read-from-hosts-folder"
           Find = '$rel = $Own + "/growth.txt"'
           Replace = '$rel = "hosts/" + (Split-Path -Leaf $Own) + "/growth.txt"' }
    )
}
