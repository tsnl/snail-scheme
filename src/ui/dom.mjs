// Semantic controls at Scheme-computed rectangles. No layout measurement flows
// back from a child. A stable key keeps its DOM node, focus, draft and scroll.
const setText = (element, value) => { if (element.textContent !== value) element.textContent = value; };
let nextField = 0;
function element(tag, className) {
  const value = document.createElement(tag); value.className = className; return value;
}
function bounds(element, [x, y, width, height]) {
  Object.assign(element.style, {left: `${x}px`, top: `${y}px`, width: `${width}px`, height: `${height}px`});
}
function retainedFocus(root) {
  const node = document.activeElement;
  return root.contains(node) ? {node, start: node.selectionStart, end: node.selectionEnd} : undefined;
}
function restoreFocus(focus) {
  if (!focus?.node.isConnected || document.activeElement === focus.node) return;
  focus.node.focus({preventScroll: true});
  if (typeof focus.start === 'number') focus.node.setSelectionRange(focus.start, focus.end);
}
export class DomUi {
  nodes = new Map();
  constructor(root, dispatch) { this.root = root; this.dispatch = dispatch; }
  render(tree) {
    const seen = new Set(), focus = retainedFocus(this.root);
    if (tree) this.patch(tree, this.root, 0, seen);
    for (const [key, element] of this.nodes) if (!seen.has(key)) { element.remove(); this.nodes.delete(key); }
    restoreFocus(focus);
  }
  patch(model, parent, index, seen) {
    let node = this.nodes.get(model.key);
    if (node && node.model.kind !== model.kind) { node.remove(); this.nodes.delete(model.key); node = undefined; }
    if (!node) { node = this.create(model.kind); this.nodes.set(model.key, node); }
    node.model = model; node.dataset.uiKey = model.key; seen.add(model.key); bounds(node, model.rect);
    if (parent.children[index] !== node) parent.insertBefore(node, parent.children[index] ?? null);
    this.update(node, model);
    model.children.forEach((child, index) => this.patch(child, node.content, index, seen));
  }
  create(kind) {
    if (kind === 2) return this.button();
    if (kind === 3) return this.number();
    const node = element('div', `snail-ui-node snail-ui-kind-${kind}`);
    if (kind === 5) { node.content = element('div', 'snail-ui-content'); node.append(node.content); }
    if (kind === 4) { node.label = element('span', 'snail-ui-meter-label'); node.bar = element('meter', 'snail-ui-meter'); node.append(node.label, node.bar); }
    return node;
  }
  button() {
    const node = element('button', 'snail-ui-node snail-ui-button'); node.type = 'button';
    node.label = element('span', 'snail-ui-button-label'); node.detail = element('span', 'snail-ui-button-detail');
    node.append(node.label, node.detail);
    node.addEventListener('click', () => this.dispatch(node.model.action));
    return node;
  }
  number() {
    const node = element('form', 'snail-ui-node snail-ui-number');
    node.dataset.uiForm = ''; node.revision = 0;
    node.label = element('label', 'snail-ui-number-label'); node.input = element('input', 'snail-ui-number-input');
    node.input.type = 'text'; node.input.inputMode = 'numeric'; node.label.append(node.input);
    node.submit = element('button', 'snail-ui-number-submit'); node.submit.type = 'submit'; node.submit.textContent = 'Apply';
    node.error = element('span', 'snail-ui-number-error'); node.error.setAttribute('role', 'status');
    node.error.id = `snail-ui-error-${++nextField}`; node.input.setAttribute('aria-describedby', node.error.id);
    node.append(node.label, node.submit, node.error);
    node.addEventListener('input', () => { node.draft = true; node.revision++; this.clearError(node); });
    node.addEventListener('submit', event => { event.preventDefault(); this.submitNumber(node); });
    return node;
  }
  clearError(node) { node.error.textContent = ''; node.input.removeAttribute('aria-invalid'); }
  submitNumber(node) {
    const revision = ++node.revision; node.draft = true;
    const text = node.input.value.trim(), value = Number(text), properties = node.model.properties;
    if (!/^[+-]?\d+$/.test(text) || !Number.isInteger(value) || value < properties[4] || value > properties[5]) {
      node.error.textContent = `Enter a whole number from ${properties[4]} to ${properties[5]}.`;
      node.input.setAttribute('aria-invalid', 'true'); node.input.focus(); return;
    }
    this.clearError(node);
    const action = {...node.model.action, command: {...node.model.action.command, args: [value]}};
    Promise.resolve(this.dispatch(action)).then(committed => {
      if (committed && revision === node.revision) node.draft = false;
    });
  }
  update(node, model) {
    const p = model.properties; node.dataset.tone = p[0] ?? 0;
    if (model.kind === 1) setText(node, model.text);
    if (model.kind === 2) this.updateButton(node, model);
    if (model.kind === 3) this.updateNumber(node, model);
    if (model.kind === 4) {
      setText(node.label, model.text); node.bar.max = p[5]; node.bar.value = Math.max(0, Math.min(p[5], p[3]));
      node.bar.setAttribute('aria-label', model.text);
    }
    if (model.kind === 5) this.updateGroup(node, model);
  }
  updateButton(node, model) {
    setText(node.label, model.text); setText(node.detail, model.help);
    node.disabled = model.properties[1] !== 1; node.title = model.help;
    node.setAttribute('aria-pressed', model.properties[2] === 1 ? 'true' : 'false');
    node.setAttribute('aria-description', model.help);
  }
  updateNumber(node, model) {
    node.input.setAttribute('aria-label', model.text); node.input.title = model.help;
    node.input.placeholder = model.text;
    const value = String(model.properties[3]);
    if (!node.draft && node.input.value !== value) node.input.value = value;
    node.submit.setAttribute('aria-label', `Apply ${model.text}`);
  }
  updateGroup(node, model) {
    const padding = model.properties[6], extent = model.properties[8];
    node.dataset.panel = model.properties[7]; node.style.overflow = extent > 0 ? 'auto' : 'hidden';
    bounds(node.content, [padding, padding, Math.max(0, model.rect[2] - 2 * padding),
      Math.max(0, Math.max(extent, model.rect[3]) - 2 * padding)]);
  }
}
