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

// THE NEWEST ITEM OF A LOG, SEEN FROM ITS TOP (the chat's Jump to latest, the progress log's Jump to newest and its
// opening at the newest end; the founder, 2026-10-20). The foot of the page is where a short item is whole; an item
// taller than the room between the sticky bar and the foot has its top under the bar there. So: to the foot, and
// then, if the item's top is above the bar's foot, the item is brought to the top of the view - scrollIntoView keeps
// the scroll margin app.css gives it from --bar-h. newest may be null (an empty log): the foot only.
export function scrollToNewest(win, root, newest, barBottom) {
  win.scrollTo(0, root.scrollHeight);
  if (newest && newest.getBoundingClientRect().top < barBottom) newest.scrollIntoView({ block: "start", behavior: "instant" });
}
