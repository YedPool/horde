// surfaces/pwa/page/published-lists.js - EACH ORC'S PUBLISHED LIST ON THE DECISIONS PAGE (T-0328).
//
// The founder opened the Thrall's questions on his phone and saw one - the only question in the decisions
// store - while the Thrall had published a list of four with `horde decisions publish`. The machine now
// sends every Orc's published list in the snapshot (channels/decisions/Channel.ps1, EACH ORC'S PUBLISHED
// LIST; relay/js/protocol.js, readPublishedLists), and this page shows the list of the lane he has chosen
// beside that lane's questions: each item's text, recommendation, importance and blocking, the question it
// links when it links one, and when the list was published.
//
// A PURE VIEW AND A PURE RENDER: it knows nothing of the list or the bridge - what was sent, the questions
// the snapshot holds and the lane chosen are handed in; the clock's words are handed in too (fmt).
//
//   publishedView(published, questions, lane, laneOf, listed) -> { words, lists }
//     published   readPublishedLists' answer: null (the machine sent none) or the lists
//     questions   the snapshot's questions: an item that links one of them that is open is NOT drawn here
//                 (the question is in the list, once), and mergePublished gives the question the item's
//                 recommendation
//     lane        the lane chosen, "" for all, "thrall" for the Thrall's
//     laneOf      the document's laneOf(question) -> lane (window.HordeDecisionsDocument.lanes.laneOf), or null.
//                 A question counts as drawn in the list of questions only if the document draws it: with a lane
//                 chosen the document shows that lane's questions alone, so an item that links ANOTHER lane's open
//                 question stays in this list (review of PR 365, S1). With laneOf null every open question counts.
//     listed      the document's listed(question) -> true only when the document SHOWS the question in its list of
//                 questions (the lane chosen, and not in a collapsed or hidden fold such as With Thrall; review of
//                 PR 365, S1). When given, it decides which open questions hide an item and laneOf is not used for that.
//     words       one plain sentence when there is nothing to draw (the machine sends none, or the lane never
//                 published); "" otherwise
//     lists       [{ lane, title, state ("items", "empty" or "linked"), publishedAt, items, more, hidden, words }]
//   mergePublished(questions, published, laneOf) -> the questions, each linked by an item that has a recommendation
//     carrying that recommendation (a copy; the snapshot's own are not touched); with laneOf, only an item of
//     the question's own lane gives it one
//   renderPublishedLists(doc, view, { fmt }) -> the nodes to draw
//
// EVERY TEXT IS SET AS TEXT (textContent): an item's words are an Orc's, never markup.
export const THRALL_LANE = "thrall";

const BLOCKS_WORDS = { all: "blocks all work", part: "blocks part of the work", none: "blocks nothing" };

const titleOf = (lane) => (lane === THRALL_LANE ? "Thrall" : "Orc " + lane);
const whoOf = (lane) => (lane === THRALL_LANE ? "The Thrall" : "Orc " + lane);

function openNumbers(questions, lane, laneOf, listed) {
  const open = new Set();
  for (const q of Array.isArray(questions) ? questions : []) {
    if (!q || !Number.isSafeInteger(q.number) || q.state !== "open") continue;
    if (typeof listed === "function") { if (listed(q) === true) open.add(q.number); continue; }
    if (lane && typeof laneOf === "function" && laneOf(q) !== lane) continue;
    open.add(q.number);
  }
  return open;
}

function byLane(a, b) {
  if (a.lane === b.lane) return 0;
  if (a.lane === THRALL_LANE || b.lane === THRALL_LANE) return a.lane === THRALL_LANE ? -1 : 1;
  return a.lane < b.lane ? -1 : 1;
}

export function publishedView(published, questions, lane = "", laneOf = null, listed = null) {
  if (!Array.isArray(published)) return { words: "This machine has not sent the Orcs' published lists yet, so none can be shown here.", lists: [] };
  const open = openNumbers(questions, lane, laneOf, listed);
  const chosen = published.filter((l) => !lane || l.lane === lane).sort(byLane);
  if (lane && chosen.length === 0) return { words: whoOf(lane) + " has never published a list.", lists: [] };
  const lists = chosen.map((l) => {
    const items = l.items.filter((it) => it.question === null || !open.has(it.question));
    const hidden = l.items.length - items.length;
    let state = "items";
    let words = "";
    if (l.count === 0 && l.items.length === 0) { state = "empty"; words = whoOf(l.lane) + " published an empty list: nothing waits on you from here."; }
    else if (items.length === 0 && hidden > 0) { state = "linked"; words = "Every item of this list is a question in the list of questions."; }
    return { lane: l.lane, title: titleOf(l.lane), state, publishedAt: l.publishedAt, items, more: l.more, hidden, words };
  });
  return { words: "", lists };
}

export function mergePublished(questions, published, laneOf = null) {
  if (!Array.isArray(questions) || !Array.isArray(published)) return questions;
  const rec = new Map();
  for (const l of published.slice().sort(byLane)) {
    for (const it of l.items) if (it.question !== null && it.recommendation !== null && !rec.has(it.question + "|" + l.lane)) rec.set(it.question + "|" + l.lane, it.recommendation);
  }
  const recOf = (q) => {
    if (typeof laneOf === "function") return rec.get(q.number + "|" + laneOf(q));
    for (const l of published.slice().sort(byLane)) if (rec.has(q.number + "|" + l.lane)) return rec.get(q.number + "|" + l.lane);
    return undefined;
  };
  if (rec.size === 0) return questions;
  return questions.map((q) => {
    const r = q && q.state === "open" ? recOf(q) : undefined;
    return r === undefined ? q : { ...q, recommendation: r };
  });
}

function line(doc, cls, text) {
  const el = doc.createElement("div");
  el.className = cls;
  el.textContent = text;
  return el;
}

export function renderPublishedLists(doc, view, { fmt = (ms) => new Date(ms).toISOString() } = {}) {
  const out = [];
  if (view.words) { out.push(line(doc, "pl-note", view.words)); return out; }
  for (const l of view.lists) {
    const box = doc.createElement("section");
    box.className = "pl-list";
    box.setAttribute("aria-label", l.title + " published list");
    box.appendChild(line(doc, "pl-head", l.title + ": published list"));
    box.appendChild(line(doc, "pl-times", "Published " + fmt(l.publishedAt)));
    if (l.words) box.appendChild(line(doc, "pl-note", l.words));
    for (const it of l.items) {
      const row = doc.createElement("div");
      row.className = "pl-item";
      row.appendChild(line(doc, "pl-text", it.text));
      if (it.recommendation !== null) row.appendChild(line(doc, "pl-rec", "Recommended: " + it.recommendation));
      const meta = [];
      if (it.question !== null) meta.push("Question " + it.question);
      if (it.importance !== null) meta.push("importance " + it.importance);
      if (it.blocks !== null) meta.push(BLOCKS_WORDS[it.blocks] || "blocks " + it.blocks);
      if (meta.length) row.appendChild(line(doc, "pl-meta", meta.join(" - ")));
      box.appendChild(row);
    }
    if (l.hidden > 0 && l.state !== "linked") box.appendChild(line(doc, "pl-note", l.hidden + (l.hidden === 1 ? " item is a question in the list of questions." : " items are questions in the list of questions.")));
    if (l.more > 0) box.appendChild(line(doc, "pl-note", l.more + (l.more === 1 ? " more item is" : " more items are") + " shown at the machine only."));
    out.push(box);
  }
  return out;
}
