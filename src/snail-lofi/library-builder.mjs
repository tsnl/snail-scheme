// An invocation owns immutable syntax nodes. Wasm sees tagged scalar handles;
// a completed transfer owns copied data, never the producer's heap or arena.
import {instantiate, invokeEntry, closeInstance} from './execute.mjs';

const transfers = new WeakMap();
const scalarNames = ['I32', 'I64', 'F32', 'F64', 'Bool', 'Char', 'Unit', 'String', 'Bytevector', 'Never', 'Any'];
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

const typeKinds = ['scalar-type', 'function-type', 'rest-function-type', 'reference-type', 'list-type',
  'vector-type', 'nominal-type', 'variable-type', 'rest-type'];
const signatureKinds = [...typeKinds, 'all-signature'];
const referenceKinds = ['local-reference', 'import-reference'];
const expressionKinds = ['literal', 'reference', 'lambda', 'application', 'conditional', 'string-literal',
  'bytevector-literal', 'rest-lambda', 'block', 'annotation', 'instantiation', 'match', 'number-literal'];
const staticKinds = ['datatype', 'typeclass', 'instance'];
const declarationKinds = ['definition', 'inferred-definition', 'local-binding', 'inferred-local-binding',
  'expression-statement', 'extern', 'overload', ...staticKinds, 'kind-annotation'];
const kindKinds = ['kind-type', 'kind-constraint', 'kind-function', 'kind-evidence'];
const selectionKinds = ['all', 'only', 'rename'];
const sequenceKinds = ['nil', 'cons'];

// Each row is one syntax constructor. A sequence descriptor checks its
// elements now; the receiver separately establishes lexical ownership.
const syntaxForms = [
  ['variable-id', ['scope-id', 'name', 'span']],
  ['variable-type', ['variable-id']],
  ['reference-type', ['type']], ['list-type', ['type']], ['vector-type', ['type']],
  ['rest-function-type', ['types', 'type', 'type']],
  ['nominal-type', ['binding-reference', 'types']],
  ['constraint', ['binding-reference', 'types', 'span']],
  ['all-signature', ['child-scope', 'variables', 'constraints', 'type', 'span']],
  ['kind-type', []], ['kind-constraint', []], ['kind-function', ['kinds', 'kind']],
  ['kind-evidence', ['constraint']],
  ['string-literal', ['name', 'span']], ['bytevector-literal', ['bytes', 'span']],
  ['rest-lambda', ['child-scope', 'bindings', 'binding', 'expression', 'span']],
  ['block', ['child-scope', 'declarations', 'expression', 'span']],
  ['annotation', ['expression', 'type', 'span']],
  ['instantiation', ['binding-reference', 'types', 'span']],
  ['match-arm', ['binding-reference', 'child-scope', 'bindings', 'expression', 'span']],
  ['match', ['expression', 'arms', 'span']],
  ['inferred-definition', ['binding', 'expression', 'span']],
  ['local-binding', ['binding', 'signature', 'expression', 'span']],
  ['inferred-local-binding', ['binding', 'expression', 'span']],
  ['expression-statement', ['expression']],
  ['data-field', ['name', 'type', 'span']],
  ['accessor-field', ['name', 'type', 'binding', 'span']],
  ['data-case', ['binding', 'fields', 'span']],
  ['datatype', ['binding', 'child-scope', 'variables', 'cases', 'span']],
  ['class-method', ['binding', 'type', 'span']],
  ['typeclass', ['binding', 'child-scope', 'variables', 'methods', 'span']],
  ['method-implementation', ['binding-reference', 'expression', 'span']],
  ['instance', ['binding', 'constraint', 'implementations', 'span']],
  ['kind-annotation', ['kind', 'static-declaration', 'span']],
  ['extern', ['binding', 'name', 'name', 'type', 'span']],
  ['overload', ['binding', 'signature', 'expression', 'span']],
  ['number-literal', ['name', 'span']], ['rest-type', ['type']],
];
const categories = {
  'scope-id': ['scope', 'child-scope'], type: typeKinds, signature: signatureKinds,
  'binding-reference': referenceKinds, expression: expressionKinds, declaration: declarationKinds,
  kind: kindKinds, 'static-declaration': staticKinds, 'data-field': ['data-field', 'accessor-field'],
};
const sequences = {
  types: 'type', variables: 'variable-id', constraints: 'constraint', kinds: 'kind', bytes: 'byte',
  bindings: 'binding', declarations: 'declaration', arms: 'match-arm', fields: 'data-field',
  cases: 'data-case', methods: 'class-method', implementations: 'method-implementation',
};

function addSyntaxConstructors(arena, add) {
  for (const [kind, fields] of syntaxForms)
    add(kind, fields.map(() => 'i64'), (...values) => {
      const expected = fields.map((field, index) => {
        if (!sequences[field]) return [index, categories[field] ?? [field]];
        arena.sequence(values[index], categories[sequences[field]] ?? [sequences[field]]);
        return [index, sequenceKinds];
      });
      return arena.node(kind, values, expected);
    });
}

function constructors(arena) {
  const functions = [];
  const add = (name, parameters, implementation, result = 'i64') => functions.push({name, parameters, implementation, result});
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
    node('definition', [binding, type, expression, span], [[0, ['binding']], [1, signatureKinds], [2, expressionKinds], [3, ['span']]]));
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
    sequence(imports, ['import']); sequence(exports, ['export']); sequence(declarations, declarationKinds);
    return node('library', [key, scope, imports, exports, declarations, span],
      [[0, sequenceKinds], [1, ['scope']], [2, sequenceKinds], [3, sequenceKinds], [4, sequenceKinds], [5, ['span']]]);
  });
  add('byte', ['i64'], value => {
    if (value < 0n || value > 255n) throw new RangeError('byte literal must be in 0..255');
    return arena.put('byte', [Number(value)]);
  });
  add('signature-location', ['i64'], handle => {
    const node = arena.get(handle, ['definition', 'local-binding', 'overload']);
    return node[5] ?? node[4];
  });
  add('with-signature-location', ['i64', 'i64'], (handle, span) => {
    const node = arena.get(handle, ['definition', 'local-binding', 'overload']);
    arena.get(span, ['span']);
    return arena.put(node[0], [...node.slice(1, 5), span], [1, 2, 3, 4, 5]);
  });
  add('checked-library', ['i64'], handle => { arena.get(handle, ['library']); return handle; });
  addSyntaxConstructors(arena, add);
  addInspection(arena, add);
  return functions;
}

// ---- Received packets are copied into the same arena as constructed syntax ----

// These are the scalar-bearing rows; other rows share the constructor schema.
// Packet IDs have no authority outside this packet. Only copied arena handles
// are exposed, after the entire closed graph has passed structural checks.
const packetForms = new Map([
  ['name', ['text']], ['span', ['name', 'positive', 'positive']], ['scope', []],
  ['child-scope', ['scope-id']], ['binding', ['scope-id', 'name', 'span']],
  ['nil', []], ['cons', ['any', 'sequence']], ['scalar-type', ['scalar']],
  ['function-type', ['types', 'type']], ['local-reference', ['binding', 'span']],
  ['import-reference', ['scope', 'name', 'span']], ['reference', ['binding-reference']],
  ['literal', ['scalar', 'text', 'span']], ['lambda', ['child-scope', 'bindings', 'expression', 'span']],
  ['application', ['expression', 'expressions', 'span']],
  ['conditional', ['expression', 'expression', 'expression', 'span']],
  ['definition', ['binding', 'signature', 'expression', 'span']], ['all', []],
  ['only', ['selection', 'names']], ['rename-pair', ['name', 'name']],
  ['rename', ['selection', 'renames']], ['import', ['names', 'selection', 'scope', 'span']],
  ['export', ['name', 'binding-reference']], ['library', ['names', 'scope', 'imports', 'exports', 'declarations', 'span']],
  ['byte', ['byte-value']], ...syntaxForms,
]);
const packetSequences = {...sequences, expressions: 'expression', names: 'name',
  renames: 'rename-pair', imports: 'import', exports: 'export'};
const packetCategories = {...categories, sequence: sequenceKinds, selection: selectionKinds};
const scalarFields = ['text', 'positive', 'scalar', 'byte-value'];

function packetScalar(value, descriptor) {
  if (descriptor === 'text') {
    if (typeof value !== 'string') throw new TypeError('expected transfer text');
    for (const character of value) scalar(character.codePointAt(0));
  } else if (descriptor === 'scalar') {
    if (!scalarNames.includes(value)) throw new TypeError('unsupported transfer scalar type');
  } else if (!Number.isInteger(value) || value < (descriptor === 'positive' ? 1 : 0) ||
    value > (descriptor === 'positive' ? 0x7fffffff : 255)) throw new TypeError('invalid transfer scalar field');
  return value;
}

function packetNode(nodes, id, descriptor) {
  if (!Number.isInteger(id) || id < 0 || id >= nodes.length) throw new TypeError('dangling transfer node ID');
  const node = nodes[id], kinds = packetSequences[descriptor] ? sequenceKinds : packetCategories[descriptor] ?? [descriptor];
  if (!Array.isArray(node) || (descriptor !== 'any' && !kinds.includes(node[0])))
    throw new TypeError('transfer node has wrong kind');
  return node;
}

function checkPacketSequence(nodes, id, descriptor) {
  const element = packetSequences[descriptor];
  if (!element) return;
  for (let node = nodes[id]; node[0] === 'cons'; node = nodes[node[2]]) packetNode(nodes, node[1], element);
}

function packetSchema(node) {
  const fields = packetForms.get(node[0]);
  if (fields && node.length === fields.length + 1) return fields;
  if (['definition', 'local-binding', 'overload'].includes(node[0]) && node.length === fields.length + 2)
    return [...fields, 'span'];
  throw new TypeError('unsupported transfer node');
}

function packetOrder(nodes) {
  const marks = new Map(), order = [];
  const visit = id => {
    if (marks.get(id) === 'pending') throw new TypeError('cyclic transfer structure');
    if (marks.has(id)) return;
    const node = packetNode(nodes, id, 'any'), fields = packetSchema(node);
    marks.set(id, 'pending');
    fields.forEach((descriptor, index) => {
      const value = node[index + 1];
      if (scalarFields.includes(descriptor)) packetScalar(value, descriptor);
      else { packetNode(nodes, value, descriptor); visit(value); checkPacketSequence(nodes, value, descriptor); }
    });
    marks.set(id, 'complete'); order.push([id, fields]);
  };
  nodes.forEach((_, id) => visit(id));
  return order;
}

function copyPacketNode(arena, node, fields, handles) {
  const references = [];
  const copied = node.slice(1).map((value, index) => {
    if (scalarFields.includes(fields[index])) return value;
    references.push(index + 1); return handles.get(value);
  });
  return arena.put(node[0], copied, references);
}

function receivePacket(arena, text) {
  arena.checkOpen();
  const packet = JSON.parse(text);
  if (!packet || Object.keys(packet).sort().join(',') !== 'nodes,root,version' || packet.version !== 1 || !Array.isArray(packet.nodes))
    throw new TypeError('unsupported library transfer packet');
  const order = packetOrder(packet.nodes), handles = new Map();
  packetNode(packet.nodes, packet.root, 'library');
  for (const [id, fields] of order) handles.set(id, copyPacketNode(arena, packet.nodes[id], fields, handles));
  return handles.get(packet.root);
}

// ---- Inspection copies values and preserves child identities ----

const nodeTags = ['name', 'span', 'scope', 'child-scope', 'binding', 'nil', 'cons', 'scalar-type',
  'function-type', 'local-reference', 'import-reference', 'reference', 'literal', 'lambda', 'application',
  'conditional', 'definition', 'all', 'only', 'rename-pair', 'rename', 'import', 'export', 'library', 'byte',
  ...syntaxForms.map(([kind]) => kind)];

function addInspection(arena, add) {
  add('inspect-tag', ['i64'], handle => nodeTags.indexOf(arena.get(handle)[0]), 'i32');
  add('inspect-field', ['i64', 'i32'], (handle, index) => {
    const node = arena.get(handle), position = index + 1;
    if (!arena.edges[Number(handle % handleWidth)].includes(position)) throw new TypeError('expected a syntax reference field');
    return node[position];
  });
  add('name-length', ['i64'], handle => BigInt([...arena.get(handle, ['name'])[1]].length));
  add('name-ref', ['i64', 'i64'], (handle, index) => {
    const chars = [...arena.get(handle, ['name'])[1]];
    if (index < 0n || index >= BigInt(chars.length)) throw new RangeError('name character index out of range');
    return chars[Number(index)].codePointAt(0);
  }, 'i32');
  for (const [name, index] of [['span-line', 2], ['span-column', 3]])
    add(name, ['i64'], handle => arena.get(handle, ['span'])[index], 'i32');
  add('scalar-index', ['i64'], handle => scalarNames.indexOf(arena.get(handle, ['scalar-type'])[1]), 'i32');
  add('literal-index', ['i64'], handle => scalarNames.indexOf(arena.get(handle, ['literal'])[1]), 'i32');
  add('byte-value', ['i64'], handle => BigInt(arena.get(handle, ['byte'])[1]));
  add('sequence-length', ['i64'], handle => BigInt(arena.sequence(handle).length));
  for (const [type, result] of [['I32', 'i32'], ['I64', 'i64'], ['F32', 'f32'], ['F64', 'f64'], ['Bool', 'i32'], ['Char', 'i32']])
    add(`inspect-literal-${type}`, ['i64'], handle => {
      const node = arena.get(handle, ['literal']);
      if (node[1] !== type) throw new TypeError('literal has the wrong scalar type');
      return type === 'I64' ? BigInt(node[2]) : node[2] === '+nan.0' ? NaN :
        node[2] === '+inf.0' ? Infinity : node[2] === '-inf.0' ? -Infinity : Number(node[2]);
    }, result);
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
  const signatures = functions.flatMap(({parameters, result}) => [0x60, ...unsigned(parameters.length),
    ...parameters.map(type => types[type]), 1, types[result]]);
  const imports = functions.flatMap(({name}, index) => [...wasmText('builder'), ...wasmText(name), 0, ...unsigned(index)]);
  const exports = functions.flatMap(({name}, index) => [...wasmText(name), 0, ...unsigned(index)]);
  const bytes = [0, 97, 115, 109, 1, 0, 0, 0, ...section(1, [...unsigned(functions.length), ...signatures]),
    ...section(2, [...unsigned(functions.length), ...imports]), ...section(7, [...unsigned(functions.length), ...exports])];
  return new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from(bytes)),
    {builder: Object.fromEntries(functions.map(({name, implementation}) => [name, implementation]))});
}

export function openLibraryBuilder() {
  const arena = new Arena(), provider = typedProvider(constructors(arena));
  return Object.freeze({provider, receive: packet => receivePacket(arena, packet),
    finish: handle => arena.finish(handle), close: () => arena.close()});
}

export function libraryTransferJSON(transfer) {
  if (!transfers.has(transfer)) throw new TypeError('expected an owned library transfer');
  return transfers.get(transfer);
}

export function invokeLibraryGenerator(code, providers = new Map(), arguments_ = []) {
  if (code?.result !== 'I64') throw new TypeError('library generator ABI must return an I64 transfer token');
  if (!(providers instanceof Map) || providers.has('lofi.builder')) throw new TypeError('builder provider must be invocation-owned');
  const bindings = new Map(providers), builder = openLibraryBuilder();
  let instance;
  try {
    bindings.set('lofi.builder', builder.provider);
    instance = instantiate(code, bindings);
    return builder.finish(invokeEntry(instance, arguments_));
  } finally {
    if (instance) closeInstance(instance);
    builder.close();
  }
}
