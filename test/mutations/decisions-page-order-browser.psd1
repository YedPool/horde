# Mutations of decisions/page/list.js's ORDER LINE as it is tapped (A PRESS RE-SORTS WHAT HE IS LOOKING
# AT; THE ORDER TURNS OVER). Run:
#   powershell -File tools\Mutate.ps1 -Spec test\mutations\decisions-page-order-browser.psd1
# test\test-decisions-page-browser.ps1 (headless Chrome, real touch events) must fail for each. The
# sorting itself is test\mutations\decisions-page-order.psd1. Each find string occurs once.
@{
    Target = "decisions\page\list.js"
    Suite  = "test\test-decisions-page-browser.ps1"
    Mutations = @(
        # THE SCROLL FIX IS TWO LAYERS, and each alone holds the order line still in the browser
        # suite: without keepBar, draw follows the old top question and setOrder's compensation
        # scrolls the bar back; without the compensation, keepBar leaves the scroll alone (Chrome's own
        # anchoring did not move it in the cases measured). So each half survives by itself, and the
        # mutant that removes both is the one that must be caught (review of PR 280).
        @{ Name = "a-press-follows-the-question-at-the-top-again"
           Find = '      var before = (how && how.keepBar === true) ? null : place();'
           Replace = '      var before = place();'
           Expect = "survives"
           Reason = "setOrder's compensation (barWas, moved) scrolls the order line back to where it was pressed, so the view ends where it would have without the follow" }
        @{ Name = "the-order-line-is-not-held-under-the-finger"
           Find = '        var moved = orderBar.getBoundingClientRect().top - barWas;'
           Replace = '        var moved = 0;'
           Expect = "survives"
           Reason = "draw({ keepBar: true }) already leaves the scroll where it was, and Chrome's own scroll anchoring did not move the page in the measured cases (top, and scrolled 13-19 px)" }
        @{ Name = "both-layers-of-the-scroll-fix-gone"
           Find = '      draw({ keepBar: true });'
           Replace = '      draw(); barWas = null;' }
        @{ Name = "a-second-press-does-not-turn-it-over"
           Find = '      setOrder(key, key === orderKey ? !orderTurned : false);'
           Replace = '      setOrder(key, false);' }
        @{ Name = "another-order-keeps-the-turn"
           Find = '      setOrder(key, key === orderKey ? !orderTurned : false);'
           Replace = '      setOrder(key, key === orderKey ? !orderTurned : orderTurned);' }
        @{ Name = "the-arrows-swapped"
           Find = '(orderTurned ? ARROW_TURNED : ARROW_FIRST)'
           Replace = '(orderTurned ? ARROW_FIRST : ARROW_TURNED)' }
        @{ Name = "an-arrow-on-every-order"
           Find = '        orderArrows[i].textContent = on ?'
           Replace = '        orderArrows[i].textContent = true ?' }
        @{ Name = "the-words-never-say-turned-over"
           Find = '(orderTurned ? o.turned : o.says) + ". Press'
           Replace = 'o.says + ". Press' }
        @{ Name = "the-turn-is-not-kept"
           Find = ' prefs.setItem(ORDER_TURN_KEY, orderTurned ? "1" : "0");'
           Replace = '' }
        @{ Name = "the-turn-kept-is-not-read"
           Find = '    try { orderTurned = !!prefs && prefs.getItem(ORDER_TURN_KEY) === "1"; } catch (e) { orderTurned = false; }'
           Replace = '' }
        @{ Name = "storage-that-throws-breaks-the-page"
           Find = '    try { orderTurned = !!prefs && prefs.getItem(ORDER_TURN_KEY) === "1"; } catch (e) { orderTurned = false; }'
           Replace = '    orderTurned = !!prefs && prefs.getItem(ORDER_TURN_KEY) === "1";' }
    )
}
