// The in-process assembler end to end, without Binaryen:
//
//   node tests/assembler.mjs ASSEMBLER.wasm RUNTIME.wasm PROGRAM.wat EXPECTED.out
//
// The assembler, itself running as Wasm, turns the compiler's text into a
// module; the module runs with the Rust runtime as a separate instance,
// which it imports as snail.library, and must print what the program's
// expected output says. Broken text must fail with its line and column.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {WASI} from 'node:wasi';
import {fileURLToPath} from 'node:url';
import {createAssembler} from '../scripts/assemble.mjs';

// ---- Running a module unlinked ----

// Runs in a child process, so the program's standard output can be compared.
async function runUnlinked(runtimePath, modulePath) {
  const wasi = new WASI({version: 'preview1', args: [modulePath], env: {}, preopens: {'/': '/'}, returnOnExit: true});
  let runtime;
  const platform = {'diagnostics/report-error': (pointer, length) => runtime.exports['snail:report-error'](pointer, length)};
  ({instance: runtime} = await WebAssembly.instantiate(await readFile(runtimePath), {...wasi.getImportObject(), 'snail.platform': platform}));
  wasi.initialize(runtime);
  const {instance} = await WebAssembly.instantiate(await readFile(modulePath), {'snail.library': runtime.exports});
  instance.exports.main();
  runtime.exports['snail:io/close-all']();
}

// ---- Test ----

async function test([assemblerPath, runtimePath, programPath, expectedPath]) {
  const assemble = await createAssembler(await readFile(assemblerPath));
  assert.throws(() => assemble('(module\n  (func (result i32) (i32.bogus)))'), /:2:23/, 'broken text names its line and column');
  const directory = await mkdtemp(join(tmpdir(), 'lofi-assembler-'));
  try {
    const modulePath = join(directory, 'program.wasm');
    await writeFile(modulePath, assemble(await readFile(programPath, 'utf8')));
    const run = spawnSync(process.execPath, ['--no-warnings', fileURLToPath(import.meta.url), '--run', runtimePath, modulePath], {encoding: 'utf8'});
    assert.equal(run.stdout + run.stderr, await readFile(expectedPath, 'utf8'));
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
  console.log('assembler: the module it assembled runs');
}

const [mode, ...rest] = process.argv.slice(2);
await (mode === '--run' ? runUnlinked(...rest) : test([mode, ...rest]));
