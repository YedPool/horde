# Mutations of the dash as the cards channel sends it (channels/cards/Channel.ps1, THE DASH RIDES IN THE
# SAME SNAPSHOT). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-cards-dash.psd1
# test\test-orcs-registry.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "channels\cards\Channel.ps1"
    Suite  = "test\test-orcs-registry.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-dash-goes-without-its-orcs"
           Find = '$dashHead + (@($dashTexts | Select-Object -First $DashKept) -join ",")'
           Replace = '$dashHead' }
        @{ Name = "a-secret-domain-is-sent"
           Find = 'return (Protect-HordeCardsChannelField -Text $Text -Field $Field -Refused $no) }'
           Replace = 'return $Text }' }
        @{ Name = "the-dash-is-not-versioned"
           Find = '$dashHead = ''{"v":'''
           Replace = '$dashHead = ''{"w":''' }
        @{ Name = "the-dash-forgets-the-registry-version"
           Find = ''',"version":'' + $dashDoc.version'
           Replace = ''',"version":0''' }
    )
}
