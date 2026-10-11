// surfaces/pwa/page/scan.js - reading the machine's pairing offer from its QR code with the camera,
// where the browser can (BarcodeDetector: Chrome on Android has it), and saying so where it cannot -
// the app then offers a field to paste the offer's text into. No library is loaded for this: a QR
// decoder in JavaScript would be third-party code holding the pairing secret (design, threat model:
// no third-party script), and the paste path covers every browser.
//
// The offer is a bearer secret for its short life (relay/Pairing.ps1, WHAT A STOLEN OFFER CAN AND
// CANNOT DO): the frames are read in memory and never kept, and the camera is stopped the moment a
// code is read or the founder cancels.
const SCAN_EVERY_MS = 250;

export async function canScan() {
  if (typeof globalThis.BarcodeDetector === "undefined" || !globalThis.navigator || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return false;
  try { const formats = await globalThis.BarcodeDetector.getSupportedFormats(); return formats.indexOf("qr_code") >= 0; } catch (e) { return false; }
}

// Scan into a <video> element until a QR code is read: { text } or { cancelled: true }. The returned
// stop() ends it early.
export function scanQr(video) {
  let stopped = false;
  let stream = null;
  let timer = null;
  let finish = null;
  const done = new Promise((resolve) => { finish = resolve; });
  function stop(result = { cancelled: true }) {
    if (stopped) return;
    stopped = true;
    if (timer) clearTimeout(timer);
    if (stream) for (const t of stream.getTracks()) t.stop();
    video.srcObject = null;
    finish(result);
  }
  (async () => {
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false });
      if (stopped) { for (const t of stream.getTracks()) t.stop(); return; }
      video.srcObject = stream;
      await video.play();
      const detector = new globalThis.BarcodeDetector({ formats: ["qr_code"] });
      const tick = async () => {
        if (stopped) return;
        try {
          const found = await detector.detect(video);
          const hit = found.find((c) => typeof c.rawValue === "string" && c.rawValue.indexOf("horde-relay-pairing-offer") >= 0);
          if (hit) { stop({ text: hit.rawValue }); return; }
        } catch (e) { /* a frame that could not be read: the next one may */ }
        timer = setTimeout(tick, SCAN_EVERY_MS);
      };
      tick();
    } catch (e) { stop({ cancelled: true, reason: "the camera could not be used: " + (e && e.message ? e.message : e) }); }
  })();
  return { done, stop: () => stop() };
}
