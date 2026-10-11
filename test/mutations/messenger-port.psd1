# Mutations of the messenger port. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\messenger-port.psd1
# Each mutation switches off or loosens one rule of messengers/Port.ps1 (remote plan step R21, slice 3),
# and test\test-messenger-port.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "messengers\Port.ps1"
    Suite  = "test\test-messenger-port.ps1"
    Mutations = @(
        @{ Name = "find-picks-one-of-several"
           Find = 'if ($able.Count -eq 1) { return (New-HordeKnown -Value $able[0]) }'
           Replace = 'if ($able.Count -ge 1) { return (New-HordeKnown -Value $able[0]) }' }
        @{ Name = "find-ignores-what-is-required"
           Find = '$missing = @($Require | Where-Object { -not (Test-HordeMessengerCapability -Messenger $m -Capability $_) }) | Select-Object -First 1'
           Replace = '$missing = $null' }
        @{ Name = "node-requires-no-receiver-receipt"
           Find = '$script:HordeNodeMessengerRequires = @("body.untyped", "idempotent.post", "receipt.receiver")'
           Replace = '$script:HordeNodeMessengerRequires = @("body.untyped", "idempotent.post")' }
        @{ Name = "unverified-counts-as-yes"
           Find = 'return ((Get-HordeMessengerSupport -Messenger $Messenger -Capability $Capability) -ceq "yes")'
           Replace = 'return ((Get-HordeMessengerSupport -Messenger $Messenger -Capability $Capability) -cne "no")' }
        @{ Name = "misnamed-folder-allowed"
           Find = 'if ("$($Capabilities.messenger)" -cne $leaf) {'
           Replace = 'if ($false) {' }
        @{ Name = "second-registration-replaces"
           Find = 'if ($script:HordeMessengers.ContainsKey("$($caps.messenger)")) {'
           Replace = 'if ($false) {' }
        @{ Name = "message-member-outside-list-allowed"
           Find = 'if ($script:HordeMessengerMembers -cnotcontains $n) {'
           Replace = 'if ($false) {' }
        @{ Name = "sender-member-outside-list-allowed"
           Find = 'if ($script:HordeMessengerFromMembers -cnotcontains $n) {'
           Replace = 'if ($false) {' }
        @{ Name = "line-break-in-identifier-allowed"
           Find = '$Value -cnotmatch "[`r`n]" -and '
           Replace = '' }
        @{ Name = "body-cap-in-characters"
           Find = 'elseif ([System.Text.Encoding]::UTF8.GetByteCount([string]$body.value) -gt $script:HordeMessengerBodyBytes) {'
           Replace = 'elseif (([string]$body.value).Length -gt $script:HordeMessengerBodyBytes) {' }
        @{ Name = "ttl-zero-allowed"
           Find = '-or $ttl.value -lt 1) {'
           Replace = '-or $ttl.value -lt 0) {' }
        @{ Name = "label-unchecked"
           Find = 'if ($lab.has -and -not (Test-HordeMessengerText $lab.value $p.label)) {'
           Replace = 'if ($false) {' }
        @{ Name = "stage-unchecked"
           Find = 'if (-not $stage.has -or $stage.value -isnot [string] -or $script:HordeMessengerStages -cnotcontains $stage.value) {'
           Replace = 'if (-not $stage.has) {' }
        @{ Name = "stage-time-unchecked"
           Find = 'if (-not $at.has -or $at.value -isnot [datetime]) {'
           Replace = 'if ($false) {' }
        @{ Name = "post-absent-allowed"
           Find = 'if ($AllowAbsent) { return $Answer }'
           Replace = 'return $Answer' }
        @{ Name = "invalid-message-handed-over"
           Find = 'if ($findings.Count -gt 0) { return (New-HordeUnknown -Reason ("the message was not handed'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the message was not handed' }
        @{ Name = "status-id-unchecked"
           Find = 'if (-not (Test-HordeMessengerText $MessageId $p.uuid)) {'
           Replace = 'if ($false) {' }
        @{ Name = "adapter-throw-escapes"
           Find = 'catch { return (New-HordeUnknown -Reason ("messenger ''" + $Messenger.name + "'' failed to post " + $id) -ErrorRecord $_) }'
           Replace = 'catch { throw }' }
        # Review of #102.
        @{ Name = "non-string-identifier-allowed"
           Find = 'return ($Value -is [string] -and $Value -cnotmatch'
           Replace = 'return ($Value -cnotmatch' }
        @{ Name = "ttl-ceiling-dropped"
           Find = 'elseif ($ttl.value -gt $script:HordeMessengerTtlMaxSeconds) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "answer-without-message-id-read"
           Find = 'if (-not $said.has -or $said.value -isnot [string]) {'
           Replace = 'if ($false) {' }
        @{ Name = "answer-about-another-message-read"
           Find = 'if ($said.value -cne $MessageId) {'
           Replace = 'if ($false) {' }
        @{ Name = "reason-line-break-allowed"
           Find = 'if ($why -cmatch "[`r`n]") {'
           Replace = 'if ($false) {' }
        @{ Name = "reason-cap-dropped"
           Find = 'if ([System.Text.Encoding]::UTF8.GetByteCount($why) -gt $script:HordeMessengerReasonBytes) {'
           Replace = 'if ($false) {' }
        @{ Name = "held-without-reason-read"
           Find = 'if ($script:HordeMessengerReasonStages -ccontains $stage.value -and $why.Trim() -eq "") {'
           Replace = 'if ($false) {' }
        @{ Name = "empty-reason-written"
           Find = 'if ($why.Trim() -ne "") { $value["reason"] = $why }'
           Replace = '$value["reason"] = $why' }
        @{ Name = "look-alike-messenger-called"
           Find = 'return [object]::ReferenceEquals($script:HordeMessengers[$n.Value], $Messenger)'
           Replace = 'return $true' }
        @{ Name = "send-skips-registration"
           Find = 'if (-not (Test-HordeMessengerRegistered $Messenger)) { return (New-HordeUnknown -Reason ("messenger ''" + (Get-HordeMessengerLabel $Messenger) + "'' is not registered through Register-HordeMessenger, so the post was not made")) }'
           Replace = '' }
        @{ Name = "status-skips-registration"
           Find = 'if (-not (Test-HordeMessengerRegistered $Messenger)) { return (New-HordeUnknown -Reason ("messenger ''" + (Get-HordeMessengerLabel $Messenger) + "'' is not registered through Register-HordeMessenger, so its status was not asked")) }'
           Replace = '' }
    )
}
