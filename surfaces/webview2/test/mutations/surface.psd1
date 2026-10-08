# Mutations of surfaces/webview2/Surface.ps1, the window surface. Run:
#   powershell -File tools\Mutate.ps1 -Spec surfaces\webview2\test\mutations\surface.psd1
# surfaces\webview2\test\test-webview2-surface.ps1 must fail for each. That suite opens no window, so
# this spec holds only what can be broken without one: the pinned files, the address rule, what a
# load is answered with, where a message may come from, the handlers and the settings. What only a real window can catch is in
# surface-window.psd1 beside this file, held by surfaces\webview2\test\test-webview2-window.ps1.
@{
    Target = "surfaces\webview2\Surface.ps1"
    Suite  = "surfaces\webview2\test\test-webview2-surface.ps1"
    Mutations = @(
        # --- the pinned files
        # No mutant removes the return on a failed check by itself: a refused folder hands back no file
        # (the third mutant below guards that), so going on would stop on an empty path, and a suite
        # that stops has caught nothing (measured 2026-10-06: "the suite broke with no failed check").
        @{ Name = "a-file-the-list-does-not-pin-is-loaded"
           Find = 'foreach ($need in $script:HordeWebView2LibFiles) { if ($have -cnotcontains $need) {'
           Replace = 'foreach ($need in $script:HordeWebView2LibFiles) { if ($false) {' }
        @{ Name = "a-refused-folder-still-hands-back-its-files"
           Find = '(@($why | Select-Object -Unique) -join "; ")); files = @(); held = @() }'
           Replace = '(@($why | Select-Object -Unique) -join "; ")); files = @($check.files); held = @() }' }
        # --- nothing beside the pinned files, and what is loaded is what was checked
        @{ Name = "a-file-nobody-listed-is-let-stand"
           Find = 'if ($script:HordeWebView2LibOtherFiles -cnotcontains $other) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-file-beside-them-is-matched-without-case"
           Find = 'if ($script:HordeWebView2LibOtherFiles -cnotcontains $other) {'
           Replace = 'if ($script:HordeWebView2LibOtherFiles -notcontains $other) {' }
        @{ Name = "a-refused-folder-keeps-its-files-held"
           Find = 'foreach ($h in @($check.held)) { $h.Dispose() }'
           Replace = '' }
        @{ Name = "asked-to-hold-the-check-holds-nothing"
           Find = '$check = Test-HordeFingerprints -Folder $Folder -Hold:$Hold'
           Replace = '$check = Test-HordeFingerprints -Folder $Folder' }
        @{ Name = "the-files-are-loaded-without-being-held"
           Find = '$libs = Test-HordeWebView2Libraries -Folder $Folder -Hold'
           Replace = '$libs = Test-HordeWebView2Libraries -Folder $Folder' }
        @{ Name = "the-files-are-let-go-before-the-engine-has-loaded-the-third"
           Find = '$kept = [bool]$Hold'
           Replace = '$kept = $false' }
        @{ Name = "a-plain-load-leaves-the-files-held"
           Find = '} finally { if (-not $kept) { Clear-HordeWebView2HeldFiles } }'
           Replace = '} finally { }' }
        # No mutant removes the letting-go once the engine is up: that line is the same text as three
        # others in the file, and a find string must be one place. The real-window suite checks it.
        @{ Name = "window-opened-on-unchecked-files"
           Find = 'if ($notLoaded -ne "") { return (& $fail $notLoaded) }'
           Replace = '' }
        # --- the page's own address
        @{ Name = "plain-http-allowed"
           Find = '$parsed.Scheme -ceq $origin.Scheme -and '
           Replace = '' }
        @{ Name = "any-host-allowed"
           Find = '$parsed.Host -ceq $origin.Host -and '
           Replace = '' }
        @{ Name = "a-host-that-begins-with-ours-allowed"
           Find = '$parsed.Host -ceq $origin.Host -and '
           Replace = '$parsed.Host.StartsWith($origin.Host) -and ' }
        @{ Name = "a-host-that-ends-with-ours-allowed"
           Find = '$parsed.Host -ceq $origin.Host -and '
           Replace = '$parsed.Host.EndsWith($origin.Host) -and ' }
        @{ Name = "the-page-may-go-to-another-mount"
           Find = 'return [bool]($null -ne $path -and $path.StartsWith(("/" + $StartMount + "/"), [System.StringComparison]::Ordinal))'
           Replace = 'return [bool]($null -ne $path)' }
        @{ Name = "a-mount-that-only-begins-with-the-pages-own"
           Find = '$path.StartsWith(("/" + $StartMount + "/"), [System.StringComparison]::Ordinal))'
           Replace = '$path.StartsWith(("/" + $StartMount), [System.StringComparison]::Ordinal))' }
        @{ Name = "the-pages-own-mount-matched-without-case"
           Find = '$path.StartsWith(("/" + $StartMount + "/"), [System.StringComparison]::Ordinal))'
           Replace = '$path.StartsWith(("/" + $StartMount + "/"), [System.StringComparison]::OrdinalIgnoreCase))' }
        @{ Name = "the-path-is-tidied-before-the-port-sees-it"
           Find = 'return ("" + $Matches["path"])'
           Replace = 'return $parsed.AbsolutePath' }
        @{ Name = "the-question-mark-is-part-of-the-path"
           Find = '(?<path>/[^?#]*)?'') { return $null }'
           Replace = '(?<path>/[^#]*)?'') { return $null }' }
        # --- every load is answered here
        @{ Name = "a-load-from-outside-is-let-through"
           Find = 'return [pscustomobject]@{ file = ""; type = ""; status = 403; refusal = ("the page asked for something that is not one of its own files'
           Replace = 'return [pscustomobject]@{ file = ""; type = ""; status = 200; refusal = ("the page asked for something that is not one of its own files' }
        @{ Name = "a-load-from-outside-is-not-recorded"
           Find = '($answer.refusal -ne "") { Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason $answer.refusal }'
           Replace = '($false) { Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason $answer.refusal }' }
        @{ Name = "the-record-of-a-load-holds-whatever-kind-it-was-given"
           Find = 'if ("$Kind" -cmatch ''\A[A-Za-z]{1,32}\z'') { $word = "$Kind" }'
           Replace = '$word = "$Kind"' }
        @{ Name = "a-climb-out-of-the-mounts-is-not-refused"
           Find = 'if ($found.file -eq "") { return [pscustomobject]@{ file = ""; type = ""; status = 403; refusal = ($found.reason + ", and nothing was served") } }'
           Replace = 'if ($found.file -eq "") { return [pscustomobject]@{ file = ""; type = ""; status = 200; refusal = "" } }' }
        @{ Name = "the-engines-own-ask-is-held-against-the-page"
           Find = 'if ($script:HordeWebView2EngineOwnPaths -ccontains $path) {'
           Replace = 'if ($false) {' }
        @{ Name = "a-refused-load-is-answered-as-found"
           Find = '$What.Response = $environment.CreateWebResourceResponse($null, [int]$answer.status, "Refused", "")'
           Replace = '$What.Response = $environment.CreateWebResourceResponse($null, 200, "Refused", "")' }
        @{ Name = "a-refused-load-is-left-to-the-engine"
           Find = '$What.Response = $environment.CreateWebResourceResponse($null, [int]$answer.status, "Refused", "")'
           Replace = '' }
        @{ Name = "a-file-that-cannot-be-read-is-left-to-the-engine"
           Find = 'try { $What.Response = $environment.CreateWebResourceResponse($null, 403, "Refused", "") } catch { }'
           Replace = '' }
        @{ Name = "a-served-file-may-be-kept-by-the-engine"
           Find = '`r`nCache-Control: no-store'
           Replace = '' }
        @{ Name = "the-engine-is-not-told-to-ask-about-every-load"
           Find = '$core.AddWebResourceRequestedFilter("*", [Microsoft.Web.WebView2.Core.CoreWebView2WebResourceContext]::All)'
           Replace = '$core.AddWebResourceRequestedFilter("*", [Microsoft.Web.WebView2.Core.CoreWebView2WebResourceContext]::Document)' }
        @{ Name = "the-load-handler-is-not-given-to-the-engine"
           Find = '$core.add_WebResourceRequested($h.resource)'
           Replace = '' }
        @{ Name = "the-engine-keeps-its-way-to-the-network"
           Find = '$props.AdditionalBrowserArguments = $script:HordeWebView2NoNetwork'
           Replace = '' }
        @{ Name = "loopback-is-excused-from-the-closed-network"
           Find = '$script:HordeWebView2NoNetwork = "--proxy-server=http://0.0.0.0:0 --proxy-bypass-list=<-loopback>"'
           Replace = '$script:HordeWebView2NoNetwork = "--proxy-server=http://0.0.0.0:0"' }
        @{ Name = "a-user-name-in-front-allowed"
           Find = ' -and $parsed.UserInfo -eq ""'
           Replace = '' }
        @{ Name = "another-port-allowed"
           Find = ' -and $parsed.IsDefaultPort)'
           Replace = ')' }
        @{ Name = "text-that-is-no-address-allowed"
           Find = 'if (-not [System.Uri]::TryCreate("$Uri", [System.UriKind]::Absolute, [ref]$parsed)) { return $null }'
           Replace = 'if (-not [System.Uri]::TryCreate("$Uri", [System.UriKind]::Absolute, [ref]$parsed)) { return "/shell/index.html" }' }
        # --- where a message may come from, and what is refused
        @{ Name = "a-message-from-anywhere-is-read"
           Find = 'if (-not (Test-HordeWebView2Address -Uri $Source -StartMount $s.spec.startMount)) {'
           Replace = 'if ($false) {' }
        @{ Name = "what-a-failed-request-said-does-not-reach-the-caller"
           Find = '    Add-HordeWebView2Error -Text $answer.failed'
           Replace = '' }
        @{ Name = "a-message-from-elsewhere-not-recorded"
           Find = 'Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "a message came from an address that is not the page''s own, and was not read"'
           Replace = '' }
        @{ Name = "navigation-elsewhere-not-cancelled"
           Find = '$What.Cancel = $true'
           Replace = '$What.Cancel = $false' }
        @{ Name = "a-frame-is-loaded"
           Find = '$Frame.Cancel = $true'
           Replace = '$Frame.Cancel = $false' }
        @{ Name = "navigation-to-the-page-itself-cancelled"
           Find = 'if (Test-HordeWebView2Address -Uri ("" + $What.Uri) -StartMount $s.spec.startMount) { return }'
           Replace = '' }
        @{ Name = "navigation-elsewhere-not-recorded"
           Find = 'Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "the page tried to go to an address that is not its own, and was kept where it is"'
           Replace = '' }
        @{ Name = "a-frame-not-recorded"
           Find = 'Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "the page tried to load a frame, and no frame is loaded"'
           Replace = '' }
        @{ Name = "a-new-window-opens"
           Find = '$What.Handled = $true'
           Replace = '$What.Handled = $false' }
        @{ Name = "a-new-window-not-recorded"
           Find = 'Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "the page asked for a new window, and none was opened"'
           Replace = '' }
        @{ Name = "a-download-is-saved"
           Find = '$Download.Cancel = $true'
           Replace = '$Download.Cancel = $false' }
        @{ Name = "a-download-not-recorded"
           Find = 'Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason "the page tried to save a file, and none was saved"'
           Replace = '' }
        @{ Name = "the-download-handler-is-not-given-to-the-engine"
           Find = '$core.add_DownloadStarting($h.download)'
           Replace = '' }
        # --- a page that floods
        @{ Name = "a-flooding-page-is-still-read"
           Find = 'if ($turn -cne "read") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-flood-is-neither-recorded-nor-shut-out"
           Find = 'if ($turn -ceq "refuse") {'
           Replace = 'if ($false) {' }
        @{ Name = "a-flood-goes-on-being-handed-over"
           Find = '$s.view.CoreWebView2.remove_WebMessageReceived($s.messageHandler)'
           Replace = '' }
        @{ Name = "the-silence-after-a-flood-never-ends"
           Find = '$s.view.CoreWebView2.add_WebMessageReceived($s.messageHandler)'
           Replace = '' }
        @{ Name = "the-timer-that-ends-the-silence-is-never-started"
           Find = '$s.listenTimer.Start()'
           Replace = '' }
        @{ Name = "what-a-page-asks-the-machine-for-is-not-denied"
           Find = '$What.State = "Deny"'
           Replace = '$What.State = "Allow"' }
        @{ Name = "what-a-page-asks-the-machine-for-is-not-recorded"
           Find = 'Add-HordeSurfaceRefusal -Bridge $s.spec.bridge -Reason ("the page asked the machine for something (the engine''s word for it: " + $word + "), and it was denied")'
           Replace = '' }
        @{ Name = "the-record-holds-whatever-the-engine-called-it"
           Find = 'if (("" + $What.PermissionKind) -cmatch ''\A[A-Za-z]{1,40}\z'') { $word = "" + $What.PermissionKind }'
           Replace = '$word = "" + $What.PermissionKind' }
        @{ Name = "the-permission-handler-is-not-given-to-the-engine"
           Find = '$core.add_PermissionRequested($h.permission)'
           Replace = '' }
        # --- the handlers
        @{ Name = "a-failed-tick-closes-the-window-unrecorded"
           Find = 'try { & $s.spec.onTick $s.window $s.spec.state } catch { Add-HordeWebView2Error -Text ("a tick failed: " + $_.Exception.Message) }'
           Replace = 'try { & $s.spec.onTick $s.window $s.spec.state } catch { }' }
        @{ Name = "the-tick-is-not-handed-the-callers-state"
           Find = 'try { & $s.spec.onTick $s.window $s.spec.state } catch {'
           Replace = 'try { & $s.spec.onTick $s.window $null } catch {' }
        @{ Name = "the-list-of-errors-grows-for-ever"
           Find = 'Add-HordeSurfaceError -Errors $s.errors -Text $Text -Kept $s.spec.errorsKept'
           Replace = '[void]$s.errors.Add($Text)' }
        # --- what the page can do
        @{ Name = "developer-tools-left-on"
           Find = '$core.Settings.AreDevToolsEnabled = $false'
           Replace = '$core.Settings.AreDevToolsEnabled = $true' }
        @{ Name = "host-objects-allowed"
           Find = '$core.Settings.AreHostObjectsAllowed = $false'
           Replace = '$core.Settings.AreHostObjectsAllowed = $true' }
        @{ Name = "the-browsers-own-keys-left-on"
           Find = '$core.Settings.AreBrowserAcceleratorKeysEnabled = $false'
           Replace = '' }
        @{ Name = "context-menu-left-on"
           Find = '$core.Settings.AreDefaultContextMenusEnabled = $false'
           Replace = '' }
        # --- a picture
        @{ Name = "a-picture-written-at-a-relative-path"
           Find = 'if (-not [System.IO.Path]::IsPathRooted("$Path") -or '
           Replace = 'if (' }
        @{ Name = "a-second-picture-taken-while-one-is-drawn"
           Find = ' -or $null -ne $s.capture) { return $false }'
           Replace = ') { return $false }' }
        @{ Name = "an-unfinished-picture-is-saved"
           Find = 'if ($null -eq $s -or $null -eq $s.capture -or -not $s.capture.task.IsCompleted) { return }'
           Replace = 'if ($null -eq $s -or $null -eq $s.capture) { return }' }
        @{ Name = "a-failed-ask-for-a-picture-leaves-its-file"
           Find = 'try { [System.IO.File]::Delete($temp) } catch { }'
           Replace = '' }
        # --- the folder the engine keeps its files in
        # NO MUTANT REMOVES THE REFUSAL ITSELF. It was written and run once, 2026-10-07: caught, but the
        # suite then really started the engine on a folder it cannot write to, which took 75 s and left
        # one engine process running after the suite had gone (it was stopped by hand). That is the very
        # fault the trial exists to prevent, and a spec must not reproduce it on every run.
        @{ Name = "the-trial-file-is-left-in-the-folder"
           Find = '[System.IO.File]::Delete($trial)'
           Replace = '' }
        @{ Name = "the-folder-is-only-looked-at-not-written-to"
           Find = '[System.IO.File]::WriteAllText($trial, "x")'
           Replace = '' }
        # --- how a window first appears
        @{ Name = "a-free-standing-window-takes-the-keyboard"
           Find = 'quiet = [bool]($Spec.hidden -or -not $Spec.takeKeyboard)'
           Replace = 'quiet = [bool]($Spec.hidden -or $Spec.companion)' }
        @{ Name = "a-hidden-window-takes-the-keyboard-when-asked"
           Find = 'quiet = [bool]($Spec.hidden -or -not $Spec.takeKeyboard)'
           Replace = 'quiet = [bool](-not $Spec.takeKeyboard)' }
        @{ Name = "no-window-ever-takes-the-keyboard"
           Find = 'quiet = [bool]($Spec.hidden -or -not $Spec.takeKeyboard)'
           Replace = 'quiet = $true' }
        @{ Name = "a-companion-has-a-place-in-the-taskbar"
           Find = 'taskbar = [bool](-not ($Spec.companion -or $Spec.hidden))'
           Replace = 'taskbar = [bool](-not $Spec.hidden)' }
        @{ Name = "a-hidden-window-has-a-place-in-the-taskbar"
           Find = 'taskbar = [bool](-not ($Spec.companion -or $Spec.hidden))'
           Replace = 'taskbar = [bool](-not $Spec.companion)' }
        @{ Name = "a-hidden-window-stands-where-it-would-be-seen"
           Find = 'offScreen = [bool]$Spec.hidden'
           Replace = 'offScreen = $false' }
        # --- the screen's real scale
        @{ Name = "real-scale-judged-by-whether-the-call-was-taken"
           Find = 'if ("$($Scale.realScale)" -ceq "yes") { return "" }'
           Replace = 'if ("$($Scale.state)" -cne "unavailable") { return "" }' }
        @{ Name = "unknown-real-scale-read-as-yes"
           Find = 'if ("$($Scale.realScale)" -ceq "yes") { return "" }'
           Replace = 'if ("$($Scale.realScale)" -cne "no") { return "" }' }
        @{ Name = "real-scale-only-read-never-asked-for"
           Find = '$scale = Enable-HordeWindowsRealScale'
           Replace = '$scale = Get-HordeWindowsScaleAwareness' }
        # --- what the caller is told as the window opens
        # No mutant of a fault in the settings file: the adapter no longer hears of one. A file that
        # fails a check makes no spec (surfaces/Port.ps1), and test\mutations\surface-port.psd1 has it.
        @{ Name = "the-scale-is-not-said-as-the-window-opens"
           Find = 'if ($scaleNote -ne "") { $notes += $scaleNote }'
           Replace = '' }
        # --- real keys for a check: only when the spec asks, only three kinds of call
        @{ Name = "every-window-is-given-input"
           Find = 'if ($ProbeInput) {'
           Replace = 'if ($true) {' }
        @{ Name = "a-window-not-opened-for-input-takes-it"
           Find = 'if (-not $s.spec.probeInput) {'
           Replace = 'if ($false) {' }
        @{ Name = "an-ask-that-cannot-be-acted-out-is-said-to-be-handed-over"
           Find = 'if ($made.problem -ne "") { Add-HordeWebView2Error -Text $made.problem; return $false }'
           Replace = '' }
        @{ Name = "what-is-handed-over-is-not-waited-for"
           Find = '[void]$s.inputTasks.Add($s.view.CoreWebView2.CallDevToolsProtocolMethodAsync($call.method, $call.json))'
           Replace = '[void]($s.view.CoreWebView2.CallDevToolsProtocolMethodAsync($call.method, $call.json))' }
        @{ Name = "a-key-name-in-another-letter-case-is-pressed"
           Find = 'if (@($script:HordeWebView2InputKeys.Keys) -ccontains $Name) {'
           Replace = 'if (@($script:HordeWebView2InputKeys.Keys) -contains $Name) {' }
        @{ Name = "a-key-held-with-ctrl-types"
           Find = 'if ($text -ne "" -and -not $Ctrl) {'
           Replace = 'if ($text -ne "") {' }
        @{ Name = "shift-is-not-held-while-the-key-is"
           Find = '$held = $held -bor 8;'
           Replace = '$held = $held -bor 0;' }
        @{ Name = "the-arrows-up-and-down-cannot-be-pressed"
           Find = '"ArrowUp" = @("ArrowUp", 38, ""); "ArrowDown" = @("ArrowDown", 40, "")'
           Replace = '' }
        @{ Name = "a-step-that-is-not-an-object-is-looked-into"
           Find = 'if ($null -eq $step -or $step -isnot [System.Management.Automation.PSCustomObject]) {'
           Replace = 'if ($null -eq $step) {' }
        @{ Name = "the-page-is-never-told-it-has-the-keyboard"
           Find = 'if ($null -ne $focusProp -and $focusProp.Value -is [bool]) {'
           Replace = 'if ($false) {' }
        @{ Name = "any-amount-of-input-is-sent"
           Find = 'if ($calls.Count -gt $script:HordeWebView2InputMostCalls) {'
           Replace = 'if ($false) {' }
        @{ Name = "input-of-exactly-the-most-calls-is-refused"
           Find = 'if ($calls.Count -gt $script:HordeWebView2InputMostCalls) {'
           Replace = 'if ($calls.Count -ge $script:HordeWebView2InputMostCalls) {' }
        @{ Name = "a-call-the-engine-refused-is-not-said"
           Find = 'Add-HordeWebView2Error -Text ("the engine did not take an input: " + $why)'
           Replace = '' }
        @{ Name = "an-unfinished-call-is-not-waited-for"
           Find = 'if (-not $task.IsCompleted) { return $false }'
           Replace = '' }
        # --- a machine without the engine
        @{ Name = "no-engine-reads-as-an-engine"
           Find = 'if ("$Version".Trim() -ne "") { return "" }'
           Replace = 'return ""' }
        @{ Name = "blank-version-reads-as-an-engine"
           Find = 'if ("$Version".Trim() -ne "") { return "" }'
           Replace = 'if ($null -ne $Version -and "$Version" -ne "") { return "" }' }
    )
}
