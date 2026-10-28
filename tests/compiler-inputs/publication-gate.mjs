// Hold publication in the compiler worker while the parent serves the
// previous file. This preload adds no test switches to production code.
// The loop publishes through its runtime's WASI `path_rename`, which Node
// implements natively, so the preload wraps that import: each WASI instance
// remembers the memory it was initialized with, where the call's new path
// lies, relative to the preopened root.
import fs from 'node:fs';
import {resolve} from 'node:path';
import {WASI} from 'node:wasi';

const gate = process.env.SNAIL_TEST_PUBLICATION_GATE, decoder = new TextDecoder();
const {getImportObject, initialize} = WASI.prototype, memories = new WeakMap();

function hold(to) {
  if (to === process.env.SNAIL_TEST_PUBLICATION_PATH && fs.existsSync(`${gate}.armed`) && !fs.existsSync(`${gate}.entered`)) {
    fs.writeFileSync(`${gate}.entered`, 'ready');
    const wait = new Int32Array(new SharedArrayBuffer(4));
    while (!fs.existsSync(`${gate}.released`)) Atomics.wait(wait, 0, 0, 10);
  }
}

WASI.prototype.initialize = function(instance) {
  memories.set(this, instance.exports.memory);
  return initialize.call(this, instance);
};

WASI.prototype.getImportObject = function() {
  const imports = getImportObject.call(this), wasi = imports.wasi_snapshot_preview1;
  const rename = (fd, from, fromLength, toFd, to, toLength) => {
    hold(resolve('/', decoder.decode(new Uint8Array(memories.get(this).buffer, to, toLength))));
    return wasi.path_rename(fd, from, fromLength, toFd, to, toLength);
  };
  return {...imports, wasi_snapshot_preview1: {...wasi, path_rename: rename}};
};
