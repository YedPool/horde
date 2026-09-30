# Mutations of core/HostPort.ps1, the host port contract. Run one spec at a time:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hostport.psd1
# The spec sets HORDE_SKIP_REALITY=1 for its own runs: the reality check reads this machine's stores
# and proves nothing about a mutant of the contract, which the fixture sections must catch.
@{
    Target = "core\HostPort.ps1"
    Suite  = "test\test-projection.ps1"
    Environment = @{ HORDE_SKIP_REALITY = "1" }
    Mutations = @(
        @{ Name = "sigil-accepted-as-handle"
           Find = 'if ($t -cmatch ''^[A-Za-z0-9._:-]{1,64}$'') { return $t }'
           Replace = 'if ($t -cmatch ''^[%@$A-Za-z0-9._:-]{1,64}$'') { return $t }' }
        @{ Name = "handle-listed-twice-accepted"
           Find = 'if ($seen.ContainsKey($id)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "unverified-counts-as-yes"
           Find = 'return ($Port.available -and "$($Port.capabilities[$Name])" -ceq "yes")'
           Replace = 'return ($Port.available -and "$($Port.capabilities[$Name])" -cne "no")' }
        @{ Name = "capabilities-optional"
           Find = 'if ($null -eq $Capabilities) { throw'
           Replace = 'if ($null -eq $Capabilities) { $Capabilities = @{} }; if ($false) { throw' }
        @{ Name = "unknown-capability-accepted"
           Find = 'if ($script:HordeHostCapabilityNames -cnotcontains $p.Name) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "list-used-without-the-capability"
           Find = 'if (-not (Test-HordeHostCapability -Port $Port -Name "list")) {'
           Replace = 'if ($false) {' }
        @{ Name = "start-time-used-without-the-capability"
           Find = 'if (Test-HordeHostCapability -Port $Port -Name "instance.startedAt") {'
           Replace = 'if ($true) {' }
        @{ Name = "pid-used-without-the-capability"
           Find = 'if (-not (Test-HordeHostCapability -Port $Port -Name $Field)) { return'
           Replace = 'if ($false) { return' }
        @{ Name = "pid-compared-across-namespaces"
           Find = 'if ("$($sp.value)" -cne $LocalSpace) {'
           Replace = 'if ($false) {' }
        @{ Name = "pid-with-no-namespace-placed"
           Find = 'if ($sp.state -ne "known" -or "$($sp.value)" -cnotmatch $script:HordeProcessSpacePattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "stored-handles-optional"
           Find = 'if ($null -eq $StoredHandles) { throw'
           Replace = 'if ($null -eq $StoredHandles) { $StoredHandles = @("W1", "W2", "W4", "W5", "X1") }; if ($false) { throw' }
        @{ Name = "malformed-instance-id-dropped"
           Find = 'if ($null -eq $id) { return (New-HordeUnknown -Reason "the host gave an instance id'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason "the host gave an instance id' }
        @{ Name = "non-boolean-ambiguity-read-as-false"
           Find = 'if ($amb.value -isnot [bool]) { return'
           Replace = 'if ($amb.value -isnot [bool]) { $amb = New-HordeKnown -Value $false }; if ($false) { return' }
        @{ Name = "two-writers-of-one-store-accepted"
           Find = 'if ($script:HordeStoreWriters.ContainsKey($st) -and $script:HordeStoreWriters[$st] -cne $Name) {'
           Replace = 'if ($false) {' }
    )
}
