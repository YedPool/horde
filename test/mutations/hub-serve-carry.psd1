# Mutations of cli/HubServe.ps1's part in carrying requests over a dialled link, and of what `horde nodes`
# says of a dialled node (mesh v1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-serve-carry.psd1
# test\test-hub-carry.ps1 must fail for every one.
@{
    Target = "cli\HubServe.ps1"
    Suite  = "test\test-hub-carry.ps1"
    Mutations = @(
        @{ Name = "carry-skipped"
           Find = '        if ($ActDir -ne "") {'
           Replace = '        if ($false) {' }
        @{ Name = "carried-lines-dropped"
           Find = 'if ($null -ne $p.PSObject.Properties["carried"]) { $carried = @($p.carried | ForEach-Object { $who + ": " + $_ }) }'
           Replace = '' }
        @{ Name = "dialled-lines-nested"
           Find = '{ foreach ($l in @(Invoke-HordeHubDialled -Link $acc.value -Root $Root -Hub $Hub -Contract $Contract -TimeoutMs $TimeoutMs -BudgetMs $BudgetMs -Admit $Admit -ActDir $ActDir -ActTimeoutMs $ActTimeoutMs)) { [void]$lines.Add($l) }; continue }'
           Replace = '{ [void]$lines.Add((Invoke-HordeHubDialled -Link $acc.value -Root $Root -Hub $Hub -Contract $Contract -TimeoutMs $TimeoutMs -BudgetMs $BudgetMs -Admit $Admit -ActDir $ActDir -ActTimeoutMs $ActTimeoutMs)); continue }' }
        @{ Name = "serve-drops-the-act-dir"
           Find = '-Admit $Admit -ActDir $ActDir -ActTimeoutMs $ActTimeoutMs)) { [void]$outcomes.Add($l) }'
           Replace = '-Admit $Admit -ActTimeoutMs $ActTimeoutMs)) { [void]$outcomes.Add($l) }' }
        @{ Name = "report-route-not-dialled"
           Find = '            $n["route"] = "dialled"'
           Replace = '' }
        @{ Name = "report-revoked-said-live"
           Find = 'live = [bool]$en[0].live;'
           Replace = 'live = $true;' }
        @{ Name = "text-hides-not-enrolled"
           Find = 'else { $how = " [dialled, NOT ENROLLED: " + $en.reason + "]" }'
           Replace = 'else { $how = "" }' }
        @{ Name = "text-heard-hides-enrolment"
           Find = '[void]$lines.Add($line + $how)'
           Replace = '[void]$lines.Add($line)' }
    )
}
