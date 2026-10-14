// surfaces/pwa/page/lane-card.js - ONE LANE'S CARD, the one card every page of the phone shows (the founder,
// 2026-10-13, record 184: the Progress tab and the decisions page show the SAME cards, one for the Thrall
// and one per Orc). A PURE RENDER of a lane and one slot: it knows nothing of the page it is on - no
// question, no stream, no store. What a tap does is the page's, handed in.
//
//   renderLaneCard(doc, lanes, laneId, { machine, badge, onOpen, nowMs }) -> a <button> element, or null
//     doc      the document to make elements in (the page's own; the suites hand in a small stand-in)
//     lanes    THE LANES DOCUMENT, merged: relay/js/protocol.js mergeCards(...) - { machines, thrall,
//              cards } - which phone-core.js cards(id) answers and the bridge's "cards" request carries
//     laneId   the lane: an Orc's letter as its lane file says it ("A", "B", "F1", ...), or "thrall"
//     machine  which machine's card, by name, when the lane is on more than one; left out, the first by
//              name. A Thrall card is always one machine's
//     badge    THE ONE OPEN SLOT: an element, a short text or a number, put in the card's head beside
//              its name - the Progress tab leaves it empty; the decisions page fills it with the lane's
//              open questions. A number is shown as its digits, 0 too (review of PR 244: a number was
//              handed to appendChild and threw); null, undefined or "" leave the slot empty. The slot is
//              in every card, empty or not, so a card is the same either way
//     onOpen   called with { lane, machine, entry } when the card is tapped - entry the phone's pairing
//              whose machine sent it; no onOpen, and a tap does nothing
//     nowMs    the time the card's age is said against; left out, now
//   laneCardView(lanes, laneId, { machine, nowMs }) -> the same card as plain data, or null: what
//     renderLaneCard draws, for a page or a suite that wants the words without elements.
//
// THE LANES DOCUMENT, per machine (channels/cards/Channel.ps1 makes it; relay/js/protocol.js
// readCardsSnapshot reads it), whole and replaced, machine to phone only:
//   { v: 1, kind: "cards-snapshot", horde, machine (key id), snapshot (hash), made (ISO), name (machine
//     name), thrall: { asOf, now, hasStatus, orcs, working, waitingFounder, blocked, unknown,
//     waitingFounderLanes: [lane], census: { running, waiting } | null, refused: [field] },
//     cards: [{ lane, name, form (standard|other|missing|unreadable), asOf, now, lastDone, waitingOn,
//     blocked (yes|no|""), blockedText, note, tasksOpen, doneWeek, refused: [field] }],
//     cardsLeftOut, areas: [{ area, lanes: [lane] }], areasLeftOut }. Within one snapshot no two cards
//     share a lane, and none is "thrall": readCardsSnapshot drops such a card and counts it
//
// EVERY TEXT IS SET AS TEXT (textContent): nothing from a machine is read as markup.
import { ageWords } from "../relay/protocol.js";

export const THRALL_LANE = "thrall";

function fromWords(machine, at, nowMs) { const age = ageWords(at, nowMs); return machine + (age ? ", " + age : ""); }

export function laneCardView(lanes, laneId, { machine = "", nowMs = Date.now() } = {}) {
  if (!lanes || typeof laneId !== "string") return null;
  if (laneId === THRALL_LANE) {
    const t = (lanes.thrall || []).find((x) => !machine || x.machine === machine);
    if (!t) return null;
    const made = ((lanes.machines || []).find((m) => m.name === t.machine) || {}).made;
    return {
      lane: THRALL_LANE, machine: t.machine, entry: t.entry, thrall: true, blocked: false, title: "Thrall", from: fromWords(t.machine, t.asOf || made, nowMs),
      lines: [
        { label: "Now", words: t.now || (t.hasStatus ? "" : "The Thrall keeps no status of its own yet; this card is made from the lanes.") },
        { label: "Fleet", words: t.orcs + " Orcs - " + t.working + " working, " + t.waitingFounder + " waiting on the founder, " + t.blocked + " blocked" + (t.unknown ? ", " + t.unknown + " not known" : "") },
        { label: "Waiting on the founder", words: (t.waitingFounderLanes || []).join(", ") }
      ].filter((l) => l.words),
      stats: t.census ? "Sessions running " + t.census.running + " - waiting on a person " + t.census.waiting : "Sessions: not known on this machine",
      note: ""
    };
  }
  const c = (lanes.cards || []).find((x) => x.lane === laneId && (!machine || x.machine === machine));
  if (!c) return null;
  const lines = [{ label: "Now", words: c.now }, { label: "Last done", words: c.lastDone }];
  if (c.form === "standard" || c.form === "other") {
    lines.push({ label: "Waiting on", words: c.waitingOn || (c.form === "standard" ? "nothing said" : "") });
    lines.push({ label: "Blocked", words: c.blocked === "yes" ? (c.blockedText ? "yes - " + c.blockedText : "yes") : c.blocked });
  }
  return {
    lane: c.lane, machine: c.machine, entry: c.entry, thrall: false, blocked: c.blocked === "yes", title: c.lane === c.name ? c.name : c.lane + " - " + c.name, from: fromWords(c.machine, c.asOf, nowMs),
    lines: lines.filter((l) => l.words),
    stats: c.tasksOpen === null ? "Tasks: not known" : "Tasks open " + c.tasksOpen + " - done this week " + c.doneWeek,
    note: c.note || ""
  };
}

export function renderLaneCard(doc, lanes, laneId, { machine = "", badge = null, onOpen = null, nowMs = Date.now() } = {}) {
  const v = laneCardView(lanes, laneId, { machine, nowMs });
  if (!v) return null;
  const el = (tag, className, words) => { const e = doc.createElement(tag); if (className) e.className = className; if (words !== undefined) e.textContent = words; return e; };
  const box = el("button", "card" + (v.thrall ? " thrall" : "") + (v.blocked ? " blocked" : ""));
  box.type = "button";
  box.setAttribute("data-lane", v.lane);
  const head = el("div", "card-head");
  head.appendChild(el("span", "card-name", v.title));
  // THE ONE OPEN SLOT, the page's to fill.
  const slot = el("span", "card-badge");
  if (badge !== null && badge !== undefined && badge !== "") { if (typeof badge === "string" || typeof badge === "number") slot.textContent = String(badge); else slot.appendChild(badge); }
  head.appendChild(slot);
  head.appendChild(el("span", "card-from", v.from));
  box.appendChild(head);
  for (const l of v.lines) {
    const p = el("div", "card-line");
    p.appendChild(el("b", "", l.label + ": "));
    p.appendChild(doc.createTextNode(l.words));
    box.appendChild(p);
  }
  if (v.stats) box.appendChild(el("div", "card-stats", v.stats));
  if (v.note) box.appendChild(el("div", "card-note", v.note));
  if (typeof onOpen === "function") box.addEventListener("click", () => onOpen({ lane: v.lane, machine: v.machine, entry: v.entry }));
  return box;
}
