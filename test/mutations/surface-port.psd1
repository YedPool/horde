# Mutations of surfaces/Port.ps1, the surface port and the closed list of requests a page may make. Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\surface-port.psd1
# test\test-surface-port.ps1 must fail for each.
@{
    Target = "surfaces\Port.ps1"
    Suite  = "test\test-surface-port.ps1"
    Mutations = @(
        # --- the closed list
        # No mutant removes the look-up in the table: without it an unknown name reaches no handler
        # either, the suite stops on a null request, and a suite that stops has caught nothing.
        @{ Name = "request-name-matched-without-case"
           Find = '$nameProp.Value -cnotmatch $script:HordeSurfaceNamePattern'
           Replace = '$false' }
        @{ Name = "refusal-not-recorded"
           Find = '        Add-HordeSurfaceRefusal -Bridge $Bridge -Reason $Why -Now $Now'
           Replace = '' }
        @{ Name = "refusal-not-counted"
           Find = '$Bridge.refused = [int]$Bridge.refused + 1'
           Replace = '' }
        @{ Name = "refusal-record-grows-for-ever"
           Find = 'while ($Bridge.refusals.Count -gt $script:HordeSurfaceRefusalsKept) { $Bridge.refusals.RemoveAt(0) }'
           Replace = '' }
        @{ Name = "refusal-answered-with-no-reason"
           Find = 'ok = $false; reason = ("refused: " + $Why) })'
           Replace = 'ok = $true; reason = ("refused: " + $Why) })' }
        # --- the message
        @{ Name = "oversized-message-read"
           Find = 'if ($Text.Length -gt $script:HordeSurfaceRequestChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "size-cap-one-short"
           Find = 'if ($Text.Length -gt $script:HordeSurfaceRequestChars) {'
           Replace = 'if ($Text.Length -ge $script:HordeSurfaceRequestChars) {' }
        @{ Name = "a-list-taken-as-a-message"
           Find = 'if ($null -eq $message -or $message -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($null -eq $message) {' }
        @{ Name = "id-of-zero-taken"
           Find = '[long]$idProp.Value -ge 1 -and'
           Replace = '[long]$idProp.Value -ge 0 -and' }
        @{ Name = "unknown-member-ignored"
           Find = 'if (@("v", "id", "request", "args") -cnotcontains $p.Name) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-version-taken"
           Find = ' -or [long]$vProp.Value -ne $script:HordeSurfaceProtocol) {'
           Replace = ') {' }
        # --- the arguments
        @{ Name = "undeclared-argument-passed-on"
           Find = 'foreach ($n in $names) { if (-not $Request.args.Contains($n)) {'
           Replace = 'foreach ($n in $names) { if ($false) {' }
        @{ Name = "missing-argument-accepted"
           Find = 'if ($names -cnotcontains $argName) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-taken-for-a-number"
           Find = 'if ($v -isnot [int] -and $v -isnot [long]) {'
           Replace = 'if ($false) {' }
        @{ Name = "number-past-its-cap-taken"
           Find = 'if ([long]$v -lt 0 -or [long]$v -gt $spec.most) {'
           Replace = 'if ([long]$v -lt 0) {' }
        @{ Name = "negative-number-taken"
           Find = 'if ([long]$v -lt 0 -or [long]$v -gt $spec.most) {'
           Replace = 'if ([long]$v -gt $spec.most) {' }
        @{ Name = "number-taken-for-text"
           Find = 'if ($v -isnot [string]) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-past-its-cap-taken"
           Find = 'if ($v.Length -gt $spec.most) {'
           Replace = 'if ($false) {' }
        @{ Name = "text-taken-for-true-or-false"
           Find = 'elseif ($v -isnot [bool]) {'
           Replace = 'elseif ($false) {' }
        @{ Name = "args-as-a-list-taken"
           Find = 'if ($Given -isnot [System.Management.Automation.PSCustomObject]) { return "its args is not an object" }'
           Replace = '' }
        @{ Name = "argument-type-open"
           Find = 'if ($script:HordeSurfaceArgTypes -cnotcontains "$($spec["type"])") {'
           Replace = 'if ($false) {' }
        # --- the answer
        @{ Name = "handler-failure-counted-as-a-refusal"
           Find = 'return [pscustomobject]@{ reply = $failLine; refused = ""; request = $request.name }'
           Replace = 'return [pscustomobject]@{ reply = $failLine; refused = "the request failed"; request = $request.name }' }
        @{ Name = "non-ascii-sent-raw"
           Find = 'return [regex]::Replace($json, ''[^\x20-\x7E]'', { param($m) ''\u'' + ([int][char]$m.Value).ToString("x4") })'
           Replace = 'return $json' }
        @{ Name = "undeclared-event-pushed"
           Find = 'if (@($Bridge.events) -cnotcontains $Name) {'
           Replace = 'if ($false) {' }
        # --- the surfaces
        @{ Name = "look-alike-surface-opened"
           Find = 'if ($null -eq $registered -or -not [object]::ReferenceEquals($registered, $Surface)) {'
           Replace = 'if ($false) {' }
        @{ Name = "second-registration-swaps-the-first"
           Find = 'if ($script:HordeSurfaces.ContainsKey("$($caps.surface)")) {'
           Replace = 'if ($false) {' }
        @{ Name = "capabilities-may-name-another-folder"
           Find = 'if ("$($Capabilities.surface)" -cne $leaf) {'
           Replace = 'if ($false) {' }
        @{ Name = "anything-but-yes-counts"
           Find = 'return ("$($Surface.capabilities.capabilities.$Capability.support)" -ceq "yes")'
           Replace = 'return ("$($Surface.capabilities.capabilities.$Capability.support)" -cne "")' }
        @{ Name = "surface-that-throws-is-shown"
           Find = 'catch { return [pscustomobject]@{ state = "failed"; reason = ("the surface could not be shown: " + $_.Exception.Message) } }'
           Replace = 'catch { return [pscustomobject]@{ state = "closed"; reason = "" } }' }
        @{ Name = "any-answer-taken-as-shown"
           Find = 'if ($null -eq $last -or @("closed", "failed") -cnotcontains "$($last.state)") {'
           Replace = 'if ($null -eq $last) {' }
        # --- the spec
        @{ Name = "start-page-may-climb-out"
           Find = '\A([a-z][a-z0-9-]{0,31})/([A-Za-z0-9][A-Za-z0-9._-]{0,63})\z'
           Replace = '\A([a-z][a-z0-9-]{0,31})/(.+)\z' }
        @{ Name = "missing-start-page-accepted"
           Find = 'if (-not (Test-Path -LiteralPath (Join-Path $mountTable[$startMount] $startFile) -PathType Leaf)) {'
           Replace = 'if ($false) {' }
        @{ Name = "relative-mount-accepted"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($folder) -or '
           Replace = 'if (' }
        @{ Name = "relative-data-folder-accepted"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($DataFolder)) {'
           Replace = 'if ($false) {' }
    )
}
