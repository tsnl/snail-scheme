// The page's document for the `dom` effect of src/snail/shell/dom.sld, as
// `with-page-dom` in src/snail/shell/dom/page.sld calls it. The interface
// owns the container, handle 0; every node it makes is a handle in `nodes`,
// and every listener an id in `listeners`. Removing a node frees its
// handle, those of the nodes under it, and their listeners, so the tables
// hold only what the document still shows.

import {byteSnapshot} from './load.mjs';

// The kinds of event an interface is fired, after the host's own 11 to 13
// (runtime.mjs), and the bits of `capture-bits` and the modifier keys.
export const FIRED = 14, WAKE = 15;
const VALUE = 1, KEY = 2, POINTER = 4, SCROLL = 8, SELECTION = 16, CHECKED = 32;
const CONTROL = 1, SHIFT = 2, ALT = 4, META = 8;
const ALWAYS = 1, CHORDS = 2;

// The runtime gives the running program's memory, to read a string argument
// from staging, and the event it last polled, whose numbers and texts the
// program reads beside its fields.
export function createDom(container, runtime) {
  const decoder = new TextDecoder();
  let nodes, handles, listeners, owned, next, nextListener, reply = [];
  reset();

  // A program that starts, cold or after a reload, knows no handles, so the
  // container and the tables start over with it.
  function reset() {
    for (const listener of listeners?.values() ?? []) listener.node.removeEventListener(listener.type, listener.handler);
    container.replaceChildren();
    nodes = new Map([[0, container]]);
    handles = new WeakMap([[container, 0]]);
    listeners = new Map();
    owned = new WeakMap();
    next = 1;
    nextListener = 1;
  }
  const text = address => decoder.decode(byteSnapshot(runtime.execution.entry.memory, address));
  // A name and its value cross as one string, the name ended by a NUL.
  function named(address) {
    const string = text(address), end = string.indexOf('\0');
    return [string.slice(0, end), string.slice(end + 1)];
  }
  function node(handle) {
    const found = nodes.get(handle);
    if (!found) throw new Error(`no node has the handle ${handle}`);
    return found;
  }
  function made(value) {
    nodes.set(next, value);
    handles.set(value, next);
    return next++;
  }
  function free(value) {
    for (const child of value.childNodes) free(child);
    const handle = handles.get(value);
    if (handle === undefined) return;
    nodes.delete(handle);
    handles.delete(value);
    for (const [id, listener] of owned.get(value) ?? []) {
      value.removeEventListener(listener.type, listener.handler);
      listeners.delete(id);
    }
  }
  // A string answered a scalar at a time, until the next one.
  function answer(value) {
    reply = typeof value === 'string' ? [...value] : [];
    return reply.length;
  }

  // ---- Listeners ----

  const modifiers = event => (event.ctrlKey ? CONTROL : 0) | (event.shiftKey ? SHIFT : 0) |
    (event.altKey ? ALT : 0) | (event.metaKey ? META : 0);

  // What the event carried as it was dispatched, since the program reads it
  // later: the fields `fired-event` reads, in its order.
  function captured(id, bits, event) {
    const target = event.target;
    const has = bit => (bits & bit) !== 0;
    return [FIRED, id, has(KEY) || has(POINTER) ? modifiers(event) : 0, has(POINTER) ? event.buttons : 0,
      has(SELECTION) ? target.selectionStart ?? 0 : 0, has(SELECTION) ? target.selectionEnd ?? 0 : 0,
      has(CHECKED) && target.checked ? 1 : 0,
      has(POINTER) ? event.clientX : 0, has(POINTER) ? event.clientY : 0,
      has(SCROLL) ? target.scrollTop : 0, has(SCROLL) ? target.scrollLeft : 0,
      has(VALUE) ? String(target.value ?? '') : '', has(KEY) ? event.key ?? '' : ''];
  }
  function prevents(listener, event) {
    if (listener.prevent === ALWAYS) return true;
    if (listener.prevent !== CHORDS) return false;
    return listener.chords.some(([key, held]) => key === event.key && held === modifiers(event));
  }
  function listen(handle, bits, prevent, type) {
    const target = node(handle), id = nextListener++;
    const listener = {node: target, type, prevent, chords: [], handler: null};
    listener.handler = event => {
      if (prevents(listener, event)) event.preventDefault();
      runtime.send(...captured(id, bits, event));
    };
    target.addEventListener(type, listener.handler);
    if (!owned.has(target)) owned.set(target, new Map());
    owned.get(target).set(id, listener);
    listeners.set(id, listener);
    return id;
  }

  // ---- Imports ----

  // A property is set only when it differs, so setting an input's value to
  // what the user typed leaves the caret where it is.
  const imports = {
    root: () => 0,
    'create-element': address => made(document.createElement(text(address))),
    'create-text': address => made(document.createTextNode(text(address))),
    'set-attribute'(handle, address) {
      const [name, value] = named(address);
      if (value === '') node(handle).removeAttribute(name);
      else node(handle).setAttribute(name, value);
    },
    'set-text'(handle, address) {
      const target = node(handle);
      if (target.nodeType === Node.TEXT_NODE) { target.data = text(address); return; }
      for (const child of target.childNodes) free(child);
      target.textContent = text(address);
    },
    'set-string-property'(handle, address) {
      const [name, value] = named(address), target = node(handle);
      if (target[name] !== value) target[name] = value;
    },
    'set-number-property'(handle, value, address) {
      const name = text(address), target = node(handle);
      if (target[name] !== value) target[name] = value;
    },
    'set-flag-property'(handle, value, address) {
      const name = text(address), target = node(handle);
      if (target[name] !== (value !== 0)) target[name] = value !== 0;
    },
    'string-property': (handle, address) => answer(node(handle)[text(address)]),
    'number-property'(handle, address) {
      const value = node(handle)[text(address)];
      return typeof value === 'number' ? value : 0;
    },
    'reply-scalar': index => reply[index].codePointAt(0),
    insert: (parent, child, before) => { node(parent).insertBefore(node(child), before < 0 ? null : node(before)); },
    remove(handle) {
      const target = node(handle);
      target.remove();
      free(target);
    },
    listen: (handle, bits, prevent, address) => listen(handle, bits, prevent, text(address)),
    'listen-chord': (id, held, address) => { listeners.get(id).chords.push([text(address), held]); },
    unlisten(id) {
      const listener = listeners.get(id);
      listener.node.removeEventListener(listener.type, listener.handler);
      owned.get(listener.node).delete(id);
      listeners.delete(id);
    },
    focus: handle => { node(handle).focus(); },
    // Any task may wake the interface; the queue takes the wake from any.
    wake: () => { runtime.send(WAKE); },
    'event-number': index => runtime.execution.event[7 + index],
    'event-text': index => answer(runtime.execution.event[11 + index]),
  };
  return {imports, reset};
}
