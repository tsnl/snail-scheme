// A complete presentation is parsed before it reaches the DOM. Widget keys and
// endpoint identities survive normal redraws and compatible module replacement.
const validScalar = value => value >= 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff);
function textField(node, field, index, value) {
  if (field < 0 || field > 2) throw new Error('invalid UI text field');
  if (index === -1) {
    if (value < 0 || value > 32768) throw new Error('invalid UI text length');
    node.text[field] = {values: [], length: value}; return;
  }
  const text = node.text[field];
  if (!text || index !== text.values.length || index >= text.length || !validScalar(value))
    throw new Error('invalid UI text sequence');
  text.values.push(value);
}
function finishText(field) {
  if (!field) return '';
  if (field.values.length !== field.length) throw new Error('incomplete UI text');
  return String.fromCodePoint(...field.values);
}
function endpointAction(action, kind, manifest) {
  if (!action) throw new Error('interactive UI node requires an endpoint');
  const owner = action.owner === 1 ? 'match' : 'client';
  const endpoint = manifest?.applications.find(app => app.owner === owner)?.handlers[action.slot];
  if (!endpoint || ![1, 2].includes(action.owner) || (kind === 3 && endpoint.payload.length !== 1))
    throw new Error('invalid UI endpoint or number input payload');
  return {owner: action.owner, command: {handler: endpoint.id, args: action.args.slice(0, endpoint.payload.length)}};
}
function finishNode(node, keys, manifest) {
  const [key, text, help] = node.text.map(finishText);
  if (!key || keys.has(key)) throw new Error('UI widget keys must be nonempty and unique');
  keys.add(key);
  if (node.kind !== 5 && node.children.length) throw new Error('only UI groups contain children');
  const action = [2, 3].includes(node.kind) ? endpointAction(node.action, node.kind, manifest) : undefined;
  if (node.kind === 3 && node.properties[4] > node.properties[5]) throw new Error('invalid UI number range');
  return {key, kind: node.kind, rect: node.rect, text, help, properties: node.properties, action,
    children: node.children.map(child => finishNode(child, keys, manifest))};
}
export function createUiBridge(provider, transaction) {
  let width = 320, height = 720;
  function frame() {
    const tx = transaction();
    if (!tx?.readOnly) throw new Error('UI output requires a presentation query');
    return tx.ui ??= {stack: [], roots: [], count: 0};
  }
  function current() {
    const stack = frame().stack;
    if (!stack.length) throw new Error('UI property outside a node');
    return stack.at(-1);
  }
  const host = {
    viewport(axis) {
      if (!transaction()?.readOnly) throw new Error('UI viewport requires a presentation query');
      return axis === 0 ? width : height;
    },
    begin(kind, x, y, width, height) {
      const value = frame();
      if (kind < 1 || kind > 5 || width < 0 || height < 0 || ++value.count > 4096 || value.stack.length > 64)
        throw new Error('invalid UI node or presentation budget exceeded');
      const node = {kind, rect: [x, y, width, height], text: [undefined, undefined, undefined], properties: [], children: []};
      (value.stack.at(-1)?.children ?? value.roots).push(node); value.stack.push(node);
    },
    property(field, value) {
      if (field < 0 || field > 8) throw new Error('invalid UI property');
      current().properties[field] = value;
    },
    text: (field, index, value) => textField(current(), field, index, value),
    action: (owner, slot, a, b) => { current().action = {owner, slot, args: [a, b]}; },
    end() { if (!frame().stack.pop()) throw new Error('unbalanced UI node'); }
  };
  return {
    provider: provider(host, [['viewport', 1, true], ['begin', 5, false], ['property', 2, false],
      ['text', 3, false], ['action', 4, false], ['end', 0, false]]),
    resize(w, h) { width = Math.max(0, Math.min(16384, Math.floor(w))); height = Math.max(0, Math.min(16384, Math.floor(h))); },
    finish(tx, manifest) {
      if (!tx.ui) return undefined;
      if (tx.ui.stack.length || tx.ui.roots.length !== 1) throw new Error('UI requires one complete root');
      return finishNode(tx.ui.roots[0], new Set(), manifest);
    }
  };
}
