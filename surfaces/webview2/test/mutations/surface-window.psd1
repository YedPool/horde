# Mutations of surfaces/webview2/Surface.ps1 that ONLY A REAL WINDOW can catch. Run:
#   powershell -File tools\Mutate.ps1 -Spec surfaces\webview2\test\mutations\surface-window.psd1
# surfaces\webview2\test\test-webview2-window.ps1 must fail for each. That suite opens a real hidden
# window (about 15 s a run, machine-bound), so this spec is kept to what the suite with no window
# cannot see: that each lock is handed to the engine, and what the engine then does with it. The rest
# of the file's mutants are in surface.psd1 beside this one.
@{
    Target = "surfaces\webview2\Surface.ps1"
    Suite  = "surfaces\webview2\test\test-webview2-window.ps1"
    Mutations = @(
        # --- a handler nobody handed to the engine locks nothing
        @{ Name = "the-navigation-lock-is-not-given-to-the-engine"
           Find = '$core.add_NavigationStarting($h.navigation)'
           Replace = '' }
        @{ Name = "the-frame-lock-is-not-given-to-the-engine"
           Find = '$core.add_FrameNavigationStarting($h.frame)'
           Replace = '' }
        @{ Name = "the-new-window-lock-is-not-given-to-the-engine"
           Find = '$core.add_NewWindowRequested($h.newWindow)'
           Replace = '' }
        @{ Name = "the-download-lock-is-not-given-to-the-engine-seen-live"
           Find = '$core.add_DownloadStarting($h.download)'
           Replace = '' }
        @{ Name = "the-permission-lock-is-not-given-to-the-real-engine"
           Find = '$core.add_PermissionRequested($h.permission)'
           Replace = '' }
        # --- every load is answered by the surface, in the real engine
        @{ Name = "the-engine-is-asked-about-pages-only"
           Find = '$core.AddWebResourceRequestedFilter("*", [Microsoft.Web.WebView2.Core.CoreWebView2WebResourceContext]::All)'
           Replace = '$core.AddWebResourceRequestedFilter("*", [Microsoft.Web.WebView2.Core.CoreWebView2WebResourceContext]::Document)' }
        @{ Name = "a-refused-load-is-left-to-the-real-engine"
           Find = '$What.Response = $environment.CreateWebResourceResponse($null, [int]$answer.status, "Refused", "")'
           Replace = '' }
        @{ Name = "the-real-engine-keeps-its-way-to-the-network"
           Find = '$props.AdditionalBrowserArguments = $script:HordeWebView2NoNetwork'
           Replace = '' }
        @{ Name = "loopback-is-excused-in-the-real-engine"
           Find = '$script:HordeWebView2NoNetwork = "--proxy-server=http://0.0.0.0:0 --proxy-bypass-list=<-loopback>"'
           Replace = '$script:HordeWebView2NoNetwork = "--proxy-server=http://0.0.0.0:0"' }
        @{ Name = "a-served-file-carries-no-type"
           Find = '("Content-Type: " + $answer.type + '
           Replace = '("X-Type: " + $answer.type + ' }
        @{ Name = "the-engines-own-ask-is-recorded-in-the-real-engine"
           Find = 'if ($script:HordeWebView2EngineOwnPaths -ccontains $path) {'
           Replace = 'if ($false) {' }
        # NO MUTANT DROPS THE NOTES A WINDOW OPENS WITH ANY MORE. The one that did was caught by a fault in
        # the settings file reaching the caller; such a file now makes no spec at all (surfaces/Port.ps1).
        # What is left in the notes is the screen's scale, said only where the process does not draw at
        # the real scale, which this suite cannot arrange in a real window: a mutant here would survive.
        # --- a flood, in the real engine
        @{ Name = "a-flood-is-handed-over-by-the-real-engine"
           Find = '$s.view.CoreWebView2.remove_WebMessageReceived($s.messageHandler)'
           Replace = '' }
        # No mutant hands the engine the script block instead of the kept delegate: the real engine
        # still forgot it when asked with the delegate (measured 2026-10-07: it survived).
        @{ Name = "the-real-engine-is-never-listened-to-again"
           Find = '$listenTimer.add_Tick($handlers.listen)'
           Replace = '' }
        # --- how a real window appears
        # NO MUTANT MAKES A REAL WINDOW TAKE THE KEYBOARD: running it would take the keyboard from whoever
        # is at the machine, three windows in a row. The rule is held with no window by surface.psd1, and
        # that the real form follows it by this suite's own checks of the hidden and the free window.
        @{ Name = "a-free-standing-real-window-is-kept-out-of-the-taskbar"
           Find = 'if (-not $look.taskbar) { $form.ShowInTaskbar = $false }'
           Replace = '$form.ShowInTaskbar = $false' }
        # --- what the real engine does with them
        @{ Name = "a-new-window-opens-in-the-real-engine"
           Find = '$What.Handled = $true'
           Replace = '$What.Handled = $false' }
        # No mutant turns host objects on here: with none added the page finds none either way
        # (measured 2026-10-07: it survived), so the setting is held by surface.psd1, which reads it.
        @{ Name = "a-hidden-window-stands-on-the-screen"
           Find = '$form.Location = New-Object System.Drawing.Point($script:HordeWebView2HiddenAt, $script:HordeWebView2HiddenAt)'
           Replace = '$form.Location = New-Object System.Drawing.Point(-31000, -31000)' }
        @{ Name = "an-event-is-never-posted"
           Find = '$s.view.CoreWebView2.PostWebMessageAsJson($Json)'
           Replace = '' }
    )
}
