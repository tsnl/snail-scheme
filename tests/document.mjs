// A document for host/browser/dom.mjs on Node, with just what a HUD needs:
// elements with attributes, properties, children and listeners, and text
// nodes. Import it before the host, which reads the globals it sets.
class TestNode {
  constructor(type, name, data = '') {
    Object.assign(this, {nodeType: type, tagName: name, data, childNodes: [], parentNode: null,
                         attributes: new Map(), listeners: []});
  }
  setAttribute(name, value) { this.attributes.set(name, value); }
  removeAttribute(name) { this.attributes.delete(name); }
  getAttribute(name) { return this.attributes.get(name) ?? null; }
  insertBefore(child, before) {
    child.remove();
    child.parentNode = this;
    this.childNodes.splice(before ? this.childNodes.indexOf(before) : this.childNodes.length, 0, child);
  }
  remove() {
    const siblings = this.parentNode?.childNodes;
    if (siblings) siblings.splice(siblings.indexOf(this), 1);
    this.parentNode = null;
  }
  replaceChildren() { for (const child of [...this.childNodes]) child.remove(); }
  addEventListener(type, handler) { this.listeners.push({type, handler}); }
  removeEventListener(type, handler) {
    this.listeners = this.listeners.filter(listener => listener.type !== type || listener.handler !== handler);
  }
  get textContent() { return this.nodeType === TestNode.TEXT_NODE ? this.data : this.childNodes.map(child => child.textContent).join(''); }
  set textContent(text) { this.replaceChildren(); if (text !== '') this.insertBefore(new TestNode(TestNode.TEXT_NODE, '#text', text), null); }
  focus() {}
}
TestNode.TEXT_NODE = 3;

globalThis.Node = TestNode;
globalThis.window = new TestNode(0, '#window');
globalThis.addEventListener ??= () => {};
globalThis.document = {
  createElement: name => new TestNode(1, name),
  createTextNode: text => new TestNode(TestNode.TEXT_NODE, '#text', text),
};

// A page's overlay, and what a test asks of the HUD in it: the widget with
// a key, a widget's text or one of its parts', and a user's event on it.
export function createOverlay() {
  return new TestNode(1, 'div');
}

export function widget(node, key) {
  if (node.getAttribute?.('data-key') === key && node.getAttribute('class') !== 'panel') return node;
  for (const child of node.childNodes) {
    const found = widget(child, key);
    if (found) return found;
  }
  return null;
}

export const part = (node, name) => node?.childNodes.find(child => child.getAttribute?.('class') === name);
export const text = node => part(node, 'text')?.textContent;

export function fire(node, type) {
  for (const listener of [...node.listeners]) if (listener.type === type) listener.handler({target: node});
}
