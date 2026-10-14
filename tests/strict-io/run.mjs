import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {WASI} from 'node:wasi';

// ---- One real WASI instance for each success or terminal failure ----

const [artifact, directory] = process.argv.slice(2);
const module = new WebAssembly.Module(fs.readFileSync(artifact));
assert(WebAssembly.Module.imports(module).every(entry => entry.module === 'wasi_snapshot_preview1'));
assert(WebAssembly.Module.exports(module).every(entry => !entry.name.startsWith('snail:')));

function open(label, failWrites = false) {
  const root = path.join(directory, label);
  fs.mkdirSync(root, {recursive: true});
  const wasi = new WASI({version: 'preview1', args: [], env: {}, preopens: {'.': root}, returnOnExit: true});
  const imports = {...wasi.wasiImport};
  const live = new Set(), counts = {opened: 0, closed: 0};
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
  imports.fd_write = (...args) => failWrites && live.has(args[0]) ? 29 : wasi.wasiImport.fd_write(...args);
  const instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: imports});
  memory = instance.exports.memory;
  wasi.initialize(instance);
  instance.exports.main();
  return {api: instance.exports, root, live, counts};
}

function cleanup(run) {
  assert.equal(run.api['close-resources'](), 0);
  assert.equal(run.live.size, 0, 'every file descriptor must be closed');
  assert.equal(run.counts.closed, run.counts.opened);
}

function bytes(run, name) {
  return fs.readFileSync(path.join(run.root, name));
}

const positive = open('positive');
try {
  for (const number of [0n, 1n, -1n, 10n, -10n, 1234567890123456789n, -(2n ** 63n), 2n ** 63n - 1n]) {
    assert.equal(positive.api['format-number'](number), number);
    assert.equal(bytes(positive, 'number.txt').toString(), `${number}\n`);
  }
  assert.equal(positive.api.exists(), 0);
  assert.equal(positive.api.unicode(), 42n);
  assert.deepEqual(bytes(positive, 'λ😀.txt'), Buffer.from('\0λ😀\u{10ffff}\n'));
  assert.equal(positive.api.exists(), 1);
  positive.api.remove();
  assert.equal(positive.api.exists(), 0);
  assert.equal(positive.api['callback-result'](), 1.25);
  assert.equal(bytes(positive, 'result.txt').toString(), 'answer');
  positive.api['close-alias']();
  assert.equal(bytes(positive, 'alias.txt').toString(), 'once');
  assert.equal(positive.api['callback-close'](), 19n);
  assert.equal(bytes(positive, 'self-close.txt').toString(), 'closed');
} finally {
  cleanup(positive);
}

for (const name of ['escaped-alias', 'missing-directory', 'nul-path', 'delete-absent',
                    'callback-trap', 'invalid-character', 'invalid-handle', 'interrupted-path']) {
  const run = open(name);
  try {
    assert.throws(() => run.api[name](), undefined, name);
  } finally {
    cleanup(run);
  }
  if (name === 'callback-trap') assert.equal(bytes(run, 'trap.txt').toString(), 'buffered');
  if (name === 'interrupted-path') assert.deepEqual(fs.readdirSync(run.root), []);
}

// Returned EIO during flush must release that file and still attempt the other
// file. Fatal diagnostics occur only after both descriptors have been closed.
const failed = open('close-failure', true);
try {
  assert.throws(() => failed.api['close-failure']());
  assert.equal(failed.counts.opened, 2);
  assert.equal(failed.counts.closed, 2);
  assert.equal(failed.live.size, 0);
} finally {
  cleanup(failed);
}
console.log('PASS strict scalar text output, aliases, UTF-8, integer boundaries and cleanup');
