// Experimental Node host. Each subprocess owns one linked Scheme/WASI instance.
// S-expression strings cross IPC; Node's binary framing never JSON-encodes them.
import { fork } from 'node:child_process';
import { resolve } from 'node:path';

// ---- Transport frames ----

const textLimit = 65536;

export function frame(connection, request, datum) {
  if (typeof datum !== 'string' || datum.length > textLimit) {
    throw new Error('actor message must be S-expression text within 65536 code units');
  }
  return `(${connection} ${request} ${datum}\n)`;
}

// Only the fixed envelope is interpreted here. The Scheme reader validates the
// entire payload; the host neither parses application values nor evaluates them.
export function unframe(text) {
  if (typeof text !== 'string' || text.length > textLimit + 64) {
    throw new Error('invalid actor frame');
  }
  const match = /^\(([1-9][0-9]*) ([1-9][0-9]*) ([\s\S]*)\n\)$/.exec(text);
  if (!match) throw new Error('invalid actor frame');
  return { connection: match[1], request: match[2], datum: match[3] };
}

// ---- Connection-owned calls ----

class Connection {
  pending = new Map();
  nextRequest = 1n;
  closed = false;

  constructor(actor, id) {
    this.actor = actor;
    this.id = id;
  }

  call(datum) {
    if (this.closed) return Promise.reject(new Error('connection is closed'));
    const request = String(this.nextRequest++);
    return new Promise((resolveCall, reject) => {
      this.pending.set(request, { resolve: resolveCall, reject });
      try { this.actor.send(frame(this.id, request, datum)); }
      catch (error) { this.pending.delete(request); reject(error); }
    });
  }

  receive(request, datum) {
    const call = this.pending.get(request);
    if (!call) return; // A closed connection may still have produced effects.
    this.pending.delete(request);
    call.resolve(datum);
  }

  close(error = new Error('connection is closed; pending outcomes are unknown')) {
    if (this.closed) return;
    this.closed = true;
    this.actor.connections.delete(this.id);
    for (const call of this.pending.values()) call.reject(error);
    this.pending.clear();
  }
}

// ---- Actor lifetime and supervision ----

class Actor {
  connections = new Map();
  nextConnection = 1n;
  failure = null;
  stopping = null;

  constructor(filename) {
    this.worker = fork(new URL('./actor-worker.mjs', import.meta.url), [resolve(filename)], {
      serialization: 'advanced', execArgv: ['--no-warnings'], stdio: ['ignore', 'inherit', 'inherit', 'ipc'],
    });
    this.terminated = new Promise(accept => this.worker.once('close', accept));
    this.ready = new Promise((accept, reject) => { this.accept = accept; this.reject = reject; });
    this.worker.on('message', text => this.receive(text));
    this.worker.on('error', error => this.fail(error));
    this.worker.on('exit', code => this.fail(new Error(`actor exited (${code}); pending outcomes are unknown`)));
  }

  send(text) {
    this.worker.send(text, error => {
      if (error) { this.fail(error); void this.stop(); }
    });
  }

  receive(text) {
    if (this.failure) return;
    if (text === '(ready)') { this.accept(); return; }
    try {
      const reply = unframe(text);
      this.connections.get(reply.connection)?.receive(reply.request, reply.datum);
    } catch (error) { this.fail(error); void this.stop(); }
  }

  connect() {
    if (this.failure) throw this.failure;
    const connection = new Connection(this, String(this.nextConnection++));
    this.connections.set(connection.id, connection);
    return connection;
  }

  fail(error) {
    if (this.failure) return;
    this.failure = error;
    this.reject(error);
    for (const connection of this.connections.values()) connection.close(error);
  }

  stop() {
    this.fail(new Error('actor stopped; pending outcomes are unknown'));
    if (!this.stopping) {
      this.stopping = this.terminated;
      this.worker.kill('SIGKILL');
    }
    return this.stopping;
  }
}

export async function spawn(filename) {
  const actor = new Actor(filename);
  try { await actor.ready; return actor; }
  catch (error) { await actor.stop(); throw error; }
}
