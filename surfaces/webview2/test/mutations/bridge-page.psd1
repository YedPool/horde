# Mutations of surfaces/webview2/page/bridge.js, the page's side of the bridge. Run:
#   powershell -File tools\Mutate.ps1 -Spec surfaces\webview2\test\mutations\bridge-page.psd1
# surfaces\webview2\test\test-webview2-window.ps1 must fail for each: the script runs only inside the
# engine, so only the real window can hold it. That suite's second window has another definition of
# the messages in force, which is what catches a name or a number written into this script.
@{
    Target = "surfaces\webview2\page\bridge.js"
    Suite  = "surfaces\webview2\test\test-webview2-window.ps1"
    Mutations = @(
        @{ Name = "the-protocol-number-is-the-pages-own"
           Find = 'message[m.request.version] = m.protocol;'
           Replace = 'message[m.request.version] = 1;' }
        @{ Name = "a-request-id-is-sent-under-a-name-of-the-pages-own"
           Find = 'message[m.request.id] = id;'
           Replace = 'message["id"] = id;' }
        @{ Name = "a-reply-is-read-under-a-name-of-the-pages-own"
           Find = 'if (typeof data[m.reply.id] === "number") {'
           Replace = 'if (typeof data["reply"] === "number") {' }
        @{ Name = "an-event-is-read-under-a-name-of-the-pages-own"
           Find = 'if (typeof data[m.event.name] === "string") {'
           Replace = 'if (typeof data["event"] === "string") {' }
        @{ Name = "a-refusal-reads-as-an-answer"
           Find = 'if (data[m.reply.ok] === true) { w.resolve(data[m.reply.value]); }'
           Replace = 'if (true) { w.resolve(data[m.reply.value]); }' }
        @{ Name = "a-reply-of-another-protocol-is-taken"
           Find = 'if (data[m.reply.version] !== m.protocol) { return; }'
           Replace = ''
           Expect = "survives"
           Reason = "Horde's side never sends a reply of another protocol number, and nothing in a test can make the real engine deliver one; the check is the page's guard against a surface built for another version, held by reading." }
    )
}
