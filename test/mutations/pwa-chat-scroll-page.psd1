# Mutations of surfaces/pwa/page/app.js where it hands the chat's moments to chat-scroll.js: a tab picked,
# the app come back to, and his own line sent (the founder, 2026-10-15). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\pwa-chat-scroll-page.psd1
# surfaces\pwa\test\test-pwa-browser.ps1 (headless Chrome, section 10b) must fail for each. Every find
# string occurs exactly once. The rule itself is test\mutations\pwa-chat-scroll.psd1's.
@{
    Target = "surfaces\pwa\page\app.js"
    Suite  = "surfaces\pwa\test\test-pwa-browser.ps1"
    Environment = @{ HORDE_FAIL_FAST = "1" }
    Mutations = @(
        @{ Name = "chat-tab-not-an-opening"
           Find = 'if (which === "chat" && pane !== "chat") chatScroll.open();'
           Replace = '' }
        @{ Name = "return-to-the-app-not-an-opening"
           Find = 'chatScroll.open(); // back to the app: the chat opens at its newest message again'
           Replace = '' }
        @{ Name = "his-own-line-not-followed"
           Find = 'draftId = ""; chatScroll.sent(); }'
           Replace = 'draftId = ""; }' }
    )
}
