# Mutations of cli/commands/fleet.ps1, the tier gate of `horde fleet hibernate`. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\fleet-hibernate-command.psd1
# Each breaks one thing the command chooses about who may be hibernated; test\test-fleet-hibernate.ps1 must fail
# a check for every one.
@{
    Target = "cli\commands\fleet.ps1"
    Suite  = "test\test-fleet-hibernate.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "tier-gate-not-asked-for"
           Find = 'if ($Tier -ne 2) { throw (New-HordeUsageError'
           Replace = 'if ($false) { throw (New-HordeUsageError' }
        @{ Name = "tier-not-handed-to-the-hibernation"
           Find = '-Names $orcList -Tier $Tier -DryRun:$DryRun'
           Replace = '-Names $orcList -DryRun:$DryRun' }
        @{ Name = "orc-tiers-never-read"
           Find = 'OrcTiers = $tiers'
           Replace = '' }
        @{ Name = "tier-on-another-verb-accepted"
           Find = '-or $PSBoundParameters.ContainsKey("Tier"))) { throw (New-HordeUsageError'
           Replace = '-or $false)) { throw (New-HordeUsageError' }
    )
}
