// surfaces/pwa/page/decision-cards.js - THE CARDS AT THE HEAD OF THE DECISIONS PAGE (the founder's decision
// 74, 2026-10-14: "the cards on the decisions page lets go" - cards first, one per lane with its open
// questions and a mark when one of them blocks all its work, plus one "All questions" card; a tap on a card
// shows that lane's questions, or all of them).
//
// THE SAME CARD AS THE PROGRESS TAB (lane-card.js, record 184: the two pages show the same cards): each is
// renderLaneCard's card, its one slot holding the lane's count. A lane that asked a question and has no
// card in the lanes document (no machine sent one yet, or the lane keeps no status) is the same card with
// its name alone (lane-card.js, orName). A PURE RENDER: it knows nothing of the list - what is counted,
// and what a tap does, are handed in.
//
//   decisionCardsView(lanes, counts, chosen) -> [{ lane, title, open, blocksAll, chosen }]
//     lanes    THE LANES DOCUMENT (lane-card.js), or null when none has come
//     counts   decisions/page/list.js doc.lanes(): [{ lane, open, blocksAll }] for the lanes with a
//              question he has still to answer
//     chosen   the lane chosen, "" for all (doc.lane())
//   The "All questions" card first (lane ALL), then the Thrall's, then every other lane by name: each lane
//   of the lanes document - with 0 when it asks nothing - and each lane that asks and has no card there.
//   renderDecisionCards(doc, lanes, counts, { chosen, onChoose, nowMs }) -> the cards, as <button>s
//     onChoose(lane)   a tap on a card: its lane, "" for All questions
//
// THE MARK, WHEN A LANE'S QUESTION BLOCKS ALL ITS WORK, is words and a sign together, never a colour
// alone: the slot says "3 open" and, after it, the stop sign (an escape: this source is ASCII) and the
// words "blocks all work". The chosen card says so to a screen reader (aria-pressed) and by its class.
//
// EVERY TEXT IS SET AS TEXT (textContent), by lane-card.js and here alike.
import { renderLaneCard, THRALL_LANE } from "./lane-card.js";

export const ALL = "all";
const ALL_TITLE = "All questions";
const STOP_SIGN = "\u26D4";
const BLOCKS_WORDS = "blocks all work";

const titleOf = (lane) => (lane === THRALL_LANE ? "Thrall" : "Orc " + lane);

export function decisionCardsView(lanes, counts, chosen = "") {
  const by = new Map();
  for (const c of Array.isArray(counts) ? counts : []) {
    if (c && typeof c.lane === "string" && c.lane) by.set(c.lane, { open: Number(c.open) || 0, blocksAll: c.blocksAll === true });
  }
  const names = new Set(by.keys());
  if (lanes && Array.isArray(lanes.thrall) && lanes.thrall.length) names.add(THRALL_LANE);
  for (const c of lanes && Array.isArray(lanes.cards) ? lanes.cards : []) if (c && typeof c.lane === "string" && c.lane) names.add(c.lane);
  const order = Array.from(names).sort((a, b) => (a === b ? 0 : a === THRALL_LANE ? -1 : b === THRALL_LANE ? 1 : a < b ? -1 : 1));
  let open = 0;
  let blocksAll = false;
  for (const v of by.values()) { open += v.open; blocksAll = blocksAll || v.blocksAll; }
  const out = [{ lane: ALL, title: ALL_TITLE, open, blocksAll, chosen: !chosen }];
  for (const lane of order) {
    const v = by.get(lane) || { open: 0, blocksAll: false };
    out.push({ lane, title: titleOf(lane), open: v.open, blocksAll: v.blocksAll, chosen: chosen === lane });
  }
  return out;
}

function slot(doc, v) {
  const box = doc.createElement("span");
  box.className = "dq-count";
  box.textContent = v.open + " open";
  if (v.blocksAll) {
    const mark = doc.createElement("span");
    mark.className = "dq-blocks";
    mark.textContent = " " + STOP_SIGN + " " + BLOCKS_WORDS;
    box.appendChild(mark);
  }
  return box;
}

export function renderDecisionCards(doc, lanes, counts, { chosen = "", onChoose = null, nowMs = Date.now() } = {}) {
  const out = [];
  for (const v of decisionCardsView(lanes, counts, chosen)) {
    const pick = v.lane === ALL ? "" : v.lane;
    // All questions is never a lane of the lanes document: it is always the card with its name alone.
    const card = renderLaneCard(doc, v.lane === ALL ? null : lanes, v.lane, { badge: slot(doc, v), orName: v.title, nowMs, onOpen: typeof onChoose === "function" ? () => onChoose(pick) : null });
    if (!card) continue;
    card.className += " dq-card";
    if (v.blocksAll) card.className += " dq-blocking";
    if (v.chosen) card.className += " chosen";
    card.setAttribute("aria-pressed", v.chosen ? "true" : "false");
    out.push(card);
  }
  return out;
}
