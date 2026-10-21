# Mutations of the -OnlyIds half of fleet/Wake.ps1: a wake of part of a lot (T-0216). test/test-fleet-lots.ps1 must fail a check for every one. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\wake-lots.psd1
@{
    Target = "fleet\Wake.ps1"
    Suite  = "test\test-fleet-lots.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "only-ids-wakes-everyone"
           Find = 'if ($idsAsked.Count -gt 0) { $all = @($all | Where-Object { $idsAsked -ccontains ("" + $_.sessionId) }) }'
           Replace = '' }
    )
}
