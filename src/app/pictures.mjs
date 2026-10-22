// Pictures: textures composed from regions of encoded image files that the
// application sends as bytes. Sources are decoded once by key; a picture is
// composed on a canvas once all its sources have decoded, and kept until the
// application sends another version. The renderer uploads a composed
// picture as a texture, and the HUD draws regions of it on canvases.

// ---- Sources ----

// PNG files begin with these bytes; other formats are left to the browser
// to recognize.
const PNG = [0x89, 0x50, 0x4e, 0x47];

function decode(bytes) {
  const png = PNG.every((byte, index) => bytes[index] === byte);
  return createImageBitmap(new Blob([bytes], png ? {type: 'image/png'} : {}));
}

// A layer's region with its colors swapped: each 0xRRGGBB color found in
// the swaps becomes its replacement, alpha unchanged.
function recolored(bitmap, layer) {
  const canvas = new OffscreenCanvas(Math.max(1, layer.fw), Math.max(1, layer.fh));
  const context = canvas.getContext('2d');
  context.drawImage(bitmap, layer.fx, layer.fy, layer.fw, layer.fh, 0, 0, layer.fw, layer.fh);
  const image = context.getImageData(0, 0, canvas.width, canvas.height), data = image.data;
  for (let i = 0; i < data.length; i += 4) {
    const to = layer.swaps.get((data[i] << 16) | (data[i + 1] << 8) | data[i + 2]);
    if (to !== undefined) { data[i] = (to >> 16) & 255; data[i + 1] = (to >> 8) & 255; data[i + 2] = to & 255; }
  }
  context.putImageData(image, 0, 0);
  return canvas;
}

// ---- Pictures ----

export function createPictures() {
  const sources = new Map(), pictures = new Map(), listeners = new Map();

  // Draws each layer once every source it needs has decoded. A newer
  // version arriving meanwhile wins: the older composition is dropped.
  async function compose(picture) {
    const bitmaps = await Promise.all(picture.layers.map(layer => sources.get(layer.source)));
    if (pictures.get(picture.key) !== picture) return;
    const canvas = new OffscreenCanvas(Math.max(1, picture.width), Math.max(1, picture.height));
    const context = canvas.getContext('2d');
    context.imageSmoothingEnabled = false;
    picture.layers.forEach((layer, index) => {
      const image = layer.swaps.size ? recolored(bitmaps[index], layer) : bitmaps[index];
      const [fx, fy] = layer.swaps.size ? [0, 0] : [layer.fx, layer.fy];
      context.drawImage(image, fx, fy, layer.fw, layer.fh, layer.x, layer.y, layer.fw, layer.fh);
    });
    picture.canvas = canvas;
    for (const listener of listeners.get(picture.key) ?? []) listener(picture);
  }

  return {
    has(key, version) { return pictures.get(key)?.version === version; },
    hasSource(key) { return sources.has(key); },
    // Starts a picture; its layers follow, then `finish`.
    define(key, version, width, height) {
      const picture = {key, version, width, height, layers: [], canvas: null};
      pictures.set(key, picture);
      return picture;
    },
    addSource(key, bytes) {
      sources.set(key, decode(bytes).catch(error => { console.error(`source ${key}:`, error.message); throw error; }));
    },
    finish(picture) {
      compose(picture).catch(error => console.error(`picture ${picture.key}:`, error.message));
    },
    // The composed picture, or null until it is ready.
    get(key) { return pictures.get(key)?.canvas ? pictures.get(key) : null; },
    // Another module may key its pictures and sources the same way, so after
    // a module is replaced, every picture and source is asked for again.
    forget() {
      sources.clear();
      for (const picture of pictures.values()) picture.version = null;
    },
    // Calls `listener` whenever the picture under `key` is composed, until
    // the function this returns is called. Until then the store keeps the
    // listener and whatever it draws on, so a watcher that goes away must
    // call it, as the HUD does for an image that leaves.
    watch(key, listener) {
      if (!listeners.has(key)) listeners.set(key, new Set());
      listeners.get(key).add(listener);
      return () => listeners.get(key).delete(listener);
    },
  };
}
