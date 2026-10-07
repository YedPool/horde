# Mutations of surfaces/webview2/Surface.ps1, the window surface. Run:
#   powershell -File tools\Mutate.ps1 -Spec surfaces\webview2\test\mutations\surface.psd1
# surfaces\webview2\test\test-webview2-surface.ps1 must fail for each. That suite opens no window, so
# this spec holds only what can be broken without one: the pinned files, the address rule, where a
# message may come from, the handlers and the settings. What needs a real window is
# test\e2e\e2e-decisions-window.ps1's.
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
           Find = '(@($why | Select-Object -Unique) -join "; ")); files = @() }'
           Replace = '(@($why | Select-Object -Unique) -join "; ")); files = @($check.files) }' }
        @{ Name = "window-opened-on-unchecked-files"
           Find = 'if ($notLoaded -ne "") { return (& $fail $notLoaded) }'
           Replace = '' }
        # --- the page's own address
        @{ Name = "plain-http-allowed"
           Find = '$parsed.Scheme -ceq "https" -and '
           Replace = '' }
        @{ Name = "any-host-allowed"
           Find = '$parsed.Host -ceq $StartHost.ToLowerInvariant() -and '
           Replace = '' }
        @{ Name = "a-host-that-begins-with-ours-allowed"
           Find = '$parsed.Host -ceq $StartHost.ToLowerInvariant() -and '
           Replace = '$parsed.Host.StartsWith($StartHost.ToLowerInvariant()) -and ' }
        @{ Name = "a-user-name-in-front-allowed"
           Find = ' -and $parsed.UserInfo -eq ""'
           Replace = '' }
        @{ Name = "another-port-allowed"
           Find = ' -and $parsed.IsDefaultPort)'
           Replace = ')' }
        @{ Name = "text-that-is-no-address-allowed"
           Find = 'if (-not [System.Uri]::TryCreate("$Uri", [System.UriKind]::Absolute, [ref]$parsed)) { return $false }'
           Replace = 'if (-not [System.Uri]::TryCreate("$Uri", [System.UriKind]::Absolute, [ref]$parsed)) { return $true }' }
        # --- where a message may come from, and what is refused
        @{ Name = "a-message-from-anywhere-is-read"
           Find = 'if (-not (Test-HordeWebView2Address -Uri $Source -StartHost $s.startHost)) {'
           Replace = 'if ($false) {' }
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
           Find = 'if (Test-HordeWebView2Address -Uri ("" + $What.Uri) -StartHost $s.startHost) { return }'
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
        # --- the handlers
        @{ Name = "a-failed-tick-closes-the-window-unrecorded"
           Find = 'try { & $s.spec.onTick $s.window $s.spec.state } catch { [void]$s.errors.Add("a tick failed: " + $_.Exception.Message) }'
           Replace = 'try { & $s.spec.onTick $s.window $s.spec.state } catch { }' }
        @{ Name = "the-tick-is-not-handed-the-callers-state"
           Find = 'try { & $s.spec.onTick $s.window $s.spec.state } catch {'
           Replace = 'try { & $s.spec.onTick $s.window $null } catch {' }
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
        # --- a machine without the engine
        @{ Name = "no-engine-reads-as-an-engine"
           Find = 'if ("$Version".Trim() -ne "") { return "" }'
           Replace = 'return ""' }
        @{ Name = "blank-version-reads-as-an-engine"
           Find = 'if ("$Version".Trim() -ne "") { return "" }'
           Replace = 'if ($null -ne $Version -and "$Version" -ne "") { return "" }' }
    )
}
