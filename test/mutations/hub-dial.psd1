# Mutations of the hub's dialled links (cli/HubServe.ps1; remote plan R17c). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\hub-dial.psd1
# test\test-hub-dial.ps1 must fail for each. The preamble checks are this file's stand-in for R17a's
# Read-HordeAttachPreamble; the cases keep holding when the stand-in becomes a call to it.
@{
    Target = "cli\HubServe.ps1"
    Suite  = "test\test-hub-dial.ps1"
    Mutations = @(
        @{ Name = "preamble-not-required"
           Find = 'if ($dev.state -cne "known") { return ("a dialled link was refused: " + $dev.reason) }'
           Replace = 'if ($dev.state -cne "known") { $dev = New-HordeKnown -Value "0f8fad5b-d9cb-469f-a165-70867728950e" }' }
        @{ Name = "preamble-read-from-a-later-line"
           Find = '$dev = Read-HordeAttachPreamble -Line "$($first.value)"'
           Replace = '$dev = Read-HordeAttachPreamble -Line ("horde-attach 1 " + "$($first.value)".Split(" ")[-1])' }
        @{ Name = "dialled-link-left-open"
           Find = '    } finally { Close-HordeLink -Link $Link }'
           Replace = '    } finally { }' }
        # Issue #144, item 2: a round whose pulls ran past its interval still listens.
        @{ Name = "dial-window-floor-dropped"
           Find = 'return [int][Math]::Max([Math]::Max(0, $MinMs), $IntervalMs - $ElapsedMs)'
           Replace = 'return [int][Math]::Max(0, $IntervalMs - $ElapsedMs)' }
        # Issue #144 item 3 and issue #124: only an enrolled device is bound, and only while it stays so.
        @{ Name = "unenrolled-device-bound"
           Find = 'if ($why -ne "") { return ("a dialled link for device " + $dev.value + " was refused: " + $why) }'
           Replace = '' }
        @{ Name = "no-check-binds-anyone"
           Find = 'if ($null -eq $Admit) { return ("a dialled link for device "'
           Replace = 'if ($false) { return ("a dialled link for device "' }
        @{ Name = "check-that-throws-admits"
           Find = 'catch { $why = "its enrolment could not be checked: " + $_.Exception.Message }'
           Replace = 'catch { $why = "" }' }
        @{ Name = "not-rechecked-before-the-ping"
           Find = 'if ($cutPing -ne "") { $res.reason = $cutPing; return $res }'
           Replace = '' }
        @{ Name = "not-rechecked-before-the-list"
           Find = 'if ($cutList -ne "") { $res.reason = $cutList; return $res }'
           Replace = '' }
        @{ Name = "cut-without-a-bye"
           Find = '$null = Send-HordeHubFrame -Link $Link -Frame (New-HordeLinkBye -Code "refused" -Reason $reason -Seq $Seq -Contract $Contract) -Contract $Contract'
           Replace = '' }
        @{ Name = "dialled-pull-not-rechecked"
           Find = '-Link $Link -Admit $Admit -ActDir $ActDir -ActTimeoutMs $ActTimeoutMs)'
           Replace = '-Link $Link -ActDir $ActDir -ActTimeoutMs $ActTimeoutMs)' }
        @{ Name = "serve-drops-the-check"
           Find = '-BudgetMs $NodeBudgetMs -Admit $Admit -ActDir $ActDir -ActTimeoutMs $ActTimeoutMs)) {'
           Replace = '-BudgetMs $NodeBudgetMs -ActDir $ActDir -ActTimeoutMs $ActTimeoutMs)) {' }
        @{ Name = "listener-window-skipped"
           Find = 'if ($null -ne $Listener) {'
           Replace = 'if ($false) {' }
    )
}
