// A host owns actor lifetimes and mailboxes. Promises resume JSPI stacks;
// there is no second runnable queue. This backend uses one JS execution agent.
import {createWasi, instantiate, linkProgram, runProgram, programExports} from './load.mjs';

// ---- Wasm entries ----

const entered = new WeakSet();

export function programEntry(program, name = 'actor_main') {
  const modules = program.linked ? [...program.linked.values()].map(instance => instance.exports) : [program.exports];
  const exports = program.linked ? programExports(program) : program.exports;
  return {exports, main: exports[name], memory: program.linked ? program.runtime.exports.memory : exports.memory,
          handlers: modules.flatMap(exports => Object.entries(exports).filter(([name]) => name.startsWith('handler.')).map(([, value]) => value))};
}

// Dynamic handler globals belong to one invocation, including while suspended.
// Restore after settlement, before anyone observes completion or reuses them.
export async function runEntry(entry, ...args) {
  if (entry.handlers.some(global => entered.has(global))) throw new Error('Wasm entries with shared handlers must not overlap');
  const saved = entry.handlers.map(global => [global, global.value]);
  saved.forEach(([global]) => entered.add(global));
  try { return await WebAssembly.promising(entry.main)(...args); }
  finally { saved.forEach(([global, value]) => { global.value = value; entered.delete(global); }); }
}

// A foreign Bytes argument borrows staging memory. Own its bytes before any
// await or another Wasm call can overwrite or grow the buffer.
export function byteSnapshot(memory, address) {
  const pointer = address >>> 0, buffer = memory.buffer;
  const length = new DataView(buffer).getUint32(pointer, true);
  return new Uint8Array(buffer, pointer + 4, length).slice();
}

// ---- Host lifetimes ----

export function createHost({programs = {}, imports = () => ({}), print = () => {}} = {}) {
  const catalog = new Map(Object.entries(programs)), actors = new Map(), waiting = new Set(), failures = [];
  let nextId = 1;

  function reserve(name) {
    const actor = {id: nextId++, name, entry: null, mailbox: [], incoming: null, receive: null,
                   outgoing: new Set(), ready: Promise.withResolvers(), response: null, spelling: ''};
    actor.ready.promise.catch(() => {});
    actors.set(actor.id, actor);
    return actor;
  }

  function finish(actor, error) {
    const stopped = error ?? new Error(`actor ${actor.name} has stopped`);
    actors.delete(actor.id);
    actor.receive?.reject(stopped);
    for (const request of [...actor.mailbox, actor.incoming, ...actor.outgoing]) if (request) settle(request, null, stopped);
    if (error) { failures.push({id: actor.id, name: actor.name, error}); actor.ready.reject(error); }
    if (!actors.size) { for (const resolve of waiting) resolve(failures.slice()); waiting.clear(); }
  }

  function spawn(name, witness = null) {
    const actor = reserve(name);
    // The reservation precedes asynchronous resolution, linking and execution.
    Promise.resolve().then(() => load(actor, witness)).then(
      () => finish(actor, null), error => finish(actor, error));
    return actor.ready.promise;
  }

  async function load(actor, witness) {
    const resolve = catalog.get(actor.name);
    if (!resolve) throw new Error(`this host has no actor program ${actor.name}`);
    const source = await resolve();
    actor.wire = source.transport === 'wire';
    const wasi = createWasi({print: (fd, line) => print(actor.name, fd, line)});
    const host = {...imports(actor.name), 'snail.actor': actorImports(actor)};
    const program = await loadProgram(source, wasi, host);
    actor.entry = programEntry(program);
    if (typeof actor.entry.main !== 'function') throw new Error(`actor ${actor.name} has no actor_main entry`);
    if (witness !== null && !actor.entry.exports.actor_accept(witness)) throw new Error(`actor ${actor.name} has a different protocol`);
    actor.ready.resolve(actor.id);
    await runEntry(actor.entry);
  }

  function endpoint(id) {
    const actor = actors.get(id);
    if (!actor?.entry) throw new Error(`actor ${id} is not running`);
    return actor;
  }

  // ---- Requests ----

  function request(caller, id, value, wire) {
    const target = endpoint(id);
    if (target.wire !== wire) throw new Error('the request uses the wrong transport');
    const envelope = {caller, target, value, wire, result: Promise.withResolvers()};
    caller.outgoing.add(envelope);
    target.mailbox.push(envelope);
    if (target.receive) { const waiter = target.receive; target.receive = null; waiter.resolve(claim(target)); }
    return envelope.result.promise;
  }

  function settle(envelope, value, error = null) {
    if (!envelope.caller.outgoing.delete(envelope)) return;
    const index = envelope.target.mailbox.indexOf(envelope);
    if (index >= 0) envelope.target.mailbox.splice(index, 1);
    if (error) envelope.result.reject(error); else envelope.result.resolve(value);
  }

  function claim(actor) {
    actor.incoming = actor.mailbox.shift();
    return actor.incoming.wire ? actor.incoming.value.length : -1;
  }

  function receive(actor) {
    if (actor.incoming || actor.receive) throw new Error('reply before receiving another request');
    if (actor.mailbox.length) return Promise.resolve(claim(actor));
    actor.receive = Promise.withResolvers();
    return actor.receive.promise;
  }

  function reply(actor, value, wire) {
    const request = actor.incoming;
    if (!request || request.wire !== wire) throw new Error('there is no matching request to reply to');
    actor.incoming = null;
    settle(request, value);
  }

  // Imports are leaves: waking or starting another actor only queues a promise
  // job, never reenters Wasm beneath the calling actor's suspended stack.
  function actorImports(actor) {
    return {
      character: code => { actor.spelling += String.fromCodePoint(code); },
      spawn: new WebAssembly.Suspending(witness => { const name = actor.spelling; actor.spelling = ''; return spawn(name, witness); }),
      local: id => !endpoint(id).wire,
      request: new WebAssembly.Suspending((id, value) => request(actor, id, value, false)),
      'request-bytes': new WebAssembly.Suspending(async (id, address) => {
        actor.response = await request(actor, id, byteSnapshot(actor.entry.memory, address), true);
        return actor.response.length;
      }),
      'response-byte': index => actor.response[index],
      receive: new WebAssembly.Suspending(() => receive(actor)),
      value: () => actor.incoming.value,
      'request-byte': index => actor.incoming.value[index],
      'reply-local': () => !actor.incoming.wire,
      reply: value => reply(actor, value, false),
      'reply-bytes': address => reply(actor, byteSnapshot(actor.entry.memory, address), true),
    };
  }

  function drain() {
    if (!actors.size) return Promise.resolve(failures.slice());
    return new Promise(resolve => waiting.add(resolve));
  }

  return {spawn, drain, get size() { return actors.size; },
          run(initial) { for (const name of initial) spawn(name); return drain(); }};
}

// ---- Program loading ----

async function loadProgram(source, wasi, host) {
  if (source.manifest) {
    const program = await linkProgram(source.read, source.manifest, wasi, host, {strictHost: true});
    runProgram(program);
    return program;
  }
  const module = source.module;
  requireImports(module, host);
  const instance = await instantiate(module, {...wasi.getImportObject(), ...host});
  wasi.initialize(instance);
  instance.exports.main();
  return instance;
}

function requireImports(module, host) {
  for (const {module: from, name} of WebAssembly.Module.imports(module)) {
    if (from === 'wasi_snapshot_preview1') continue;
    if (host[from]?.[name] === undefined) throw new Error(`this host does not provide ${from} ${name}`);
  }
}
