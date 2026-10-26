// The editor area: a binary tree of panes. A node is either a leaf, which
// holds one editor, or a split, which lays two nodes side by side (`row`) or
// one above the other (`column`), the first taking `ratio` of the room.
// One leaf is active: files open there, and splitting or closing acts on it.

export function createPanes(container, makeEditor) {
  const first = {editor: makeEditor()};
  const panes = {root: first, active: first};
  Object.assign(panes, {
    // The active pane splits in two, the new half showing the same buffer.
    split(direction) {
      const leaf = {editor: makeEditor()};
      leaf.editor.show(panes.active.editor.buffer);
      replace(panes, panes.active, {direction, ratio: 0.5, first: panes.active, second: leaf});
      activate(panes, leaf);
      render(container, panes);
      leaf.editor.focus();
    },
    // The active pane closes, and its sibling takes the split's place; the
    // last pane stays.
    close() {
      const parent = parentOf(panes.root, panes.active);
      if (!parent) return;
      const sibling = parent.first === panes.active ? parent.second : parent.first;
      replace(panes, parent, sibling);
      activate(panes, firstLeaf(sibling));
      render(container, panes);
      panes.active.editor.focus();
    },
    activateEditor(editor) { activate(panes, leaves(panes.root).find(leaf => leaf.editor === editor)); },
    editors() { return leaves(panes.root).map(leaf => leaf.editor); },
  });
  activate(panes, first);
  render(container, panes);
  return panes;
}

function activate(panes, leaf) {
  for (const each of leaves(panes.root)) each.editor.setActive(each === leaf);
  panes.active = leaf;
}

function replace(panes, node, replacement) {
  const parent = parentOf(panes.root, node);
  if (!parent) panes.root = replacement;
  else if (parent.first === node) parent.first = replacement;
  else parent.second = replacement;
}

function parentOf(root, node) {
  if (root.editor) return null;
  if (root.first === node || root.second === node) return root;
  return parentOf(root.first, node) ?? parentOf(root.second, node);
}

function leaves(node) {
  return node.editor ? [node] : [...leaves(node.first), ...leaves(node.second)];
}

function firstLeaf(node) {
  return node.editor ? node : firstLeaf(node.first);
}

// ---- Layout ----

function render(container, panes) {
  container.replaceChildren(nodeElement(panes.root));
}

function nodeElement(node) {
  if (node.editor) return node.editor.element;
  const element = document.createElement('div'), divider = document.createElement('div');
  element.className = `split ${node.direction}`;
  divider.className = 'divider';
  const first = nodeElement(node.first), second = nodeElement(node.second);
  setShares(node, first, second);
  divider.addEventListener('pointerdown', event => dragDivider(event, node, element, first, second));
  element.append(first, divider, second);
  return element;
}

function setShares(node, first, second) {
  first.style.flex = `${node.ratio} 1 0`;
  second.style.flex = `${1 - node.ratio} 1 0`;
}

// Dragging a divider moves the split's ratio, keeping each side at least a
// tenth of the room.
function dragDivider(event, node, element, first, second) {
  event.preventDefault();
  const box = element.getBoundingClientRect(), row = node.direction === 'row';
  const move = ({clientX, clientY}) => {
    const fraction = row ? (clientX - box.left) / box.width : (clientY - box.top) / box.height;
    node.ratio = Math.min(0.9, Math.max(0.1, fraction));
    setShares(node, first, second);
  };
  const stop = () => { removeEventListener('pointermove', move); removeEventListener('pointerup', stop); };
  addEventListener('pointermove', move);
  addEventListener('pointerup', stop);
}
