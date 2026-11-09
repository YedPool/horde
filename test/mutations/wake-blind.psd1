# Mutations of the blind-look rules in core/Wake.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-blind.psd1
# Each breaks one rule of a look the terminal did not answer; test\test-wake-blind.ps1 must fail for every one.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-wake-blind.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-blind-look-is-read-as-a-look-that-read"
           Find = 'if ($why -cne "") { $blindLooks["$($d.id)"] = $why } else { [void]$seenLooks.Add("$($d.id)") }'
           Replace = '[void]$seenLooks.Add("$($d.id)")' }
        @{ Name = "a-blind-session-is-looked-at-every-pass"
           Find = 'if ($hold.action -ceq "look" -and $null -ne $BlindWait -and $BlindWait.ContainsKey($id)) {'
           Replace = 'if ($false) {' }
        @{ Name = "nobody-is-held-back-by-a-spell"
           Find = '$blindWait = Get-HordeWakeBlindWait -Seen $Blind -Now $Now'
           Replace = '$blindWait = @{}' }
        @{ Name = "the-back-off-never-grows"
           Find = 'nextAt = $Now.AddSeconds((Get-HordeWakeBackoffSeconds -Attempts $looks -Settings $Settings))'
           Replace = 'nextAt = $Now.AddSeconds((Get-HordeWakeBackoffSeconds -Attempts 1 -Settings $Settings))' }
        @{ Name = "the-back-off-is-the-longest-at-once"
           Find = 'nextAt = $Now.AddSeconds((Get-HordeWakeBackoffSeconds -Attempts $looks -Settings $Settings))'
           Replace = 'nextAt = $Now.AddSeconds((Get-HordeWakeBackoffSeconds -Attempts 99 -Settings $Settings))' }
        @{ Name = "a-session-is-held-back-at-the-moment-its-back-off-ends"
           Find = 'if ($left -gt 0) { $wait["$id"]'
           Replace = 'if ($left -ge 0) { $wait["$id"]' }
        @{ Name = "every-blind-look-is-journaled"
           Find = 'if ($null -eq $was -or "$($was.reason)" -cne $reason) {'
           Replace = 'if ($true) {' }
        @{ Name = "a-changed-reason-is-not-journaled"
           Find = 'if ($null -eq $was -or "$($was.reason)" -cne $reason) {'
           Replace = 'if ($null -eq $was) {' }
        @{ Name = "a-spell-never-ends"
           Find = '        $next.Remove("$id")'
           Replace = '        $null = $id' }
        @{ Name = "the-seen-line-forgets-how-many-looks"
           Find = '$next["$id"].looks + " blind look(s) since "'
           Replace = '"0" + " blind look(s) since "' }
        @{ Name = "a-session-gone-from-the-listing-is-kept"
           Find = 'if ($null -eq $Listed -or @($Listed) -ccontains "$id") {'
           Replace = 'if ($true) {' }
        @{ Name = "an-unreadable-listing-forgets-every-spell"
           Find = 'if ($null -eq $Listed -or @($Listed) -ccontains "$id") {'
           Replace = 'if (@($Listed) -ccontains "$id") {' }
        @{ Name = "the-passs-looks-are-not-counted"
           Find = 'acks = $Acks; looks = $looks;'
           Replace = 'acks = $Acks; looks = 0;' }
        @{ Name = "a-blind-reason-is-lost"
           Find = '$blindLooks["$($d.id)"] = $why'
           Replace = '$blindLooks["$($d.id)"] = "unknown"' }
    )
}
