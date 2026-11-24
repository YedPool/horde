# Mutations of tools/NightlyNet.ps1's unit queue when a unit no longer fits the night (T-0514 part b). Night
# 2026-11-22 the 3600 s pytest-all no longer fitted and a break dropped flake8-critical behind it, which did. Run:
# powershell -File tools\Mutate.ps1 -Spec test\mutations\nightly-skip-unfit.psd1
@{
    Target = "tools\NightlyNet.ps1"
    Suite  = "test\test-nightly-net.ps1"
    Mutations = @(
        @{ Name = "unfit-unit-breaks-the-queue"
           Find = 'slot wait " + (Get-NightlySlotWait) + " s)"); continue }'
           Replace = 'slot wait " + (Get-NightlySlotWait) + " s)"); break }' }
        @{ Name = "unfit-unit-not-logged"
           Find = '$Ctx.incomplete = "the night ran out before every unit ran"; Write-NightlyNetLine ($Ctx.repo + " " + $u + " -> not tried'
           Replace = '$Ctx.incomplete = "the night ran out before every unit ran"; [void]($Ctx.repo + " " + $u + " -> not tried' }
        @{ Name = "unfit-unit-night-still-complete"
           Find = 'if ($secs -le 0) { $Ctx.incomplete = "the night ran out before every unit ran"; '
           Replace = 'if ($secs -le 0) { ' }
        @{ Name = "undecided-pytest-all-counted-only-when-sent-back"
           Find = 'if (@($Ctx.units) -ccontains "pytest-all" -and -not $Ctx.pytestDecided) {'
           Replace = 'if ($Ctx.requeued.ContainsKey("pytest-all") -and -not $Ctx.pytestDecided) {' }
    )
}
