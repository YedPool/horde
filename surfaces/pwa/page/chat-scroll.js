// surfaces/pwa/page/chat-scroll.js - where the Chat tab stands in its log, and its Jump to latest
// button (the founder asked, 2026-10-15: "we also need a jump to bottom button on the chat part of
// Horde. And it should always default show the latest message on the Horde chat, not the earliest or
// somewhere in the middle").
//
// THE RULE, as every chat app keeps it:
//   - THE CHAT OPENS AT ITS NEWEST MESSAGE: drawn first, its tab picked again, the app come back to,
//     another horde picked, a horde unlocked again. Each of these marks the next drawing an opening.
//   - A REFRESH STICKS TO THE BOTTOM ONLY WHEN HE WAS ALREADY THERE (within STICK_PX of it). Scrolled up
//     to read what was said before, a refresh keeps his place: the first message on his screen stays
//     where it stood.
//   - HIS OWN LINE, SENT, ALWAYS TAKES HIM TO THE BOTTOM.
//   - AWAY FROM THE BOTTOM, A BUTTON SAYS SO: Jump to latest, with how many messages came since he left
//     the bottom ("Jump to latest (2 new)"); at the bottom it goes. The count is said once each time it
//     grows, in a polite live region, never on a refresh that brings nothing.
//
// WHY THE CHAT OPENED AT THE TOP OR IN THE MIDDLE BEFORE THIS (app.js, drawChat, before 2026-10-15). The
// chat, the questions and the progress log scroll ONE window. The chat went to its end only when the
// window already stood at the end of the page - measured against wherever the window was: at the top
// after the questions (scrolled to 0) or after the app came back (the views are hidden on return, the page
// shrinks to the bar, and the browser puts the window back at 0), and part way down after a long list
// of questions or the progress log. So it opened at the earliest message or somewhere in the middle. And
// the composer's height was never measured (--compose-h kept its 120 px guess), so on a phone whose
// composer is taller (the iPhone's home bar adds its safe area) even the end of the page left the
// newest message's last line under the composer.
//
// The rule is pure here and checked by units.mjs; createChatScroll puts it on the page (app.js hands it
// the window and the chat's parts). Every text is set as text.

// How close to the bottom counts as at the bottom, in CSS pixels: a finger's slack, under one line of
// a message (24 px) plus its padding.
export const STICK_PX = 48;

import { scrollToNewest } from "./bar-height.js";

// How far the window stands above the bottom of the page.
export function distanceFromBottom(m) {
  return Math.max(0, m.scrollHeight - (m.scrollTop + m.viewHeight));
}
export function nearBottom(m, threshold = STICK_PX) {
  return distanceFromBottom(m) <= threshold;
}
// CAUGHT UP: at the bottom, or - a newest message taller than the screen, brought up to the bar's foot so that
// its top is seen - with the newest message's top on the screen (m.newestTop between m.barBottom and m.composeTop).
// Caught up, nothing is unseen, the Jump to latest button goes, and a message that arrives is followed.
export function caughtUp(m, threshold = STICK_PX) {
  if (nearBottom(m, threshold)) return true;
  return typeof m.newestTop === "number" && m.newestTop >= m.barBottom && m.newestTop < m.composeTop;
}
// What a drawing of the log does to his place: "bottom", or "keep" it where it was.
export function placeAfterDraw(s) {
  if (s.opening === true) return "bottom";
  return s.near === true ? "bottom" : "keep";
}
// The window's new top so that the message that stood at anchorBefore stands there again.
export function keptTop(scrollTop, anchorBefore, anchorAfter) {
  return Math.max(0, scrollTop + (anchorAfter - anchorBefore));
}
// The messages he has not had on screen at the bottom: the keys not in seen.
export function unseenCount(seen, keys) {
  let n = 0;
  for (const k of keys) if (!seen.has(k)) n++;
  return n;
}
// The button is shown only away from the bottom.
export function showJump(m, threshold = STICK_PX) {
  return !caughtUp(m, threshold);
}
export function jumpWords(count) {
  return count > 0 ? "Jump to latest (" + count + " new)" : "Jump to latest";
}
// What the live region says when the count moves from before to after: words when it grew, null to
// leave the region as it is (a refresh that brings nothing says nothing).
export function newsWords(before, after) {
  if (!(after > before)) return null;
  return after === 1 ? "1 new message below. Jump to latest to read it." : after + " new messages below. Jump to latest to read them.";
}

// The rule on the page. parts: { win, log, compose, button, news, field, topInset() }. The log's
// messages carry their key in data-key (app.js, drawChat); the day lines carry none and count for
// nothing.
export function createChatScroll(parts) {
  const { win, log, compose, button, news, field, topInset } = parts;
  const root = win.document.documentElement;
  let opening = true;
  let seen = new Set();
  let count = 0;
  const items = () => Array.from(log.children).filter((el) => el.dataset && el.dataset.key);
  function metrics() {
    const newest = items().pop();
    return { scrollTop: win.scrollY, viewHeight: win.innerHeight, scrollHeight: root.scrollHeight,
      newestTop: newest ? newest.getBoundingClientRect().top : undefined, barBottom: topInset(), composeTop: compose.getBoundingClientRect().top };
  }
  const keys = () => items().map((el) => el.dataset.key);
  // The page's foot is the composer's height (app.css, #chat): measured, never guessed, with the button
  // row hidden - the button stands only while he is away from the bottom. (The composer is fixed, so it
  // has no offsetParent: whether the chat is on screen is asked of the log.)
  function fitCompose() {
    if (button.hidden && log.offsetParent !== null) root.style.setProperty("--compose-h", Math.ceil(compose.getBoundingClientRect().height) + "px");
  }
  function update() {
    if (log.offsetParent === null) return;
    const away = showJump(metrics());
    const before = count;
    if (!away) { seen = new Set(keys()); count = 0; } else count = unseenCount(seen, keys());
    button.hidden = !away;
    button.textContent = jumpWords(count);
    const said = newsWords(before, count);
    if (!away) news.textContent = "";
    else if (said !== null) news.textContent = said;
  }
  // THE NEWEST MESSAGE IS SEEN FROM ITS TOP (the founder, 2026-10-20, desktop: "it jumps a little too far and
  // I can't see the question - it's blocked by the decisions button"): bar-height.js scrollToNewest. This is
  // also what follows a message that arrives while he is at the bottom (after) and his own line (sent): a tall
  // one shows its top below the bar, and the next arrival is followed too, since caughtUp holds with its top on
  // the screen. Scrolled up, an arrival never gets here (placeAfterDraw keeps his place).
  function toBottom() {
    button.hidden = true;
    fitCompose();
    scrollToNewest(win, root, items().pop(), topInset());
    update();
  }
  return {
    // The next drawing is an opening: it goes to the newest message.
    open() { opening = true; },
    // The horde locked: nothing of its log is remembered, and the next drawing opens.
    reset() { opening = true; seen = new Set(); count = 0; news.textContent = ""; button.hidden = true; button.textContent = jumpWords(0); },
    // Before the log is drawn again: whether he was at the bottom, and the first message on his screen.
    before() {
      const top = topInset();
      const first = items().find((el) => el.getBoundingClientRect().bottom > top);
      return { near: caughtUp(metrics()), key: first ? first.dataset.key : "", at: first ? first.getBoundingClientRect().top : 0 };
    },
    // After it is drawn: to the bottom, or his place kept.
    after(was) {
      const plan = placeAfterDraw({ opening, near: was.near });
      opening = false;
      if (plan === "bottom") { toBottom(); return; }
      const same = was.key ? items().find((el) => el.dataset.key === was.key) : null;
      if (same) win.scrollTo(0, keptTop(win.scrollY, was.at, same.getBoundingClientRect().top));
      update();
    },
    // His own line went: to the bottom.
    sent() { toBottom(); },
    update,
    toBottom,
    // The button: to the newest message; from the keyboard (Enter or Space: a click with no pointer),
    // on to the composer, since the button goes once at the bottom.
    jump(e) {
      toBottom();
      if (e && e.detail === 0 && field && !field.disabled) field.focus();
    }
  };
}
