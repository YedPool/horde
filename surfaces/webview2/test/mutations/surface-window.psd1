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
