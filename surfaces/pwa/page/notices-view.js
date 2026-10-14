// surfaces/pwa/page/notices-view.js - THE NOTICES AND THE FOLLOW SWITCH, drawn: pure renders the page hands
// its document and its own taps to, as lane-card.js is, so each can be checked under Node with a stand-in
// document (surfaces/pwa/test/units.mjs). Nothing here sends or stores: what a tap does is the page's.
//
//   renderFollowSwitch(doc, { held, sending, onToggle }) -> a <span role="switch">, for a card's one slot
//     held      what THE MACHINE holds for this lane (the newest notices envelope of the card's machine,
//               phone-core.js, THE NOTICES): never what the phone only asked for
//     sending   a change is on its way: the switch says so, and a tap does nothing until the machine's
//               answer comes back
//     onToggle  called with the value wanted (the opposite of held) on a tap. THE TAP IS THE SWITCH'S OWN:
//               it is stopped there, so the card it sits in - a button whose tap opens the lane's stream -
//               is not opened by it too
//   renderNoticeItem(doc, item, { nowMs, onOpen }) -> a <button>: who it is from, when in plain words (the
//     exact time as its title), whether it is read, and its words; onOpen(item) on a tap
//   noticeTarget(item) -> { entry, lane, machine } for a notice that opens something (a followed lane's
//     progress entry opens that lane's stream), or null
//   noticesTabWords(unread) -> "Notices", or "Notices (3)" with unread ones
//
// EVERY TEXT IS SET AS TEXT (textContent): nothing from a machine is read as markup.
import { ageWords, exactTime } from "../relay/protocol.js";

export function renderFollowSwitch(doc, { held = false, sending = false, onToggle = null } = {}) {
  const sw = doc.createElement("span");
  sw.className = "follow" + (sending ? " sending" : "");
  sw.setAttribute("role", "switch");
  sw.setAttribute("aria-checked", held ? "true" : "false");
  sw.setAttribute("aria-label", "Follow this lane's progress as notices");
  sw.textContent = sending ? "Sending..." : held ? "Following" : "Follow";
  sw.addEventListener("click", (e) => {
    if (e) { e.stopPropagation(); e.preventDefault(); }
    if (!sending && typeof onToggle === "function") onToggle(!held);
  });
  return sw;
}

export function noticeTarget(item) {
  if (!item || item.kind !== "progress" || !item.lane) return null;
  return { entry: item.entry, lane: item.lane, machine: item.machine || "" };
}

export function noticesTabWords(unread) { return "Notices" + (unread > 0 ? " (" + unread + ")" : ""); }

export function renderNoticeItem(doc, item, { nowMs = Date.now(), onOpen = null } = {}) {
  const el = (tag, className, words) => { const e = doc.createElement(tag); if (className) e.className = className; if (words !== undefined) e.textContent = words; return e; };
  const box = el("button", "notice-item" + (item.read ? "" : " unread"));
  box.type = "button";
  box.setAttribute("data-id", item.id);
  const head = el("div", "notice-head");
  head.appendChild(el("span", "notice-from", item.from));
  if (!item.read) head.appendChild(el("span", "chip kind-merged", "Unread"));
  const when = el("span", "notice-when", ageWords(item.said, nowMs));
  if (item.said) when.setAttribute("title", exactTime(item.said));
  head.appendChild(when);
  box.appendChild(head);
  box.appendChild(el("div", "notice-text", item.text));
  if (typeof onOpen === "function") box.addEventListener("click", () => onOpen(item));
  return box;
}
