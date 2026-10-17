# Mutations of the one place that decides what becomes a notice (notices/Decide.ps1). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\notices.psd1
# test\test-notices.ps1 must fail for every one. Every find string occurs exactly once.
@{
    Target = "notices\Decide.ps1"
    Suite  = "test\test-notices.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "a-secret-is-sent"
           Find = 'if ((Find-HordeSecretKind -Text $whole) -cne "") { return [pscustomobject]@{ text = (Get-HordeNoticeSecretWords); refused = $true } }'
           Replace = '' }
        @{ Name = "the-text-is-cut-before-it-is-checked"
           Find = '    $whole = ([regex]::Replace($Text, ''\p{Cc}'', '' '')).Trim()'
           Replace = '    $whole = ([regex]::Replace($Text, ''\p{Cc}'', '' '')).Trim(); if ($whole.Length -gt $Chars) { $whole = $whole.Substring(0, $Chars - 3) }' }
        @{ Name = "no-hourly-cap"
           Find = 'if ($mine.count -ge $cap) {'
           Replace = 'if ($false) {' }
        @{ Name = "the-founder-is-told-every-time"
           Find = 'if ($mine.told) { return [pscustomobject]@{ outcome = "held"; reason = $why; notice = $null } }'
           Replace = '' }
        @{ Name = "the-count-never-starts-again"
           Find = 'if ($null -eq $mine -or $mine.hour -cne $hour) {'
           Replace = 'if ($null -eq $mine) {' }
        @{ Name = "the-count-is-not-kept"
           Find = '        $mine.count = $mine.count + 1'
           Replace = '' }
        @{ Name = "a-two-line-text-is-taken"
           Find = 'if ($Text -cmatch "[\r\n]") { return (& $fail "no notice was sent: -Text is one line, and it has a line break") }'
           Replace = '' }
        @{ Name = "an-unproven-sender-sends"
           Find = 'if ($null -eq $Sender -or -not $Sender.ok -or'
           Replace = 'if ($null -eq $Sender -or' }
        @{ Name = "followed-by-default"
           Find = '$on = @(@($f.value.Keys) | Where-Object { $f.value[$_].on })'
           Replace = '$on = @(@($f.value.Keys) + @("E", "B", "thrall"))' }
        @{ Name = "an-entry-is-a-notice-again"
           Find = '            if ($done.Contains($e.id)) { continue }'
           Replace = '' }
        @{ Name = "an-entry-of-two-lanes-is-two-notices"
           Find = '$through = @($lanes | Where-Object { $on -ccontains $_ } | Select-Object -First 1)'
           Replace = '$through = @($lanes | Where-Object { $on -ccontains $_ } | Select-Object -Last 1)' }
        @{ Name = "an-entry-of-no-lane-is-nobodys"
           Find = '            if ($lanes.Count -eq 0) { $lanes = @("thrall") }'
           Replace = '' }
        @{ Name = "an-earlier-switch-overrules-a-later-one"
           Find = 'if ($null -ne $had -and ($had.at -gt $At -or'
           Replace = 'if ($null -ne $had -and ($false -or' }
        @{ Name = "a-secret-label-is-shown"
           Find = '$fromWords = $(if ($from.refused) { $(if ($isService) { "a service" } else { "a session" }) } else { $from.text })'
           Replace = '$fromWords = $Sender.label' }
    )
}
