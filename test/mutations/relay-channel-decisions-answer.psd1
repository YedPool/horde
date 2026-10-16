# Mutations of channels/decisions/Answer.ps1: the phone's answer body and the request id made from it,
# moved there from channels/decisions/Channel.ps1 (audit of 2026-10-16, item 17) with their mutants. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-channel-decisions-answer.psd1
# Each breaks one promise to the founder; test\test-relay-channels.ps1 must fail for every one.
@{
    Target = "channels\decisions\Answer.ps1"
    Suite  = "test\test-relay-channels.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "id-not-bound-to-the-sender"
           Find = '($Domain + "`n" + $From + "`n" + $AnswerId)'
           Replace = '($Domain + "`n" + $AnswerId)' }
        @{ Name = "extra-member-taken"
           Find = 'if ((@($names | Sort-Object) -join ",") -cne (@($members | Sort-Object) -join ",")) {'
           Replace = 'if ($false) {' }
        # --- one part's answer, version 2 (2026-10-12) ---
        @{ Name = "a-version-1-answer-must-name-a-part"
           Find = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @("part") }'
           Replace = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @("part"); "2" = @("part") }' }
        @{ Name = "a-version-2-answer-is-not-read"
           Find = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @("part") }'
           Replace = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @() }' }
        @{ Name = "a-version-2-answer-need-name-no-part"
           Find = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @("part") }'
           Replace = '$script:HordeDecisionsChannelAnswerVersions = [ordered]@{ "1" = @(); "2" = @() }' }
        @{ Name = "a-part-of-any-spelling-is-handed-on"
           Find = "        if (`$a.part -isnot [string] -or `$a.part -cnotmatch '\A[a-z]\z') {"
           Replace = "        if (`$false) {" }
    )
}
