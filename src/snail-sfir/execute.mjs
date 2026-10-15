// Load Chibi-produced Wasm artifacts and own independently initialized instances.
// The host supplies already instantiated Wasm providers; no files or runtimes
// are discovered here. Compiler/library-value transport is a separate boundary.

const codes = new WeakMap();
const instances = new WeakMap();
const scalarTypes = new Map([['I32', 0x7f], ['I64', 0x7e], ['F32', 0x7d], ['F64', 0x7c],
  ['Bool', 0x7f], ['Char', 0x7f]]);
const providerExports = Object.getOwnPropertyDescriptor(WebAssembly.Instance.prototype, 'exports').get;
const text = new TextEncoder();

// ---- Artifact structure and saved semantic signature ----

function unsignedLeb(bytes, cursor) {
  let value = 0;
  for (let shift = 0; shift < 35; shift += 7) {
    const byte = bytes[cursor.position++];
    if (byte === undefined) throw new TypeError('truncated Wasm section length');
    value += (byte & 127) * 2 ** shift;
    if (!(byte & 128)) return value;
  }
  throw new TypeError('invalid Wasm section length');
}

function rejectStartSection(bytes) {
  const cursor = {position: 8};
  while (cursor.position < bytes.length) {
    const section = bytes[cursor.position++], size = unsignedLeb(bytes, cursor);
    if (section === 8) throw new TypeError('Wasm artifact must not have an automatic start function');
    cursor.position += size;
  }
}

function readSignature(module) {
  const sections = WebAssembly.Module.customSections(module, 'sfir.entry');
  if (sections.length !== 1) throw new TypeError('expected one sfir.entry artifact section');
  const signature = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(sections[0]));
  if (!signature || Object.keys(signature).sort().join(',') !== 'export,library,parameters,result,version'
      || signature.version !== 1 || !Array.isArray(signature.library) || !signature.library.length
      || !signature.library.every(name => typeof name === 'string') || typeof signature.export !== 'string'
      || !Array.isArray(signature.parameters) || !signature.parameters.every(type => scalarTypes.has(type))
      || !(scalarTypes.has(signature.result) || signature.result === 'Unit'))
    throw new TypeError('unsupported SFIR scalar entry metadata');
  return Object.freeze({...signature, library: Object.freeze(signature.library),
    parameters: Object.freeze(signature.parameters)});
}

function functionImports(module) {
  const imports = WebAssembly.Module.imports(module);
  if (imports.some(value => value.kind !== 'function'))
    throw new TypeError('Wasm execution adapter accepts only function imports');
  return imports;
}

function requireAbiExports(module) {
  const exports = WebAssembly.Module.exports(module);
  for (const name of ['entry', 'main']) {
    if (!exports.some(value => value.name === name && value.kind === 'function'))
      throw new TypeError(`missing Wasm function export: ${name}`);
  }
}

function snapshotWasmBytes(artifactBytes) {
  if (!(artifactBytes instanceof Uint8Array)) throw new TypeError('loadWasm requires artifact bytes');
  const bytes = Uint8Array.from(artifactBytes);
  if (bytes[0] === 0x7f && bytes[1] === 0x45 && bytes[2] === 0x4c && bytes[3] === 0x46)
    throw new TypeError('native64 loading is not supported by the Wasm execution adapter');
  return bytes;
}

export function loadWasm(artifactBytes) {
  const bytes = snapshotWasmBytes(artifactBytes);
  const module = new WebAssembly.Module(bytes);
  rejectStartSection(bytes);
  const imports = functionImports(module), signature = readSignature(module);
  requireAbiExports(module);
  const code = Object.freeze({entry: Object.freeze({library: signature.library, export: signature.export}),
    parameters: signature.parameters, result: signature.result});
  codes.set(code, {module, imports, probe: signatureProbe(signature)});
  return code;
}

// ---- Engine-checked signatures without running guest functions ----

function encodeUnsigned(value) {
  const bytes = [];
  do {
    const low = value % 128;
    value = Math.floor(value / 128);
    bytes.push(value ? low + 128 : low);
  } while (value);
  return bytes;
}

function wasmName(name) {
  const bytes = text.encode(name);
  return [...encodeUnsigned(bytes.length), ...bytes];
}

function wasmSection(id, bytes) {
  return [id, ...encodeUnsigned(bytes.length), ...bytes];
}

// This module has only types and imports. Instantiating it cannot call either
// imported function. The engine checks the actual Wasm function types, including
// parameter/result counts; JS function labels would not establish that evidence.
function signatureProbe(signature) {
  const entry = [0x60, ...encodeUnsigned(signature.parameters.length),
    ...signature.parameters.map(type => scalarTypes.get(type)),
    ...(signature.result === 'Unit' ? [0] : [1, scalarTypes.get(signature.result)])];
  const types = wasmSection(1, [2, ...entry, 0x60, 0, 0]);
  const imports = wasmSection(2, [2, ...wasmName('abi'), ...wasmName('entry'), 0, 0,
    ...wasmName('abi'), ...wasmName('main'), 0, 1]);
  return new WebAssembly.Module(Uint8Array.from([0, 97, 115, 109, 1, 0, 0, 0, ...types, ...imports]));
}

function importsFromProviders(imports, providers) {
  if (!(providers instanceof Map)) throw new TypeError('providers must be a Map of Wasm instances');
  const bindings = Object.create(null);
  for (const {module, name} of imports) {
    if (!providers.has(module)) throw new TypeError(`missing Wasm provider: ${module}`);
    const exports = providerExports.call(providers.get(module));
    if (typeof exports[name] !== 'function') throw new TypeError(`missing provider function: ${module}/${name}`);
    (bindings[module] ??= Object.create(null))[name] = exports[name];
  }
  return bindings;
}

export class InitializationError extends Error {
  constructor(cause) {
    super('SFIR instance initialization failed', {cause});
    this.name = 'InitializationError';
  }
}

export function instantiate(code, providers = new Map()) {
  const loaded = codes.get(code);
  if (!loaded) throw new TypeError('instantiate requires loaded Wasm code');
  // No start function or mutable imports can expose effects during linking.
  // Check all provider types, then both ABI exports, before calling main.
  const runtime = new WebAssembly.Instance(loaded.module, importsFromProviders(loaded.imports, providers));
  new WebAssembly.Instance(loaded.probe, {abi: runtime.exports});
  try { runtime.exports.main(); } catch (cause) { throw new InitializationError(cause); }
  const instance = Object.freeze({});
  instances.set(instance, {code, runtime, busy: false});
  return instance;
}

// ---- Checked semantic scalar transport ----

function unicodeScalar(value) {
  return Number.isInteger(value) && value >= 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff);
}

function float32(value) {
  const rounded = Math.fround(value);
  if (Number.isFinite(value) && !Number.isFinite(rounded))
    throw new RangeError('finite F32 value overflows its representation');
  return rounded;
}

function machineScalar(type, value) {
  switch (type) {
    case 'I32':
      if (Number.isInteger(value) && value >= -0x80000000 && value <= 0x7fffffff) return value;
      break;
    case 'I64':
      if (typeof value === 'bigint' && value >= -(1n << 63n) && value < (1n << 63n)) return value;
      break;
    case 'F32': case 'F64':
      if (typeof value === 'number') return type === 'F32' ? float32(value) : value;
      break;
  }
  throw new TypeError(`value does not satisfy scalar type ${type}`);
}

function encodeArgument(type, value) {
  if (type === 'Bool') {
    if (typeof value !== 'boolean') throw new TypeError('Bool argument requires a boolean');
    return value ? 1 : 0;
  }
  if (type === 'Char') {
    if (typeof value !== 'string' || [...value].length !== 1 || !unicodeScalar(value.codePointAt(0)))
      throw new TypeError('Char argument requires one Unicode scalar');
    return value.codePointAt(0);
  }
  return machineScalar(type, value);
}

function decodeResult(type, value) {
  if (type === 'Unit' && value === undefined) return undefined;
  if (type === 'Bool' && (value === 0 || value === 1)) return value === 1;
  if (type === 'Char' && unicodeScalar(value)) return String.fromCodePoint(value);
  if (type === 'Unit' || type === 'Bool' || type === 'Char') throw new TypeError(`invalid ${type} entry result`);
  return machineScalar(type, value);
}

// ---- Instance lifetime and calls ----

function liveInstance(instance) {
  const state = instances.get(instance);
  if (!state) throw new TypeError('expected an SFIR Wasm instance');
  if (!state.runtime) throw new Error('SFIR Wasm instance is closed');
  if (state.busy) throw new Error('SFIR Wasm instance is already executing');
  return state;
}

export function invokeEntry(instance, arguments_) {
  const state = liveInstance(instance);
  state.busy = true;
  try {
    if (!Array.isArray(arguments_) || arguments_.length !== state.code.parameters.length)
      throw new TypeError('entry arguments do not match the saved parameter count');
    const values = state.code.parameters.map((type, index) => encodeArgument(type, arguments_[index]));
    return decodeResult(state.code.result, state.runtime.exports.entry(...values));
  } finally { state.busy = false; }
}

export function closeInstance(instance) {
  const state = instances.get(instance);
  if (!state) throw new TypeError('expected an SFIR Wasm instance');
  if (state.busy) throw new Error('SFIR Wasm instance is already executing');
  state.runtime = undefined;
  state.code = undefined;
}
