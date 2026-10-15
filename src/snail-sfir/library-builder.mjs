// An invocation owns immutable syntax nodes. Wasm sees tagged scalar handles;
// a completed transfer owns copied data, never the producer's heap or arena.
import {instantiate, invokeEntry, closeInstance} from './execute.mjs';

const transfers = new WeakMap();
const scalarNames = ['I32', 'I64', 'F32', 'F64', 'Bool', 'Char', 'Unit'];
const handleWidth = 1n << 32n;
let nextInvocation = 1n;

// ---- Invocation-owned immutable nodes ----

function invocationOrigin() {
  if (nextInvocation >= 1n << 31n) throw new RangeError('library builder invocation IDs exhausted');
  return nextInvocation++;
}

function scalar(value) {
  if (!Number.isInteger(value) || value < 0 || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff))
    throw new TypeError('expected a Unicode scalar');
  return value;
}

function floatingText(value) {
  if (Object.is(value, -0)) return '-0.0';
  if (Number.isNaN(value)) return '+nan.0';
  if (!Number.isFinite(value)) return value < 0 ? '-inf.0' : '+inf.0';
  const spelling = String(value);
  return /[.e]/i.test(spelling) ? spelling : `${spelling}.0`;
}

class Arena {
  origin = invocationOrigin();
  nodes = [];
  completed = new Map();

  checkOpen() {
    if (!this.nodes) throw new Error('library builder invocation is closed');
  }

  get(handle, kinds) {
    this.checkOpen();
    if (typeof handle !== 'bigint' || handle / handleWidth !== this.origin)
      throw new TypeError('foreign library builder invocation handle');
    const node = this.nodes[Number(handle % handleWidth)];
    if (!node || (kinds && !kinds.includes(node[0]))) throw new TypeError('invalid library builder handle kind');
    return node;
  }

  put(kind, fields, references = []) {
    this.checkOpen();
    if (this.nodes.length >= 0xffffffff) throw new RangeError('library builder node IDs exhausted');
    const id = this.nodes.length;
    this.nodes.push(Object.freeze([kind, ...fields]));
    // Reference positions distinguish identity edges from literal integers.
    this.edges.push(references);
    return this.origin * handleWidth + BigInt(id);
  }

  edges = [];

  node(kind, fields, expected) {
    expected.forEach(([index, kinds]) => this.get(fields[index], kinds));
    return this.put(kind, fields, expected.map(([index]) => index + 1));
  }

  sequence(handle, kinds) {
    const values = [];
    for (let node = this.get(handle, ['nil', 'cons']); node[0] === 'cons'; node = this.get(node[2], ['nil', 'cons'])) {
      this.get(node[1], kinds);
      values.push(node[1]);
    }
    return values;
  }

  finish(handle) {
    this.get(handle, ['library']);
    if (this.completed.has(handle)) return this.completed.get(handle);
    const packet = this.materialize(handle), transfer = Object.freeze({});
    transfers.set(transfer, JSON.stringify(packet));
    this.completed.set(handle, transfer);
    return transfer;
  }

  materialize(root) {
    const nodes = [], copied = new Map();
    const copy = handle => {
      if (copied.has(handle)) return copied.get(handle);
      const source = this.get(handle), id = nodes.length, node = [...source];
      copied.set(handle, id); nodes.push(node);
      for (const index of this.edges[Number(handle % handleWidth)]) node[index] = copy(node[index]);
      return id;
    };
    return {version: 1, root: copy(root), nodes};
  }

  close() {
    this.nodes = undefined;
    this.edges = undefined;
    this.completed.clear();
  }
}

// ---- A fixed scalar constructor protocol ----

const typeKinds = ['scalar-type', 'function-type'];
const referenceKinds = ['local-reference', 'import-reference'];
const expressionKinds = ['literal', 'reference', 'lambda', 'application', 'conditional'];
const selectionKinds = ['all', 'only', 'rename'];
const sequenceKinds = ['nil', 'cons'];

function constructors(arena) {
  const functions = [];
  const add = (name, parameters, implementation) => functions.push({name, parameters, implementation});
  const node = (kind, fields, expected) => arena.node(kind, fields, expected);
  const sequence = (value, kinds) => arena.sequence(value, kinds);
  add('name-empty', [], () => arena.put('name', ['']));
  add('name-character', ['i64', 'i32'], (name, char) =>
    arena.put('name', [arena.get(name, ['name'])[1] + String.fromCodePoint(scalar(char))]));
  add('span', ['i64', 'i32', 'i32'], (name, line, column) => {
    if (line < 1 || column < 1) throw new TypeError('source locations are one-based');
    return node('span', [name, line, column], [[0, ['name']]]);
  });
  add('root-scope', [], () => arena.put('scope', []));
  add('child-scope', ['i64'], parent => node('child-scope', [parent], [[0, ['scope', 'child-scope']]]));
  add('binding', ['i64', 'i64', 'i64'], (scope, name, span) =>
    node('binding', [scope, name, span], [[0, ['scope', 'child-scope']], [1, ['name']], [2, ['span']]]));
  add('nil', [], () => arena.put('nil', []));
  add('cons', ['i64', 'i64'], (head, tail) => node('cons', [head, tail], [[0], [1, sequenceKinds]]));
  add('scalar-type', ['i32'], index => {
    if (!scalarNames[index]) throw new TypeError('unsupported scalar type');
    return arena.put('scalar-type', [scalarNames[index]]);
  });
  add('function-type', ['i64', 'i64'], (parameters, result) => {
    sequence(parameters, typeKinds);
    return node('function-type', [parameters, result], [[0, sequenceKinds], [1, typeKinds]]);
  });
  add('local-reference', ['i64', 'i64'], (binding, span) =>
    node('local-reference', [binding, span], [[0, ['binding']], [1, ['span']]]));
  add('import-reference', ['i64', 'i64', 'i64'], (scope, name, span) =>
    node('import-reference', [scope, name, span], [[0, ['scope']], [1, ['name']], [2, ['span']]]));
  add('reference', ['i64'], reference => node('reference', [reference], [[0, referenceKinds]]));
  for (const [type, physical] of [['I32', 'i32'], ['I64', 'i64'], ['F32', 'f32'], ['F64', 'f64'], ['Bool', 'i32'], ['Char', 'i32']])
    add(`literal-${type}`, [physical, 'i64'], (value, span) => {
      if (type === 'Bool' && value !== 0 && value !== 1) throw new TypeError('Bool literal must be canonical');
      if (type === 'Char') scalar(value);
      const spelling = physical.startsWith('f') ? floatingText(value) : String(value);
      return node('literal', [type, spelling, span], [[2, ['span']]]);
    });
  add('lambda', ['i64', 'i64', 'i64', 'i64'], (scope, parameters, body, span) => {
    sequence(parameters, ['binding']);
    return node('lambda', [scope, parameters, body, span],
      [[0, ['child-scope']], [1, sequenceKinds], [2, expressionKinds], [3, ['span']]]);
  });
  add('application', ['i64', 'i64', 'i64'], (operator, arguments_, span) => {
    sequence(arguments_, expressionKinds);
    return node('application', [operator, arguments_, span], [[0, expressionKinds], [1, sequenceKinds], [2, ['span']]]);
  });
  add('conditional', ['i64', 'i64', 'i64', 'i64'], (test, yes, no, span) =>
    node('conditional', [test, yes, no, span], [[0, expressionKinds], [1, expressionKinds], [2, expressionKinds], [3, ['span']]]));
  add('definition', ['i64', 'i64', 'i64', 'i64'], (binding, type, expression, span) =>
    node('definition', [binding, type, expression, span], [[0, ['binding']], [1, typeKinds], [2, expressionKinds], [3, ['span']]]));
  add('all', [], () => arena.put('all', []));
  add('only', ['i64', 'i64'], (selection, names) => {
    sequence(names, ['name']);
    return node('only', [selection, names], [[0, selectionKinds], [1, sequenceKinds]]);
  });
  add('rename-pair', ['i64', 'i64'], (from, to) => node('rename-pair', [from, to], [[0, ['name']], [1, ['name']]]));
  add('rename', ['i64', 'i64'], (selection, names) => {
    sequence(names, ['rename-pair']);
    return node('rename', [selection, names], [[0, selectionKinds], [1, sequenceKinds]]);
  });
  add('import', ['i64', 'i64', 'i64', 'i64'], (key, selection, scope, span) => {
    if (!sequence(key, ['name']).length) throw new TypeError('library key must not be empty');
    return node('import', [key, selection, scope, span], [[0, sequenceKinds], [1, selectionKinds], [2, ['scope']], [3, ['span']]]);
  });
  add('export', ['i64', 'i64'], (name, reference) => node('export', [name, reference], [[0, ['name']], [1, referenceKinds]]));
  add('library', Array(6).fill('i64'), (key, scope, imports, exports, declarations, span) => {
    if (!sequence(key, ['name']).length) throw new TypeError('library key must not be empty');
    sequence(imports, ['import']); sequence(exports, ['export']); sequence(declarations, ['definition']);
    return node('library', [key, scope, imports, exports, declarations, span],
      [[0, sequenceKinds], [1, ['scope']], [2, sequenceKinds], [3, sequenceKinds], [4, sequenceKinds], [5, ['span']]]);
  });
  return functions;
}

// ---- Typed Wasm provider, with no raw managed references ----

function unsigned(value) {
  const bytes = [];
  do { const rest = Math.floor(value / 128); bytes.push(value % 128 + (rest ? 128 : 0)); value = rest; } while (value);
  return bytes;
}

function wasmText(value) {
  const bytes = new TextEncoder().encode(value);
  return [...unsigned(bytes.length), ...bytes];
}

function section(id, bytes) {
  return [id, ...unsigned(bytes.length), ...bytes];
}

function typedProvider(functions) {
  const types = {i32: 0x7f, i64: 0x7e, f32: 0x7d, f64: 0x7c};
  const signatures = functions.flatMap(({parameters}) => [0x60, ...unsigned(parameters.length),
    ...parameters.map(type => types[type]), 1, types.i64]);
  const imports = functions.flatMap(({name}, index) => [...wasmText('builder'), ...wasmText(name), 0, ...unsigned(index)]);
  const exports = functions.flatMap(({name}, index) => [...wasmText(name), 0, ...unsigned(index)]);
  const bytes = [0, 97, 115, 109, 1, 0, 0, 0, ...section(1, [...unsigned(functions.length), ...signatures]),
    ...section(2, [...unsigned(functions.length), ...imports]), ...section(7, [...unsigned(functions.length), ...exports])];
  return new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from(bytes)),
    {builder: Object.fromEntries(functions.map(({name, implementation}) => [name, implementation]))});
}

export function openLibraryBuilder() {
  const arena = new Arena(), provider = typedProvider(constructors(arena));
  return Object.freeze({provider, finish: handle => arena.finish(handle), close: () => arena.close()});
}

export function libraryTransferJSON(transfer) {
  if (!transfers.has(transfer)) throw new TypeError('expected an owned library transfer');
  return transfers.get(transfer);
}

export function invokeLibraryGenerator(code, providers = new Map(), arguments_ = []) {
  if (code?.result !== 'I64') throw new TypeError('library generator ABI must return an I64 transfer token');
  if (!(providers instanceof Map) || providers.has('sfir.builder')) throw new TypeError('builder provider must be invocation-owned');
  const bindings = new Map(providers), builder = openLibraryBuilder();
  let instance;
  try {
    bindings.set('sfir.builder', builder.provider);
    instance = instantiate(code, bindings);
    return builder.finish(invokeEntry(instance, arguments_));
  } finally {
    if (instance) closeInstance(instance);
    builder.close();
  }
}
