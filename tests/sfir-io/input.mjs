import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {WASI} from 'node:wasi';

// ---- Observe actual file ownership through successful and failed reads ----

const [artifact, directory, contract] = process.argv.slice(2);
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(entry => entry.module === 'wasi_snapshot_preview1'));
assert(WebAssembly.Module.exports(module).every(entry => !entry.name.startsWith('snail:')));

function open(label, contents, failReads = false) {
  const root = path.join(directory, label);
  fs.mkdirSync(root, {recursive: true});
  fs.writeFileSync(path.join(root, 'λ😀.txt'), contents);
  const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': root}, returnOnExit: true});
  const imports = {...wasi.wasiImport}, live = new Set(), counts = {opened: 0, closed: 0};
  let memory;
  imports.path_open = (...args) => {
    const status = wasi.wasiImport.path_open(...args);
    if (status === 0) {
      live.add(new DataView(memory.buffer).getUint32(args.at(-1), true));
      counts.opened++;
    }
    return status;
  };
  imports.fd_close = fd => {
    const status = wasi.wasiImport.fd_close(fd);
    if (status === 0 && live.delete(fd)) counts.closed++;
    return status;
  };
  imports.fd_read = (...args) => failReads && live.has(args[0]) ? 29 : wasi.wasiImport.fd_read(...args);
  const instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: imports});
  memory = instance.exports.memory;
  return {instance, wasi, api: instance.exports, root, live, counts};
}

function cleanup(run) {
  assert.equal(run.api['close-resources'](), 0);
  assert.equal(run.live.size, 0);
  assert.equal(run.counts.closed, run.counts.opened);
}

function copy(label, text, expected, count) {
  const run = open(label, text);
  try {
    run.wasi.initialize(run.instance);
    run.api.main();
    assert.equal(run.api['copy-lines'](), BigInt(count));
    assert.deepEqual(fs.readFileSync(path.join(run.root, 'lines.txt')), Buffer.from(expected));
    assert.equal(run.counts.closed, 2, 'normal callbacks close before returning');
  } finally { cleanup(run); }
}

function failure(label, worker, contents, releases, failReads = false) {
  const run = open(label, contents, failReads);
  try {
    run.wasi.initialize(run.instance);
    run.api.main();
    assert.throws(() => run.api[worker]());
    if (worker !== 'input-callback-trap') assert.equal(run.counts.closed, releases);
  } finally { cleanup(run); }
  assert.equal(run.counts.opened, releases);
  if (worker === 'read-invalid')
    assert.equal(fs.readFileSync(path.join(run.root, 'buffered.txt'), 'utf8'), 'released after read failure');
}

// ---- Empty lines, Unicode, all line endings and buffer-growth boundaries ----

if (contract === 'input-main-trap') {
  const run = open('main-trap', 'line\n');
  try {
    run.wasi.initialize(run.instance);
    assert.throws(() => run.api.main(), WebAssembly.RuntimeError);
  } finally { cleanup(run); }
  assert.equal(run.counts.opened, 1);
} else {
  for (const [label, text, expected, count] of [
    ['empty', '', '', 0], ['blank', '\n', '\n', 1], ['blanks', '\n\n', '\n\n', 2],
    ['cr-eof', 'last\r', 'last\n', 1], ['empty-cr-eof', '\r', '\n', 1],
    ['unterminated', 'last', 'last\n', 1], ['terminated', 'first\nlast\n', 'first\nlast\n', 2],
    ['endings', 'a\rb\r\nc\n\r\n\rfinal', 'a\nb\nc\n\n\nfinal\n', 6],
    ['unicode', '\0λ😀\u{10ffff}\n\t\u0085\u2028\u2029', '\0λ😀\u{10ffff}\n\t\u0085\u2028\u2029\n', 2],
  ]) copy(label, text, expected, count);
  for (const count of [1, 63, 64, 65, 127, 128, 129, 4095, 4096, 4097, 65537]) {
    const line = '😀'.repeat(count);
    copy(`growth-${count}`, `${line}\r\nend`, `${line}\nend\n`, 2);
  }
  const run = open('ownership', 'same\nsame\n');
  try {
    run.wasi.initialize(run.instance);
    run.api.main();
    assert.equal(run.api['line-storage'](), 1);
    run.api['close-input-alias']();
    assert.equal(run.api['input-callback-close'](), 19n);
    assert.equal(run.counts.closed, 3);
  } finally { cleanup(run); }
  for (const [worker, releases] of [['input-escaped-alias', 1], ['input-missing', 0],
    ['input-callback-trap', 1], ['input-raw-output', 1], ['input-stale-handle', 1],
    ['input-invalid-handle', 0], ['input-invalid-peek', 0]])
    failure(worker, worker, 'line\n', releases);
  for (const [index, contents] of [[0, Buffer.from([0xff])], [1, Buffer.from([0xf0, 0x9f])],
                                 [2, Buffer.from([13, 0xff])]])
    failure(`invalid-utf8-${index}`, 'read-invalid', contents, 2);
  failure('read-error', 'read-invalid', 'text', 2, true);
}
console.log('PASS strict text input values, Unicode, line endings, storage, aliases and cleanup');
