// THE JUMP TO THE LATEST MESSAGE STOPS UNDER THE STICKY BAR, IN A REAL BROWSER (surfaces/pwa/page/chat-scroll.js,
// bar-height.js, app.css), for test/test-pwa-bar-offset-browser.ps1: headless Chrome through browser-harness.mjs's
// /bar.html - the phone app's own bar, list and chat, cut out of index.html - at three screens.
//
// The founder, 2026-10-20, on his desktop browser: "When horde jumps to the latest question, it jumps a little
// too far and I can't see the question - it's blocked by the decisions button." Jump to latest went to the foot
// of the page; a newest message taller than the room between the bar and the composer then had its top, where
// the question is asked, under the sticky bar. Checked here at desktop width (1400 by 900), phone width (390 by
// 844) and 200 percent zoom (a 700 by 450 CSS screen at twice the pixels):
//   1. the newest message taller than the screen: after Jump to latest its top stands at or below the bar's
//      bottom, and on the screen above the composer;
//   1b. one that reaches only partly under the bar (its top below the window's top) comes down below it too;
//   2. the newest message that fits: whole, between the bar and the composer;
//   3. the bar grown (the PC-offline line wraps to many lines): the bar's height in --bar-h follows it, and the
//      jump still clears it;
//   4. a question of the list brought to the top of the view by the browser (scrollIntoView, as a focus or a
//      link does) stands below the bar, by the scroll margin the cards carry.
//   1a/1c/1d. Jump to latest is gone with the newest message's top on the screen and back when he is scrolled away;
//      a tall message arriving while he is caught up shows its top below the bar and the next arrival is followed
//      (the stick state is kept); scrolled up, an arrival never moves the view and is counted;
//   5. the progress log's Jump to newest: a tall newest entry is shown from its top, below the bar.
// And app.js is asked to track the bar's height at all, and to take the newest progress entry through the same helper.
//
//   node browser-bar.mjs <decisions/page folder> <chrome.exe> <profile folder>
//
// Prints one line per check, "[PASS] name" or "[FAIL] name: detail", then "[DONE] n".
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { openBrowser, check, question, sleep } from "./browser-harness.mjs";

const [, , pageDir, chromePath, profileDir] = process.argv;
const { cdp, evaluate, load, settle, problems, finish } = await openBrowser(pageDir, chromePath, profileDir);

const appJs = readFileSync(join(pageDir, "..", "..", "surfaces", "pwa", "page", "app.js"), "utf8");
check(/trackBarHeight\(\$\("bar"\), document\.documentElement\)/.test(appJs), "app.js tracks the bar's height (trackBarHeight on #bar)");

check((appJs.match(/progressToNewest/g) || []).length >= 3 && /scrollToNewest\(window, document\.documentElement, \$\("progressLog"\)\.lastElementChild/.test(appJs), "app.js takes both progress jumps (the click and the opening) through scrollToNewest");

const SCREENS = [
  { name: "desktop 1400x900", width: 1400, height: 900, scale: 1, mobile: false },
  { name: "phone 390x844", width: 390, height: 844, scale: 3, mobile: true },
  { name: "200 percent zoom (700x450 CSS px)", width: 700, height: 450, scale: 2, mobile: false }
];
const px = (n) => Math.round(n * 10) / 10;
// Where the newest message, the bar and the composer stand.
const STANDS = `(() => { const n = document.getElementById('newest').getBoundingClientRect(); return { top: n.top, bottom: n.bottom, bar: document.getElementById('bar').getBoundingClientRect().bottom, compose: document.getElementById('chatCompose').getBoundingClientRect().top, height: innerHeight, barVar: getComputedStyle(document.documentElement).getPropertyValue('--bar-h').trim(), barH: document.getElementById('bar').getBoundingClientRect().height, jumpHidden: document.getElementById('chatJump').hidden, jumpText: document.getElementById('chatJump').textContent, scrollY: Math.round(scrollY) }; })()`;
// Away from the foot, then the real button pressed.
async function jump() {
  await evaluate("scrollTo(0, 0), true");
  await settle();
  await evaluate("document.getElementById('chatJump').click(), true");
  await settle();
  await sleep(100);
}

for (const s of SCREENS) {
  await cdp("Emulation.setDeviceMetricsOverride", { width: s.width, height: s.height, deviceScaleFactor: s.scale, mobile: s.mobile });
  await load("/bar.html");
  await settle();
  await evaluate("new Promise((r) => { const t = setInterval(() => { if (window.hostReady) { clearInterval(t); r(true); } }, 20); })");

  // 1. A newest message taller than the screen.
  await evaluate("window.drawChat(40, Math.round(innerHeight * 1.2)), true");
  await jump();
  let m = await evaluate(STANDS);
  check(m.top >= m.bar - 0.5, s.name + ": a tall newest message - its top stands at or below the bar", "top " + px(m.top) + " bar " + px(m.bar));
  check(m.top < m.compose, s.name + ": a tall newest message - its top is on the screen above the composer", "top " + px(m.top) + " composer " + px(m.compose));
  check(m.jumpHidden === true, s.name + ": with the tall newest message's top on the screen, Jump to latest is gone", "hidden " + m.jumpHidden + " text " + m.jumpText);

  // 1a. Scrolled away, the button is there again (and the jump brings the newest message's top back, button gone).
  await evaluate("scrollTo(0, 0), true");
  await settle();
  m = await evaluate(STANDS);
  check(m.jumpHidden === false, s.name + ": scrolled away from the newest message, Jump to latest is shown", "hidden " + m.jumpHidden);

  // 1e. Read on down inside the tall newest message: its top is under the bar again, he is not at the foot - the button is back.
  await jump();
  await evaluate("scrollBy(0, 100), true");
  await settle();
  await sleep(100);
  m = await evaluate(STANDS);
  check(m.jumpHidden === false && m.top < m.bar, s.name + ": reading on down a tall newest message (its top under the bar), Jump to latest is shown", "hidden " + m.jumpHidden + " top " + px(m.top) + " bar " + px(m.bar));

  // 1c. A TALL MESSAGE ARRIVES while he is caught up (his place asked before, the log drawn, then the rule): its top
  // is brought below the bar, and the next arrival is followed too - the stick state is kept.
  await jump();
  await evaluate("window.arrive(Math.round(innerHeight * 1.2)), true");
  await settle();
  m = await evaluate(STANDS);
  check(m.top >= m.bar - 0.5 && m.top < m.compose && m.jumpHidden === true, s.name + ": a tall message arriving while he is caught up shows its top below the bar, button gone", "top " + px(m.top) + " bar " + px(m.bar) + " hidden " + m.jumpHidden);
  await evaluate("window.arrive(Math.round(innerHeight * 0.2)), true");
  await settle();
  m = await evaluate(STANDS);
  check(m.top >= m.bar - 0.5 && m.bottom <= m.compose + 0.5 && m.jumpHidden === true, s.name + ": the next arrival is followed (the stick state was kept)", "top " + px(m.top) + " bottom " + px(m.bottom) + " composer " + px(m.compose) + " hidden " + m.jumpHidden);

  // 1d. SCROLLED UP, an arrival never moves the view; the button says so.
  await evaluate("scrollTo(0, 0), true");
  await settle();
  const before = (await evaluate(STANDS)).scrollY;
  await evaluate("window.arrive(Math.round(innerHeight * 1.2)), true");
  await settle();
  m = await evaluate(STANDS);
  check(m.scrollY === before && m.jumpHidden === false && /1 new/.test(m.jumpText), s.name + ": scrolled up, an arrival leaves the view where it was and the button counts it", "scrollY " + before + " -> " + m.scrollY + " hidden " + m.jumpHidden + " text " + m.jumpText);

  // 1b. A newest message that reaches only partly under the bar: its top is below the window's top, but above the bar's foot.
  await evaluate("window.drawChat(40, Math.round(document.getElementById('chatCompose').getBoundingClientRect().top - 26 - document.getElementById('bar').getBoundingClientRect().bottom / 2)), true");
  await jump();
  m = await evaluate(STANDS);
  check(m.top >= m.bar - 0.5, s.name + ": a newest message half under the bar comes down below it", "top " + px(m.top) + " bar " + px(m.bar));

  // 2. A newest message that fits.
  await evaluate("window.drawChat(40, Math.round(innerHeight * 0.3)), true");
  await jump();
  m = await evaluate(STANDS);
  check(m.top >= m.bar - 0.5 && m.bottom <= m.compose + 0.5, s.name + ": a newest message that fits stands whole between the bar and the composer", "top " + px(m.top) + " bottom " + px(m.bottom) + " bar " + px(m.bar) + " composer " + px(m.compose));

  // 3. The bar grows: its height, followed, is what the jump clears.
  await evaluate("document.getElementById('pcOffline').textContent = 'PC Orc-Workstation-Of-The-Founder is offline since 2026-10-20 09:15 local time. Your answers are kept on this device and go to the PC the moment it is back; nothing you have written is lost, and nothing is sent until then. ' .repeat(2), true");
  await settle();
  await sleep(150);
  await settle();
  await evaluate("window.drawChat(40, Math.round(innerHeight * 1.2)), true");
  await jump();
  m = await evaluate(STANDS);
  check(Math.abs(parseFloat(m.barVar) - m.barH) <= 1, s.name + ": --bar-h follows a bar that grew", "--bar-h " + m.barVar + " bar " + px(m.barH));
  check(m.top >= m.bar - 0.5 && m.top < m.compose, s.name + ": the bar grown - the tall newest message's top still clears it", "top " + px(m.top) + " bar " + px(m.bar));

  // 4. A question brought to the top of the view by the browser.
  await evaluate("document.getElementById('pcOffline').textContent = '', true");
  await settle();
  await evaluate("window.drawChat(0, 10), true");
  const qs = [];
  for (let n = 1; n <= 30; n++) qs.push(question(n));
  await evaluate("window.doc.setList({ state: 'known', value: { questions: " + JSON.stringify(qs) + " } }), true");
  await settle();
  const q = await evaluate("(() => { const all = Array.from(document.querySelectorAll('#lists .hd-q:not(.hd-done)')); const el = all[4]; scrollTo(0, 0); el.scrollIntoView({ block: 'start' }); const r = el.getBoundingClientRect(); return { n: all.length, top: r.top, bar: document.getElementById('bar').getBoundingClientRect().bottom }; })()");
  await settle();
  check(q.n >= 20 && q.top >= q.bar - 0.5, s.name + ": a question scrolled to the top of the view stands below the bar", "questions " + q.n + " top " + px(q.top) + " bar " + px(q.bar));

  // 5. THE PROGRESS LOG: Jump to newest, a newest entry taller than the screen.
  await load("/bar.html?view=progress");
  await settle();
  await evaluate("new Promise((r) => { const t = setInterval(() => { if (window.hostReady) { clearInterval(t); r(true); } }, 20); })");
  await evaluate("window.drawProgress(40, Math.round(innerHeight * 1.2)), true");
  await evaluate("scrollTo(0, 0), true");
  await settle();
  await evaluate("document.getElementById('progressNewest').click(), true");
  await settle();
  await sleep(100);
  const g = await evaluate("(() => ({ top: document.getElementById('newest').getBoundingClientRect().top, bar: document.getElementById('bar').getBoundingClientRect().bottom, y: scrollY }))()");
  check(g.y > 0 && g.top >= g.bar - 0.5 && g.top < 1000, s.name + ": the progress log's Jump to newest shows a tall newest entry from its top, below the bar", "top " + px(g.top) + " bar " + px(g.bar));
}

check(problems.length === 0, "no error was thrown in the page", problems.join(" | "));
finish();
