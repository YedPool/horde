// surfaces/pwa/page/bar-height.js - the sticky bar's real height, in --bar-h on the page, kept current.
//
// WHY (the founder, 2026-10-20, desktop browser: "When horde jumps to the latest question, it jumps a
// little too far and I can't see the question - it's blocked by the decisions button"). The bar of hordes
// and the Decisions / Chat / Progress / Notices tabs is sticky (app.css, #bar), so whatever the page
// scrolls to with its top at the window's top has that top under the bar. The bar's height is not one
// number: it wraps to more lines when the PC is offline, the page is narrow or zoomed, a horde's name is
// long. So the bar is measured, never guessed, and app.css hangs scroll-margin-top on the cards from this
// variable: a scroll that brings a card to the top of the view (scrollIntoView, a focus, a link) stops
// below the bar at every width and zoom.
//
// trackBarHeight(bar, root): sets --bar-h on root now, and again each time the bar changes size (a
// ResizeObserver; a browser without one is told by the window's resize). Returns a function that stops it.
export function trackBarHeight(bar, root, win = window) {
  const set = () => root.style.setProperty("--bar-h", Math.ceil(bar.getBoundingClientRect().height) + "px");
  set();
  if (typeof win.ResizeObserver === "function") {
    const watcher = new win.ResizeObserver(set);
    watcher.observe(bar);
    return () => watcher.disconnect();
  }
  win.addEventListener("resize", set);
  return () => win.removeEventListener("resize", set);
}
