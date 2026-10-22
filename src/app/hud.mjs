// The HUD: panels of labels, buttons, dials and images, stacked in columns
// in the screen's corners or shown as dialogs over a backdrop. Elements are
// kept by key and changed only where the description changed, so hover and
// focus survive the updates that arrive several times a second. An image
// draws a region of a picture, crisply scaled, once the picture is ready.

const corners = ['top-left', 'top-right', 'bottom-left', 'bottom-right'];
const tones = ['plain', 'good', 'warning', 'danger', 'muted'];
const LABEL = 0, BUTTON = 1, DIAL = 2, IMAGE = 3;
const DISABLED = 1, SELECTED = 2;

// The button under the pointer. One removed while hovered never reports
// leaving, so the HUD reports it after the update that removed it.
let hovered = null;

function element(tag, className) {
  const node = document.createElement(tag);
  node.className = className;
  return node;
}

// ---- Widgets ----

function createWidget(widget, press, hover) {
  if (widget.kind === IMAGE) {
    const node = element('canvas', 'image');
    node.dataset.kind = IMAGE;
    return node;
  }
  if (widget.kind === BUTTON) {
    const node = element('button', 'button');
    node.append(element('span', 'icon'), element('span', 'text'), element('span', 'caption'));
    node.addEventListener('click', () => press(node.action, node.argument));
    node.addEventListener('pointerenter', () => { hovered = node; hover(node.action, node.argument); });
    node.addEventListener('pointerleave', () => { hovered = null; hover(0, 0); });
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

// Draws the image's region at its scale, again whenever its picture is
// composed anew. The canvas keeps the last description it drew.
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
  setText(node, '.text', widget.text);
  setText(node, '.caption', widget.caption);
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

function updatePanel(state, panel, press, hover, pictures) {
  setAttribute(state.node, 'data-key', panel.key);
  const seen = new Map();
  const nodes = panel.widgets.map((widget, index) => {
    const id = widget.key || `#${index}`;
    let node = state.widgets.get(id);
    if (!node || Number(node.dataset.kind) !== widget.kind) node = createWidget(widget, press, hover);
    updateWidget(node, widget, pictures);
    seen.set(id, node);
    return node;
  });
  state.widgets = seen;
  arrange(state.node, nodes);
}

export function createHud(overlay, press, hover, pictures) {
  const cornerNodes = corners.map(name => {
    const node = element('div', `corner ${name}`);
    overlay.append(node);
    return node;
  });
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
        updatePanel(state, panel, press, hover, pictures);
        next.set(panel.key, state);
        const parent = panel.place === 1 ? dialogs : column(panel.corner, panel.column);
        if (!placed.has(parent)) placed.set(parent, parent === dialogs ? [backdrop] : []);
        placed.get(parent).push(state.node);
        if (panel.place === 1) dismiss = panel.dismiss;
      }
      for (const node of cornerNodes) for (const child of node.children) if (!placed.has(child)) placed.set(child, []);
      if (!placed.has(dialogs)) placed.set(dialogs, [backdrop]);
      for (const [parent, nodes] of placed) arrange(parent, nodes);
      dialogs.classList.toggle('open', placed.get(dialogs).length > 1);
      panels = next;
      if (hovered && !hovered.isConnected) { hovered = null; setTimeout(() => hover(0, 0)); }
    },
  };
}
