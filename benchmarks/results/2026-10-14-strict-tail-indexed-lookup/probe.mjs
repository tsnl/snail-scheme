import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {WASI} from 'node:wasi';

// ---- Real scalar provider instances retain terminal error evidence ----

const [artifact, directory] = process.argv.slice(2);
assert(!fs.existsSync(directory), 'never replace a prior probe');
fs.mkdirSync(directory);
const module = new WebAssembly.Module(fs.readFileSync(artifact));
const results = [];
const save = () => fs.writeFileSync(path.join(directory, 'results.json'), JSON.stringify(results, null, 2) + '\n');

function create(label, failedOutput) {
  const root = path.join(directory, label);
  fs.mkdirSync(root);
  fs.writeFileSync(path.join(root, 'input.txt'), Buffer.from('\0λ😀\u{10ffff}'));
  const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': root}, returnOnExit: true});
  const live = new Map(), events = [], diagnostics = [], issued = [];
  const imports = {wasi_snapshot_preview1: {...wasi.wasiImport}};
  let memory;
  imports.wasi_snapshot_preview1.path_open = (...args) => {
    const status = wasi.wasiImport.path_open(...args);
    const pathname = new TextDecoder().decode(new Uint8Array(memory.buffer, args[2], args[3]));
    events.push(['open', pathname, status]);
    if (status === 0) live.set(new DataView(memory.buffer).getUint32(args.at(-1), true), pathname);
    return status;
  };
  imports.wasi_snapshot_preview1.fd_close = fd => {
    const pathname = live.get(fd), status = wasi.wasiImport.fd_close(fd);
    events.push(['close', pathname, status]);
    if (status === 0) live.delete(fd);
    return status;
  };
  imports.wasi_snapshot_preview1.fd_write = (...args) => {
    if (live.get(args[0]) === failedOutput) {
      events.push(['returned-write-error', failedOutput, 29]);
      return 29; // Returned WASI EIO, rather than a host exception.
    }
    return wasi.wasiImport.fd_write(...args);
  };
  for (const entry of WebAssembly.Module.imports(module)) {
    assert.equal(entry.kind, 'function');
    if (entry.module === 'wasi_snapshot_preview1') continue;
    assert(['snail.abi', 'snail.platform'].includes(entry.module));
    imports[entry.module] ??= {};
    imports[entry.module][entry.name] = entry.module === 'snail.platform' && entry.name === 'diagnostics/report-error' ? (pointer, length) => {
      const message = new TextDecoder().decode(new Uint8Array(memory.buffer, pointer, length));
      diagnostics.push(message);
      assert.equal(live.size, 0, 'owned descriptors must be dropped before the nonreturning diagnostic');
      throw new Error(message);
    } : () => { throw new Error('unexpected legacy ABI import: ' + entry.name); };
  }
  const instance = new WebAssembly.Instance(module, imports);
  memory = instance.exports.memory;
  wasi.initialize(instance);
  return {api: instance.exports, root, live, events, diagnostics, issued};
}

function pathname(run, text) {
  run.api['snail:io/path-begin']();
  for (const character of text) run.api['snail:io/path-character'](character.codePointAt(0));
}

function open(run, text, direction = 'output') {
  pathname(run, text);
  const id = run.api['snail:io/open-' + direction + '-file']();
  run.issued.push([id, text]);
  return id;
}

function write(run, id, text) {
  for (const character of text) run.api['snail:io/write-character'](id, character.codePointAt(0));
}

function closes(run) {
  return run.events.filter(event => event[0] === 'close').map(event => event[1]);
}

function checked(label, failedOutput, action) {
  const record = {label, status: 'started'};
  results.push(record);
  save();
  let run;
  try {
    run = create(label, failedOutput);
    action(run);
    record.valid = true;
  } catch (error) {
    record.failure = String(error);
    throw error;
  } finally {
    if (run) {
      assert.equal(run.api['snail:io/close-all'](), 0);
      assert.equal(run.live.size, 0);
      Object.assign(record, {events: run.events, diagnostics: run.diagnostics, issued: run.issued});
    }
    record.status = record.valid ? 'passed' : 'failed';
    save();
  }
}

// ---- Monotonic successful IDs, sparse cleanup and returned error precedence ----

checked('unicode-and-ids', null, run => {
  const input = open(run, 'input.txt', 'input'), output = open(run, 'output.txt');
  assert.deepEqual([input, output], [0, 1]);
  for (const code of [0, 0x03bb, 0x1f600, 0x10ffff, -1, -1]) {
    assert.equal(run.api['snail:io/peek-character'](input), code);
    assert.equal(run.api['snail:io/peek-character'](input), code);
    assert.equal(run.api['snail:io/read-character'](input), code);
    if (code >= 0) run.api['snail:io/write-character'](output, code);
  }
  run.api['snail:io/close'](output);
  run.api['snail:io/close'](input);
  const later = open(run, 'later.txt');
  assert.equal(later, 2);
  write(run, later, 'later');
  run.api['snail:io/close'](later);
  assert.deepEqual(fs.readFileSync(path.join(run.root, 'output.txt')), fs.readFileSync(path.join(run.root, 'input.txt')));
});

checked('ordered-cleanup-with-hole-and-eio', 'bad.txt', run => {
  const input = open(run, 'input.txt', 'input'), hole = open(run, 'hole.txt');
  const bad = open(run, 'bad.txt'), good = open(run, 'good.txt');
  assert.deepEqual([input, hole, bad, good], [0, 1, 2, 3]);
  run.api['snail:io/close'](hole);
  write(run, bad, 'failed buffered payload');
  write(run, good, 'retained buffered payload');
  pathname(run, 'pending-unused.txt');
  assert.equal(run.api['snail:io/close-all'](), 1);
  assert.deepEqual(closes(run), ['hole.txt', 'input.txt', 'bad.txt', 'good.txt']);
  assert(run.events.some(event => event[0] === 'returned-write-error'));
  assert.deepEqual(run.diagnostics, []);
  assert.equal(fs.readFileSync(path.join(run.root, 'good.txt'), 'utf8'), 'retained buffered payload');
  assert(!fs.existsSync(path.join(run.root, 'pending-unused.txt')));
});

checked('primary-error-survives-cleanup-eio', 'bad.txt', run => {
  const bad = open(run, 'bad.txt'), hole = open(run, 'hole.txt'), good = open(run, 'good.txt');
  run.api['snail:io/close'](hole);
  write(run, bad, 'failed buffered payload');
  write(run, good, 'retained buffered payload');
  pathname(run, 'pending-unused.txt');
  assert.throws(() => run.api['snail:io/read-character'](-1), /unknown or closed file port/);
  assert.deepEqual(run.diagnostics, ['unknown or closed file port']);
  assert.deepEqual(closes(run), ['hole.txt', 'bad.txt', 'good.txt']);
  assert(run.events.some(event => event[0] === 'returned-write-error'));
  assert.equal(fs.readFileSync(path.join(run.root, 'good.txt'), 'utf8'), 'retained buffered payload');
});

checked('failed-open-cleans-owned-port', null, run => {
  const output = open(run, 'before-failure.txt');
  write(run, output, 'flushed before the failed-open diagnostic');
  pathname(run, 'absent/child.txt');
  assert.throws(() => run.api['snail:io/open-input-file']());
  assert.equal(run.diagnostics.length, 1);
  assert.match(run.diagnostics[0], /absent\/child.txt/);
  assert.deepEqual(closes(run), ['before-failure.txt']);
  assert.equal(fs.readFileSync(path.join(run.root, 'before-failure.txt'), 'utf8'), 'flushed before the failed-open diagnostic');
});

// ---- Every invalid operation is terminal in its own fresh instance ----

for (const [label, operation, id] of [
  ['negative-peek', 'peek-character', -1], ['negative-write', 'write-character', -1],
  ['negative-close', 'close', -1], ['unknown-read', 'read-character', 123],
  ['stale-read', 'read-character', 0], ['stale-close', 'close', 0],
]) checked(label, null, run => {
  const old = open(run, 'old.txt');
  run.api['snail:io/close'](old);
  const live = open(run, 'live.txt');
  write(run, live, 'disposed before terminal error');
  assert.throws(() => run.api['snail:io/' + operation](id, 0x03bb), /unknown or closed file port/);
  assert.deepEqual(run.diagnostics, ['unknown or closed file port']);
  assert.deepEqual(closes(run), ['old.txt', 'live.txt']);
  assert.equal(fs.readFileSync(path.join(run.root, 'live.txt'), 'utf8'), 'disposed before terminal error');
});

assert(results.every(record => record.valid));
console.log(JSON.stringify({valid: true, cases: results.length, performance_samples: false}));
