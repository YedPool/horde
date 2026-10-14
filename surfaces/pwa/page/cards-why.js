// surfaces/pwa/page/cards-why.js - the one plain line the Progress tab shows when it falls back to the
// whole log because there are no cards, so the founder (and we) can tell the cases apart. Pure: app.js
// puts the line on the page by textContent; units.mjs checks every case.
//
// The cases, from what phone-core.js cards(id) answers ({ machines, refused, unpaired }):
//   refused   a cards snapshot from a paired PC that did not read: its reason, the protocol's own short
//             words (relay/js/protocol.js, readCardsSnapshot) - no secret and no path is in them, and
//             what is said is cut short and kept to plain ASCII all the same;
//   unpaired  a cards envelope came, into this horde's mailbox, from a PC this phone has no pairing for;
//   neither   no cards have come yet.
// With cards present there is no line.

const MAX_REASON = 100;

export function cardsFallbackLine(v) {
  if (v && Array.isArray(v.machines) && v.machines.length > 0) return "";
  const reason = v && typeof v.refused === "string" ? v.refused.replace(/[^\x20-\x7e]/g, "").trim().replace(/\.+$/, "").slice(0, MAX_REASON) : "";
  if (reason) return "Cards could not be read: " + reason + ".";
  if (v && v.unpaired === true) return "This phone is not paired to the PC that sends cards.";
  return "No cards from your PC yet.";
}
