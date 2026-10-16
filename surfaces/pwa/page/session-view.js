// surfaces/pwa/page/session-view.js - the unlocked session in plain words, for the Account screen
// (phone-core.js, THE UNLOCKED SESSION; bridge.js, sessions). No DOM: the page puts the line where it
// goes, and the suites read the words here.
//
// sessionLines(list, timeOf) -> one sentence for each unlocked horde, in the list's order:
//   list    bridge.js's sessions: [{ horde, open, until, keeps }]
//   timeOf  ms -> the page's short time ("18:40")
// open is whether the session key may sign now; until when it ends unless used again; keeps false when
// the PC says nothing of sessions (an older PC: each envelope asks for the passkey), null before any
// snapshot has come.
export function sessionLines(list, timeOf) {
  const out = [];
  for (const x of Array.isArray(list) ? list : []) {
    const who = String(x.horde || "This horde") + ": ";
    if (x.open && x.keeps === false) out.push(who + "your PC needs an update before answers can go without the passkey, so each answer, chat line and photo asks for it.");
    else if (x.open) out.push(who + "an unlocked session is open until " + timeOf(Number(x.until)) + ". Answers, chat lines and photos go without the passkey until then - sooner if the app stays in the background too long.");
    else out.push(who + "no unlocked session is open. The next answer asks for your passkey once, and opens one.");
  }
  return out;
}
