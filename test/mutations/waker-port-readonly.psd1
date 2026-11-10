# Mutations of the read-only view in wakers/Port.ps1 (T-0116). Run: powershell -File tools\Mutate.ps1 -Spec test\mutations\waker-port-readonly.psd1
# The view of a registered waker has no nudge and no exit, no member that leads back to the real waker, is the
# port's own object (not a shape anyone can copy), goes stale when its waker's registry entry is replaced, is
# the same object every time, and a nudge asked of a waker with none is a refusal that falls back to nothing;
# test\test-wake-port.ps1 must fail for every one.
@{
    Target = "wakers\Port.ps1"
    Suite  = "test\test-wake-port.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "the-view-keeps-the-nudge"
           Find = 'nudge = $null; begin = $Waker.begin'
           Replace = 'nudge = $Waker.nudge; begin = $Waker.begin' }
        @{ Name = "the-view-keeps-the-exit"
           Find = 'reserved = $Waker.reserved; exit = $null }'
           Replace = 'reserved = $Waker.reserved; exit = $Waker.exit }' }
        @{ Name = "the-view-names-the-real-waker"
           Find = '$script:HordeWakerViewOrigin[$name] = $Waker'
           Replace = '$script:HordeWakerViewOrigin[$name] = $Waker; Add-Member -InputObject $view -MemberType NoteProperty -Name "of" -Value $Waker' }
        @{ Name = "a-waker-with-no-nudge-is-asked-anyway"
           Find = 'if ($null -eq $Waker.nudge) { return (New-HordeUnknown'
           Replace = 'if ($false) { return (New-HordeUnknown' }
        @{ Name = "the-view-is-not-the-registered-wakers-own"
           Find = 'if (-not ($script:HordeWakerViews.ContainsKey($n.Value) -and [object]::ReferenceEquals($script:HordeWakerViews[$n.Value], $Waker))) { return $false }'
           Replace = 'return $false' }
        @{ Name = "a-look-alike-passes-for-the-view"
           Find = '-and [object]::ReferenceEquals($script:HordeWakerViews[$n.Value], $Waker))) { return $false }'
           Replace = ')) { return $false }' }
        @{ Name = "a-stale-view-is-accepted"
           Find = 'return ($script:HordeWakerViewOrigin.ContainsKey($n.Value) -and [object]::ReferenceEquals($script:HordeWakerViewOrigin[$n.Value], $script:HordeWakers[$n.Value]))'
           Replace = 'return $true' }
        @{ Name = "the-view-is-made-afresh-every-time"
           Find = 'if (-not $script:HordeWakerViews.ContainsKey($name) -or -not [object]::ReferenceEquals($script:HordeWakerViewOrigin[$name], $Waker)) {'
           Replace = 'if ($true) {' }
        @{ Name = "the-view-of-a-view-is-another-view"
           Find = 'if ($script:HordeWakerViews.ContainsKey($name) -and [object]::ReferenceEquals($script:HordeWakerViews[$name], $Waker)) { return $Waker }'
           Replace = 'if ($false) { return $Waker }' }
    )
}
