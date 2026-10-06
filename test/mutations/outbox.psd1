# Mutations of the node's outbox. Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\outbox.psd1
# Each mutation loosens one guarantee of remote/Outbox.ps1 (R21 slice 4), and test\test-outbox.ps1 must
# fail for every one. Every find string occurs exactly once.
@{
    Target = "remote\Outbox.ps1"
    Suite  = "test\test-outbox.ps1"
    Mutations = @(
        @{ Name = "unmade-root-read-as-empty"
           Find = 'if ($m.kind -ne "ok" -or "$(Get-HordeJournalProp $m.data ''kind'')" -cne "outbox") {'
           Replace = 'if ($false) {' }
        @{ Name = "second-write-accepted"
           Find = 'if ($made -eq "exists") { return (New-HordeUnknown -Reason ("message "'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("message "' }
        @{ Name = "uncarriable-mail-accepted"
           Find = 'if ($found.Count -gt 0) { return (New-HordeUnknown -Reason ("not put in the outbox'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("not put in the outbox' }
        @{ Name = "ttl-ceiling-unchecked"
           Find = 'if ($found.Count -eq 0) { $found = @(Test-HordeLinkTtlCeiling'
           Replace = 'if ($false) { $found = @(Test-HordeLinkTtlCeiling' }
        @{ Name = "marker-for-a-missing-message"
           Find = 'if ($rec.kind -ne "ok") { return (New-HordeUnknown -Reason ("the outbox holds no message'
           Replace = 'if ($false) { return (New-HordeUnknown -Reason ("the outbox holds no message' }
        @{ Name = "handed-out-never-read"
           Find = '$handed = @($mine | Where-Object { $_.marker -ceq $script:HordeOutboxHanded }).Count -gt 0'
           Replace = '$handed = $false' }
    )
}
