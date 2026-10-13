# Mutations of Get-HordeConversationSession in conversations/Port.ps1: a session described by its id. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\conversation-port-session.psd1
# Each believes an adapter it should not, shows a label that is not one, or chooses between two answers;
# test\test-conversation-port.ps1 must fail for every one. (The port's other operations are
# test\mutations\conversation-port.psd1's.)
@{
    Target = "conversations\Port.ps1"
    Suite  = "test\test-conversation-port.ps1"
    Mutations = @(
        @{ Name = "bad-session-id-asked"
           Find = 'if ($SessionId -cnotmatch $script:HordeConversationSessionPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "bad-horde-name-asked"
           Find = 'if ($Fleet -cnotmatch $script:HordeConversationFleetPattern) { return (New-HordeUnknown -Reason "the horde asked about'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason "the horde asked about' }
        @{ Name = "unverified-lookup-asked"
           Find = '$fit = Find-HordeConversationAdapter -Require @("sessionLookup") -Refuse @()'
           Replace = '$fit = Find-HordeConversationAdapter -Require @() -Refuse @()' }
        @{ Name = "unverified-lookup-asked-by-name"
           Find = '$one = Resolve-HordeConversationAdapter -Name $Vendor -Require @("sessionLookup") -Refuse @()'
           Replace = '$one = Resolve-HordeConversationAdapter -Name $Vendor -Require @() -Refuse @()' }
        @{ Name = "missing-describe-called"
           Find = 'if ($null -eq $adapter.describe) {'
           Replace = 'if ($false) {' }
        @{ Name = "answer-about-another-session-believed"
           Find = 'if (-not $described.has -or $described.value -isnot [string] -or $described.value -cne $SessionId) {'
           Replace = 'if ($false) {' }
        @{ Name = "two-describers-one-chosen"
           Find = 'if ($describers.Count -gt 1) {'
           Replace = 'if ($false) {' }
        @{ Name = "unsure-adapter-ignored"
           Find = 'if ($doubts.Count -gt 0) {'
           Replace = 'if ($false) {' }
        @{ Name = "look-alike-fact-believed"
           Find = 'if (-not (Test-HordeAnswer $Fact)) {'
           Replace = 'if ($null -eq $Fact) {' }
        @{ Name = "fact-reason-not-redacted"
           Find = 'could not be told: " + (Protect-HordeConversationNote $Fact.reason)))'
           Replace = 'could not be told: " + $Fact.reason))' }
        @{ Name = "fact-not-text-kept"
           Find = 'if ($Fact.value -isnot [string] -or $Fact.value -cnotmatch $Pattern) {'
           Replace = 'if ($Fact.value -cnotmatch $Pattern) {' }
        @{ Name = "fact-shape-not-checked"
           Find = 'if ($Fact.value -isnot [string] -or $Fact.value -cnotmatch $Pattern) {'
           Replace = 'if ($Fact.value -isnot [string]) {' }
        @{ Name = "label-any-text"
           Find = '-What "label" -Pattern $script:HordeConversationLabelPattern'
           Replace = '-What "label" -Pattern $script:HordeConversationSessionPattern' }
        @{ Name = "label-ends-at-a-line-end"
           Find = '$script:HordeConversationLabelPattern = ''\A[A-Z]{1,2}([1-9][0-9]{0,3})?\z'''
           Replace = '$script:HordeConversationLabelPattern = ''\A[A-Z]{1,2}([1-9][0-9]{0,3})?$''' }
        @{ Name = "role-outside-the-list-kept"
           Find = '-What "role" -Pattern $rolePattern'
           Replace = '-What "role" -Pattern $script:HordeConversationSessionPattern' }
        @{ Name = "parent-any-text"
           Find = '-What "parent" -Pattern $script:HordeConversationSessionPattern'
           Replace = '-What "parent" -Pattern ''.''' }
        @{ Name = "fleet-not-the-one-asked"
           Find = '$value = [pscustomobject]@{ vendor = $f.adapter.name; session = $SessionId; fleet = $Fleet'
           Replace = '$value = [pscustomobject]@{ vendor = $f.adapter.name; session = $SessionId; fleet = $f.adapter.name' }
    )
}
