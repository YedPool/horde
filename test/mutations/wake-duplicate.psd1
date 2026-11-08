# Mutations of core/Wake.ps1 for T-0116 (two running copies of a session with mail waiting). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-duplicate.psd1
# Kept in a spec of its own: the suite that holds the cases is test\test-wake-run.ps1, which reads the
# pass through the tick. Each breaks one thing the line and the hold exist for; that suite must fail for every one.
@{
    Target = "core\Wake.ps1"
    Suite  = "test\test-wake-run.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-duplicate-with-no-mail-is-said"
           Find = 'if ($a.value.unreadCount -gt 0 -and "$(Get-HordeWakeEntryValue $t "duplicate")" -ceq "yes"'
           Replace = 'if ($a.value.unreadCount -ge 0 -and "$(Get-HordeWakeEntryValue $t "duplicate")" -ceq "yes"' }
        @{ Name = "a-session-that-is-not-a-duplicate-is-said"
           Find = 'if ($a.value.unreadCount -gt 0 -and "$(Get-HordeWakeEntryValue $t "duplicate")" -ceq "yes"'
           Replace = 'if ($a.value.unreadCount -gt 0 -and "$(Get-HordeWakeEntryValue $t "duplicate")" -cne "zzz"' }
        @{ Name = "a-duplicate-is-nudged"
           Find = 'if ("$(Get-HordeWakeEntryValue $Target "duplicate")" -ceq "yes") { return'
           Replace = 'if ($false) { return' }
        @{ Name = "a-duplicate-is-not-said-at-all"
           Find = '$duplicate[$t.id] = "two running copies'
           Replace = '$null = "two running copies' }
    )
}
