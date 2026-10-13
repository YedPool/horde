# Mutations of the runner's sending during its watch (cli/RelayRun.ps1, SENDING DURING THE WATCH,
# 2026-10-13). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\relay-run-send.psd1
# Each breaks one promise of it; test\test-relay-run-send.ps1 must fail for every one. Every find string
# occurs exactly once. The loop's other promises are test\mutations\relay-run.psd1's, against
# test\test-relay-channels.ps1; they are a spec of their own because that suite is slow and this one is
# not, and a mutant should be run against the suite that can catch it.
#
# NOT HERE, and why: a slice shorter than the interval (-SliceMs 5, say) changes nothing a suite can
# see, because the run itself waits out what is left of each interval before it looks - the rule
# "looks-not-paced" and "pace-clock-never-restarts" below hold. And a stop asked while the run waits out
# the rest of an interval ends the look at once; without that it is seen at the top of the next look,
# one Glance later, which no suite can tell apart ("stop-not-seen-between-slices" holds the rule).
@{
    Target = "cli\RelayRun.ps1"
    Suite  = "test\test-relay-run-send.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        # --- the watch is held open and looked into: without it, everything waits for the watch to end
        @{ Name = "nothing-looked-at-during-the-watch"
           Find = '-Between $script:HordeRelayRunBetweenSlices -With $watching'
           Replace = '-With $watching' }
        @{ Name = "slices-as-long-as-the-watch"
           Find = '-SliceMs ([int]$set.sendCheckMs)'
           Replace = '-SliceMs 60000' }
        @{ Name = "a-look-sends-nothing"
           Find = 'if (@($look.due).Count -eq 0) { return $false }'
           Replace = 'if ($true) { return $false }' }
        @{ Name = "what-was-sent-is-not-said"
           Find = '        foreach ($l in @($ticked.lines)) { $null = & $Watching.say $l }'
           Replace = '' }
        # --- a send that fails is not tried again in that watch, and the turn backs off
        @{ Name = "failed-send-tried-again-in-the-watch"
           Find = '        if ($Watching.failed) { return $false }'
           Replace = '' }
        @{ Name = "failed-send-during-the-watch-forgotten"
           Find = 'if ($ticked.failed) { $Watching.failed = $true }'
           Replace = '' }
        @{ Name = "failed-send-during-the-watch-not-counted"
           Find = 'if ($failed -ceq "" -and $watching.failed) {'
           Replace = 'if ($false) {' }
        @{ Name = "turn-that-failed-at-its-top-sends-in-its-watch"
           Find = '$watching.failed = [bool]$ticks.failed;'
           Replace = '$watching.failed = $false;' }
        # --- no spin
        @{ Name = "looks-not-paced"
           Find = 'if ($early -gt 0 -and (Wait-HordeRelayRunSliced -Ms $early -Why "check"'
           Replace = 'if ($false -and (Wait-HordeRelayRunSliced -Ms $early -Why "check"' }
        @{ Name = "pace-clock-never-restarts"
           Find = '    } finally { $Watching.sinceLook.Restart() }'
           Replace = '    } finally { }' }
        # --- a clean stop
        @{ Name = "stop-not-seen-between-slices"
           Find = '    if (Test-HordeRelayRunStopAsked -Path $Watching.stopPath -StartedMs $Watching.startedMs) { return $true }'
           Replace = '' }
        # --- a Glance that cannot look
        @{ Name = "glance-fault-said-every-look"
           Find = 'if (-not $Watching.said.ContainsKey($l)) { $Watching.said[$l] = $true; $null = & $Watching.say $l }'
           Replace = '$null = & $Watching.say $l' }
        @{ Name = "glance-fault-never-said"
           Find = 'if (-not $Watching.said.ContainsKey($l)) { $Watching.said[$l] = $true; $null = & $Watching.say $l }'
           Replace = '$null = $l' }
        # --- the setting
        @{ Name = "interval-has-no-floor"
           Find = 'min = 200; max = 60000'
           Replace = 'min = 0; max = 60000' }
        @{ Name = "interval-has-no-ceiling"
           Find = 'default = 1000; min = 200; max = 60000'
           Replace = 'default = 1000; min = 200; max = 6000000' }
        @{ Name = "interval-default-is-not-a-second"
           Find = 'name = "sendCheckMs"; kind = "whole"; default = 1000'
           Replace = 'name = "sendCheckMs"; kind = "whole"; default = 5000' }
    )
}
