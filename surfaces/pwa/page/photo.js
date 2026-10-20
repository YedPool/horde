// surfaces/pwa/page/photo.js - the phone shrinks a picture before it goes to the PC (channels/chat/Photo.ps1).
//
// WHAT IT MAKES: one JPEG, its longest side at most 1600 px - or 2000 px when the picture is mostly text
// or a screenshot, so small letters stay readable - and at most PHOTO_OUT_BYTES. Re-encoding through a
// canvas writes new JPEG bytes from pixels only, so the camera's EXIF block, with the location and the
// camera's make, is not in what is sent (test-pwa-browser.ps1 checks a real canvas JPEG carries no Exif).
//
// HOW IT TELLS TEXT FROM A PHOTO (the heuristic, measured on made-up pixels in units.mjs): the picture is
// sampled at most 256 px on its longest side; each pixel's colour is cut to 4 bits a channel;
//   flat  the share of pixels in the 4 most common of those colours - a screenshot or a page of text is
//         mostly a few flat colours (background, text, one or two accents), a photo's noise and
//         shading spread it over hundreds;
//   edges the share of side-by-side pixel pairs whose brightness differs by more than 96 of 255 - the
//         hard strokes of letters.
// It is text-like when flat >= 0.5 AND edges >= 0.02: a white wall is flat with no edges (a photo), and
// a photo of leaves has edges but is not flat. A wrong guess costs only size: 1600 px of text is still
// legible on most screenshots, and 2000 px of a photo is still under the byte cap.
//
// NO DOM IN THE LOGIC: shrinkWith takes an encode(width, height, quality) -> JPEG bytes, so the suites
// run it under Node with a made-up encoder; shrinkInBrowser is the one function that touches a canvas.

export const PHOTO_OUT_BYTES = 1000000;
export const PHOTO_SIDE = 1600;
export const PHOTO_TEXT_SIDE = 2000;
const QUALITIES = [0.86, 0.78, 0.7, 0.62, 0.55];
const SAMPLE_SIDE = 256;

// The text-likeness of RGBA pixels (width x height): { textLike, flat, edges }.
export function textLikeness(rgba, width, height) {
  const n = width * height;
  if (!n || rgba.length < n * 4) return { textLike: false, flat: 0, edges: 0 };
  const counts = new Map();
  let edgePairs = 0;
  let pairs = 0;
  for (let y = 0; y < height; y++) {
    let lastLum = -1;
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      const r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      const q = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      counts.set(q, (counts.get(q) || 0) + 1);
      const lum = (r * 299 + g * 587 + b * 114) / 1000;
      if (lastLum >= 0) { pairs++; if (Math.abs(lum - lastLum) > 96) edgePairs++; }
      lastLum = lum;
    }
  }
  const top = [...counts.values()].sort((a, b) => b - a).slice(0, 4).reduce((s, c) => s + c, 0);
  const flat = top / n;
  const edges = pairs ? edgePairs / pairs : 0;
  return { textLike: flat >= 0.5 && edges >= 0.02, flat, edges };
}

// The size to draw at: the longest side no more than the cap for the kind of picture, never enlarged.
export function targetSize(width, height, textLike) {
  const cap = textLike ? PHOTO_TEXT_SIDE : PHOTO_SIDE;
  const long = Math.max(width, height);
  if (long <= cap) return { width, height };
  const k = cap / long;
  return { width: Math.max(1, Math.round(width * k)), height: Math.max(1, Math.round(height * k)) };
}

function isJpeg(b) { return b instanceof Uint8Array && b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff; }

// Shrink to a JPEG within the caps: { bytes, width, height, quality, tries }. Quality steps down first,
// then the size by 15% a round, at most 6 rounds; throws in plain words when even that does not fit.
export async function shrinkWith({ width, height, textLike }, encode, maxBytes = PHOTO_OUT_BYTES) {
  let size = targetSize(width, height, textLike);
  let tries = 0;
  for (let round = 0; round < 6; round++) {
    for (const q of QUALITIES) {
      tries++;
      const bytes = await encode(size.width, size.height, q);
      if (!isJpeg(bytes)) throw new Error("The phone could not make a JPEG of this picture.");
      if (bytes.length <= maxBytes) return { bytes, width: size.width, height: size.height, quality: q, tries };
    }
    size = { width: Math.max(1, Math.round(size.width * 0.85)), height: Math.max(1, Math.round(size.height * 0.85)) };
  }
  throw new Error("This picture could not be made small enough to send.");
}

// In the browser: a picked file to { bytes, width, height, textLike, thumb } - thumb a small canvas the
// page draws in the chat (a canvas, not an image URL: the page's policy loads images from itself only).
export async function shrinkInBrowser(blob) {
  const bitmap = await createImageBitmap(blob, { imageOrientation: "from-image" });
  try {
    const k = Math.min(1, SAMPLE_SIDE / Math.max(bitmap.width, bitmap.height));
    const sw = Math.max(1, Math.round(bitmap.width * k)), sh = Math.max(1, Math.round(bitmap.height * k));
    const sample = canvasOf(sw, sh);
    const sctx = sample.getContext("2d", { willReadFrequently: true });
    sctx.drawImage(bitmap, 0, 0, sw, sh);
    const look = textLikeness(sctx.getImageData(0, 0, sw, sh).data, sw, sh);
    const encode = async (w, h, q) => {
      const c = canvasOf(w, h);
      const ctx = c.getContext("2d");
      ctx.fillStyle = "#fff";
      ctx.fillRect(0, 0, w, h);
      ctx.drawImage(bitmap, 0, 0, w, h);
      const out = c.convertToBlob ? await c.convertToBlob({ type: "image/jpeg", quality: q }) : await new Promise((ok) => c.toBlob(ok, "image/jpeg", q));
      return out ? new Uint8Array(await out.arrayBuffer()) : new Uint8Array(0);
    };
    const made = await shrinkWith({ width: bitmap.width, height: bitmap.height, textLike: look.textLike }, encode);
    const t = Math.min(1, 160 / Math.max(bitmap.width, bitmap.height));
    const thumb = document.createElement("canvas");
    thumb.width = Math.max(1, Math.round(bitmap.width * t));
    thumb.height = Math.max(1, Math.round(bitmap.height * t));
    thumb.getContext("2d").drawImage(bitmap, 0, 0, thumb.width, thumb.height);
    return { ...made, textLike: look.textLike, flat: look.flat, edges: look.edges, thumb };
  } finally { bitmap.close(); }
}

function canvasOf(w, h) {
  if (typeof OffscreenCanvas === "function") return new OffscreenCanvas(w, h);
  const c = document.createElement("canvas");
  c.width = w; c.height = h;
  return c;
}
