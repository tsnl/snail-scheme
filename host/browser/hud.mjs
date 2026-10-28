// The HUD: panels of labels, buttons, dials, links and images, stacked in
// columns in the screen's corners, shown as dialogs over a backdrop, or as
// banners across the top that take no input but for their links. Elements
// are kept by key and changed only where the description changed, so hover
// and focus survive the updates that arrive several times a second. An
// image draws a region of a picture, crisply scaled, once the picture is
// ready.

// The numbers src/snail/shell/app.sld sends: corners as `corner-index`, tones as
// `tone-index` and controls as `control-index` number them; places and
// widget kinds as `render-panel` and `render-widget` do, a corner's column
// being place 0 and a label kind 0.
const corners = ['top-left', 'top-right', 'bottom-left', 'bottom-right'];
const tones = ['plain', 'good', 'warning', 'danger', 'muted', 'suggested'];
const DIALOG = 1, BANNER = 2;
const BUTTON = 1, DIAL = 2, LINK = 3, TEXT = 4, IMAGE = 5;
const DISABLED = 1, SELECTED = 2;

function element(tag, className) {
  const node = document.createElement(tag);
  node.className = className;
  return node;
}

// ---- Widgets ----

// `hud` holds the HUD's press and hover handlers and the button under the
// pointer.
function createWidget(widget, hud) {
  if (widget.kind === IMAGE) {
    const node = element('canvas', 'image');
    node.dataset.kind = IMAGE;
    return node;
  }
  if (widget.kind === BUTTON) {
    const node = element('button', 'button');
    node.append(element('span', 'icon'), element('span', 'text'), element('span', 'caption'));
    node.addEventListener('click', () => hud.press(node.action, node.argument));
    node.addEventListener('pointerenter', () => { hud.hovered = node; hud.hover(node.action, node.argument); });
    node.addEventListener('pointerleave', () => { hud.hovered = null; hud.hover(0, 0); });
    return node;
  }
  if (widget.kind === LINK) {
    const node = element('a', 'link');
    node.target = '_blank';
    node.rel = 'noopener';
    node.append(element('span', 'icon'), element('span', 'text'));
    return node;
  }
  const node = element('div', widget.kind === DIAL ? 'dial' : 'label');
  node.append(element('span', 'icon'), element('span', 'text'));
  return node;
}

function setAttribute(node, name, value) {
  if (value === '' || value === null) { if (node.hasAttribute(name)) node.removeAttribute(name); }
  else if (node.getAttribute(name) !== value) node.setAttribute(name, value);
}

function setText(node, selector, text) {
  const part = node.querySelector(selector);
  if (part && part.textContent !== text) part.textContent = text;
}

// A text's spans, rebuilt only when they change.
function setSpans(node, spans) {
  const part = node.querySelector('.text'), shape = JSON.stringify(spans);
  if (part.dataset.spans === shape) return;
  part.dataset.spans = shape;
  part.replaceChildren(...spans.map(span => {
    const piece = document.createElement(span.strong ? 'strong' : 'span');
    piece.textContent = span.words;
    return piece;
  }));
}

// Draws the image's region at its scale, again whenever its picture is
// composed anew. The canvas keeps the last description it drew, and how to
// stop watching its picture: the picture store holds the drawing function,
// and with it the canvas, until `unwatch` runs, which `release` does once
// the image leaves the HUD.
function updateImage(node, widget, pictures) {
  const {key, x, y, width, height, scale} = widget.image;
  const description = `${key} ${x} ${y} ${width} ${height} ${scale}`;
  if (node.description === description) return;
  node.description = description;
  node.width = width * scale;
  node.height = height * scale;
  node.unwatch?.();
  const draw = picture => {
    const context = node.getContext('2d');
    context.imageSmoothingEnabled = false;
    context.clearRect(0, 0, node.width, node.height);
    context.drawImage(picture.canvas, x, y, width, height, 0, 0, node.width, node.height);
  };
  node.unwatch = pictures.watch(key, draw);
  const ready = pictures.get(key);
  if (ready) draw(ready);
}

function release(node) {
  node.unwatch?.();
}

function updateWidget(node, widget, pictures) {
  if (widget.kind === IMAGE) {
    setAttribute(node, 'data-key', widget.key);
    setAttribute(node, 'title', widget.help);
    updateImage(node, widget, pictures);
    return;
  }
  node.dataset.kind = widget.kind;
  setAttribute(node, 'data-key', widget.key);
  setAttribute(node, 'data-icon', widget.icon);
  setAttribute(node, 'data-badge', widget.badge);
  setAttribute(node, 'data-tone', tones[widget.tone]);
  setAttribute(node, 'title', widget.help);
  setAttribute(node, 'aria-label', widget.help ? `${widget.text} ${widget.help}`.trim() : '');
  if (widget.kind === TEXT) setSpans(node, widget.spans);
  else setText(node, '.text', widget.text);
  setText(node, '.caption', widget.caption);
  if (widget.kind === LINK) setAttribute(node, 'href', widget.url);
  if (widget.kind === BUTTON) {
    node.action = widget.action;
    node.argument = widget.argument;
    node.disabled = widget.control === DISABLED;
    setAttribute(node, 'aria-pressed', widget.control === SELECTED ? 'true' : '');
    setAttribute(node, 'data-ring', widget.value >= 0 ? 'true' : '');
  }
  const fraction = widget.kind === BUTTON || widget.kind === DIAL ? Math.max(0, Math.min(1, widget.value)) : 0;
  node.style.setProperty('--fraction', `${Math.round(fraction * 1000) / 10}%`);
}

// ---- Panels ----

// Keeps `parent`'s children equal to `wanted`, in order, moving only those
// out of place.
function arrange(parent, wanted) {
  wanted.forEach((child, index) => {
    if (parent.children[index] !== child) parent.insertBefore(child, parent.children[index] ?? null);
  });
  while (parent.children.length > wanted.length) parent.lastElementChild.remove();
}

// A widget is kept by its key, or else its place, while its kind stays;
// one that leaves is released.
function updatePanel(state, panel, hud) {
  setAttribute(state.node, 'data-key', panel.key);
  const seen = new Map();
  const nodes = panel.widgets.map((widget, index) => {
    const id = widget.key || `#${index}`;
    let node = state.widgets.get(id);
    if (!node || Number(node.dataset.kind) !== widget.kind) node = createWidget(widget, hud);
    updateWidget(node, widget, hud.pictures);
    seen.set(id, node);
    return node;
  });
  for (const [id, node] of state.widgets) if (seen.get(id) !== node) release(node);
  state.widgets = seen;
  arrange(state.node, nodes);
}

// The button under the pointer is the HUD's: one removed while hovered
// never reports leaving, so the HUD reports it after the update that
// removed it.
export function createHud(overlay, press, hover, pictures) {
  const hud = {press, hover, pictures, hovered: null};
  const cornerNodes = corners.map(name => {
    const node = element('div', `corner ${name}`);
    overlay.append(node);
    return node;
  });
  const banner = element('div', 'banner');
  overlay.append(banner);
  const dialogs = element('div', 'dialogs');
  const backdrop = element('div', 'backdrop');
  dialogs.append(backdrop);
  overlay.append(dialogs);
  let panels = new Map(), dismiss = 0;
  backdrop.addEventListener('click', () => press(dismiss, 0));

  const column = (corner, index) => {
    const parent = cornerNodes[corner];
    let node = [...parent.children].find(child => Number(child.dataset.column) === index);
    if (!node) {
      node = element('div', 'column');
      node.dataset.column = index;
      parent.insertBefore(node, [...parent.children].find(child => Number(child.dataset.column) > index) ?? null);
    }
    return node;
  };

  return {
    update(descriptions) {
      const next = new Map(), placed = new Map();
      for (const panel of descriptions) {
        const state = panels.get(panel.key) ?? {node: element('div', 'panel'), widgets: new Map()};
        updatePanel(state, panel, hud);
        next.set(panel.key, state);
        const parent = panel.place === DIALOG ? dialogs : panel.place === BANNER ? banner : column(panel.corner, panel.column);
        if (!placed.has(parent)) placed.set(parent, parent === dialogs ? [backdrop] : []);
        placed.get(parent).push(state.node);
        if (panel.place === DIALOG) dismiss = panel.dismiss;
      }
      for (const [key, state] of panels) if (next.get(key) !== state) state.widgets.forEach(release);
      for (const node of cornerNodes) for (const child of node.children) if (!placed.has(child)) placed.set(child, []);
      if (!placed.has(dialogs)) placed.set(dialogs, [backdrop]);
      if (!placed.has(banner)) placed.set(banner, []);
      for (const [parent, nodes] of placed) arrange(parent, nodes);
      dialogs.classList.toggle('open', placed.get(dialogs).length > 1);
      panels = next;
      if (hud.hovered && !hud.hovered.isConnected) { hud.hovered = null; setTimeout(() => hover(0, 0)); }
    },
  };
}
