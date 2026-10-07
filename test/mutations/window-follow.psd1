# Mutations of platform/windows/WindowFollow.ps1, which keeps one window beside another. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\window-follow.psd1
# test\test-window-follow.ps1 must fail for each. That suite touches no window, so this spec holds the
# placement arithmetic and the refusals; the following itself is test\e2e\e2e-decisions-window.ps1's.
@{
    Target = "platform\windows\WindowFollow.ps1"
    Suite  = "test\test-window-follow.ps1"
    Mutations = @(
        @{ Name = "placed-at-the-left"
           Find = 'left = ($right - $marginRight - $width); top'
           Replace = 'left = ($left + $marginRight); top' }
        @{ Name = "right-margin-forgotten"
           Find = 'left = ($right - $marginRight - $width); top'
           Replace = 'left = ($right - $width); top' }
        @{ Name = "top-margin-forgotten"
           Find = 'top = ($top + $marginTop); width'
           Replace = 'top = $top; width' }
        @{ Name = "half-the-width"
           Find = 'widthShare = 3;'
           Replace = 'widthShare = 2;' }
        @{ Name = "no-smallest-width"
           Find = '$width = [Math]::Max([int][Math]::Round($targetWidth / [double]$f.widthShare), (& $scale $f.minWidth))'
           Replace = '$width = [int][Math]::Round($targetWidth / [double]$f.widthShare)' }
        @{ Name = "wider-than-the-other-window"
           Find = '$width = [Math]::Min($width, [Math]::Max($targetWidth - 2 * $marginRight, 1))'
           Replace = '' }
        @{ Name = "bottom-margin-forgotten"
           Find = '$height = [Math]::Max($targetHeight - $marginTop - $marginBottom,'
           Replace = '$height = [Math]::Max($targetHeight - $marginTop,' }
        @{ Name = "below-the-other-windows-bottom"
           Find = '[Math]::Min((& $scale $f.minHeight), [Math]::Max($targetHeight - $marginTop, 1)))'
           Replace = '(& $scale $f.minHeight))' }
        @{ Name = "margins-not-scaled"
           Find = '$scale = { param([int]$n) return [int][Math]::Round($n * $Dpi / 96.0) }'
           Replace = '$scale = { param([int]$n) return $n }' }
        @{ Name = "top-margin-of-another-size"
           Find = 'marginTop = 48;'
           Replace = 'marginTop = 24;' }
        @{ Name = "any-mode-placed-as-floating"
           Find = 'if ($script:HordeWindowFollowModes -cnotcontains $Mode) { throw ('
           Replace = 'if ($false) { throw (' }
        @{ Name = "mode-matched-without-case"
           Find = 'if ($script:HordeWindowFollowModes -cnotcontains $Mode) { throw ('
           Replace = 'if ($script:HordeWindowFollowModes -notcontains $Mode) { throw (' }
        @{ Name = "empty-rectangle-placed"
           Find = 'if ($right -le $left -or $bottom -le $top) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-window-with-no-height-placed"
           Find = 'if ($right -le $left -or $bottom -le $top) {'
           Replace = 'if ($right -le $left) {' }
        @{ Name = "any-scale-taken"
           Find = 'if ($Dpi -lt 48 -or $Dpi -gt 960) {'
           Replace = 'if ($Dpi -lt 0) {' }
        @{ Name = "a-mode-not-built-is-followed"
           Find = 'if ($script:HordeWindowFollowModes -cnotcontains $Mode) { return [pscustomobject]@{ state = "failed"'
           Replace = 'if ($false) { return [pscustomobject]@{ state = "failed"' }
        @{ Name = "a-window-that-is-not-there-is-followed"
           Find = 'if ($Target -eq 0 -or -not [HordeWindowFollowNative]::Exists($Target)) {'
           Replace = 'if ($Target -eq 0) {' }
    )
}
