// Hold publication in the compiler worker while the parent serves the
// previous file. This preload adds no test switches to production code.
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';

const rename = fs.renameSync, gate = process.env.LOFI_TEST_PUBLICATION_GATE;
fs.renameSync = function(from, to) {
  if (to === process.env.LOFI_TEST_PUBLICATION_PATH && fs.existsSync(`${gate}.armed`) && !fs.existsSync(`${gate}.entered`)) {
    fs.writeFileSync(`${gate}.entered`, 'ready');
    const wait = new Int32Array(new SharedArrayBuffer(4));
    while (!fs.existsSync(`${gate}.released`)) Atomics.wait(wait, 0, 0, 10);
  }
  return rename.call(this, from, to);
};
syncBuiltinESMExports();
