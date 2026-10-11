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
        @{ Name = "report-enrolment-dropped"
           Find = '            $n["enrolment"] = [ordered]@{ expires = "" + $en[0].expires; address = "" + $en[0].address }'
           Replace = '' }
        @{ Name = "report-pulled-said-dialled"
           Find = '-and "$(Get-HordeLinkProp $_ ''route'')" -ceq "dialled" })'
           Replace = '})' }
        @{ Name = "text-heard-hides-enrolment"
           Find = '[void]$lines.Add($line + $how)'
           Replace = '[void]$lines.Add($line)' }
    )
}
