// An explicit Node/Linux service for compiled Lofi build programs. Chibi owns
// parsed libraries; this scope owns copied artifacts and independent instances.
import {spawn, execFileSync} from 'node:child_process';
import {mkdtempSync, openSync, closeSync, readSync, writeSync, readFileSync,
  writeFileSync, rmSync, constants} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadWasm, instantiate, invokeEntry, closeInstance} from './execute.mjs';
import {openLibraryBuilder, libraryTransferJSON} from './builder.mjs';

const width = 1n << 32n;
let nextSession = 1n;
const scalarTypes = ['I32', 'I64', 'F32', 'F64', 'Bool', 'Char', 'Unit'];
const pauseCell = new Int32Array(new SharedArrayBuffer(4));

class CompilerDiagnostic extends Error {}

// ---- One synchronous connection to an owned Chibi process ----

function retryIO(operation, deadline) {
  for (;;) {
    if (Date.now() >= deadline) throw new Error('compiler service response timed out');
    try { return operation(); }
    catch (error) { if (error.code !== 'EAGAIN') throw error; }
    Atomics.wait(pauseCell, 0, 0, 5);
  }
}

function groupIsRunning(group, deadline) {
  const remaining = deadline - Date.now();
  if (remaining <= 0) throw new Error('compiler process group did not stop');
  const rows = execFileSync('ps', ['-e', '-o', 'pgid=,stat='],
    {encoding: 'utf8', timeout: remaining, killSignal: 'SIGKILL'});
  return rows.trim().split('\n').some(row => {
    const [id, status] = row.trim().split(/\s+/);
    return id === String(group) && !/^[ZX]/.test(status);
  });
}

function stopOwnedGroup(child) {
  if (!child?.pid) return;
  // SIGKILL cannot be ignored by the host or its tool descendants. Zombies
  // have stopped; Node reaps its direct child when the event loop resumes.
  try { process.kill(-child.pid, 'SIGKILL'); }
  catch (error) { if (error.code === 'ESRCH') return; throw error; }
  const deadline = Date.now() + 2000;
  while (groupIsRunning(child.pid, deadline)) Atomics.wait(pauseCell, 0, 0, 5);
}

class CompilerHost {
  directory = mkdtempSync(join(tmpdir(), 'lofi-compiler-'));

  constructor({chibi = process.env.CHIBI ?? 'chibi-scheme', timeout = 120000} = {}) {
    this.timeout = timeout;
    try {
      if (!Number.isFinite(timeout) || timeout <= 0) throw new TypeError('compiler timeout must be positive milliseconds');
      const deadline = Date.now() + timeout;
      this.openPipes(deadline);
      this.start(chibi);
      this.receive(deadline);
    } catch (failure) { throw this.abort(failure); }
  }

  openPipes(deadline) {
    execFileSync('mkfifo', [join(this.directory, 'requests'), join(this.directory, 'responses')],
      {timeout: Math.max(1, deadline - Date.now()), killSignal: 'SIGKILL'});
    this.request = openSync(join(this.directory, 'requests'), constants.O_RDWR | constants.O_NONBLOCK);
    this.response = openSync(join(this.directory, 'responses'), constants.O_RDWR | constants.O_NONBLOCK);
  }

  start(chibi) {
    const errors = openSync(join(this.directory, 'host-errors.txt'), 'w');
    try {
      this.child = spawn(chibi, ['-I', fileURLToPath(new URL('../../../bootstrap/', import.meta.url)),
        '-I', fileURLToPath(new URL('../../../bootstrap/', import.meta.url)),
        fileURLToPath(new URL('../../../scripts/serve-lofi-compiler.scm', import.meta.url)), this.directory],
      {detached: true, stdio: ['ignore', 'ignore', errors]});
      // A failed spawn has no PID. Consume its later error event after this
      // synchronous startup path has already reported and cleaned up failure.
      this.child.on('error', () => {});
      if (!this.child.pid) throw new Error(`could not start Chibi compiler: ${chibi}`);
    } finally { closeSync(errors); }
  }

  readLine(deadline) {
    const chunks = [];
    for (;;) {
      const buffer = Buffer.alloc(65536);
      const count = retryIO(() => readSync(this.response, buffer), deadline);
      if (!count) throw new Error('compiler service closed its response stream');
      const chunk = buffer.subarray(0, count), end = chunk.indexOf(10);
      if (end !== -1 && end !== count - 1) throw new Error('unsolicited compiler service response');
      chunks.push(chunk);
      if (end !== -1) return Buffer.concat(chunks).toString('utf8');
    }
  }

  receive(deadline) {
    const result = JSON.parse(this.readLine(deadline));
    if (!Array.isArray(result) || result.length !== 2 || typeof result[0] !== 'boolean')
      throw new Error('invalid compiler service response');
    if (!result[0]) throw new CompilerDiagnostic(result[1]);
    return result[1];
  }

  call(command) {
    if (this.request === undefined) throw new Error(this.failure ?? 'compiler service is closed');
    const bytes = Buffer.from(JSON.stringify(command) + '\n'), deadline = Date.now() + this.timeout;
    try {
      for (let offset = 0; offset < bytes.length;)
        offset += retryIO(() => writeSync(this.request, bytes, offset), deadline);
      return this.receive(deadline);
    } catch (failure) {
      throw failure instanceof CompilerDiagnostic ? failure : this.abort(failure);
    }
  }

  compile(map, key, name) {
    this.call(['compile', map, key, name]);
    return Uint8Array.from(readFileSync(join(this.directory, 'artifact.wasm')));
  }

  abort(failure) {
    let diagnostics = '';
    try { diagnostics = readFileSync(join(this.directory, 'host-errors.txt'), 'utf8').trim(); } catch {}
    this.failure = [failure.message, diagnostics].filter(Boolean).join('\n');
    try { this.close(); } catch (cleanup) { this.failure += `\nCompiler cleanup failed: ${cleanup.message}`; }
    return new Error(this.failure);
  }

  close() {
    try { stopOwnedGroup(this.child); }
    finally {
      this.child = undefined;
      for (const name of ['request', 'response']) {
        if (this[name] !== undefined) closeSync(this[name]);
        this[name] = undefined;
      }
      rmSync(this.directory, {recursive: true, force: true});
    }
  }
}

// ---- Session tokens contain host resources, never managed heap pointers ----

function snapshotProviders(providerSets) {
  const snapshots = new Map();
  for (const [name, providers] of providerSets) {
    if (typeof name !== 'string' || !(providers instanceof Map)) throw new TypeError('expected named provider Maps');
    snapshots.set(name, new Map(providers));
  }
  return snapshots;
}

class Session {
  objects = [];
  liveInstances = new Set();
  active = 0;

  constructor(options) {
    if (nextSession >= 1n << 31n) throw new RangeError('compiler session IDs exhausted');
    this.origin = nextSession++;
    this.providers = snapshotProviders(options.providerSets ?? []);
    this.host = new CompilerHost(options);
    try { this.builder = openLibraryBuilder(); }
    catch (failure) { this.host.close(); throw failure; }
  }

  put(kind, value) {
    if (!this.objects) throw new Error('compiler session is closed');
    if (this.objects.length >= 0xffffffff) throw new RangeError('compiler session handles exhausted');
    const token = this.origin * width + BigInt(this.objects.length);
    this.objects.push({kind, value});
    return token;
  }

  get(token, kind) {
    if (!this.objects) throw new Error('compiler session is closed');
    if (typeof token !== 'bigint' || token / width !== this.origin) throw new TypeError('foreign compiler session handle');
    const object = this.objects[Number(token % width)];
    if (!object || object.kind !== kind) throw new TypeError(`expected compiler ${kind} handle`);
    return object.value;
  }

  result(kind, operation) {
    // Initialization and invocation can call borrowed providers. A callback
    // cannot close this scope while any operation still owns unpublished work.
    this.active++;
    try { return this.put('result', {ok: true, token: this.put(kind, operation())}); }
    catch (failure) { return this.put('result', {ok: false, message: [...describeFailure(failure)]}); }
    finally { this.active--; }
  }

  builtLibrary(map, key, token) {
    const transfer = this.builder.finish(token);
    // The builder checks invocation ownership; its immutable token is stable
    // across insertions. The receiver caches only the unresolved library value.
    return this.host.call(['built', map, key, String(token), libraryTransferJSON(transfer)]);
  }

  instantiate(code, name) {
    if (!this.providers.has(name)) throw new TypeError(`unknown provider set: ${name}`);
    const instance = instantiate(code, this.providers.get(name)), state = {code, instance};
    this.liveInstances.add(state);
    return state;
  }

  invoke(state, values) {
    if (!state.instance) throw new Error('Lofi Wasm instance is closed');
    if (values.length !== state.code.parameters.length || values.some((value, i) => value.type !== state.code.parameters[i]))
      throw new TypeError('entry arguments do not match the saved semantic signature');
    return {type: state.code.result, value: invokeEntry(state.instance, values.map(value => value.value))};
  }

  closeInstance(state) {
    if (state.instance) closeInstance(state.instance);
    state.instance = undefined;
    this.liveInstances.delete(state);
  }

  close() {
    if (!this.objects) return;
    if (this.active) throw new Error('compiler session is already executing');
    for (const state of this.liveInstances) this.closeInstance(state);
    this.objects = undefined;
    this.providers.clear();
    this.builder.close();
    this.host.close();
  }
}

function describeFailure(failure) {
  const message = failure?.message ?? String(failure);
  return failure?.cause === undefined ? message : `${message}: ${describeFailure(failure.cause)}`;
}

// ---- Fixed scalar ABI and explicit operation results ----

function functions(session) {
  const list = [], add = (name, parameters, result, implementation) => list.push({name, parameters, result, implementation});
  const get = (token, kind) => session.get(token, kind), put = (kind, value) => session.put(kind, value);
  const operation = (name, parameters, kind, implementation) =>
    add(name, parameters, 'i64', (...values) => session.result(kind, () => implementation(...values)));
  add('text-empty', [], 'i64', () => put('text', ''));
  add('text-character', ['i64', 'i32'], 'i64', (text, char) => {
    if (char < 0 || char > 0x10ffff || (char >= 0xd800 && char <= 0xdfff)) throw new TypeError('invalid Unicode scalar');
    return put('text', get(text, 'text') + String.fromCodePoint(char));
  });
  add('list-empty', [], 'i64', () => put('list', []));
  add('list-text', ['i64', 'i64'], 'i64', (head, tail) => put('list', [get(head, 'text'), ...get(tail, 'list')]));
  add('list-scalar', ['i64', 'i64'], 'i64', (head, tail) => put('list', [get(head, 'scalar'), ...get(tail, 'list')]));
  add('result-ok', ['i64'], 'i32', token => Number(get(token, 'result').ok));
  add('result-value', ['i64'], 'i64', token => {
    const result = get(token, 'result');
    if (!result.ok) throw new TypeError('compiler result is a failure');
    return result.token;
  });
  add('error-length', ['i64'], 'i64', token => BigInt(get(token, 'result').message.length));
  add('error-character', ['i64', 'i64'], 'i32', (token, index) => get(token, 'result').message[Number(index)].codePointAt(0));
  operation('parse-library', ['i64', 'i64'], 'library', (source, text) =>
    session.builder.receive(session.host.call(['parse', get(source, 'text'), get(text, 'text')])));
  add('library-value', ['i64'], 'i64', token => get(token, 'library'));
  operation('map-empty', [], 'map', () => session.host.call(['empty']));
  operation('map-primitives', ['i64'], 'map', map => session.host.call(['primitives', get(map, 'map')]));
  operation('map-source', ['i64', 'i64', 'i64', 'i64'], 'map', (map, key, source, text) =>
    session.host.call(['source', get(map, 'map'), get(key, 'list'), get(source, 'text'), get(text, 'text')]));
  operation('map-built', ['i64', 'i64', 'i64'], 'map', (map, key, library) =>
    session.builtLibrary(get(map, 'map'), get(key, 'list'), library));
  operation('map-alias', ['i64', 'i64', 'i64'], 'map', (map, from, to) =>
    session.host.call(['alias', get(map, 'map'), get(from, 'list'), get(to, 'list')]));
  operation('compile', ['i64', 'i64', 'i64'], 'artifact', (map, key, name) =>
    session.host.compile(get(map, 'map'), get(key, 'list'), get(name, 'text')));
  operation('load', ['i64'], 'code', token => loadWasm(get(token, 'artifact')));
  operation('instantiate', ['i64', 'i64'], 'instance', (code, name) => session.instantiate(get(code, 'code'), get(name, 'text')));
  operation('invoke', ['i64', 'i64'], 'scalar', (instance, values) => session.invoke(get(instance, 'instance'), get(values, 'list')));
  operation('close-instance', ['i64'], 'unit', token => session.closeInstance(get(token, 'instance')));
  operation('write-artifact', ['i64', 'i64'], 'unit', (token, path) => writeFileSync(get(path, 'text'), get(token, 'artifact')));
  scalarFunctions(add, get, put);
  return list;
}

function scalarFunctions(add, get, put) {
  const physical = ['i32', 'i64', 'f32', 'f64', 'i32', 'i32'];
  for (const [index, type] of scalarTypes.entries()) {
    if (type === 'Unit') break;
    add(`scalar-${type}`, [physical[index]], 'i64', value => put('scalar', {type, value: scalarInput(type, value)}));
    add(`value-${type}`, ['i64'], physical[index], token => {
      const scalar = get(token, 'scalar');
      if (scalar.type !== type) throw new TypeError(`expected ${type} result`);
      return type === 'Bool' ? Number(scalar.value) : type === 'Char' ? scalar.value.codePointAt(0) : scalar.value;
    });
  }
  add('scalar-kind', ['i64'], 'i32', token => scalarTypes.indexOf(get(token, 'scalar').type));
  add('scalar-Unit', [], 'i64', () => put('scalar', {type: 'Unit', value: undefined}));
}

function scalarInput(type, value) {
  if (type === 'Bool') {
    if (value !== 0 && value !== 1) throw new TypeError('Bool scalar must be canonical');
    return value !== 0;
  }
  if (type !== 'Char') return value;
  if (value < 0 || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) throw new TypeError('invalid Unicode scalar');
  return String.fromCodePoint(value);
}

// Wasm re-exports imports with declared physical signatures. The existing
// execution adapter and engine therefore check this provider like any other.
function unsigned(value) {
  const bytes = [];
  do { const rest = Math.floor(value / 128); bytes.push(value % 128 + (rest ? 128 : 0)); value = rest; } while (value);
  return bytes;
}
function wasmText(value) {
  const bytes = new TextEncoder().encode(value);
  return [...unsigned(bytes.length), ...bytes];
}
function section(id, bytes) { return [id, ...unsigned(bytes.length), ...bytes]; }
function provider(functions) {
  const types = {i32: 0x7f, i64: 0x7e, f32: 0x7d, f64: 0x7c};
  const signatures = functions.flatMap(({parameters, result}) => [0x60, ...unsigned(parameters.length),
    ...parameters.map(type => types[type]), 1, types[result]]);
  const imports = functions.flatMap(({name}, i) => [...wasmText('service'), ...wasmText(name), 0, ...unsigned(i)]);
  const exports = functions.flatMap(({name}, i) => [...wasmText(name), 0, ...unsigned(i)]);
  const bytes = [0, 97, 115, 109, 1, 0, 0, 0, ...section(1, [...unsigned(functions.length), ...signatures]),
    ...section(2, [...unsigned(functions.length), ...imports]), ...section(7, [...unsigned(functions.length), ...exports])];
  return new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from(bytes)),
    {service: Object.fromEntries(functions.map(({name, implementation}) => [name, implementation]))});
}

export function openCompilerService(options = {}) {
  const session = new Session(options);
  try {
    return Object.freeze({providers: new Map([['lofi.compiler', provider(functions(session))],
      ['lofi.builder', session.builder.provider]]), close: () => session.close()});
  } catch (failure) { session.close(); throw failure; }
}
