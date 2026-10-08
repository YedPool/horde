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
           Find = 'while ($Bridge.refusals.Count -gt $Bridge.limits.refusalsKept) { $Bridge.refusals.RemoveAt(0) }'
           Replace = '' }
        @{ Name = "refusal-answered-with-no-reason"
           Find = '$say.ok = $false; $say.reason = ("refused: " + $Why) })'
           Replace = '$say.ok = $true; $say.reason = ("refused: " + $Why) })' }
        # --- the message
        @{ Name = "oversized-message-read"
           Find = 'if ($Text.Length -gt $Bridge.limits.messageChars) {'
           Replace = 'if ($false) {' }
        @{ Name = "size-cap-one-short"
           Find = 'if ($Text.Length -gt $Bridge.limits.messageChars) {'
           Replace = 'if ($Text.Length -ge $Bridge.limits.messageChars) {' }
        # --- the list of errors a surface keeps
        @{ Name = "the-list-of-errors-is-never-trimmed"
           Find = 'while ($Errors.Count -gt $Kept) { $Errors.RemoveAt(0) }'
           Replace = '' }
        @{ Name = "the-newest-error-is-the-one-dropped"
           Find = 'while ($Errors.Count -gt $Kept) { $Errors.RemoveAt(0) }'
           Replace = 'while ($Errors.Count -gt $Kept) { $Errors.RemoveAt($Errors.Count - 1) }' }
        @{ Name = "an-empty-line-is-kept-as-an-error"
           Find = 'if ("$Text" -eq "") { return }'
           Replace = '' }
        @{ Name = "a-spec-ignores-how-many-errors-to-keep"
           Find = 'errorsKept = [int]$Settings.values.errorsKept; messagesPerSecond'
           Replace = 'errorsKept = 50; messagesPerSecond' }
        # --- a page that floods is not read
        @{ Name = "a-flood-is-read"
           Find = 'if ($Meter.read -lt $PerSecond) {'
           Replace = 'if ($true) {' }
        @{ Name = "one-message-too-many-is-read"
           Find = 'if ($Meter.read -lt $PerSecond) {'
           Replace = 'if ($Meter.read -le $PerSecond) {' }
        @{ Name = "a-flood-is-recorded-once-a-message"
           Find = 'if (-not $Meter.told) { $Meter.told = $true; return "refuse" }'
           Replace = 'if ($true) { $Meter.told = $true; return "refuse" }' }
        @{ Name = "a-second-never-ends"
           Find = '($NowMs - $Meter.startedMs) -ge $script:HordeSurfaceMeterWindowMs -or '
           Replace = '' }
        @{ Name = "a-clock-that-went-backwards-drops-for-ever"
           Find = ' -or $NowMs -lt $Meter.startedMs) {'
           Replace = ') {' }
        @{ Name = "what-is-dropped-is-not-counted"
           Find = '$Meter.dropped = $Meter.dropped + 1'
           Replace = '' }
        @{ Name = "the-second-is-half-a-second"
           Find = '$script:HordeSurfaceMeterWindowMs = 1000'
           Replace = '$script:HordeSurfaceMeterWindowMs = 500' }
        @{ Name = "a-spec-ignores-how-many-messages-to-read"
           Find = 'messagesPerSecond = [int]$Settings.values.messagesPerSecond'
           Replace = 'messagesPerSecond = 100' }
        # --- a value too deep to be written whole
        @{ Name = "a-value-too-deep-is-written-in-pieces"
           Find = 'if (-not (Test-HordeSurfaceDepth -Value $Value -Most ($script:HordeSurfaceJsonDepth + 1))) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "a-value-one-level-too-deep-is-written"
           Find = 'if (-not (Test-HordeSurfaceDepth -Value $Value -Most ($script:HordeSurfaceJsonDepth + 1))) { throw'
           Replace = 'if (-not (Test-HordeSurfaceDepth -Value $Value -Most ($script:HordeSurfaceJsonDepth + 2))) { throw' }
        @{ Name = "a-value-of-the-allowed-depth-is-refused"
           Find = 'if (-not (Test-HordeSurfaceDepth -Value $Value -Most ($script:HordeSurfaceJsonDepth + 1))) { throw'
           Replace = 'if (-not (Test-HordeSurfaceDepth -Value $Value -Most $script:HordeSurfaceJsonDepth)) { throw' }
        @{ Name = "what-a-table-holds-is-not-looked-into"
           Find = 'if ($Value -is [System.Collections.IDictionary]) { $inside = @($Value.Values) }'
           Replace = 'if ($Value -is [System.Collections.IDictionary]) { $inside = @() }' }
        @{ Name = "an-object-is-not-a-level"
           Find = 'elseif ($Value -is [System.Management.Automation.PSCustomObject]) { $inside ='
           Replace = 'elseif ($false) { $inside =' }
        @{ Name = "a-list-is-not-a-level"
           Find = 'elseif ($Value -is [System.Collections.IEnumerable]) { $inside = @($Value) }'
           Replace = 'elseif ($false) { $inside = @($Value) }' }
        @{ Name = "why-an-answer-could-not-be-written-is-not-kept"
           Find = 'catch { return (& $fail ("its answer could not be handed over: " + $_.Exception.Message)) }'
           Replace = 'catch { return (& $fail "") }' }
        # --- a request that fails: one fixed sentence for the page, the handler's words kept on Horde's side
        @{ Name = "a-failed-request-is-said-to-be-fine"
           Find = '$say.ok = $false; $say.reason = $told })'
           Replace = '$say.ok = $true; $say.reason = $told })' }
        @{ Name = "the-page-is-handed-what-the-handler-said"
           Find = '$say.ok = $false; $say.reason = $told })'
           Replace = '$say.ok = $false; $say.reason = $kept })' }
        @{ Name = "what-a-handler-said-is-not-kept"
           Find = 'catch { return (& $fail ("" + $_.Exception.Message)) }'
           Replace = 'catch { return (& $fail "") }' }
        @{ Name = "only-that-it-failed-is-kept"
           Find = '$kept = $told + ": " + $What'
           Replace = '$kept = $told' }
        @{ Name = "a-failure-is-not-recorded-on-the-bridge"
           Find = '        Add-HordeSurfaceFailure -Bridge $Bridge -Reason $kept -Now $Now'
           Replace = '' }
        @{ Name = "a-failure-is-recorded-at-another-time"
           Find = '        Add-HordeSurfaceFailure -Bridge $Bridge -Reason $kept -Now $Now'
           Replace = '        Add-HordeSurfaceFailure -Bridge $Bridge -Reason $kept' }
        @{ Name = "a-failure-is-not-handed-to-the-surface"
           Find = 'request = $request.name; failed = $kept }'
           Replace = 'request = $request.name; failed = "" }' }
        @{ Name = "a-failure-is-not-counted"
           Find = '$Bridge.failed = [int]$Bridge.failed + 1'
           Replace = '' }
        @{ Name = "the-record-of-failures-grows-for-ever"
           Find = 'while ($Bridge.failures.Count -gt $Bridge.limits.errorsKept) { $Bridge.failures.RemoveAt(0) }'
           Replace = '' }
        @{ Name = "failures-are-kept-by-the-refusals-number"
           Find = 'errorsKept = [int]$Settings.values.errorsKept }'
           Replace = 'errorsKept = [int]$Settings.values.refusalsKept }' }
        @{ Name = "an-answered-request-says-it-failed"
           Find = 'return [pscustomobject]@{ reply = $line; refused = ""; request = $request.name; failed = "" }'
           Replace = 'return [pscustomobject]@{ reply = $line; refused = ""; request = $request.name; failed = "it failed" }' }
        @{ Name = "a-refused-request-says-it-failed"
           Find = 'return [pscustomobject]@{ reply = $line; refused = $Why; request = ""; failed = "" }'
           Replace = 'return [pscustomobject]@{ reply = $line; refused = $Why; request = ""; failed = "it failed" }' }
        # No mutant lets the walk go on past its limit: a value that holds itself would then be walked
        # until the call stack gave out, and a suite that dies has caught nothing.
        # --- the module's settings
        @{ Name = "a-bridge-ignores-the-message-size-it-was-given"
           Find = 'messageChars = [int]$Settings.values.messageChars;'
           Replace = 'messageChars = 65536;' }
        @{ Name = "a-bridge-ignores-the-argument-length-it-was-given"
           Find = 'argumentChars = [int]$Settings.values.argumentChars;'
           Replace = 'argumentChars = 16384;' }
        @{ Name = "a-bridge-ignores-how-many-refusals-to-keep"
           Find = 'refusalsKept = [int]$Settings.values.refusalsKept;'
           Replace = 'refusalsKept = 50;' }
        @{ Name = "an-argument-with-no-length-of-its-own-is-unbounded"
           Find = '$most = [long]$limits.argumentChars'
           Replace = '$most = [long][int]::MaxValue' }
        @{ Name = "settings-handed-in-are-dropped-and-the-file-read-anyway"
           Find = 'if ($null -eq $Settings) { $Settings = Get-HordeSurfaceSettings }'
           Replace = '$Settings = Get-HordeSurfaceSettings' }
        # --- a settings file that fails a check refuses the surface: nothing is made from it
        @{ Name = "a-bridge-is-made-beside-a-refused-file"
           Find = '$Settings = Resolve-HordeSurfaceSettings -Settings $Settings # no bridge from a refused file'
           Replace = 'if ($null -eq $Settings) { $Settings = Get-HordeSurfaceSettings }' }
        @{ Name = "a-spec-is-tried-beside-a-refused-file"
           Find = '$Settings = Resolve-HordeSurfaceSettings -Settings $Settings # no spec from a refused file'
           Replace = 'if ($null -eq $Settings) { $Settings = Get-HordeSurfaceSettings }' }
        @{ Name = "a-refused-file-is-not-said-in-its-own-words"
           Find = 'if ($state -ceq "refused") { throw (@($Settings.findings) -join [Environment]::NewLine) }'
           Replace = '' }
        @{ Name = "a-refusal-says-only-its-first-finding"
           Find = 'if ($state -ceq "refused") { throw (@($Settings.findings) -join [Environment]::NewLine) }'
           Replace = 'if ($state -ceq "refused") { throw ("" + @($Settings.findings)[0]) }' }
        @{ Name = "anything-handed-in-is-taken-for-settings"
           Find = 'if (@("defaults", "read") -cnotcontains $state) { throw'
           Replace = 'if ($false) { throw' }
        @{ Name = "a-spec-ignores-the-width-setting"
           Find = 'if ($null -eq $Width) { $Width = $Settings.values.widthPx }'
           Replace = 'if ($null -eq $Width) { $Width = 520 }' }
        @{ Name = "a-spec-ignores-the-height-setting"
           Find = 'if ($null -eq $Height) { $Height = $Settings.values.heightPx }'
           Replace = 'if ($null -eq $Height) { $Height = 760 }' }
        @{ Name = "a-spec-ignores-the-tick-setting"
           Find = 'if ($null -eq $TickMs) { $TickMs = $Settings.values.tickMs }'
           Replace = 'if ($null -eq $TickMs) { $TickMs = 250 }' }
        @{ Name = "a-window-one-pixel-narrower-than-the-smallest"
           Find = '$script:HordeSurfaceSmallestWidthPx = 200'
           Replace = '$script:HordeSurfaceSmallestWidthPx = 199' }
        @{ Name = "a-window-one-pixel-shorter-than-the-smallest"
           Find = '$script:HordeSurfaceSmallestHeightPx = 150'
           Replace = '$script:HordeSurfaceSmallestHeightPx = 149' }
        @{ Name = "a-setting-may-go-below-the-smallest-window"
           Find = 'min = $script:HordeSurfaceSmallestWidthPx; max = 8000;'
           Replace = 'min = 1; max = 8000;' }
        @{ Name = "a-tick-setting-may-be-a-busy-loop"
           Find = 'min = $script:HordeSurfaceFastestTickMs; max = 60000;'
           Replace = 'min = 1; max = 60000;' }
        @{ Name = "a-list-taken-as-a-message"
           Find = 'if ($null -eq $message -or $message -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($null -eq $message) {' }
        @{ Name = "id-of-zero-taken"
           Find = '[long]$idProp.Value -ge 1 -and'
           Replace = '[long]$idProp.Value -ge 0 -and' }
        @{ Name = "unknown-member-ignored"
           Find = 'if ($members -cnotcontains $p.Name) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-version-taken"
           Find = ' -or [long]$vProp.Value -ne $protocol) {'
           Replace = ') {' }
        # --- which file an address names
        @{ Name = "a-mount-matched-without-case"
           Find = 'if (@($Mounts.Keys) -cnotcontains $mount) {'
           Replace = 'if (@($Mounts.Keys) -notcontains $mount) {' }
        @{ Name = "a-device-name-is-opened"
           Find = 'foreach ($s in $steps) { if ($s -imatch $script:HordeSurfaceDeviceNamePattern) {'
           Replace = 'foreach ($s in $steps) { if ($false) {' }
        @{ Name = "a-device-name-in-capitals-is-opened"
           Find = 'foreach ($s in $steps) { if ($s -imatch $script:HordeSurfaceDeviceNamePattern) {'
           Replace = 'foreach ($s in $steps) { if ($s -cmatch $script:HordeSurfaceDeviceNamePattern) {' }
        @{ Name = "any-kind-of-file-is-served"
           Find = 'if (@($script:HordeSurfaceFileTypes.Keys) -cnotcontains $extension) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-kind-matched-without-case"
           Find = 'if (@($script:HordeSurfaceFileTypes.Keys) -cnotcontains $extension) {'
           Replace = 'if (@($script:HordeSurfaceFileTypes.Keys) -notcontains $extension) {' }
        @{ Name = "a-file-name-matched-without-case"
           Find = '$exact = @($found | Where-Object { [System.IO.Path]::GetFileName($_) -ceq $steps[$i] })'
           Replace = '$exact = @($found | Where-Object { [System.IO.Path]::GetFileName($_) -eq $steps[$i] })' }
        @{ Name = "an-address-may-go-one-step-deeper"
           Find = '$script:HordeSurfacePathSteps = 8'
           Replace = '$script:HordeSurfacePathSteps = 9' }
        @{ Name = "a-name-may-end-in-a-dot"
           Find = '$script:HordeSurfacePathStep = ''[A-Za-z0-9](?:[A-Za-z0-9._-]{0,62}[A-Za-z0-9])?'''
           Replace = '$script:HordeSurfacePathStep = ''[A-Za-z0-9][A-Za-z0-9._-]{0,63}''' }
        @{ Name = "the-surface-own-mount-serves-the-wrong-definition"
           Find = '$script:HordeSurfaceMessagesFile = (Get-HordeSurfaceMessagesPath) })'
           Replace = '$script:HordeSurfaceMessagesFile = $BridgeScript })' }
        @{ Name = "a-refused-address-is-still-handed-a-file"
           Find = '$no = { param([string]$Why) return [pscustomobject]@{ file = ""; type = ""; reason = $Why } }'
           Replace = '$no = { param([string]$Why) return [pscustomobject]@{ file = $Path; type = ""; reason = $Why } }' }
        # --- the one definition of the message shapes
        @{ Name = "the-id-is-read-under-a-name-of-the-ports-own"
           Find = '$idProp = $message.PSObject.Properties[$ask.id]'
           Replace = '$idProp = $message.PSObject.Properties["id"]' }
        @{ Name = "the-version-is-read-under-a-name-of-the-ports-own"
           Find = '$vProp = $message.PSObject.Properties[$ask.version]'
           Replace = '$vProp = $message.PSObject.Properties["v"]' }
        @{ Name = "the-request-is-read-under-a-name-of-the-ports-own"
           Find = '$nameProp = $message.PSObject.Properties[$ask.name]'
           Replace = '$nameProp = $message.PSObject.Properties["request"]' }
        @{ Name = "the-arguments-are-read-under-a-name-of-the-ports-own"
           Find = '$argsProp = $message.PSObject.Properties[$ask.arguments]'
           Replace = '$argsProp = $message.PSObject.Properties["args"]' }
        @{ Name = "the-protocol-number-is-the-ports-own"
           Find = '$protocol = $script:HordeSurfaceMessages.protocol'
           Replace = '$protocol = 1' }
        @{ Name = "an-answer-is-written-under-names-of-the-ports-own"
           Find = '([ordered]@{ $say.version = $protocol; $say.id = $id; $say.ok = $true; $say.value = $value })'
           Replace = '([ordered]@{ v = $protocol; reply = $id; ok = $true; value = $value })' }
        @{ Name = "an-event-is-written-under-names-of-the-ports-own"
           Find = '([ordered]@{ $tell.version = $script:HordeSurfaceMessages.protocol; $tell.name = $Name; $tell.value = $Value })'
           Replace = '([ordered]@{ v = $script:HordeSurfaceMessages.protocol; event = $Name; value = $Value })' }
        @{ Name = "a-definition-is-not-checked-when-read"
           Find = 'if ($findings.Count -gt 0) { throw ("the definition of the bridge''s messages at " + $Path + " is refused: " + ($findings -join "; ")) }'
           Replace = '' }
        @{ Name = "two-parts-may-share-a-name"
           Find = 'if ($seen -ccontains $part.Value) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-reply-may-pass-for-an-event"
           Find = 'if ($eventNames -ccontains $Messages.reply.id -or $replyNames -ccontains $Messages.event.name) {'
           Replace = 'if ($false) {' }
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
           Find = 'return [pscustomobject]@{ reply = $failLine; refused = ""; request = $request.name; failed = $kept }'
           Replace = 'return [pscustomobject]@{ reply = $failLine; refused = "the request failed"; request = $request.name; failed = $kept }' }
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
        @{ Name = "a-caller-may-take-the-surface-own-mount"
           Find = 'if ("$name" -ceq $script:HordeSurfaceOwnMount) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-text-is-a-mount-name"
           Find = 'if ("$name" -cnotmatch $script:HordeSurfaceMountPattern) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-spec-asks-for-the-keyboard-unasked"
           Find = 'takeKeyboard = [bool]$TakeKeyboard;'
           Replace = 'takeKeyboard = $true;' }
        @{ Name = "a-spec-gives-input-for-a-check-unasked"
           Find = 'probeInput = [bool]$ProbeInput;'
           Replace = 'probeInput = $true;' }
        @{ Name = "a-left-with-no-top"
           Find = 'if (($null -eq $Left) -ne ($null -eq $Top)) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-theme-accepted"
           Find = 'if ($script:HordeSurfaceThemes -cnotcontains $Theme) {'
           Replace = 'if ($false) {' }
        @{ Name = "relative-data-folder-accepted"
           Find = 'if (-not [System.IO.Path]::IsPathRooted($DataFolder)) {'
           Replace = 'if ($false) {' }
    )
}
